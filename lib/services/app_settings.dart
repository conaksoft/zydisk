import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'daemon_client.dart';

/// Kullanıcı tercihleri.
class AppSettings extends ChangeNotifier {
  static const _kUnmountOnQuit = 'unmountOnQuit';
  static const _kCleanAppleDouble = 'cleanAppleDouble';
  static const _kRequireAuth = 'requireAuthForSecrets';

  bool unmountOnQuit = true;
  bool cleanAppleDouble = true;
  bool requireAuthForSecrets = true;
  bool launchAtLogin = false;
  bool biometryAvailable = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    unmountOnQuit = p.getBool(_kUnmountOnQuit) ?? true;
    cleanAppleDouble = p.getBool(_kCleanAppleDouble) ?? true;
    requireAuthForSecrets = p.getBool(_kRequireAuth) ?? true;
    try {
      launchAtLogin = await DaemonClient.channel.invokeMethod<bool>('getLaunchAtLogin') ?? false;
      biometryAvailable = await DaemonClient.channel.invokeMethod<bool>('biometryAvailable') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setUnmountOnQuit(bool v) async {
    unmountOnQuit = v;
    await (await SharedPreferences.getInstance()).setBool(_kUnmountOnQuit, v);
    notifyListeners();
  }

  Future<void> setCleanAppleDouble(bool v) async {
    cleanAppleDouble = v;
    await (await SharedPreferences.getInstance()).setBool(_kCleanAppleDouble, v);
    notifyListeners();
  }

  Future<void> setRequireAuthForSecrets(bool v) async {
    requireAuthForSecrets = v;
    await (await SharedPreferences.getInstance()).setBool(_kRequireAuth, v);
    notifyListeners();
  }

  /// Hata olursa mesajı döndürür.
  Future<String?> setLaunchAtLogin(bool v) async {
    try {
      launchAtLogin = await DaemonClient.channel.invokeMethod<bool>('setLaunchAtLogin', {'enabled': v}) ?? false;
      notifyListeners();
      return null;
    } catch (e) {
      notifyListeners();
      return e.toString();
    }
  }

  /// Touch ID (yoksa Mac parolası) ile doğrulama. Ayar kapalıysa doğrudan izin verir.
  Future<bool> authenticate(String reason, {bool force = false}) async {
    if (!requireAuthForSecrets && !force) return true;
    try {
      return await DaemonClient.channel.invokeMethod<bool>('authenticate', {'reason': reason}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
