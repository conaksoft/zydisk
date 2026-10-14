import 'dart:io';
import 'dart:math';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/remote_config.dart';
import '../services/app_settings.dart';
import '../services/keychain_service.dart';
import '../services/mounter.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

class AddRemoteWindow extends StatefulWidget {
  final RemoteConfig? existing;

  const AddRemoteWindow({super.key, this.existing});

  @override
  State<AddRemoteWindow> createState() => _AddRemoteWindowState();
}

class _AddRemoteWindowState extends State<AddRemoteWindow> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pathCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _keyFileCtrl;

  RemoteType _type = RemoteType.sftp;
  AuthMethod _authMethod = AuthMethod.password;
  bool _autoMount = false;
  bool _showPassword = false;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl = TextEditingController(text: (e?.port ?? 22).toString());
    _userCtrl = TextEditingController(text: e?.user ?? '');
    _pathCtrl = TextEditingController(text: e?.path ?? '/');
    _passwordCtrl = TextEditingController();
    _keyFileCtrl = TextEditingController(text: e?.keyFilePath ?? '');
    if (e != null) {
      _type = e.type;
      _authMethod = e.authMethod;
      _autoMount = e.autoMount;
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _hostCtrl, _portCtrl, _userCtrl, _pathCtrl, _passwordCtrl, _keyFileCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _defaultPort {
    switch (_type) {
      case RemoteType.sftp:
        return 22;
      case RemoteType.ftp:
        return 21;
      case RemoteType.ftps:
        return 990;
      case RemoteType.s3:
        return 443;
    }
  }

  void _onTypeChanged(RemoteType t) {
    setState(() {
      final wasDefault = int.tryParse(_portCtrl.text) == _defaultPort || _portCtrl.text.isEmpty;
      _type = t;
      if (wasDefault) _portCtrl.text = _defaultPort.toString();
      if (t != RemoteType.sftp) _authMethod = AuthMethod.password;
      _testResult = null;
    });
  }

  RemoteConfig _buildConfig() {
    final id = widget.existing?.id ?? '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(9999)}';
    final path = _pathCtrl.text.trim();
    return RemoteConfig(
      id: id,
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? _defaultPort,
      user: _userCtrl.text.trim(),
      path: path.isEmpty ? '/' : path,
      type: _type,
      authMethod: _authMethod,
      keyFilePath: _authMethod == AuthMethod.keyFile ? _keyFileCtrl.text.trim() : null,
      autoMount: _autoMount,
      isMounted: widget.existing?.isMounted ?? false,
      mountPoint: widget.existing?.mountPoint,
    );
  }

  Future<String?> _effectivePassword() async {
    if (_passwordCtrl.text.isNotEmpty) return _passwordCtrl.text;
    if (_isEdit) return KeychainService.getPassword(widget.existing!.id);
    return null;
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final config = _buildConfig();
    final err = await Mounter.testConnection(config, await _effectivePassword());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = err == null;
      _testResult = err ?? 'Bağlantı başarılı.';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final config = _buildConfig();
    final session = context.read<SessionManager>();
    final pw = _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null;
    final navigator = Navigator.of(context);

    try {
      if (_isEdit) {
        navigator.pop();
        await session.updateRemote(
          config,
          password: pw,
          onPasswordRequested: (c, {reason}) => promptForPassword(navigator.context, c, reason: reason),
        );
      } else {
        await session.addRemote(config, password: pw);
        navigator.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, 'Kaydedilemedi: $e', error: true);
      }
    }
  }

  Future<void> _revealSavedPassword() async {
    final settings = context.read<AppSettings>();
    final ok = await settings.authenticate('kayıtlı parolayı göstermek', force: true);
    if (!ok || !mounted) return;
    final pw = await KeychainService.getPassword(widget.existing!.id);
    if (!mounted) return;
    if (pw == null) {
      showToast(context, 'Kayıtlı parola yok.', error: true);
      return;
    }
    setState(() {
      _passwordCtrl.text = pw;
      _showPassword = true;
    });
  }

  Future<void> _pickKeyFile() async {
    final file = await openFile(initialDirectory: '${Platform.environment['HOME'] ?? ''}/.ssh');
    if (file != null) setState(() => _keyFileCtrl.text = file.path);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _section('Protokol', _buildTypeSelector()),
                          _section('Bağlantı', _buildConnectionFields()),
                          _section('Kimlik Doğrulama', _buildAuthFields()),
                          _section('Seçenekler', _buildOptions()),
                          if (_testResult != null) ...[
                            _TestResult(ok: _testOk, message: _testResult!),
                            const SizedBox(height: 16),
                          ],
                          _buildActions(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 24, 8),
      child: Row(
        children: [
          GhostIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Geri (Esc)',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Text(_isEdit ? 'Bağlantıyı Düzenle' : 'Yeni Bağlantı', style: AppTheme.text(18, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: AppTheme.text(11, weight: FontWeight.w600, color: AppTheme.textMuted).copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Row(
      children: RemoteType.values.map((t) {
        final selected = t == _type;
        final color = AppTheme.typeColor(t);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: t == RemoteType.values.last ? 0 : 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _onTypeChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? color.withValues(alpha: 0.10) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? color : AppTheme.border, width: selected ? 1.5 : 1),
                  ),
                  child: Column(
                    children: [
                      Icon(AppTheme.typeIcon(t), size: 20, color: selected ? color : AppTheme.textSecondary),
                      const SizedBox(height: 6),
                      Text(
                        t.label,
                        style: AppTheme.text(12,
                            weight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConnectionFields() {
    final session = context.read<SessionManager>();
    final isS3 = _type == RemoteType.s3;
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _field(
                controller: _nameCtrl,
                label: 'Sürücü adı',
                hint: 'sunucum',
                helper: 'Finder\'da /Volumes/<ad> olarak görünür',
                validator: (v) {
                  final name = v?.trim() ?? '';
                  if (name.isEmpty) return 'Ad gerekli';
                  if (RegExp(r'[^a-zA-Z0-9_\-]').hasMatch(name)) return 'Yalnızca harf, rakam, - ve _';
                  if (name.length > 64) return 'En fazla 64 karakter';
                  if (session.isNameTaken(name, exceptId: widget.existing?.id)) return 'Bu ad zaten kullanılıyor';
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _field(
                controller: _pathCtrl,
                label: isS3 ? 'Bucket / yol' : 'Uzak klasör',
                hint: isS3 ? 'bucket/klasor' : '/var/www',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                controller: _hostCtrl,
                label: isS3 ? 'Endpoint' : 'Sunucu',
                hint: isS3 ? 's3.amazonaws.com' : 'ornek.com veya 192.168.1.10',
                validator: (v) => v == null || v.trim().isEmpty ? 'Sunucu gerekli' : null,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: _field(
                controller: _portCtrl,
                label: 'Port',
                hint: _defaultPort.toString(),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final p = int.tryParse(v ?? '');
                  if (p == null || p < 1 || p > 65535) return 'Geçersiz';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(
          controller: _userCtrl,
          label: isS3 ? 'Access Key ID' : 'Kullanıcı adı',
          hint: isS3 ? 'AKIA…' : 'ubuntu',
          validator: (v) => v == null || v.trim().isEmpty ? 'Gerekli' : null,
        ),
      ],
    );
  }

  Widget _buildAuthFields() {
    final isS3 = _type == RemoteType.s3;
    final canUseKey = _type == RemoteType.sftp;
    final usingPassword = isS3 || !canUseKey || _authMethod == AuthMethod.password;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canUseKey) ...[
          _Segmented(
            options: const ['Parola', 'SSH Anahtarı'],
            selected: _authMethod == AuthMethod.password ? 0 : 1,
            onChanged: (i) => setState(() => _authMethod = i == 0 ? AuthMethod.password : AuthMethod.keyFile),
          ),
          const SizedBox(height: 12),
        ],
        if (usingPassword)
          _field(
            controller: _passwordCtrl,
            label: isS3 ? 'Secret Access Key' : 'Parola',
            hint: _isEdit ? 'Değiştirmek istemiyorsanız boş bırakın' : null,
            obscureText: !_showPassword,
            helper: 'Parolalar macOS Anahtar Zinciri\'nde saklanır, diske düz metin yazılmaz.',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isEdit && _passwordCtrl.text.isEmpty)
                  Tooltip(
                    message: 'Kayıtlı parolayı göster (Touch ID)',
                    child: IconButton(
                      icon: const Icon(Icons.fingerprint_rounded, size: 18),
                      color: AppTheme.textMuted,
                      onPressed: _revealSavedPassword,
                    ),
                  ),
                IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
                  color: AppTheme.textMuted,
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ],
            ),
            onChanged: (_) => setState(() {}),
            validator: _isEdit ? null : (v) => v == null || v.isEmpty ? 'Gerekli' : null,
          )
        else
          _field(
            controller: _keyFileCtrl,
            label: 'Özel anahtar dosyası',
            hint: '~/.ssh/id_ed25519',
            validator: (v) => v == null || v.trim().isEmpty ? 'Anahtar dosyası gerekli' : null,
            suffixIcon: IconButton(
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              color: AppTheme.textMuted,
              tooltip: 'Dosya seç',
              onPressed: _pickKeyFile,
            ),
          ),
      ],
    );
  }

  Widget _buildOptions() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _autoMount = !_autoMount),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: _autoMount, onChanged: (v) => setState(() => _autoMount = v ?? false)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Açılışta otomatik bağlan', style: AppTheme.text(13, weight: FontWeight.w500)),
                  Text('ZyDisk başladığında bu sürücü kendiliğinden bağlanır.',
                      style: AppTheme.text(12, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _testing || _saving ? null : _test,
          icon: _testing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check_rounded, size: 16),
          label: Text(_testing ? 'Deneniyor…' : 'Bağlantıyı Test Et'),
        ),
        const Spacer(),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? 'Güncelle' : 'Kaydet'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      autocorrect: false,
      enableSuggestions: false,
      style: AppTheme.text(13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperStyle: AppTheme.text(11, color: AppTheme.textMuted),
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }
}

class _Segmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const _Segmented({required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppTheme.surfaceHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: i == selected ? AppTheme.borderStrong : Colors.transparent),
                  ),
                  child: Text(
                    options[i],
                    style: AppTheme.text(13,
                        weight: FontWeight.w500, color: i == selected ? AppTheme.textPrimary : AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestResult extends StatelessWidget {
  final bool ok;
  final String message;
  const _TestResult({required this.ok, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppTheme.success : AppTheme.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(message, style: AppTheme.text(12, color: color))),
        ],
      ),
    );
  }
}
