import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_settings.dart';
import '../services/daemon_client.dart';
import '../services/keychain_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

class SettingsWindow extends StatefulWidget {
  const SettingsWindow({super.key});

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  String? _installed;
  String _bundled = '';
  bool _checking = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _checkService();
  }

  Future<void> _checkService() async {
    setState(() => _checking = true);
    final installed = await DaemonClient.installedVersion();
    final bundled = await DaemonClient.bundledVersion();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _bundled = bundled;
      _checking = false;
    });
  }

  Future<void> _installService() async {
    setState(() => _working = true);
    final ok = await DaemonClient.ensureReady();
    if (!mounted) return;
    setState(() => _working = false);
    showToast(context, ok ? 'Arka plan servisi hazır.' : 'Servis kurulamadı veya onay verilmedi.', error: !ok);
    _checkService();
  }

  Future<void> _uninstallService() async {
    final session = context.read<SessionManager>();
    if (session.mountedCount > 0) {
      showToast(context, 'Önce tüm sürücüleri ayırın.', error: true);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Servisi kaldır',
      message: 'Arka plan servisi kaldırılırsa sürücüleri tekrar bağlamak için yeniden yönetici onayı gerekir.',
      confirmLabel: 'Kaldır',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _working = true);
    final done = await DaemonClient.uninstall();
    if (!mounted) return;
    setState(() => _working = false);
    showToast(context, done ? 'Servis kaldırıldı.' : 'Servis kaldırılamadı.', error: !done);
    await Future.delayed(const Duration(seconds: 1));
    _checkService();
  }

  Future<void> _import() async {
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) return;
    try {
      final n = await context.read<SessionManager>().importFromFile(file.path);
      if (mounted) showToast(context, '$n bağlantı içe aktarıldı. Parolalar dosyada yer almaz; ilk bağlanışta sorulur.');
    } catch (e) {
      if (mounted) showToast(context, 'İçe aktarılamadı: $e', error: true);
    }
  }

  Future<void> _export() async {
    final location = await getSaveLocation(suggestedName: 'zydisk-baglantilar.json');
    if (location == null || !mounted) return;
    await context.read<SessionManager>().exportToFile(location.path);
    if (mounted) showToast(context, 'Dışa aktarıldı (parolalar hariç).');
  }

  Future<void> _reset() async {
    final settings = context.read<AppSettings>();
    final session = context.read<SessionManager>();
    final ok = await confirmDialog(
      context,
      title: 'ZyDisk\'i sıfırla',
      message: 'Tüm sürücüler ayrılacak; bağlantılar, kayıtlı parolalar, ayarlar ve önbellekler silinecek ve '
          'uygulama kapanacak. Sunucudaki dosyalarınız etkilenmez.',
      confirmLabel: 'Sıfırla ve Kapat',
      destructive: true,
    );
    if (!ok) return;
    if (!await settings.authenticate('tüm ZyDisk verilerini silmek', force: true)) return;

    setState(() => _working = true);
    try {
      await session.disposeAll();
      final names = session.remotes.map((r) => r.rcloneName).toList();
      for (final r in session.remotes) {
        await KeychainService.deletePassword(r.id);
      }
      await (await SharedPreferences.getInstance()).clear();
      final support = await getApplicationSupportDirectory();
      if (await support.exists()) await support.delete(recursive: true);
      // Yalnızca ZyDisk'e ait rclone önbelleklerini sil; kullanıcının kendi rclone ayarlarına dokunma.
      final home = Platform.environment['HOME'] ?? '';
      // rclone, ortam değişkeniyle tanımlanan uzakların önbellek klasörünü "zd123{hash}" olarak adlandırır.
      for (final sub in ['vfs', 'vfsMeta']) {
        final dir = Directory('$home/Library/Caches/rclone/$sub');
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          final base = entry.path.split('/').last;
          if (names.any((n) => base == n || base.startsWith('$n{'))) {
            await entry.delete(recursive: true);
          }
        }
      }
      await DaemonClient.channel.invokeMethod('quitNow');
    } catch (e) {
      if (mounted) {
        setState(() => _working = false);
        showToast(context, 'Sıfırlama başarısız: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 24, 8),
                child: Row(
                  children: [
                    GhostIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Geri (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text('Ayarlar', style: AppTheme.text(18, weight: FontWeight.w700)),
                    const Spacer(),
                    if (_working) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    _Group(title: 'Arka Plan Servisi', children: [_serviceTile()]),
                    _Group(title: 'Genel', children: [
                      _SwitchTile(
                        icon: Icons.login_rounded,
                        title: 'Oturum açılışında başlat',
                        subtitle: 'ZyDisk Mac açıldığında menü çubuğunda başlar; otomatik sürücüler bağlanır.',
                        value: settings.launchAtLogin,
                        onChanged: (v) async {
                          final err = await settings.setLaunchAtLogin(v);
                          if (err != null && context.mounted) showToast(context, err, error: true);
                        },
                      ),
                      _SwitchTile(
                        icon: Icons.eject_rounded,
                        title: 'Çıkarken sürücüleri ayır',
                        subtitle: 'Kapalıysa ZyDisk kapansa da sürücüler bağlı kalır ve sonraki açılışta devralınır.',
                        value: settings.unmountOnQuit,
                        onChanged: settings.setUnmountOnQuit,
                      ),
                    ]),
                    _Group(title: 'Dosyalar', children: [
                      _SwitchTile(
                        icon: Icons.cleaning_services_rounded,
                        title: '._ ve .DS_Store dosyalarını sunucuya bırakma',
                        subtitle: 'macOS, NFS üzerinde dosya özniteliklerini ._dosya olarak yazar. ZyDisk bunları '
                            'yüklendikleri anda sunucudan siler.',
                        value: settings.cleanAppleDouble,
                        onChanged: (v) {
                          settings.setCleanAppleDouble(v);
                          context.read<SessionManager>().cleanAppleDouble = v;
                        },
                      ),
                    ]),
                    _Group(title: 'Güvenlik', children: [
                      _SwitchTile(
                        icon: Icons.fingerprint_rounded,
                        title: settings.biometryAvailable ? 'Hassas işlemlerde Touch ID iste' : 'Hassas işlemlerde parola iste',
                        subtitle: settings.biometryAvailable
                            ? 'Kayıtlı parolayı gösterme ve sıfırlama Touch ID ile onaylanır; Touch ID yoksa Mac parolanız sorulur.'
                            : 'Bu Mac\'te Touch ID yok; onay için Mac parolanız sorulur.',
                        value: settings.requireAuthForSecrets,
                        onChanged: (v) async {
                          // Kapatmak için de doğrulama iste.
                          if (!v && !await settings.authenticate('güvenlik ayarını değiştirmek', force: true)) return;
                          settings.setRequireAuthForSecrets(v);
                        },
                      ),
                    ]),
                    _Group(title: 'Veriler', children: [
                      _ActionTile(
                        icon: Icons.file_download_outlined,
                        title: 'Bağlantıları içe aktar',
                        onTap: _import,
                      ),
                      _ActionTile(
                        icon: Icons.file_upload_outlined,
                        title: 'Bağlantıları dışa aktar',
                        subtitle: 'Parolalar dosyaya yazılmaz.',
                        onTap: _export,
                      ),
                      _ActionTile(
                        icon: Icons.restart_alt_rounded,
                        title: 'ZyDisk\'i sıfırla',
                        subtitle: 'Bağlantılar, parolalar, ayarlar ve önbellekler silinir.',
                        color: AppTheme.danger,
                        onTap: _working ? null : _reset,
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceTile() {
    final upToDate = _installed != null && _installed == _bundled;
    final Color color;
    final String status;
    if (_checking) {
      color = AppTheme.textMuted;
      status = 'Kontrol ediliyor…';
    } else if (upToDate) {
      color = AppTheme.success;
      status = 'Çalışıyor · v$_installed';
    } else if (_installed != null) {
      color = AppTheme.warning;
      status = 'Güncelleme gerekli (v$_installed → v$_bundled)';
    } else {
      color = AppTheme.warning;
      status = 'Kurulu değil veya eski sürüm';
    }

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(status, style: AppTheme.text(13, weight: FontWeight.w600)),
              const Spacer(),
              if (!upToDate && !_checking)
                ElevatedButton(onPressed: _working ? null : _installService, child: const Text('Kur / Güncelle'))
              else if (!_checking)
                TextButton(onPressed: _working ? null : _uninstallService, child: const Text('Kaldır')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sürücüleri bağlamak macOS\'ta yönetici yetkisi gerektirir. Bu servis bir kez kurulduktan sonra bağlama ve '
            'ayırma işlemleri hiçbir zaman parola sormaz. Kurulum onayı macOS tarafından gösterilir; Apple, üçüncü '
            'parti uygulamaların yönetici onayında Touch ID kullanmasına izin vermediği için bu tek seferlik adımda '
            'parola istenir.',
            style: AppTheme.text(12, color: AppTheme.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title.toUpperCase(),
                style: AppTheme.text(11, weight: FontWeight.w600, color: AppTheme.textMuted).copyWith(letterSpacing: 0.8)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.text(13, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.text(12, color: AppTheme.textMuted, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Transform.scale(scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback? onTap;

  const _ActionTile({required this.icon, required this.title, this.subtitle, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.text(13, weight: FontWeight.w500, color: c)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppTheme.text(12, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
