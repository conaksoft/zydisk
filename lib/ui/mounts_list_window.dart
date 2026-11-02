import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/list_query.dart';
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

class MountsListWindow extends StatefulWidget {
  const MountsListWindow({super.key});

  @override
  State<MountsListWindow> createState() => _MountsListWindowState();
}

class _MountsListWindowState extends State<MountsListWindow> {
  static const _prefsKey = 'listQuery';

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  ListQuery _query = const ListQuery();
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _loadQuery();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadQuery() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw != null && mounted) {
        setState(() => _query = ListQuery.fromPrefs(json.decode(raw) as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  void _setQuery(ListQuery q) {
    setState(() => _query = q);
    SharedPreferences.getInstance().then((p) => p.setString(_prefsKey, json.encode(q.toPrefs())));
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _setQuery(_query.cleared());
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () => openAddRemote(context),
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () => openSettings(context),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _searchFocus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Consumer<SessionManager>(
            builder: (ctx, session, _) {
              final hasRemotes = session.remotes.isNotEmpty;
              return Column(
                children: [
                  _Header(session: session),
                  if (session.loaded && hasRemotes) _buildToolbar(session),
                  Expanded(
                    child: !session.loaded
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : !hasRemotes
                            ? const _EmptyState()
                            : _buildList(session),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(SessionManager session) {
    final mounted = session.mountedCount;
    final total = session.remotes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                onChanged: (v) => setState(() => _query = _query.copyWith(search: v)),
                style: AppTheme.text(13),
                decoration: InputDecoration(
                  hintText: 'Ara: ad, sunucu, kullanıcı, yol…  (⌘F)',
                  prefixIcon: const Icon(Icons.search_rounded, size: 17, color: AppTheme.textMuted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: _query.search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 15),
                          color: AppTheme.textMuted,
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = _query.copyWith(search: ''));
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _StatusSegment(
            value: _query.status,
            counts: {StatusFilter.all: total, StatusFilter.mounted: mounted, StatusFilter.unmounted: total - mounted},
            onChanged: (s) => _setQuery(_query.copyWith(status: s)),
          ),
          const SizedBox(width: 6),
          _ProtocolFilterButton(
            selected: _query.types,
            onChanged: (t) => _setQuery(_query.copyWith(types: t)),
          ),
          _MenuButton<SortMode>(
            icon: Icons.sort_rounded,
            tooltip: 'Sırala: ${_query.sort.label}',
            values: SortMode.values,
            selected: _query.sort,
            labelOf: (m) => m.label,
            onSelected: (m) => _setQuery(_query.copyWith(sort: m)),
          ),
          _MenuButton<GroupMode>(
            icon: Icons.workspaces_outline,
            tooltip: 'Grupla: ${_query.group.label}',
            values: GroupMode.values,
            selected: _query.group,
            active: _query.group != GroupMode.none,
            labelOf: (m) => m.label,
            onSelected: (m) => _setQuery(_query.copyWith(group: m)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(SessionManager session) {
    final groups = _query.apply(session.remotes);
    final shown = groups.fold<int>(0, (a, g) => a + g.items.length);

    if (shown == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 34, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text('Eşleşen sürücü yok', style: AppTheme.text(15, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Aramayı veya filtreleri değiştirmeyi deneyin.',
                style: AppTheme.text(12, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: _clearFilters, child: const Text('Filtreleri temizle')),
          ],
        ),
      );
    }

    final grouped = _query.group != GroupMode.none;
    final children = <Widget>[];
    if (_query.isFiltering) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text('${session.remotes.length} sürücüden $shown tanesi gösteriliyor',
                style: AppTheme.text(12, color: AppTheme.textMuted)),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: _clearFilters,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Temizle', style: AppTheme.text(12, weight: FontWeight.w500, color: AppTheme.accent)),
              ),
            ),
          ],
        ),
      ));
    }

    for (final g in groups) {
      final collapsed = grouped && _collapsed.contains(g.key);
      if (grouped) {
        children.add(_GroupHeader(
          title: g.title,
          count: g.items.length,
          mounted: g.items.where((r) => r.isMounted).length,
          collapsed: collapsed,
          onTap: () => setState(() => collapsed ? _collapsed.remove(g.key) : _collapsed.add(g.key)),
        ));
      }
      if (collapsed) continue;
      for (final r in g.items) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RemoteCard(key: ValueKey(r.id), config: r),
        ));
      }
      if (grouped) children.add(const SizedBox(height: 6));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: children,
    );
  }
}

