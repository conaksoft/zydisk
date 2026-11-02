import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'models/remote_config.dart';
import 'services/app_settings.dart';
import 'services/daemon_client.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';
import 'ui/mounts_list_window.dart';
import 'ui/tray_menu.dart';
import 'ui/setup_screen.dart';
import 'ui/widgets.dart';

/// İçerik alanının (başlık/durum çubuğu arasındaki) navigator'ı; menü çubuğundan ekran açmak için.
final contentNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(760, 680),
    minimumSize: Size(620, 520),
    center: true,
    title: 'ZyDisk',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
    backgroundColor: AppTheme.bg,
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionManager()),
        ChangeNotifierProvider(create: (_) => AppSettings()),
      ],
      child: const ZyDiskApp(),
    ),
  );
}

Future<String?> promptPasswordFromAnywhere(RemoteConfig config, {String? reason}) async {
  final ctx = contentNavigatorKey.currentContext;
  if (ctx == null) return null;
  await windowManager.show();
  await windowManager.focus();
  if (!ctx.mounted) return null;
  return promptForPassword(ctx, config, reason: reason);
}

class ZyDiskApp extends StatefulWidget {
  const ZyDiskApp({super.key});

  @override
  State<ZyDiskApp> createState() => _ZyDiskAppState();
}

class _ZyDiskAppState extends State<ZyDiskApp> with WindowListener {
  TrayMenuManager? _trayMenu;
  bool _isSetupComplete = false;
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    DaemonClient.channel.setMethodCallHandler((call) async {
      if (call.method == 'quitRequested') await _quit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray());
  }

  Future<void> _initTray() async {
    final session = context.read<SessionManager>();
    _trayMenu = TrayMenuManager(
      session: session,
      onOpenWindow: _showWindow,
      onAddRemote: () async {
        await _showWindow();
        final ctx = contentNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) openAddRemote(ctx);
      },
      onQuit: _quit,
      onPasswordRequested: promptPasswordFromAnywhere,
    );
    await _trayMenu!.init();
    session.addListener(() => _trayMenu?.refresh());
  }

  Future<void> _onSetupComplete() async {
    setState(() => _isSetupComplete = true);
    final settings = context.read<AppSettings>();
    final session = context.read<SessionManager>();
    await settings.load();
    session.cleanAppleDouble = settings.cleanAppleDouble;
    await session.load(onPasswordRequested: promptPasswordFromAnywhere);
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    final settings = context.read<AppSettings>();
    final session = context.read<SessionManager>();
    if (settings.unmountOnQuit && session.mountedCount > 0) {
      setState(() {});
      await session.disposeAll();
    }
    await DaemonClient.channel.invokeMethod('quitNow');
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _trayMenu?.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Kapat düğmesi uygulamayı sonlandırmaz; menü çubuğunda çalışmaya devam eder.
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZyDisk',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: Stack(
        children: [
          _isSetupComplete ? const _MainWindow() : SetupScreen(onComplete: _onSetupComplete),
          if (_quitting) const _QuitOverlay(),
        ],
      ),
    );
  }
}

class _QuitOverlay extends StatelessWidget {
  const _QuitOverlay();

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<SessionManager>().pendingUploadsTotal;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Material(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 14),
                  Text('Sürücüler güvenle ayrılıyor…', style: AppTheme.text(14, weight: FontWeight.w600)),
                  if (pending > 0) ...[
                    const SizedBox(height: 4),
                    Text('$pending dosyanın yüklemesi bekleniyor',
                        style: AppTheme.text(12, color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainWindow extends StatelessWidget {
  const _MainWindow();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          const _TitleBar(),
          Expanded(
            child: Navigator(
              key: contentNavigatorKey,
              onGenerateRoute: (settings) => PageRouteBuilder(
                pageBuilder: (_, _, _) => const MountsListWindow(),
              ),
            ),
          ),
          const _StatusBar(),
        ],
      ),
    );
  }
}

/// Yerel macOS trafik ışıkları için boşluk bırakan, sürüklenebilir başlık çubuğu.
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: SizedBox(
        height: 38,
        child: Center(
          child: Text('ZyDisk', style: AppTheme.text(12, weight: FontWeight.w600, color: AppTheme.textMuted)),
        ),
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  const _StatusBar();

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    final mounted = session.mountedCount;
    final pending = session.pendingUploadsTotal;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: mounted > 0 ? AppTheme.success : AppTheme.unmounted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            mounted > 0 ? '$mounted sürücü bağlı' : 'Bağlı sürücü yok',
            style: AppTheme.text(11, color: AppTheme.textMuted),
          ),
          if (pending > 0) ...[
            const SizedBox(width: 12),
            const Icon(Icons.arrow_upward_rounded, size: 11, color: AppTheme.accent),
            const SizedBox(width: 3),
            Text('$pending dosya yükleniyor', style: AppTheme.text(11, color: AppTheme.accent)),
          ],
          const Spacer(),
          _link('conaksoft.com', 'https://conaksoft.com'),
          const SizedBox(width: 14),
          _link('$_version · Güncellemeler', 'https://github.com/conaksoft/zydisk/releases'),
        ],
      ),
    );
  }

  Widget _link(String label, String url) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Text(label, style: AppTheme.text(11, color: AppTheme.textSecondary)),
      ),
    );
  }
}
