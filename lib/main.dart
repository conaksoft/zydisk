import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'services/session_manager.dart';
import 'theme/app_theme.dart';
import 'ui/mounts_list_window.dart';
import 'ui/tray_menu.dart';
import 'ui/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Window setup
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(720, 700),
    minimumSize: Size(620, 550),
    center: true,
    title: 'ZyDisk',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    backgroundColor: Color(0xFF0D1117),
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(true);
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionManager(),
      child: const ZyDiskApp(),
    ),
  );
}

class ZyDiskApp extends StatefulWidget {
  const ZyDiskApp({super.key});

  @override
  State<ZyDiskApp> createState() => _ZyDiskAppState();
}

class _ZyDiskAppState extends State<ZyDiskApp> with WindowListener {
  TrayMenuManager? _trayMenu;
  bool _isSetupComplete = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final session = context.read<SessionManager>();
    await session.load();

    // Init tray
    _trayMenu = TrayMenuManager(context);
    await _trayMenu!.init();

    // Refresh tray when session changes
    session.addListener(() => _trayMenu?.refresh());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _trayMenu?.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Hide to tray instead of quit
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZyDisk',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: _isSetupComplete
          ? const _MainWindow()
          : SetupScreen(
              onComplete: () {
                setState(() {
                  _isSetupComplete = true;
                });
              },
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
          // Custom title bar
          _TitleBar(),
          // Main content
          Expanded(
            child: Navigator(
              onGenerateRoute: (settings) {
                return PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const MountsListWindow(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                );
              },
            ),
          ),
          // Status bar
          _StatusBar(),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        windowManager.startDragging();
      },
      child: Container(
        height: 44,
        decoration: const BoxDecoration(
          color: AppTheme.bg,
          border: Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            // Traffic light buttons
            _WindowButton(
              color: const Color(0xFFFF5F57),
              hoverIcon: Icons.close_rounded,
              onTap: () => windowManager.hide(),
            ),
            const SizedBox(width: 8),
            _WindowButton(
              color: const Color(0xFFFFBD2E),
              hoverIcon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
            ),
            const SizedBox(width: 8),
            _WindowButton(
              color: const Color(0xFF28C840),
              hoverIcon: Icons.fullscreen_rounded,
              onTap: () => windowManager.maximize(),
            ),
            const Spacer(),
            Text(
              'ZyDisk',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMuted,
              ),
            ),
            const Spacer(),
            SizedBox(width: 16 + 3 * 20.0 + 16),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final Color color;
  final IconData hoverIcon;
  final VoidCallback onTap;

  const _WindowButton({
    required this.color,
    required this.hoverIcon,
    required this.onTap,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: _hovered
              ? Icon(widget.hoverIcon, size: 9, color: Colors.black54)
              : null,
        ),
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  String _version = 'v1.0.0';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = 'v${info.version}';
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (_, session, __) {
        final mounted = session.remotes.where((r) => r.isMounted).length;
        final total = session.remotes.length;

        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: mounted > 0 ? AppTheme.mounted : AppTheme.unmounted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                mounted > 0
                    ? '$mounted/$total mounted'
                    : total > 0
                    ? '$total remotes, none mounted'
                    : 'No remotes',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
              const Spacer(),
              // Website Link
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => launchUrl(Uri.parse('https://conaksoft.com')),
                  child: Text(
                    'conaksoft.com',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Version & Updates Link
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://github.com/shibware/zydisk/releases'),
                  ),
                  child: Text(
                    '$_version (Check Updates)',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