class _StatusSegment extends StatelessWidget {
  final StatusFilter value;
  final Map<StatusFilter, int> counts;
  final ValueChanged<StatusFilter> onChanged;

  const _StatusSegment({required this.value, required this.counts, required this.onChanged});

  static const _labels = {StatusFilter.all: 'Tümü', StatusFilter.mounted: 'Bağlı', StatusFilter.unmounted: 'Bağlı değil'};

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in StatusFilter.values)
            GestureDetector(
              onTap: () => onChanged(f),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: f == value ? AppTheme.surfaceHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: f == value ? AppTheme.borderStrong : Colors.transparent),
                  ),
                  child: Text(
                    '${_labels[f]} ${counts[f]}',
                    style: AppTheme.text(12,
                        weight: FontWeight.w500, color: f == value ? AppTheme.textPrimary : AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProtocolFilterButton extends StatelessWidget {
  final Set<RemoteType> selected;
  final ValueChanged<Set<RemoteType>> onChanged;

  const _ProtocolFilterButton({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final active = selected.isNotEmpty;
    return PopupMenuButton<RemoteType?>(
      tooltip: active ? 'Protokol: ${selected.map((t) => t.label).join(', ')}' : 'Protokole göre filtrele',
      offset: const Offset(0, 38),
      icon: Badge(
        isLabelVisible: active,
        backgroundColor: AppTheme.accent,
        label: Text('${selected.length}', style: AppTheme.text(9, weight: FontWeight.w700, color: Colors.white)),
        child: Icon(Icons.filter_list_rounded, size: 18, color: active ? AppTheme.accent : AppTheme.textSecondary),
      ),
      onSelected: (t) {
        if (t == null) {
          onChanged({});
          return;
        }
        final next = {...selected};
        next.contains(t) ? next.remove(t) : next.add(t);
        onChanged(next);
      },
      itemBuilder: (_) => [
        for (final t in RemoteType.values)
          CheckedPopupMenuItem<RemoteType?>(
            value: t,
            checked: selected.contains(t),
            child: Row(
              children: [
                Icon(AppTheme.typeIcon(t), size: 15, color: AppTheme.typeColor(t)),
                const SizedBox(width: 8),
                Text(t.label, style: AppTheme.text(13)),
              ],
            ),
          ),
        if (active) ...[
          const PopupMenuDivider(),
          PopupMenuItem<RemoteType?>(
            value: null,
            height: 36,
            child: Text('Tüm protokoller', style: AppTheme.text(13, color: AppTheme.accent)),
          ),
        ],
      ],
    );
  }
}

class _MenuButton<T> extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<T> values;
  final T selected;
  final bool active;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  const _MenuButton({
    required this.icon,
    required this.tooltip,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      offset: const Offset(0, 38),
      icon: Icon(icon, size: 18, color: active ? AppTheme.accent : AppTheme.textSecondary),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in values)
          PopupMenuItem<T>(
            value: v,
            height: 36,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: v == selected ? const Icon(Icons.check_rounded, size: 15, color: AppTheme.accent) : null,
                ),
                Text(labelOf(v), style: AppTheme.text(13)),
              ],
            ),
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final int mounted;
  final bool collapsed;
  final VoidCallback onTap;

  const _GroupHeader({
    required this.title,
    required this.count,
    required this.mounted,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more_rounded, size: 16, color: AppTheme.textMuted),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: AppTheme.text(11, weight: FontWeight.w600, color: AppTheme.textSecondary)
                    .copyWith(letterSpacing: 0.8),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              mounted > 0 ? '$count · $mounted bağlı' : '$count',
              style: AppTheme.text(11, color: AppTheme.textMuted),
            ),
          ],
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
