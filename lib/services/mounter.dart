import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/remote_config.dart';
import 'config_builder.dart';
import 'daemon_client.dart';
import 'keychain_service.dart';

enum MountErrorKind { auth, network, daemon, busy, other }

class MountResult {
  final bool success;
  final String? error;
  final MountErrorKind? kind;
  final String? mountPoint;

  MountResult.ok(this.mountPoint)
      : success = true,
        error = null,
        kind = null;

  MountResult.fail(this.error, [this.kind = MountErrorKind.other])
      : success = false,
        mountPoint = null;
}

/// Bir uzak için canlı aktarım bilgisi (rclone rc üzerinden).
class TransferStats {
  final int uploadsInProgress;
  final int uploadsQueued;
  final double speed; // bayt/sn
  final int erroredFiles;

  const TransferStats({
    this.uploadsInProgress = 0,
    this.uploadsQueued = 0,
    this.speed = 0,
    this.erroredFiles = 0,
  });

  int get pendingUploads => uploadsInProgress + uploadsQueued;
  bool get idle => pendingUploads == 0;

  @override
  bool operator ==(Object other) =>
      other is TransferStats &&
      other.uploadsInProgress == uploadsInProgress &&
      other.uploadsQueued == uploadsQueued &&
      other.erroredFiles == erroredFiles &&
      (other.speed - speed).abs() < 1024;

  @override
  int get hashCode => Object.hash(uploadsInProgress, uploadsQueued, erroredFiles);
}

/// Çalışan bir rclone NFS sunucusu. Süreç uygulamadan bağımsız (detached) çalışır; uygulama
/// yeniden açıldığında durum dosyasından geri alınır.
class _Session {
  final String remoteId;
  final String mountPoint;
  final String fs; // rclone fs dizgesi, ör. "zd123:/var/www"
  final int port;
  final int rcPort;
  final String rcPass;
  final String logFile;
  int pid;
  /// Birim ayrıldı, bekleyen yüklemeler bitince süreç sonlandırılacak.
  bool draining;
  int logOffset;
  int restarts = 0;
  DateTime? lastRestart;

  _Session({
    required this.remoteId,
    required this.mountPoint,
    required this.fs,
    required this.port,
    required this.rcPort,
    required this.rcPass,
    required this.logFile,
    required this.pid,
    this.draining = false,
  }) : logOffset = 0;

  Map<String, dynamic> toJson() => {
        'remoteId': remoteId,
        'mountPoint': mountPoint,
        'fs': fs,
        'port': port,
        'rcPort': rcPort,
        'rcPass': rcPass,
        'logFile': logFile,
        'pid': pid,
        'draining': draining,
      };

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        remoteId: j['remoteId'] as String,
        mountPoint: j['mountPoint'] as String,
        fs: j['fs'] as String,
        port: j['port'] as int,
        rcPort: j['rcPort'] as int? ?? 0,
        rcPass: j['rcPass'] as String? ?? '',
        logFile: j['logFile'] as String,
        pid: j['pid'] as int,
        draining: j['draining'] as bool? ?? false,
      );
}

/// Bağlama motoru: rclone `serve nfs` + root servis üzerinden `mount_nfs`.
class Mounter {
  Mounter._();
  static final Mounter instance = Mounter._();

  final Map<String, _Session> _sessions = {};
  final Map<String, TransferStats> _stats = {};
  final Map<String, RemoteConfig> _configs = {};
  Timer? _supervisor;
  bool _ticking = false;
  Directory? _supportDir;

  /// Bağlantı durumu dışarıdan değiştiğinde (Finder'dan çıkarma, yeniden bağlanma vb.) çağrılır.
  void Function(String remoteId, bool mounted, String? message)? onStateChanged;
  void Function()? onStatsChanged;

  /// AppleDouble (._*) ve .DS_Store dosyalarını sunucudan otomatik temizle.
  bool cleanAppleDouble = true;

  static String get rcloneBin {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/bin/rclone_official';
  }

  static String getMountPoint(RemoteConfig config) => '/Volumes/${config.name}';

  TransferStats statsFor(String remoteId) => _stats[remoteId] ?? const TransferStats();

