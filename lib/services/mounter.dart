import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/remote_config.dart';
import 'config_builder.dart';

class MountResult {
  final bool success;
  final String? error;
  final String? mountPoint;

  MountResult({required this.success, this.error, this.mountPoint});
}

class _MountSession {
  final Process nfsProcess;
  final int nfsPort;
  final String mountPoint;

  _MountSession({
    required this.nfsProcess,
    required this.nfsPort,
    required this.mountPoint,
  });
}

class Mounter {
  static final Map<String, _MountSession> _sessions = {};
  static const MethodChannel _daemonChannel = MethodChannel('com.conaksoft.zydisk/daemon');

  // Resmi rclone binary — macFUSE gerektirmez, Native NFS üzerinden loopback mount yapar
  static String get rcloneBin {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/bin/rclone_official';
  }

  static String getMountPoint(RemoteConfig config) {
    return '/Volumes/${config.name}';
  }

  /// Daemon servisini kurar. Kullanıcıdan bir kereliğine şifre/Touch ID ister.
  static Future<bool> installDaemon({bool force = false}) async {
    try {
      final result = await _daemonChannel.invokeMethod<bool>('installDaemon', {'force': force});
      return result ?? false;
    } catch (e) {
      print("Daemon kurulum hatası: $e");
      return false;
    }
  }

  static Future<void> _trace(String msg) async {
    print("[Mounter] $msg");
    final file = File('/tmp/zydisk_trace.txt');
    await file.writeAsString('${DateTime.now()}: $msg\n', mode: FileMode.append);
  }

