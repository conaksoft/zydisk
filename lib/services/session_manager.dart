import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import 'config_builder.dart';
import 'keychain_service.dart';
import 'mounter.dart';

typedef PasswordPrompt = Future<String?> Function(RemoteConfig config, {String? reason});

class SessionManager extends ChangeNotifier {
  static const _prefsKey = 'remotes';

  final Mounter _mounter = Mounter.instance;
  List<RemoteConfig> _remotes = [];
  final Map<String, String> _busy = {}; // id -> "Bağlanıyor…" gibi durum metni
  final Map<String, String?> _errors = {};
  final Map<String, String?> _notices = {};
  bool _loaded = false;

  SessionManager() {
    _mounter.onStateChanged = _onExternalChange;
    _mounter.onStatsChanged = notifyListeners;
  }

  List<RemoteConfig> get remotes => List.unmodifiable(_remotes);
  bool get loaded => _loaded;

  bool isLoading(String id) => _busy.containsKey(id);
  String? busyLabel(String id) => _busy[id];
  String? getError(String id) => _errors[id];
  String? getNotice(String id) => _notices[id];
  TransferStats statsFor(String id) => _mounter.statsFor(id);
  int get pendingUploadsTotal => _mounter.pendingUploadsTotal;
  int get mountedCount => _remotes.where((r) => r.isMounted).length;

  set cleanAppleDouble(bool v) => _mounter.cleanAppleDouble = v;

  Future<void> load({PasswordPrompt? onPasswordRequested}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    _remotes = raw.map((s) => RemoteConfig.fromJson(json.decode(s) as Map<String, dynamic>)).toList();

    // Eski sürümün rclone.conf'a yazdığı parolalı bölümleri temizle.
    try {
      await ConfigBuilder.cleanupLegacyConfig(_remotes);
    } catch (e) {
      debugPrint('Eski rclone yapılandırması temizlenemedi: $e');
    }

    await _mounter.restore(_remotes);
    await _refreshMountFlags();
    _loaded = true;
    notifyListeners();

    for (final r in List.of(_remotes)) {
      if (r.autoMount && !r.isMounted) {
        await toggleMount(r, onPasswordRequested: onPasswordRequested);
      }
    }
  }

  Future<void> _refreshMountFlags() async {
    final points = await Mounter.mountedNfsPoints();
    for (var i = 0; i < _remotes.length; i++) {
      final mp = Mounter.getMountPoint(_remotes[i]);
      final mounted = points.contains(mp);
      _remotes[i] = _remotes[i].copyWith(isMounted: mounted, mountPoint: mounted ? mp : null);
    }
  }

  void _onExternalChange(String id, bool mounted, String? message) {
    final idx = _remotes.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    if (_busy.containsKey(id)) return; // kullanıcı işlemi sürüyor; sonucu o bildirecek
    final r = _remotes[idx];
    if (r.isMounted != mounted) {
      _remotes[idx] = r.copyWith(isMounted: mounted, mountPoint: mounted ? Mounter.getMountPoint(r) : null);
    }
    _errors[id] = message;
    notifyListeners();
  }

  bool isNameTaken(String name, {String? exceptId}) {
    return _remotes.any((r) => r.id != exceptId && r.name.toLowerCase() == name.toLowerCase());
  }

  Future<void> addRemote(RemoteConfig config, {String? password}) async {
    if (password != null && password.isNotEmpty) {
      await KeychainService.savePassword(config.id, password);
    }
    _remotes.add(config);
    _mounter.updateConfig(config);
    await _save();
    notifyListeners();
  }

  /// Bağlıyken bağlantı ayarları değişirse sürücü otomatik olarak yeniden bağlanır.
  Future<void> updateRemote(RemoteConfig config, {String? password, PasswordPrompt? onPasswordRequested}) async {
    final idx = _remotes.indexWhere((r) => r.id == config.id);
    if (idx < 0) return;
    final old = _remotes[idx];

    final connectionChanged = old.name != config.name ||
        old.host != config.host ||
        old.port != config.port ||
        old.user != config.user ||
        old.path != config.path ||
        old.type != config.type ||
        old.authMethod != config.authMethod ||
        old.keyFilePath != config.keyFilePath ||
        (password != null && password.isNotEmpty);

    final wasMounted = old.isMounted;
    if (wasMounted && connectionChanged) {
      _busy[config.id] = 'Yeniden bağlanıyor…';
      notifyListeners();
      await _mounter.unmount(old);
      await _mounter.forget(old);
    }

    if (password != null && password.isNotEmpty) {
      await KeychainService.savePassword(config.id, password);
    }

    _remotes[idx] = config.copyWith(
      isMounted: wasMounted && !connectionChanged,
      mountPoint: wasMounted && !connectionChanged ? old.mountPoint : null,
    );
    _mounter.updateConfig(_remotes[idx]);
    await _save();
    _busy.remove(config.id);
    notifyListeners();

    if (wasMounted && connectionChanged) {
      await toggleMount(_remotes[idx], onPasswordRequested: onPasswordRequested);
    }
  }

  Future<void> setAutoMount(RemoteConfig config, bool value) async {
    final idx = _remotes.indexWhere((r) => r.id == config.id);
    if (idx < 0) return;
    _remotes[idx] = _remotes[idx].copyWith(autoMount: value);
    await _save();
    notifyListeners();
  }

