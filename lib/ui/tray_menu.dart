import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import '../models/remote_config.dart';
import '../services/session_manager.dart';

class TrayMenuManager with TrayListener {
  final BuildContext rootContext;

  TrayMenuManager(this.rootContext);

  Future<void> init() async {
    trayManager.addListener(this);

    // Set macOS menu bar icon
    await trayManager.setIcon(
      'assets/icons/tray_icon.png',
      isTemplate: true, // Auto-adapts to dark/light mode
    );
    await trayManager.setToolTip('ZyDisk');
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    final session = rootContext.read<SessionManager>();
    final remotes = session.remotes;

    final items = <MenuItem>[];

    // App title
    items.add(MenuItem(
      key: 'title',
      label: 'ZyDisk',
      disabled: true,
    ));
    items.add(MenuItem.separator());

    // Remotes
    if (remotes.isEmpty) {
      items.add(MenuItem(
        key: 'no_remotes',
        label: '  No remotes configured',
        disabled: true,
      ));
    } else {
      for (final r in remotes) {
        final status = r.isMounted ? '● ' : '○ ';
        items.add(MenuItem(
          key: 'remote_${r.id}',
          label: '$status${r.name}  (${r.type.label})',
        ));
      }
    }

    items.add(MenuItem.separator());
    items.add(MenuItem(
      key: 'open_window',
      label: 'Open ZyDisk...',
    ));
    items.add(MenuItem(key: 'add_remote', label: 'Add Remote...'));
    items.add(MenuItem.separator());
    items.add(MenuItem(key: 'quit', label: 'Quit'));

    final menu = Menu(items: items);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_window':
        _showWindow();
        break;
      case 'add_remote':
        _showWindow();
        break;
      case 'quit':
        _quit();
        break;
      default:
        if (menuItem.key?.startsWith('remote_') == true) {
          _showWindow();
        }
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    final session = rootContext.read<SessionManager>();
    await session.disposeAll();
    await windowManager.destroy();
  }

  Future<void> refresh() async {
    await _rebuildMenu();
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
