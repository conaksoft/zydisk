import 'dart:io';
import '../models/remote_config.dart';
import 'keychain_service.dart';
import 'mounter.dart';

class ConfigBuilder {
  /// Generates and writes the rclone config file for a given remote.
  static Future<void> writeConfig(RemoteConfig config) async {
    final configFile = await _getRcloneConfigFile();
    final existing = await configFile.readAsString().catchError((_) => '');

    // Remove existing section for this remote
    final cleaned = _removeSection(existing, config.name);

    // Build new section
    final password = config.authMethod == AuthMethod.password
        ? await KeychainService.getPassword(config.id)
        : null;

    final section = await _buildSection(config, password);
    final newContent = '$cleaned\n$section';

    await configFile.writeAsString(newContent);
  }

  static Future<void> removeConfig(RemoteConfig config) async {
    final configFile = await _getRcloneConfigFile();
    final existing = await configFile.readAsString().catchError((_) => '');
    final cleaned = _removeSection(existing, config.name);
    await configFile.writeAsString(cleaned);
  }

  static Future<String> _buildSection(RemoteConfig config, String? password) async {
    final buffer = StringBuffer();
    buffer.writeln('[${config.name}]');

    switch (config.type) {
      case RemoteType.sftp:
        buffer.writeln('type = sftp');
        buffer.writeln('host = ${config.host}');
        buffer.writeln('user = ${config.user}');
        buffer.writeln('port = ${config.port}');
        if (config.authMethod == AuthMethod.keyFile && config.keyFilePath != null) {
          buffer.writeln('key_file = ${config.keyFilePath}');
        } else if (password != null) {
          // rclone uses obscured passwords
          final obscured = await _obscurePassword(password);
          buffer.writeln('pass = $obscured');
        }
        break;

      case RemoteType.ftp:
        buffer.writeln('type = ftp');
        buffer.writeln('host = ${config.host}');
        buffer.writeln('user = ${config.user}');
        buffer.writeln('port = ${config.port}');
        buffer.writeln('concurrency = 3');
        if (password != null) {
          final obscured = await _obscurePassword(password);
          buffer.writeln('pass = $obscured');
        }
        break;

      case RemoteType.ftps:
        buffer.writeln('type = ftp');
        buffer.writeln('host = ${config.host}');
        buffer.writeln('user = ${config.user}');
        buffer.writeln('port = ${config.port}');
        buffer.writeln('tls = true');
        buffer.writeln('concurrency = 3');
        if (password != null) {
          final obscured = await _obscurePassword(password);
          buffer.writeln('pass = $obscured');
        }
        break;

      case RemoteType.s3:
        buffer.writeln('type = s3');
        buffer.writeln('provider = Other');
        buffer.writeln('endpoint = ${config.host}');
        buffer.writeln('access_key_id = ${config.user}');
        if (password != null) {
          buffer.writeln('secret_access_key = $password');
        }
        break;
    }

    return buffer.toString();
  }

  static Future<String> _obscurePassword(String plaintext) async {
    final result = await Process.run(Mounter.rcloneBin, ['obscure', plaintext]);
    return (result.stdout as String).trim();
  }

  static String _removeSection(String content, String name) {
    final lines = content.split('\n');
    final result = <String>[];
    bool inSection = false;

    for (final line in lines) {
      if (line.trim() == '[$name]') {
        inSection = true;
        continue;
      }
      if (inSection && line.trim().startsWith('[')) {
        inSection = false;
      }
      if (!inSection) {
        result.add(line);
      }
    }
    return result.join('\n');
  }

  static Future<File> _getRcloneConfigFile() async {
    final home = Platform.environment['HOME']!;
    final dir = Directory('$home/.config/rclone');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('$home/.config/rclone/rclone.conf');
  }
}