  Future<void> deleteRemote(RemoteConfig config) async {
    _busy[config.id] = 'Siliniyor…';
    notifyListeners();
    final current = _remotes.firstWhere((r) => r.id == config.id, orElse: () => config);
    if (current.isMounted) {
      final res = await _mounter.unmount(current);
      if (!res.success) {
        _busy.remove(config.id);
        _errors[config.id] = 'Silinemedi: ${res.error}';
        notifyListeners();
        return;
      }
    }
    await _mounter.forget(current);
    await KeychainService.deletePassword(config.id);
    _remotes.removeWhere((r) => r.id == config.id);
    _busy.remove(config.id);
    _errors.remove(config.id);
    await _save();
    notifyListeners();
  }

  Future<void> toggleMount(RemoteConfig config, {PasswordPrompt? onPasswordRequested}) async {
    if (_busy.containsKey(config.id)) return; // çift tıklama vb.
    final current = _remotes.firstWhere((r) => r.id == config.id, orElse: () => config);
    if (current.isMounted) {
      await unmount(current);
    } else {
      await mount(current, onPasswordRequested: onPasswordRequested);
    }
  }

  Future<void> mount(RemoteConfig config, {PasswordPrompt? onPasswordRequested}) async {
    _busy[config.id] = 'Bağlanıyor…';
    _errors[config.id] = null;
    _notices[config.id] = null;
    notifyListeners();

    try {
      final needsSecret = config.type == RemoteType.s3 || config.authMethod == AuthMethod.password;
      if (needsSecret) {
        final pwd = await KeychainService.getPassword(config.id);
        if (pwd == null || pwd.isEmpty) {
          final entered = await onPasswordRequested?.call(config);
          if (entered == null || entered.isEmpty) {
            _errors[config.id] = 'Bağlanmak için parola gerekli.';
            return;
          }
          await KeychainService.savePassword(config.id, entered);
        }
      }

      var result = await _mounter.mount(config);

      // Parola yanlışsa bir kez yeni parola sor ve tekrar dene.
      if (!result.success && result.kind == MountErrorKind.auth && needsSecret && onPasswordRequested != null) {
        final entered = await onPasswordRequested(config, reason: result.error);
        if (entered != null && entered.isNotEmpty) {
          await KeychainService.savePassword(config.id, entered);
          _busy[config.id] = 'Bağlanıyor…';
          notifyListeners();
          result = await _mounter.mount(config);
        }
      }

      if (result.success) {
        _setMounted(config.id, true);
      } else {
        _errors[config.id] = result.error ?? 'Bağlama başarısız';
      }
    } catch (e) {
      _errors[config.id] = e.toString();
    } finally {
      _busy.remove(config.id);
      notifyListeners();
    }
  }

  Future<void> unmount(RemoteConfig config) async {
    _busy[config.id] = 'Ayrılıyor…';
    _errors[config.id] = null;
    notifyListeners();
    try {
      final result = await _mounter.unmount(config);
      if (result.success) {
        _setMounted(config.id, false);
        final pending = _mounter.statsFor(config.id).pendingUploads;
        _notices[config.id] = pending > 0 ? '$pending dosyanın yüklemesi arka planda tamamlanıyor.' : null;
      } else {
        _errors[config.id] = result.error;
      }
    } finally {
      _busy.remove(config.id);
      notifyListeners();
    }
  }

  Future<void> refresh(RemoteConfig config) => _mounter.refresh(config);

  Future<String> cleanRemoteJunk(RemoteConfig config) => _mounter.cleanRemoteJunk(config);

  void _setMounted(String id, bool mounted) {
    final idx = _remotes.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      final r = _remotes[idx];
      _remotes[idx] = r.copyWith(isMounted: mounted, mountPoint: mounted ? Mounter.getMountPoint(r) : null);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _remotes.map((r) => json.encode(r.toJson())).toList());
  }

  /// Çıkışta çağrılır: sürücüleri ayırır ve bekleyen yüklemeleri bir süre bekler.
  Future<void> disposeAll() async {
    await _mounter.unmountAll(_remotes);
    await _refreshMountFlags();
    notifyListeners();
  }

  Future<void> exportToFile(String path) async {
    final raw = _remotes.map((r) => r.toJson()).toList();
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(raw));
  }

  /// İçe aktarır; içe aktarılan kayıt sayısını döndürür.
  Future<int> importFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    final List<dynamic> raw = json.decode(await file.readAsString());
    var count = 0;
    for (final item in raw) {
      final r = RemoteConfig.fromJson(item as Map<String, dynamic>);
      final existingIndex = _remotes.indexWhere((e) => e.id == r.id);
      RemoteConfig stored;
      if (existingIndex >= 0) {
        final existing = _remotes[existingIndex];
        if (existing.isMounted) continue; // bağlı bir sürücünün ayarlarını altından değiştirme
        stored = r;
        _remotes[existingIndex] = stored;
      } else {
        var name = r.name;
        var n = 2;
        while (isNameTaken(name)) {
          name = '${r.name}-${n++}';
        }
        stored = r.copyWith(name: name);
        _remotes.add(stored);
      }
      _mounter.updateConfig(stored);
      count++;
    }
    await _save();
    notifyListeners();
    return count;
  }
}
