import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Root yetkili yardımcı servisle (ZyDiskDaemon) konuşur.
///
/// Servis bir kez kurulduktan sonra bağlama/ayırma işlemleri hiçbir zaman parola sormaz.
/// Uygulama güncellendiğinde servis, imzası doğrulanarak kendini günceller; yalnızca ilk kurulumda
/// (veya ad-hoc imzalı geliştirme derlemelerinde sürüm değiştiğinde) macOS yönetici onayı ister.
class DaemonClient {
  static const MethodChannel channel = MethodChannel('com.conaksoft.zydisk/daemon');
  static const _label = 'com.conaksoft.zydisk.daemon';

  static Future<bool>? _ensuring;

  /// Kurulu servisin sürümü; servis yoksa veya eski protokoldeyse null.
  static Future<String?> installedVersion() async {
    try {
      return await channel.invokeMethod<String>('daemonVersion');
    } catch (_) {
      return null;
    }
  }

  static Future<String> bundledVersion() async {
    return await channel.invokeMethod<String>('bundledDaemonVersion') ?? '';
  }

  /// Servisin çalışır ve güncel olduğundan emin olur. Aynı anda birden fazla çağrı tek bir
  /// kurulum isteğine birleştirilir (art arda parola penceresi açılmaz).
  static Future<bool> ensureReady({bool allowPrompt = true}) {
    return _ensuring ??= _ensureReady(allowPrompt).whenComplete(() => _ensuring = null);
  }

  static Future<bool> _ensureReady(bool allowPrompt) async {
    final bundled = await bundledVersion();
    final current = await installedVersion();
    if (current == bundled) return true;

    if (current != null) {
      // Yeni protokolü konuşan ama eski sürüm bir servis: parolasız kendini güncellemeyi dene.
      try {
        await channel.invokeMethod('updateDaemon');
        if (await _waitForVersion(bundled)) return true;
      } on PlatformException catch (e) {
        debugPrint('Servis kendini güncelleyemedi: ${e.message}');
      }
    }

    if (!allowPrompt) return false;
    final installed = await install();
    if (!installed) return false;
    return _waitForVersion(bundled);
  }

  static Future<bool> _waitForVersion(String expected) async {
    for (var i = 0; i < 20; i++) {
      if (await installedVersion() == expected) return true;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// Servisi /Library altına kurar. macOS bu işlem için tek seferlik yönetici onayı ister.
  static Future<bool> install() async {
    final contentsDir = File(Platform.resolvedExecutable).parent.parent.path;
    final daemonBinary = '$contentsDir/MacOS/ZyDiskDaemon';
    if (!await File(daemonBinary).exists()) {
      debugPrint('Daemon ikilisi bulunamadı: $daemonBinary');
      return false;
    }

    const script = r'''
set -e
SRC="$1"
LABEL=com.conaksoft.zydisk.daemon
DST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
/bin/launchctl bootout system/$LABEL >/dev/null 2>&1 || true
/bin/mkdir -p /Library/PrivilegedHelperTools
/bin/rm -f /Library/PrivilegedHelperTools/ZyDiskDaemon
/bin/cp -f "$SRC" "$DST.new"
/usr/sbin/chown root:wheel "$DST.new"
/bin/chmod 755 "$DST.new"
/bin/mv -f "$DST.new" "$DST"
/bin/cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DST</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>$LABEL</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.conaksoft.zydisk</string>
    </array>
</dict>
</plist>
EOF
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
for i in 1 2 3 4 5; do
  /bin/launchctl bootstrap system "$PLIST" >/dev/null 2>&1 && exit 0
  sleep 1
done
/bin/launchctl load -w "$PLIST"
''';

    const prompt = 'ZyDisk, sürücüleri parola sormadan bağlayıp ayırabilmek için '
        'arka plan servisini kuracak. Bu onay yalnızca bir kez istenir.';

    // Değişkenler AppleScript'e argv ile ve `quoted form of` kullanılarak aktarılır; kabuk enjeksiyonu yok.
    final result = await Process.run('osascript', [
      '-e', 'on run argv',
      '-e', 'do shell script "/bin/sh -c " & quoted form of (item 1 of argv) & " zydisk-install " & '
          'quoted form of (item 2 of argv) with prompt (item 3 of argv) with administrator privileges',
      '-e', 'end run',
      script,
      daemonBinary,
      prompt,
    ]);
    if (result.exitCode != 0) {
      debugPrint('Servis kurulumu başarısız: ${result.stderr}');
      return false;
    }
    return true;
  }

  /// Servisi kaldırır (parola sormaz).
  static Future<bool> uninstall() async {
    try {
      await channel.invokeMethod('uninstallDaemon');
      return true;
    } catch (e) {
      debugPrint('Servis kaldırılamadı: $e');
      return false;
    }
  }

  static Future<bool> isInstalledOnDisk() async {
    return File('/Library/LaunchDaemons/$_label.plist').exists();
  }

  static Future<void> mount({required int port, required String mountPoint}) async {
    await channel.invokeMethod('mount', {'port': port, 'mountPoint': mountPoint});
  }

  static Future<void> unmount({required String mountPoint, bool force = true}) async {
    await channel.invokeMethod('unmount', {'mountPoint': mountPoint, 'force': force});
  }

  /// Servise ulaşılamadığını gösteren hata kodları (kurulum/güncelleme ile düzelir).
  static bool isUnavailableError(Object e) {
    return e is PlatformException && (e.code == 'XPC_ERROR' || e.code == 'TIMEOUT');
  }
}
