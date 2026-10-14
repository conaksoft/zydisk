import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/remote_config.dart';
import '../services/mounter.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'add_remote_window.dart';
import 'settings_window.dart';
import 'widgets.dart';

void openAddRemote(BuildContext context, {RemoteConfig? existing}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => AddRemoteWindow(existing: existing),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

void openSettings(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => const SettingsWindow(),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class MountsListWindow extends StatelessWidget {
  const MountsListWindow({super.key});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => openAddRemote(context),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => openSettings(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Consumer<SessionManager>(
            builder: (ctx, session, _) {
              return Column(
                children: [
                  _Header(session: session),
                  Expanded(
                    child: !session.loaded
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : session.remotes.isEmpty
                            ? const _EmptyState()
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                                itemCount: session.remotes.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (ctx, i) => _RemoteCard(
                                  key: ValueKey(session.remotes[i].id),
                                  config: session.remotes[i],
                                ),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final SessionManager session;
  const _Header({required this.session});

  @override
  Widget build(BuildContext context) {
    final total = session.remotes.length;
    final mounted = session.mountedCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sürücüler', style: AppTheme.text(20, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  total == 0 ? 'Henüz bağlantı yok' : '$total bağlantı · $mounted bağlı',
                  style: AppTheme.text(12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          GhostIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Ayarlar (⌘,)',
            onPressed: () => openSettings(context),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => openAddRemote(context),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Yeni Bağlantı'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.dns_rounded, size: 30, color: AppTheme.accent),
          ),
          const SizedBox(height: 18),
          Text('İlk sürücünü ekle', style: AppTheme.text(16, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'SFTP, FTP/FTPS veya S3 uyumlu bir depolamayı\nFinder\'da yerel bir disk gibi kullan.',
            textAlign: TextAlign.center,
            style: AppTheme.text(13, color: AppTheme.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => openAddRemote(context),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Yeni Bağlantı'),
          ),
        ],
      ),
    );
  }
}

class _RemoteCard extends StatefulWidget {
  final RemoteConfig config;
  const _RemoteCard({super.key, required this.config});

  @override
  State<_RemoteCard> createState() => _RemoteCardState();
}

class _RemoteCardState extends State<_RemoteCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    final config = widget.config;
    final busy = session.busyLabel(config.id);
    final error = session.getError(config.id);
    final notice = session.getNotice(config.id);
    final stats = session.statsFor(config.id);
    final typeColor = AppTheme.typeColor(config.type);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.surfaceElevated : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: config.isMounted ? AppTheme.success.withValues(alpha: 0.35) : AppTheme.border,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(AppTheme.typeIcon(config.type), size: 20, color: typeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              config.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.text(14, weight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(config: config, busy: busy, stats: stats),
                          if (config.autoMount) ...[
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: 'Açılışta otomatik bağlanır',
                              child: Icon(Icons.bolt_rounded, size: 14, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${config.type.label} · ${config.endpointLabel}',
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.text(12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _MountButton(config: config, busy: busy != null),
                _MoreMenu(config: config, disabled: busy != null),
              ],
            ),
            if (config.isMounted) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 54),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChipButton(
                      icon: Icons.folder_open_rounded,
                      label: 'Finder',
                      onTap: () => Mounter.openInFinder(config),
                    ),
                    ActionChipButton(
                      icon: Icons.code_rounded,
                      label: 'VS Code',
                      onTap: () => Mounter.openInVSCode(config),
                    ),
                    ActionChipButton(
                      icon: Icons.terminal_rounded,
                      label: 'Terminal',
                      onTap: () => Mounter.openInTerminal(config),
                    ),
                    ActionChipButton(
                      icon: Icons.refresh_rounded,
                      label: 'Yenile',
                      onTap: () async {
                        await session.refresh(config);
                        if (context.mounted) showToast(context, 'Klasör listesi yenilendi');
                      },
                    ),
                    const SizedBox(width: 4),
                    _CopyablePath(path: Mounter.getMountPoint(config)),
                  ],
                ),
              ),
            ],
            if (notice != null && error == null) ...[
              const SizedBox(height: 10),
              _Banner(message: notice, color: AppTheme.accent, icon: Icons.cloud_upload_rounded),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              _Banner(message: error, color: AppTheme.danger, icon: Icons.error_outline_rounded),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final RemoteConfig config;
  final String? busy;
  final TransferStats stats;

  const _StatusPill({required this.config, required this.busy, required this.stats});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    Widget? leading;

    if (busy != null) {
      color = AppTheme.accent;
      label = busy!;
      leading = const SizedBox(width: 9, height: 9, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accent));
    } else if (!stats.idle) {
      color = AppTheme.accent;
      final speed = stats.speed > 0 ? ' · ${formatSpeed(stats.speed)}' : '';
      label = '${stats.pendingUploads} yükleniyor$speed';
      leading = const Icon(Icons.arrow_upward_rounded, size: 11, color: AppTheme.accent);
    } else if (config.isMounted) {
      color = AppTheme.success;
      label = 'Bağlı';
    } else {
      color = AppTheme.textMuted;
      label = 'Bağlı değil';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: AppTheme.text(11, weight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _MountButton extends StatelessWidget {
  final RemoteConfig config;
  final bool busy;
  const _MountButton({required this.config, required this.busy});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionManager>();
    final mounted = config.isMounted;
    return SizedBox(
      height: 34,
      child: mounted
          ? OutlinedButton.icon(
              onPressed: busy ? null : () => session.toggleMount(config),
              icon: const Icon(Icons.eject_rounded, size: 16),
              label: const Text('Ayır'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
            )
          : ElevatedButton.icon(
              onPressed: busy
                  ? null
                  : () => session.toggleMount(
                        config,
                        onPasswordRequested: (c, {reason}) => promptForPassword(context, c, reason: reason),
                      ),
              icon: const Icon(Icons.power_settings_new_rounded, size: 16),
              label: const Text('Bağla'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
            ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final RemoteConfig config;
  final bool disabled;
  const _MoreMenu({required this.config, required this.disabled});

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionManager>();
    return PopupMenuButton<String>(
      enabled: !disabled,
      tooltip: 'Diğer',
      icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textSecondary),
      offset: const Offset(0, 36),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            openAddRemote(context, existing: config);
            break;
          case 'auto':
            await session.setAutoMount(config, !config.autoMount);
            break;
          case 'clean':
            final ok = await confirmDialog(
              context,
              title: 'Sunucuyu temizle',
              message: '"${config.name}" üzerindeki tüm ._* (AppleDouble), .DS_Store ve .apdisk dosyaları '
                  'kalıcı olarak silinecek. Büyük sunucularda bu işlem biraz sürebilir.',
              confirmLabel: 'Temizle',
              destructive: true,
            );
            if (!ok || !context.mounted) return;
            showToast(context, 'Sunucu taranıyor…');
            final msg = await session.cleanRemoteJunk(config);
            if (context.mounted) showToast(context, msg);
            break;
          case 'delete':
            final ok = await confirmDialog(
              context,
              title: 'Bağlantıyı sil',
              message: '"${config.name}" silinsin mi? Kayıtlı parolası da anahtar zincirinden kaldırılır. '
                  'Sunucudaki dosyalarınız etkilenmez.',
              confirmLabel: 'Sil',
              destructive: true,
            );
            if (ok) await session.deleteRemote(config);
            break;
        }
      },
      itemBuilder: (_) => [
        _item('edit', Icons.edit_rounded, 'Düzenle'),
        CheckedPopupMenuItem(
          value: 'auto',
          checked: config.autoMount,
          child: Text('Açılışta otomatik bağlan', style: AppTheme.text(13)),
        ),
        _item('clean', Icons.cleaning_services_rounded, 'Sunucudaki ._ dosyalarını temizle'),
        const PopupMenuDivider(),
        _item('delete', Icons.delete_outline_rounded, 'Sil', color: AppTheme.danger),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label, {Color? color}) {
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: AppTheme.text(13, color: color ?? AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

class _CopyablePath extends StatelessWidget {
  final String path;
  const _CopyablePath({required this.path});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Yolu kopyala',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          Clipboard.setData(ClipboardData(text: path));
          showToast(context, 'Kopyalandı: $path');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(path, style: AppTheme.text(11, color: AppTheme.textMuted)),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;
  const _Banner({required this.message, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(message, style: AppTheme.text(12, color: color, height: 1.4))),
        ],
      ),
    );
  }
}
