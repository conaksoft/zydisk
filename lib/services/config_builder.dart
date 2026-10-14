import 'dart:convert';
import 'dart:io';
import '../models/remote_config.dart';
import 'mounter.dart';

/// rclone uzak tanımını üretir.
///
/// Yapılandırma artık rclone.conf dosyasına yazılmaz: tüm ayarlar (gizlenmiş parola dahil) yalnızca
/// rclone sürecinin ortam değişkenlerine verilir. Böylece diskte parola kalmaz ve uzak yeniden
/// adlandırıldığında eski bölümler birikmez.
class ConfigBuilder {
  static Future<Map<String, String>> buildEnvironment(RemoteConfig config, String? password) async {
    final prefix = 'RCLONE_CONFIG_${config.rcloneName.toUpperCase()}_';
    final opts = <String, String>{};

    switch (config.type) {
      case RemoteType.sftp:
        opts['type'] = 'sftp';
        opts['host'] = config.host;
        opts['user'] = config.user;
        opts['port'] = '${config.port}';
        // Sunucuda md5sum/sha1sum aramasını atla: bağlantı hızlanır, gereksiz komut çalışmaz.
        opts['disable_hashcheck'] = 'true';
        opts['shell_type'] = 'unix';
        if (config.authMethod == AuthMethod.keyFile && (config.keyFilePath ?? '').isNotEmpty) {
          opts['key_file'] = config.keyFilePath!;
        } else if (password != null) {
          opts['pass'] = await obscure(password);
        }
        break;

      case RemoteType.ftp:
      case RemoteType.ftps:
        opts['type'] = 'ftp';
        opts['host'] = config.host;
        opts['user'] = config.user;
        opts['port'] = '${config.port}';
        opts['concurrency'] = '4';
        if (config.type == RemoteType.ftps) {
          // 990 = implicit TLS, diğer portlar explicit (AUTH TLS).
          if (config.port == 990) {
            opts['tls'] = 'true';
          } else {
            opts['explicit_tls'] = 'true';
          }
        }
        if (password != null) {
          opts['pass'] = await obscure(password);
        }
        break;

      case RemoteType.s3:
        opts['type'] = 's3';
        opts['provider'] = 'Other';
        opts['endpoint'] = _s3Endpoint(config);
        opts['access_key_id'] = config.user;
        if (password != null) {
          opts['secret_access_key'] = password;
        }
        break;
    }

    return opts.map((k, v) => MapEntry('$prefix${k.toUpperCase()}', v));
  }

  static String _s3Endpoint(RemoteConfig config) {
    final host = config.host.trim();
    if (host.startsWith('http://') || host.startsWith('https://')) return host;
    if (config.port == 443 || config.port == 0) return host;
    return 'https://$host:${config.port}';
  }

  /// Parolayı komut satırı argümanında göstermeden (stdin üzerinden) gizler.
  static Future<String> obscure(String plaintext) async {
    final p = await Process.start(Mounter.rcloneBin, ['obscure', '-']);
    p.stdin.write(plaintext);
    await p.stdin.close();
    final out = await p.stdout.transform(utf8.decoder).join();
    await p.exitCode;
    return out.trim();
  }

  /// Önceki sürümlerin ~/.config/rclone/rclone.conf içine yazdığı ve gizlenmiş parola içeren
  /// bölümleri temizler. Yalnızca ad + host eşleşen (yani ZyDisk'in yazdığı) bölümler silinir.
  static Future<void> cleanupLegacyConfig(List<RemoteConfig> remotes) async {
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final file = File('$home/.config/rclone/rclone.conf');
    if (!await file.exists()) return;

    final content = await file.readAsString();
    final lines = content.split('\n');
    final result = <String>[];
    var changed = false;

    var i = 0;
    while (i < lines.length) {
      final header = RegExp(r'^\s*\[(.+)\]\s*$').firstMatch(lines[i]);
      if (header == null) {
        result.add(lines[i]);
        i++;
        continue;
      }
      final name = header.group(1)!;
      final section = <String>[lines[i]];
      i++;
      while (i < lines.length && !RegExp(r'^\s*\[').hasMatch(lines[i])) {
        section.add(lines[i]);
        i++;
      }
      final hostLine = section.firstWhere((l) => l.trim().startsWith('host =') || l.trim().startsWith('endpoint ='),
          orElse: () => '');
      final host = hostLine.split('=').skip(1).join('=').trim();
      final owned = remotes.any((r) => r.name == name && r.host == host);
      if (owned) {
        changed = true;
      } else {
        result.addAll(section);
      }
    }

    if (changed) {
      final backup = File('${file.path}.zydisk-backup');
      if (!await backup.exists()) {
        await file.copy(backup.path);
        await Process.run('chmod', ['600', backup.path]);
      }
      await file.writeAsString(result.join('\n'));
    }
  }
}
