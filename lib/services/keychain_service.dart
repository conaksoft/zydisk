import 'dart:io';

/// macOS Keychain entegrasyon servisi.
/// flutter_secure_storage yerine doğrudan macOS 'security' CLI kullanır
/// — debug modda code signing gerektirmez.
class KeychainService {
  static const _service = 'com.zydisk.app';

  static Future<void> savePassword(String remoteId, String password) async {
    // Parola komut satırı argümanı olarak verilirse `ps` ile görülebilir; bu yüzden
    // `security -i` etkileşimli kipine stdin üzerinden gönderilir.
    final p = await Process.start('security', ['-i']);
    p.stdin.writeln(
      'add-generic-password -U -s ${_quote(_service)} -a ${_quote(remoteId)} -w ${_quote(password)}',
    );
    await p.stdin.close();
    await p.stdout.drain<void>();
    await p.stderr.drain<void>();
    final code = await p.exitCode;
    if (code != 0) {
      throw Exception('Parola anahtar zincirine kaydedilemedi ($code)');
    }
  }

  static String _quote(String value) {
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  static Future<String?> getPassword(String remoteId) async {
    var result = await Process.run('security', [
      'find-generic-password',
      '-s', _service,
      '-a', remoteId,
      '-w', // just print password
    ]);
    
    if (result.exitCode != 0) {
      // Geriye dönük uyumluluk (DevulusDrive -> ZyDisk geçişi)
      result = await Process.run('security', [
        'find-generic-password',
        '-s', 'com.devulusdrive.app',
        '-a', remoteId,
        '-w', 
      ]);
      
      if (result.exitCode != 0) return null;
      
      // Eski serviste bulundu, yeniye taşıyalım
      final pw = (result.stdout as String).trim();
      if (pw.isNotEmpty) {
        await savePassword(remoteId, pw);
        return pw;
      }
      return null;
    }
    
    final pw = (result.stdout as String).trim();
    return pw.isEmpty ? null : pw;
  }

  static Future<void> deletePassword(String remoteId) async {
    await _deleteEntry(remoteId);
  }

  static Future<void> _deleteEntry(String remoteId) async {
    await Process.run('security', [
      'delete-generic-password',
      '-s', _service,
      '-a', remoteId,
    ]);
    // Exit code non-zero if not found — OK to ignore
  }
}