  static Future<MountResult> mount(RemoteConfig config) async {
    await _trace('mount started for ${config.name}');
    final mountPoint = getMountPoint(config);

    // rclone config'i yaz
    await ConfigBuilder.writeConfig(config);
    await _trace('config written');

    // Rastgele yüksek port seç (çakışma önlemek için)
    final port = 10000 + Random().nextInt(50000);
    final logFile = '/tmp/rclone_${config.name}.log';

    // rclone'u NFS server olarak başlat
    final remotePath = config.path.isNotEmpty && config.path != '/'
        ? '${config.name}:${config.path}'
        : '${config.name}:';

    await _trace('starting rclone process');
    final nfsProcess = await Process.start(
      rcloneBin,
      [
        'serve', 'nfs',
        remotePath,
        '--addr', '127.0.0.1:$port',
        '--vfs-cache-mode', 'full',
        '--vfs-cache-max-size', '512M',
        '--dir-cache-time', '5m',
        '--no-checksum',
        '--transfers', '2',
        '--checkers', '2',
        '--log-level', 'INFO',
        '--log-file', logFile,
        '--exclude', '._*',
        '--exclude', '.DS_Store',
        '--exclude', '.Trashes/**',
        '--exclude', '.TemporaryItems/**',
        '--exclude', '.apdisk',
      ],
      mode: ProcessStartMode.normal,
    );
    await _trace('rclone process started, waiting 3s');

    // NFS server'ın başlaması için bekle
    await Future.delayed(const Duration(seconds: 3));
    await _trace('wait done, calling daemon mount');

    bool mounted = false;
    String errorMsg = '';
    try {
      mounted = await _daemonChannel.invokeMethod('mount', {
        'port': port,
        'mountPoint': mountPoint,
      }).timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception("Daemon yanıt vermedi (Zaman aşımı). Servis çökmüş olabilir.");
      }) ?? false;
    } catch (e) {
      await _trace('daemon mount threw: $e');
      final isXpcError = e is PlatformException && e.code == 'XPC_ERROR';
      final isTimeout = e.toString().contains('Zaman aşımı');
      
      if (isXpcError || isTimeout) {
        // Servis kurulu değilse veya durmuşsa otomatik kurmayı dene
        await _trace('installing daemon...');
        bool installed = await installDaemon(force: true);
        await _trace('installDaemon returned: $installed');
        if (installed) {
          try {
            // Kurulum başarılıysa mount işlemini tekrar dene
            await _trace('retrying daemon mount');
            mounted = await _daemonChannel.invokeMethod('mount', {
              'port': port,
              'mountPoint': mountPoint,
            }).timeout(const Duration(seconds: 10), onTimeout: () {
              throw Exception("Daemon yanıt vermedi (Zaman aşımı). Servis çökmüş olabilir.");
            }) ?? false;
            await _trace('retry returned: $mounted');
          } catch (retryE) {
            errorMsg = retryE.toString();
            mounted = false;
            await _trace('retry threw: $retryE');
          }
        } else {
          errorMsg = "Arka plan servisi (Daemon) kurulamadı.";
          mounted = false;
        }
      } else {
        errorMsg = e.toString();
        mounted = false;
      }
    }

    // YEREL GELİŞTİRME İÇİN FALLBACK (AppleScript):
    // Apple Geliştirici sertifikası olmadığı durumlarda Daemon başlatılamaz ve çöker.
    // Bu durumda macOS'in kendi arayüzüyle şifre sorarak mount etmesini sağlıyoruz.
    if (!mounted) {
      await _trace('Daemon failed, falling back to AppleScript...');
      final script = '''
        do shell script "mkdir -p \\"$mountPoint\\" && chmod 755 \\"$mountPoint\\" && mount_nfs -o port=$port,mountport=$port,tcp,locallocks,resvport,nolocks 127.0.0.1:/ \\"$mountPoint\\"" with administrator privileges
      ''';
      try {
        final result = await Process.run('osascript', ['-e', script]);
        if (result.exitCode == 0) {
          mounted = true;
          await _trace('AppleScript mount success');
        } else {
          errorMsg = "AppleScript Error: ${result.stderr}";
          await _trace('AppleScript mount failed: $errorMsg');
        }
      } catch (scriptErr) {
        errorMsg = scriptErr.toString();
        await _trace('AppleScript threw: $errorMsg');
      }
    }

    await _trace('mount attempts finished, mounted=$mounted');

    if (!mounted) {
      nfsProcess.kill();
      // Log'dan hata oku
      final log = await File(logFile).readAsString().catchError((_) => '');
      final err = log.split('\n').lastWhere(
        (l) => l.contains('ERROR') || l.contains('CRITICAL'),
        orElse: () => 'NFS mount başarısız: $errorMsg',
      );
      await _trace('returning failure: $err');
      return MountResult(success: false, error: err);
    }

    // Mount aktif mi kontrol et
    await _trace('verifying mount');
    final mountCheck = await Process.run('mount', []);
    if (!(mountCheck.stdout as String).contains(mountPoint)) {
      nfsProcess.kill();
      await _trace('mount verification failed');
      return MountResult(success: false, error: 'Mount aktif değil');
    }

    _sessions[config.id] = _MountSession(
      nfsProcess: nfsProcess,
      nfsPort: port,
      mountPoint: mountPoint,
    );

    await _trace('mount complete');
    return MountResult(success: true, mountPoint: mountPoint);
  }

  static Future<bool> unmount(RemoteConfig config) async {
    final session = _sessions.remove(config.id);
    final mountPoint = getMountPoint(config);

    bool unmounted = false;
    try {
      // Daemon üzerinden şifresiz unmount işlemini tetikliyoruz
      await _daemonChannel.invokeMethod('unmount', {
        'mountPoint': mountPoint,
      }).timeout(const Duration(seconds: 5));
      unmounted = true;
    } catch (e) {
      print("Daemon unmount error: $e");
      unmounted = false;
    }

    if (!unmounted) {
      print('Daemon failed, falling back to AppleScript for unmount...');
      final script = '''
        do shell script "diskutil unmount force \\"$mountPoint\\"" with administrator privileges
      ''';
      try {
        final result = await Process.run('osascript', ['-e', script]);
        if (result.exitCode == 0) {
          unmounted = true;
        } else {
          print("AppleScript unmount error: ${result.stderr}");
        }
      } catch (e) {
        print("AppleScript unmount threw: $e");
      }
    }

    // rclone NFS server'ı durdur
    session?.nfsProcess.kill();

    return unmounted;
  }

  static Future<bool> isMounted(RemoteConfig config) async {
    final mountPoint = getMountPoint(config);
    final result = await Process.run('mount', []);
    return (result.stdout as String).contains(mountPoint);
  }

  static Future<void> openInFinder(RemoteConfig config) async {
    await Process.run('open', [getMountPoint(config)]);
  }

  static Future<void> openInVSCode(RemoteConfig config) async {
    final mountPoint = getMountPoint(config);
    final result = await Process.run('code', [mountPoint]);
    if (result.exitCode != 0) {
      await Process.run('open', ['-a', 'Visual Studio Code', mountPoint]);
    }
  }

  static Future<void> unmountAll() async {
    for (var session in _sessions.values) {
      bool unmounted = false;
      try {
        await _daemonChannel.invokeMethod('unmount', {
          'mountPoint': session.mountPoint,
        }).timeout(const Duration(seconds: 5));
        unmounted = true;
      } catch (e) {
        print("Daemon unmountAll error: $e");
      }

      if (!unmounted) {
        final script = '''
          do shell script "diskutil unmount force \\"${session.mountPoint}\\"" with administrator privileges
        ''';
        try {
          await Process.run('osascript', ['-e', script]);
        } catch (e) {
          print("AppleScript unmountAll threw: $e");
        }
      }
      session.nfsProcess.kill();
    }
    _sessions.clear();
  }
}
