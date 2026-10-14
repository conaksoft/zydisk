import 'package:tray_manager/tray_manager.dart';
import '../models/remote_config.dart';
import '../services/session_manager.dart';

/// Menü çubuğu simgesi: sürücüleri pencere açmadan bağlayıp ayırmayı sağlar.
class TrayMenuManager with TrayListener {
  final SessionManager session;
  final Future<void> Function() onOpenWindow;
  final Future<void> Function() onAddRemote;
  final Future<void> Function() onQuit;
  final PasswordPrompt onPasswordRequested;

  TrayMenuManager({
    required this.session,
    required this.onOpenWindow,
    required this.onAddRemote,
    required this.onQuit,
    required this.onPasswordRequested,
  });

  String _lastSignature = '';

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/icons/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('ZyDisk');
    await _rebuildMenu(force: true);
  }

  Future<void> _rebuildMenu({bool force = false}) async {
    final remotes = session.remotes;
    // Yalnızca menüde görünen bilgiler değiştiyse yeniden kur (istatistik güncellemeleri sık gelir).
    final signature = [
      for (final r in remotes) '${r.id}:${r.name}:${r.isMounted}:${session.isLoading(r.id)}',
      'p${session.pendingUploadsTotal > 0}',
    ].join('|');
    if (!force && signature == _lastSignature) return;
    _lastSignature = signature;

    final items = <MenuItem>[];
    final mounted = remotes.where((r) => r.isMounted).length;

    items.add(MenuItem(
      key: 'title',
      label: mounted > 0 ? 'ZyDisk — $mounted sürücü bağlı' : 'ZyDisk',
      disabled: true,
    ));
    if (session.pendingUploadsTotal > 0) {
      items.add(MenuItem(key: 'uploads', label: '↑ ${session.pendingUploadsTotal} dosya yükleniyor', disabled: true));
    }
    items.add(MenuItem.separator());

    if (remotes.isEmpty) {
      items.add(MenuItem(key: 'no_remotes', label: 'Henüz bağlantı yok', disabled: true));
    } else {
      for (final r in remotes) {
        final loading = session.isLoading(r.id);
        items.add(MenuItem.checkbox(
          key: 'remote_${r.id}',
          label: loading ? '${r.name}  (${session.busyLabel(r.id)})' : '${r.name}  ·  ${r.type.label}',
          checked: r.isMounted,
          disabled: loading,
        ));
      }
      if (mounted > 0) {
        items.add(MenuItem.separator());
        items.add(MenuItem(key: 'unmount_all', label: 'Tümünü Ayır'));
      }
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'open_window', label: 'ZyDisk\'i Aç'));
    items.add(MenuItem(key: 'add_remote', label: 'Yeni Bağlantı…'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'quit', label: 'ZyDisk\'ten Çık'));

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    switch (key) {
      case 'open_window':
        onOpenWindow();
        break;
      case 'add_remote':
        onAddRemote();
        break;
      case 'unmount_all':
        for (final r in session.remotes.where((r) => r.isMounted)) {
          session.unmount(r);
        }
        break;
      case 'quit':
        onQuit();
        break;
      default:
        if (key.startsWith('remote_')) {
          final id = key.substring('remote_'.length);
          final r = session.remotes.where((r) => r.id == id).firstOrNull;
          if (r != null) _toggle(r);
        }
    }
  }

  void _toggle(RemoteConfig r) {
    session.toggleMount(r, onPasswordRequested: onPasswordRequested);
  }

  Future<void> refresh() => _rebuildMenu();

  void dispose() {
    trayManager.removeListener(this);
  }
}
