import 'dart:io';

import 'mounter.dart';

class SetupService {
  static Future<void> ensureRcloneInstalled(Function(String, double?) onProgress) async {
    final rcloneFile = File(Mounter.rcloneBin);
    if (await rcloneFile.exists()) {
      return; // Already installed
    }

    onProgress('Sistem mimarisi kontrol ediliyor...', null);
    
    // Detect architecture
    final uname = await Process.run('uname', ['-m']);
    final arch = (uname.stdout as String).trim();
    
    final isArm = arch == 'arm64' || arch == 'aarch64';
    final url = isArm 
        ? 'https://downloads.rclone.org/rclone-current-osx-arm64.zip'
        : 'https://downloads.rclone.org/rclone-current-osx-amd64.zip';
        
    final tempZip = '/tmp/rclone.zip';
    final tempExtract = '/tmp/rclone_extract';
    
    onProgress('rclone indiriliyor...', 0.0);
    
    // Download using HttpClient
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      final contentLength = response.contentLength;
      int downloaded = 0;
      
      final file = File(tempZip);
      final sink = file.openWrite();
      
      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress('rclone indiriliyor...', downloaded / contentLength);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }
    
    onProgress('Dosyalar çıkartılıyor...', null);
    
    // Clean and create extract dir
    final extractDir = Directory(tempExtract);
    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);
    
    // Unzip
    await Process.run('unzip', ['-o', tempZip, '-d', tempExtract]);
    
    onProgress('İzinler ayarlanıyor...', null);
    
    // Find the binary inside the extracted folder
    final entities = await extractDir.list(recursive: true).toList();
    File? binaryFile;
    
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('/rclone') && !entity.path.contains('__MACOSX')) {
        binaryFile = entity;
        break;
      }
    }
    
    if (binaryFile == null) {
      throw Exception('İndirilen zip dosyasında rclone bulunamadı.');
    }
    
    // Ensure bin folder exists
    final binDir = rcloneFile.parent;
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    
    // Move binary
    if (await rcloneFile.exists()) {
      await rcloneFile.delete();
    }
    await binaryFile.copy(rcloneFile.path);
    
    // Set executable and remove quarantine
    await Process.run('chmod', ['+x', rcloneFile.path]);
    await Process.run('xattr', ['-d', 'com.apple.quarantine', rcloneFile.path]);
    
    // Cleanup
    try {
      await File(tempZip).delete();
      await Directory(tempExtract).delete(recursive: true);
    } catch (_) {}
    
    onProgress('Kurulum tamamlandı.', 1.0);
  }
}
