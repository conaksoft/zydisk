import 'package:flutter/material.dart';
import '../models/remote_config.dart';
import '../theme/app_theme.dart';

void showToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: Duration(seconds: error ? 6 : 3),
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 16,
            color: error ? AppTheme.danger : AppTheme.success,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppTheme.text(16, weight: FontWeight.w600)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(message, style: AppTheme.text(13, color: AppTheme.textSecondary, height: 1.5)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Uzak sunucu parolasını sorar. [reason] doluysa (ör. yanlış parola) uyarı olarak gösterilir.
Future<String?> promptForPassword(BuildContext context, RemoteConfig config, {String? reason}) {
  final ctrl = TextEditingController();
  var obscure = true;
  final isS3 = config.type == RemoteType.s3;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(isS3 ? 'Secret Key gerekli' : 'Parola gerekli', style: AppTheme.text(16, weight: FontWeight.w600)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${config.name}" (${config.endpointLabel}) için ${isS3 ? 'secret access key' : 'parolayı'} girin. '
                'Anahtar zincirinize güvenle kaydedilir.',
                style: AppTheme.text(13, color: AppTheme.textSecondary, height: 1.5),
              ),
              if (reason != null) ...[
                const SizedBox(height: 10),
                Text(reason, style: AppTheme.text(12, color: AppTheme.danger)),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                style: AppTheme.text(13),
                decoration: InputDecoration(
                  labelText: isS3 ? 'Secret Access Key' : 'Parola',
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
                    color: AppTheme.textMuted,
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Kaydet ve Bağla')),
        ],
      ),
    ),
  );
}

/// Küçük, sade ikon düğmesi.
class GhostIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const GhostIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: color ?? AppTheme.textSecondary,
        hoverColor: AppTheme.surfaceHover,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.all(8),
          minimumSize: const Size(34, 34),
        ),
      ),
    );
  }
}

/// Bağlı sürücü için hızlı eylem çipi.
class ActionChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ActionChipButton({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceElevated,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        hoverColor: AppTheme.surfaceHover,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: AppTheme.text(12, weight: FontWeight.w500, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

String formatSpeed(double bytesPerSec) {
  if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/sn';
  if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/sn';
  return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/sn';
}
