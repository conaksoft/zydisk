import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import 'keychain_service.dart';
import 'mounter.dart';

class SessionManager extends ChangeNotifier {
  static const _prefsKey = 'remotes';

  List<RemoteConfig> _remotes = [];
  final Map<String, bool> _loadingStates = {};
  final Map<String, String?> _errors = {};

  List<RemoteConfig> get remotes => List.unmodifiable(_remotes);

  bool isLoading(String id) => _loadingStates[id] ?? false;
  String? getError(String id) => _errors[id];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    _remotes = raw
        .map((s) => RemoteConfig.fromJson(json.decode(s) as Map<String, dynamic>))
        .toList();

    // Refresh mount status
    for (final r in _remotes) {
      r.isMounted = await Mounter.isMounted(r);
    }
    notifyListeners();
  }

  Future<void> addRemote(RemoteConfig config, {String? password}) async {
    if (password != null && password.isNotEmpty) {
      await KeychainService.savePassword(config.id, password);
    }
    _remotes.add(config);
    await _save();
    notifyListeners();
  }

  Future<void> updateRemote(RemoteConfig config, {String? password}) async {
    if (password != null && password.isNotEmpty) {
      await KeychainService.savePassword(config.id, password);
    }
    final idx = _remotes.indexWhere((r) => r.id == config.id);
    if (idx >= 0) {
      _remotes[idx] = config;
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteRemote(RemoteConfig config) async {
    if (config.isMounted) {
      await Mounter.unmount(config);
    }
    await KeychainService.deletePassword(config.id);
    _remotes.removeWhere((r) => r.id == config.id);
    await _save();
    notifyListeners();
  }

  Future<void> toggleMount(RemoteConfig config, {Future<String?> Function()? onPasswordRequested}) async {
    _loadingStates[config.id] = true;
    _errors[config.id] = null;
    notifyListeners();

    try {
      if (config.isMounted) {
        final ok = await Mounter.unmount(config);
        if (ok) {
          _updateMountState(config.id, false, null);
        } else {
          _errors[config.id] = 'Unmount failed';
        }
      } else {
        if (config.authMethod == AuthMethod.password) {
          String? pwd = await KeychainService.getPassword(config.id);
          if (pwd == null || pwd.isEmpty) {
            if (onPasswordRequested != null) {
              pwd = await onPasswordRequested();
              if (pwd != null && pwd.isNotEmpty) {
                await KeychainService.savePassword(config.id, pwd);
              } else {
                throw Exception('Password required to mount.');
              }
            } else {
              throw Exception('Password missing.');
            }
          }
        }

        final result = await Mounter.mount(config);
        if (result.success) {
          _updateMountState(config.id, true, result.mountPoint);
        } else {
          _errors[config.id] = result.error ?? 'Mount failed';
        }
      }
    } catch (e) {
      _errors[config.id] = e.toString();
    } finally {
      _loadingStates[config.id] = false;
      notifyListeners();
    }
  }

  void _updateMountState(String id, bool mounted, String? mountPoint) {
    final idx = _remotes.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _remotes[idx] = _remotes[idx].copyWith(
        isMounted: mounted,
        mountPoint: mountPoint,
      );
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _remotes.map((r) => json.encode(r.toJson())).toList();
    await prefs.setStringList(_prefsKey, raw);
  }

  Future<void> disposeAll() async {
    await Mounter.unmountAll();
  }

  Future<void> exportToFile(String path) async {
    final raw = _remotes.map((r) => r.toJson()).toList();
    final file = File(path);
    await file.writeAsString(json.encode(raw), mode: FileMode.write);
  }

  Future<void> importFromFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final contents = await file.readAsString();
      final List<dynamic> raw = json.decode(contents);
      
      for (var item in raw) {
        final r = RemoteConfig.fromJson(item as Map<String, dynamic>);
        final existingIndex = _remotes.indexWhere((existing) => existing.id == r.id);
        if (existingIndex >= 0) {
          _remotes[existingIndex] = r;
        } else {
          _remotes.add(r);
        }
      }
      await _save();
      notifyListeners();
    } catch (e) {
      debugPrint("Import failed: $e");
    }
  }
}
