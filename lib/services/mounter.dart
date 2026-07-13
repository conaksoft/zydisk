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
  static Future<bool> installDaemon() async {
    try {
      final result = await _daemonChannel.invokeMethod<bool>('installDaemon');
      return result ?? false;
    } catch (e) {
      print("Daemon kurulum hatası: $e");
      return false;
    }
  }

  static Future<MountResult> mount(RemoteConfig config) async {
    final mountPoint = getMountPoint(config);

    // rclone config'i yaz
    await ConfigBuilder.writeConfig(config);

    // Rastgele yüksek port seç (çakışma önlemek için)
    final port = 10000 + Random().nextInt(50000);
    final logFile = '/tmp/rclone_${config.name}.log';

    // rclone'u NFS server olarak başlat
    final remotePath = config.path.isNotEmpty && config.path != '/'
        ? '${config.name}:${config.path}'
        : '${config.name}:';

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
        '--transfers', '4',
        '--log-level', 'INFO',
        '--log-file', logFile,
      ],
      mode: ProcessStartMode.detached,
    );

    // NFS server'ın başlaması için bekle
    await Future.delayed(const Duration(seconds: 3));

    bool mounted = false;
    String errorMsg = '';
    try {
      // Daemon üzerinden şifresiz mount işlemini tetikliyoruz
      mounted = await _daemonChannel.invokeMethod('mount', {
        'port': port,
        'mountPoint': mountPoint,
      }) ?? false;
    } catch (e) {
      if (e is PlatformException && e.code == 'XPC_ERROR') {
        // Servis kurulu değilse veya durmuşsa otomatik kurmayı dene
        print("Daemon bulunamadı, otomatik kurulum tetikleniyor...");
        bool installed = await installDaemon();
        if (installed) {
          try {
            // Kurulum başarılıysa mount işlemini tekrar dene
            mounted = await _daemonChannel.invokeMethod('mount', {
              'port': port,
              'mountPoint': mountPoint,
            }) ?? false;
          } catch (retryE) {
            errorMsg = retryE.toString();
            mounted = false;
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

    if (!mounted) {
      nfsProcess.kill();
      // Log'dan hata oku
      final log = await File(logFile).readAsString().catchError((_) => '');
      final err = log.split('\n').lastWhere(
        (l) => l.contains('ERROR') || l.contains('CRITICAL'),
        orElse: () => 'NFS mount başarısız: $errorMsg',
      );
      return MountResult(success: false, error: err);
    }

    // Mount aktif mi kontrol et
    final mountCheck = await Process.run('mount', []);
    if (!(mountCheck.stdout as String).contains(mountPoint)) {
      nfsProcess.kill();
      return MountResult(success: false, error: 'Mount aktif değil');
    }

    _sessions[config.id] = _MountSession(
      nfsProcess: nfsProcess,
      nfsPort: port,
      mountPoint: mountPoint,
    );

    return MountResult(success: true, mountPoint: mountPoint);
  }

  static Future<bool> unmount(RemoteConfig config) async {
    final session = _sessions.remove(config.id);
    final mountPoint = getMountPoint(config);

    try {
      // rclone NFS server'ı durdur
      session?.nfsProcess.kill();

      // Daemon üzerinden şifresiz unmount işlemini tetikliyoruz
      await _daemonChannel.invokeMethod('unmount', {
        'mountPoint': mountPoint,
      });

      return true;
    } catch (e) {
      print("Unmount error: $e");
      return false;
    }
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
    for (final entry in _sessions.entries) {
      final mp = entry.value.mountPoint;
      try {
        await _daemonChannel.invokeMethod('unmount', {
          'mountPoint': mp,
        });
      } catch (_) {}
      entry.value.nfsProcess.kill();
    }
    _sessions.clear();
  }
}