  bool hasSession(String remoteId) => _sessions.containsKey(remoteId);

  int get drainingCount => _sessions.values.where((s) => s.draining).length;

  int get pendingUploadsTotal => _stats.values.fold(0, (a, s) => a + s.pendingUploads);

  // ---------------------------------------------------------------------------
  // Kalıcı durum
  // ---------------------------------------------------------------------------

  Future<Directory> _dir() async {
    if (_supportDir != null) return _supportDir!;
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return _supportDir = d;
  }

  Future<File> _stateFile() async => File('${(await _dir()).path}/sessions.json');

  Future<void> _saveState() async {
    final f = await _stateFile();
    await f.writeAsString(json.encode(_sessions.values.map((s) => s.toJson()).toList()));
    await Process.run('chmod', ['600', f.path]);
  }

  Future<List<_Session>> _loadState() async {
    try {
      final f = await _stateFile();
      if (!await f.exists()) return [];
      final raw = json.decode(await f.readAsString()) as List<dynamic>;
      return raw.map((e) => _Session.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Oturum durumu okunamadı: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Başlatma: önceki çalıştırmadan kalan bağlantıları sahiplen
  // ---------------------------------------------------------------------------

  /// Uygulama açılışında çağrılır. Bağlı kalan sürücüleri ve arkada çalışan rclone süreçlerini
  /// devralır; süreç ölmüşse aynı portla yeniden başlatır (Finder bağlantısı kopmaz).
  Future<void> restore(List<RemoteConfig> remotes) async {
    for (final r in remotes) {
      _configs[r.id] = r;
    }
    final mounted = await mountedNfsPoints();
    final saved = await _loadState();

    for (final s in saved) {
      final config = _configs[s.remoteId];
      if (config == null) {
        // Silinmiş bir uzak: süreci sonlandır.
        await _killPid(s.pid);
        continue;
      }
      final alive = await _isRclone(s.pid);
      final isMounted = mounted.contains(s.mountPoint);
      if (!isMounted && !s.draining) {
        if (alive) await _killPid(s.pid);
        continue;
      }
      _sessions[s.remoteId] = s;
      s.logOffset = await _fileLength(s.logFile);
      if (!alive && isMounted) {
        await _restartServer(s, reason: 'Uygulama yeniden açıldı');
      } else if (!alive) {
        _sessions.remove(s.remoteId);
      }
    }

    // Eski sürümden kalan (durum dosyasında olmayan) bağlantılar.
    for (final r in remotes) {
      final mp = getMountPoint(r);
      if (_sessions.containsKey(r.id) || !mounted.contains(mp)) continue;
      final port = await _portFromNfsstat(mp);
      if (port == null) continue;
      final pid = await _pidForPort(port);
      final session = _Session(
        remoteId: r.id,
        mountPoint: mp,
        fs: _fsFor(r),
        port: port,
        rcPort: 0,
        rcPass: '',
        logFile: await _logPath(r),
        pid: pid ?? 0,
      );
      _sessions[r.id] = session;
      if (pid == null) {
        await _restartServer(session, reason: 'Eski oturum devralındı');
      }
    }

    await _saveState();
    _ensureSupervisor();
  }

  // ---------------------------------------------------------------------------
  // Bağlama / ayırma
  // ---------------------------------------------------------------------------

  Future<MountResult> mount(RemoteConfig config) async {
    _configs[config.id] = config;
    final mountPoint = getMountPoint(config);

    if ((await mountedNfsPoints()).contains(mountPoint)) {
      return MountResult.fail('$mountPoint zaten bağlı.', MountErrorKind.busy);
    }
    if (await _isForeignVolume(mountPoint)) {
      return MountResult.fail(
        '"${config.name}" adında başka bir birim zaten var. Bağlantıya farklı bir ad verin.',
        MountErrorKind.busy,
      );
    }

    if (!await DaemonClient.ensureReady()) {
      return MountResult.fail(
        'Arka plan servisi kurulamadı. Ayarlar > Arka Plan Servisi bölümünden yeniden deneyin.',
        MountErrorKind.daemon,
      );
    }

    // Ayrılmış ama yüklemesi süren bir sunucu varsa onu yeniden kullan.
    var session = _sessions[config.id];
    if (session != null && (!session.draining || session.fs != _fsFor(config) || !await _isRclone(session.pid))) {
      await _stopSession(session);
      session = null;
    }

    if (session == null) {
      final started = await _startServer(config);
      if (started.error != null) return started.error!;
      session = started.session!;
    }

    try {
      await DaemonClient.mount(port: session.port, mountPoint: mountPoint);
    } catch (e) {
      await _stopSession(session);
      final msg = e is Exception ? _platformMessage(e) : e.toString();
      return MountResult.fail('Bağlama başarısız: $msg', MountErrorKind.daemon);
    }

    session.draining = false;
    _sessions[config.id] = session;
    await _saveState();
    _ensureSupervisor();
    return MountResult.ok(mountPoint);
  }

  /// Birimi ayırır. Parola sormaz. Bekleyen yüklemeler varsa rclone arka planda
  /// bunları bitirene kadar çalışmaya devam eder.
  Future<MountResult> unmount(RemoteConfig config, {bool force = true}) async {
    final mountPoint = getMountPoint(config);
    final session = _sessions[config.id];

    if ((await mountedNfsPoints()).contains(mountPoint)) {
      if (!await DaemonClient.ensureReady()) {
        return MountResult.fail('Arka plan servisi kullanılamıyor.', MountErrorKind.daemon);
      }
      try {
        await DaemonClient.unmount(mountPoint: mountPoint, force: force);
      } catch (e) {
        final msg = e is Exception ? _platformMessage(e) : e.toString();
        return MountResult.fail(msg, MountErrorKind.busy);
      }
    }

    if (session != null) {
      final stats = await _fetchStats(session);
      if (stats != null && !stats.idle) {
        session.draining = true;
        await _saveState();
      } else {
        await _stopSession(session);
      }
    }
    return MountResult.ok(null);
  }

  /// Tüm sürücüleri ayırır ve (en fazla [uploadTimeout] kadar) bekleyen yüklemeleri bekler.
  Future<void> unmountAll(List<RemoteConfig> remotes, {Duration uploadTimeout = const Duration(minutes: 2)}) async {
    for (final r in remotes) {
      if (_sessions.containsKey(r.id) || (await mountedNfsPoints()).contains(getMountPoint(r))) {
        await unmount(r);
      }
    }
    final deadline = DateTime.now().add(uploadTimeout);
    while (_sessions.values.any((s) => s.draining) && DateTime.now().isBefore(deadline)) {
      await _tick();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// Uzak silindiğinde: süreci durdur, önbellekleri temizle.
  Future<void> forget(RemoteConfig config) async {
    final s = _sessions[config.id];
    if (s != null) await _stopSession(s);
    _configs.remove(config.id);
    _stats.remove(config.id);
    final dir = await _dir();
    final handles = Directory('${dir.path}/nfs-handles/${config.rcloneName}');
    if (await handles.exists()) await handles.delete(recursive: true);
  }

  void updateConfig(RemoteConfig config) => _configs[config.id] = config;

  /// Dizin önbelleğini yeniler (sunucuda başka yerden yapılan değişiklikler hemen görünür).
  Future<bool> refresh(RemoteConfig config) async {
    final s = _sessions[config.id];
    if (s == null || s.rcPort == 0) return false;
    final r = await _rc(s, 'vfs/forget', {});
    return r != null;
  }

  /// Sunucudaki mevcut ._* ve .DS_Store dosyalarını tarar ve siler.
  Future<String> cleanRemoteJunk(RemoteConfig config) async {
    final password = config.authMethod == AuthMethod.password || config.type == RemoteType.s3
        ? await KeychainService.getPassword(config.id)
        : null;
    final env = await ConfigBuilder.buildEnvironment(config, password);
    final result = await Process.run(
      rcloneBin,
      [
        'delete', _fsFor(config),
        '--include', '._*',
        '--include', '.DS_Store',
        '--include', '.apdisk',
        '-v',
        '--stats', '0',
      ],
      environment: env,
    );
    final out = '${result.stdout}\n${result.stderr}';
    final deleted = RegExp(r': Deleted').allMatches(out).length;
    if (result.exitCode != 0) {
      return 'Temizlik tamamlanamadı: ${_lastError(out) ?? 'bilinmeyen hata'}';
    }
    return deleted == 0 ? 'Temizlenecek dosya bulunamadı.' : '$deleted gereksiz dosya silindi.';
  }

  /// Kaydetmeden önce bağlantıyı dener. Başarılıysa null, değilse hata mesajı döner.
  static Future<String?> testConnection(RemoteConfig config, String? password) async {
    final env = await ConfigBuilder.buildEnvironment(config, password);
    final path = config.path.trim();
    final fs = path.isEmpty || path == '/' ? '${config.rcloneName}:' : '${config.rcloneName}:$path';
    try {
      final result = await Process.run(
        rcloneBin,
        ['lsf', fs, '--max-depth', '1', '--dirs-only', '--contimeout', '10s', '--timeout', '20s',
          '--low-level-retries', '1', '--retries', '1'],
        environment: env,
      ).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) return null;
      final err = _lastError('${result.stderr}') ?? 'Bağlantı başarısız (${result.exitCode})';
      return _classify(err).error;
    } on TimeoutException {
      return 'Sunucu 30 saniye içinde yanıt vermedi.';
    }
  }

  // ---------------------------------------------------------------------------
  // rclone sunucusu
  // ---------------------------------------------------------------------------

  String _fsFor(RemoteConfig c) {
    final path = c.path.trim();
    return path.isEmpty || path == '/' ? '${c.rcloneName}:' : '${c.rcloneName}:$path';
  }

  Future<String> _logPath(RemoteConfig c) async {
    final logs = Directory('${(await _dir()).path}/logs');
    await logs.create(recursive: true);
    return '${logs.path}/${c.rcloneName}.log';
  }

  Future<({_Session? session, MountResult? error})> _startServer(RemoteConfig config) async {
    String? password;
    if (config.type == RemoteType.s3 || config.authMethod == AuthMethod.password) {
      password = await KeychainService.getPassword(config.id);
      if (password == null || password.isEmpty) {
        return (session: null, error: MountResult.fail('Parola gerekli.', MountErrorKind.auth));
      }
    }

    final env = await ConfigBuilder.buildEnvironment(config, password);
    final port = await _freePort();
    final rcPort = await _freePort();
    final rcPass = _randomToken();
    final logFile = await _logPath(config);
    await _rotateLog(logFile);

    final session = _Session(
      remoteId: config.id,
      mountPoint: getMountPoint(config),
      fs: _fsFor(config),
      port: port,
      rcPort: rcPort,
      rcPass: rcPass,
      logFile: logFile,
      pid: 0,
    );

    final err = await _spawn(session, config, env);
    if (err != null) return (session: null, error: err);

    // Kimlik ve erişim kontrolü: Finder'da boş klasör yerine anlamlı bir hata göstermek için.
    final probe = await _rc(session, 'operations/list', {
      'fs': session.fs,
      'remote': '',
      'opt': {'dirsOnly': true, 'noModTime': true, 'noMimeType': true},
    }, timeout: const Duration(seconds: 30));
    if (probe == null || probe['error'] != null) {
      final logErr = await _readLogError(session);
      final msg = (probe?['error'] as String?) ?? logErr ?? 'Sunucuya bağlanılamadı.';
      await _killPid(session.pid);
      return (session: null, error: _classify(msg));
    }

    return (session: session, error: null);
  }

  /// rclone'u başlatır ve NFS portu dinlemeye başlayana kadar bekler.
  Future<MountResult?> _spawn(_Session s, RemoteConfig config, Map<String, String> env) async {
    final handlesDir = Directory('${(await _dir()).path}/nfs-handles/${config.rcloneName}');
    await handlesDir.create(recursive: true);

    final args = [
      'serve', 'nfs', s.fs,
      '--addr', '127.0.0.1:${s.port}',
      // Disk tabanlı NFS tutamaç önbelleği: rclone yeniden başlasa da Finder "stale handle" görmez.
      '--nfs-cache-type', 'disk',
      '--nfs-cache-dir', handlesDir.path,
      '--vfs-cache-mode', 'full',
      '--vfs-cache-max-size', '2G',
      '--vfs-cache-max-age', '24h',
      '--vfs-write-back', '3s',
      '--dir-cache-time', '30s',
      '--no-checksum',
      '--transfers', '4',
      '--checkers', '4',
      '--contimeout', '15s',
      '--timeout', '5m',
      '--low-level-retries', '20',
      '--rc',
      '--rc-addr', '127.0.0.1:${s.rcPort}',
      '--log-level', 'INFO',
      '--log-file', s.logFile,
      '--exclude', '._*',
      '--exclude', '.DS_Store',
      '--exclude', '.Trashes/**',
      '--exclude', '.TemporaryItems/**',
      '--exclude', '.Spotlight-V100/**',
      '--exclude', '.fseventsd/**',
      '--exclude', '.apdisk',
    ];

    final Process proc;
    try {
      proc = await Process.start(
        rcloneBin,
        args,
        environment: {
          ...env,
          'RCLONE_RC_USER': 'zydisk',
          'RCLONE_RC_PASS': s.rcPass,
        },
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      return MountResult.fail('rclone başlatılamadı: $e');
    }
    s.pid = proc.pid;

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await _portOpen(s.port)) {
        // rc de hazır olsun.
        for (var i = 0; i < 20 && s.rcPort != 0 && !await _portOpen(s.rcPort); i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        return null;
      }
      if (!await _isRclone(s.pid)) {
        final err = await _readLogError(s) ?? 'rclone beklenmedik şekilde kapandı.';
        return _classify(err);
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    await _killPid(s.pid);
    return MountResult.fail('rclone NFS sunucusu zamanında başlamadı.', MountErrorKind.network);
  }

  Future<void> _restartServer(_Session s, {required String reason}) async {
    final config = _configs[s.remoteId];
    if (config == null) return;
    String? password;
    if (config.type == RemoteType.s3 || config.authMethod == AuthMethod.password) {
      password = await KeychainService.getPassword(config.id);
    }
    final env = await ConfigBuilder.buildEnvironment(config, password);
    s.restarts++;
    s.lastRestart = DateTime.now();
    debugPrint('rclone yeniden başlatılıyor (${config.name}): $reason');
    final err = await _spawn(s, config, env);
    await _saveState();
    if (err == null) {
      onStateChanged?.call(s.remoteId, true, null);
    } else {
      onStateChanged?.call(s.remoteId, true, 'Yeniden bağlanılamadı: ${err.error}');
    }
  }

  Future<void> _stopSession(_Session s) async {
    _sessions.remove(s.remoteId);
    _stats.remove(s.remoteId);
    await _killPid(s.pid);
    await _saveState();
  }

  // ---------------------------------------------------------------------------
  // Denetçi: çöken rclone'u yeniden başlat, Finder'dan çıkarmayı algıla, istatistik topla
  // ---------------------------------------------------------------------------

  void _ensureSupervisor() {
    _supervisor ??= Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_ticking || _sessions.isEmpty) return;
    _ticking = true;
    try {
      final mounted = await mountedNfsPoints();
      var statsChanged = false;

      for (final s in List.of(_sessions.values)) {
        final alive = await _isRclone(s.pid);
        final isMounted = mounted.contains(s.mountPoint);

        if (!isMounted && !s.draining) {
          // Kullanıcı Finder'dan çıkardı veya sistem ayırdı.
          final stats = alive ? await _fetchStats(s) : null;
          if (stats != null && !stats.idle) {
            s.draining = true;
            await _saveState();
          } else {
            await _stopSession(s);
          }
          onStateChanged?.call(s.remoteId, false, null);
          statsChanged = true;
          continue;
        }

        if (isMounted && !alive) {
          // Çöktü: aynı portla hemen geri getir. Çok sık çökerse yavaşla.
          final recent = s.lastRestart != null && DateTime.now().difference(s.lastRestart!) < const Duration(seconds: 20);
          if (!recent || s.restarts < 3) {
            if (!recent) s.restarts = 0;
            await _restartServer(s, reason: 'süreç sonlandı');
          }
          continue;
        }

        if (!alive) {
          await _stopSession(s);
          statsChanged = true;
          continue;
        }

        final stats = await _fetchStats(s);
        if (stats != null) {
          if (_stats[s.remoteId] != stats) {
            _stats[s.remoteId] = stats;
            statsChanged = true;
          }
          if (s.draining && stats.idle) {
            await _stopSession(s);
            statsChanged = true;
            continue;
          }
        }

        if (cleanAppleDouble) await _cleanJunkFromLog(s);
      }

      if (statsChanged) onStatsChanged?.call();
    } catch (e) {
      debugPrint('Denetçi hatası: $e');
    } finally {
      _ticking = false;
    }
  }

  static final _copiedLine = RegExp(r'INFO\s+: (.+): Copied \((?:new|replaced existing)\)');

  /// macOS, NFS'te genişletilmiş öznitelikleri ._dosya (AppleDouble) olarak yazar. rclone'un
  /// --exclude filtresi bu dosyaları yalnızca listeden gizler, sunucuya yüklenmelerini engellemez.
  /// Yükleme günlüğünü izleyip sunucuya gitmiş bu dosyaları hemen siliyoruz.
  Future<void> _cleanJunkFromLog(_Session s) async {
    if (s.rcPort == 0) return;
    final file = File(s.logFile);
    final len = await _fileLength(s.logFile);
    if (len < s.logOffset) s.logOffset = 0; // günlük döndürüldü
    if (len == s.logOffset) return;

    final raf = await file.open();
    try {
      await raf.setPosition(s.logOffset);
      final bytes = await raf.read(min(len - s.logOffset, 4 * 1024 * 1024));
      s.logOffset += bytes.length;
      final text = utf8.decode(bytes, allowMalformed: true);
      for (final m in _copiedLine.allMatches(text)) {
        final path = m.group(1)!;
        final base = path.split('/').last;
        if (base.startsWith('._') || base == '.DS_Store' || base == '.apdisk') {
          await _rc(s, 'operations/deletefile', {'fs': s.fs, 'remote': path});
        }
      }
    } finally {
      await raf.close();
    }
  }

  Future<TransferStats?> _fetchStats(_Session s) async {
    if (s.rcPort == 0) return null;
    final vfs = await _rc(s, 'vfs/stats', {});
    if (vfs == null) return null;
    final disk = (vfs['diskCache'] as Map?) ?? const {};
    final core = await _rc(s, 'core/stats', {});
    return TransferStats(
      uploadsInProgress: (disk['uploadsInProgress'] as num?)?.toInt() ?? 0,
      uploadsQueued: (disk['uploadsQueued'] as num?)?.toInt() ?? 0,
      erroredFiles: (disk['erroredFiles'] as num?)?.toInt() ?? 0,
      speed: (core?['speed'] as num?)?.toDouble() ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // rclone remote control (rc)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _rc(_Session s, String method, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (s.rcPort == 0) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:${s.rcPort}/$method'));
      req.headers.set(HttpHeaders.authorizationHeader,
          'Basic ${base64.encode(utf8.encode('zydisk:${s.rcPass}'))}');
      req.headers.contentType = ContentType.json;
      req.write(json.encode(body));
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final decoded = text.isEmpty ? <String, dynamic>{} : json.decode(text) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return {'error': decoded['error'] ?? 'HTTP ${res.statusCode}'};
      }
      return decoded;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Sistem yardımcıları
  // ---------------------------------------------------------------------------

  /// 127.0.0.1 kaynaklı NFS bağlama noktaları (tam yol eşleşmesi; "/Volumes/a" ≠ "/Volumes/ab").
  static Future<Set<String>> mountedNfsPoints() async {
    final result = await Process.run('/sbin/mount', ['-t', 'nfs']);
    return parseLocalNfsMounts(result.stdout as String);
  }

  @visibleForTesting
  static Set<String> parseLocalNfsMounts(String mountOutput) {
    final points = <String>{};
    for (final line in mountOutput.split('\n')) {
      final m = RegExp(r'^(?:127\.0\.0\.1|localhost):\S* on (.+) \(nfs').firstMatch(line);
      if (m != null) points.add(m.group(1)!);
    }
    return points;
  }

  Future<bool> _isForeignVolume(String mountPoint) async {
    final result = await Process.run('/sbin/mount', []);
    return (result.stdout as String).split('\n').any((l) => l.contains(' on $mountPoint ('));
  }

  Future<int?> _portFromNfsstat(String mountPoint) async {
    final r = await Process.run('nfsstat', ['-m']);
    final out = r.stdout as String;
    final idx = out.indexOf('$mountPoint from ');
    if (idx < 0) return null;
    final next = out.indexOf(RegExp(r'\n/\S'), idx + 1);
    final block = out.substring(idx, next < 0 ? out.length : next);
    final m = RegExp(r'port=(\d+)').firstMatch(block);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  Future<int?> _pidForPort(int port) async {
    final r = await Process.run('pgrep', ['-f', 'serve nfs .*127.0.0.1:$port']);
    final first = (r.stdout as String).trim().split('\n').first;
    return int.tryParse(first);
  }

  static Future<bool> _isRclone(int pid) async {
    if (pid <= 0) return false;
    final r = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
    return r.exitCode == 0 && (r.stdout as String).contains('rclone');
  }

  static Future<void> _killPid(int pid) async {
    if (!await _isRclone(pid)) return;
    Process.killPid(pid, ProcessSignal.sigterm);
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!await _isRclone(pid)) return;
    }
    Process.killPid(pid, ProcessSignal.sigkill);
  }

  static Future<bool> _portOpen(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 300));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }

  static String _randomToken() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(24, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static Future<int> _fileLength(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _rotateLog(String path) async {
    final f = File(path);
    if (await f.exists() && await f.length() > 5 * 1024 * 1024) {
      await f.rename('$path.1');
    }
  }

  Future<String?> _readLogError(_Session s) async {
    try {
      final text = await File(s.logFile).readAsString();
      return _lastError(text);
    } catch (_) {
      return null;
    }
  }

  static String? _lastError(String text) {
    final lines = text.split('\n').where((l) => l.contains('ERROR') || l.contains('CRITICAL') || l.contains('Failed'));
    if (lines.isEmpty) return null;
    return lines.last.replaceFirst(RegExp(r'^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} '), '').trim();
  }

  static String _platformMessage(Exception e) {
    final s = e.toString();
    final m = RegExp(r'PlatformException\([^,]*, ([^,]*)').firstMatch(s);
    return m?.group(1) ?? s;
  }

  @visibleForTesting
  static MountResult classifyError(String raw) => _classify(raw);

  static MountResult _classify(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('unable to authenticate') ||
        l.contains('permission denied') ||
        l.contains('530') ||
        l.contains('login incorrect') ||
        l.contains('invalidaccesskeyid') ||
        l.contains('signaturedoesnotmatch') ||
        l.contains('access denied') ||
        l.contains('authentication failed')) {
      return MountResult.fail('Kimlik doğrulama başarısız. Kullanıcı adı/parolayı kontrol edin.', MountErrorKind.auth);
    }
    if (l.contains('no such host') ||
        l.contains('connection refused') ||
        l.contains('i/o timeout') ||
        l.contains('network is unreachable') ||
        l.contains('timeout')) {
      return MountResult.fail('Sunucuya ulaşılamadı: $raw', MountErrorKind.network);
    }
    if (l.contains('directory not found') || l.contains('not found')) {
      return MountResult.fail('Uzak klasör bulunamadı: $raw');
    }
    return MountResult.fail(raw);
  }

  // ---------------------------------------------------------------------------
  // Kısayollar
  // ---------------------------------------------------------------------------

  static Future<void> openInFinder(RemoteConfig config) async {
    await Process.run('open', [getMountPoint(config)]);
  }

  static Future<void> openInTerminal(RemoteConfig config) async {
    await Process.run('open', ['-a', 'Terminal', getMountPoint(config)]);
  }

  static Future<void> openInVSCode(RemoteConfig config) async {
    final mountPoint = getMountPoint(config);
    try {
      final result = await Process.run('code', [mountPoint]);
      if (result.exitCode != 0) {
        await Process.run('open', ['-a', 'Visual Studio Code', mountPoint]);
      }
    } catch (_) {
      // Release derlemelerinde 'code' PATH'te olmayabilir.
      await Process.run('open', ['-a', 'Visual Studio Code', mountPoint]);
    }
  }
}
