import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/remote_config.dart';
import '../services/session_manager.dart';
import '../services/mounter.dart';
import '../theme/app_theme.dart';
import 'add_remote_window.dart';
import 'package:file_selector/file_selector.dart';

class MountsListWindow extends StatefulWidget {
  const MountsListWindow({super.key});

  @override
  State<MountsListWindow> createState() => _MountsListWindowState();
}

class _MountsListWindowState extends State<MountsListWindow> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Consumer<SessionManager>(
              builder: (ctx, session, _) {
                if (session.remotes.isEmpty) {
                  return _buildEmptyState(context);
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: session.remotes.length,
                  itemBuilder: (ctx, i) {
                    return _RemoteCard(config: session.remotes[i]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: const Icon(
              Icons.storage_rounded,
              color: Colors.black,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ZyDisk',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'rclone + Native NFS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Import button
          Tooltip(
            message: 'Import Remotes',
            child: IconButton(
              icon: const Icon(Icons.file_download_outlined, size: 18),
              color: AppTheme.textPrimary,
              onPressed: () => _importRemotes(context),
            ),
          ),
          const SizedBox(width: 4),
          // Export button
          Tooltip(
            message: 'Export Remotes',
            child: IconButton(
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              color: AppTheme.textPrimary,
              onPressed: () => _exportRemotes(context),
            ),
          ),
          const SizedBox(width: 10),
          // Add Remote button
          Tooltip(
            message: 'Add Remote (⌘N)',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openAddRemote(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.textPrimary, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Add Remote',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 36,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No remotes yet',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add an SFTP, FTP, or S3 connection\nto mount it as a local drive.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: () => _openAddRemote(context),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Remote'),
          ),
        ],
      ),
    );
  }

  void _openAddRemote(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return ChangeNotifierProvider.value(
            value: context.read<SessionManager>(),
            child: const AddRemoteWindow(),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _importRemotes(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'JSONs',
      extensions: <String>['json'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file != null && context.mounted) {
      final session = context.read<SessionManager>();
      await session.importFromFile(file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remotes imported successfully')),
      );
    }
  }

  Future<void> _exportRemotes(BuildContext context) async {
    final location = await getSaveLocation(suggestedName: 'remotes.json');
    if (location != null && context.mounted) {
      final session = context.read<SessionManager>();
      await session.exportToFile(location.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remotes exported to ${location.path}')),
      );
    }
  }
}

class _RemoteCard extends StatefulWidget {
  final RemoteConfig config;

  const _RemoteCard({required this.config});

  @override
  State<_RemoteCard> createState() => _RemoteCardState();
}

class _RemoteCardState extends State<_RemoteCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionManager>();
    final config = widget.config;
    final isLoading = session.isLoading(config.id);
    final error = session.getError(config.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.surfaceElevated : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: config.isMounted
                ? AppTheme.mounted.withOpacity(0.4)
                : AppTheme.border,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  // Type icon + status indicator
                  Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _typeColor(config.type).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          config.type.icon,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      // Mount status dot
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: AnimatedBuilder(
                          animation: _pulseAnim,
                          builder: (_, __) => Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: config.isMounted
                                  ? AppTheme.mounted.withOpacity(
                                      config.isMounted ? _pulseAnim.value : 1.0,
                                    )
                                  : AppTheme.unmounted,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.bg, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.name,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${config.type.label} • ${config.user}@${config.host}:${config.port}${config.path}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (config.isMounted) ...[
                          const SizedBox(height: 2),
                          Text(
                            '📂 /Volumes/${config.name}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.mounted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Mount toggle
                  const SizedBox(width: 8),
                  _buildMountToggle(context, config, session, isLoading),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppTheme.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          error,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (config.isMounted) ...[
                const SizedBox(height: 10),
                _buildMountedActions(config),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMountToggle(
    BuildContext context,
    RemoteConfig config,
    SessionManager session,
    bool isLoading,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit
        if (!config.isMounted)
          Tooltip(
            message: 'Edit',
            child: IconButton(
              icon: const Icon(Icons.edit_rounded, size: 16),
              color: AppTheme.textMuted,
              onPressed: () => _openEdit(context),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.surfaceElevated,
                padding: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        const SizedBox(width: 6),
        // Delete
        if (!config.isMounted)
          Tooltip(
            message: 'Delete',
            child: IconButton(
              icon: const Icon(Icons.delete_rounded, size: 16),
              color: AppTheme.danger,
              onPressed: () => _confirmDelete(context, config, session),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.danger.withOpacity(0.1),
                padding: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        const SizedBox(width: 6),
        // Connect/Disconnect
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: isLoading
              ? Container(
                  width: 80,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: () => session.toggleMount(
                    config,
                    onPasswordRequested: () => _promptForPassword(context, config),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: config.isMounted
                        ? AppTheme.danger.withOpacity(0.15)
                        : AppTheme.accent,
                    foregroundColor: config.isMounted
                        ? AppTheme.danger
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: config.isMounted
                            ? AppTheme.danger.withOpacity(0.4)
                            : Colors.transparent,
                      ),
                    ),
                    elevation: 0,
                    minimumSize: const Size(80, 36),
                  ),
                  child: Text(
                    config.isMounted ? 'Eject' : 'Mount',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMountedActions(RemoteConfig config) {
    return Row(
      children: [
        _actionButton(
          icon: Icons.folder_open_rounded,
          label: 'Finder',
          color: AppTheme.warning,
          onTap: () => Mounter.openInFinder(config),
        ),
        const SizedBox(width: 8),
        _actionButton(
          icon: Icons.code_rounded,
          label: 'VSCode',
          color: AppTheme.textPrimary,
          onTap: () => Mounter.openInVSCode(config),
        ),
        const SizedBox(width: 8),
        _actionButton(
          icon: Icons.terminal_rounded,
          label: 'Terminal',
          color: AppTheme.textPrimary,
          onTap: () => _openTerminal(config),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _typeColor(RemoteType type) {
    switch (type) {
      case RemoteType.sftp:
        return AppTheme.textPrimary;
      case RemoteType.ftp:
        return AppTheme.warning;
      case RemoteType.ftps:
        return AppTheme.mounted;
      case RemoteType.s3:
        return AppTheme.textPrimary;
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return ChangeNotifierProvider.value(
            value: context.read<SessionManager>(),
            child: AddRemoteWindow(existing: widget.config),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    RemoteConfig config,
    SessionManager session,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Delete Remote',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Delete "${config.name}"? This will also remove its saved password.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              session.deleteRemote(config);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTerminal(RemoteConfig config) async {
    final mountPoint = '/Volumes/${config.name}';
    await Process.run('open', ['-a', 'Terminal', mountPoint]);
  }

  Future<String?> _promptForPassword(BuildContext context, RemoteConfig config) async {
    final tc = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Password Required',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please enter the password for "${config.name}".',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tc,
              obscureText: true,
              autofocus: true,
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.accent),
                ),
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, tc.text),
            child: const Text('Save & Mount'),
          ),
        ],
      ),
    );
  }
}
