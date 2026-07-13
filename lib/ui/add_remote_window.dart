import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/remote_config.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import 'dart:math';

class AddRemoteWindow extends StatefulWidget {
  final RemoteConfig? existing;

  const AddRemoteWindow({super.key, this.existing});

  @override
  State<AddRemoteWindow> createState() => _AddRemoteWindowState();
}

class _AddRemoteWindowState extends State<AddRemoteWindow>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _keyFileCtrl;

  RemoteType _type = RemoteType.sftp;
  AuthMethod _authMethod = AuthMethod.password;
  bool _showPassword = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

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
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pathCtrl.dispose();
    _passwordCtrl.dispose();
    _keyFileCtrl.dispose();
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

  void _onTypeChanged(RemoteType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      _portCtrl.text = _defaultPort.toString();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final id =
        widget.existing?.id ??
        DateTime.now().millisecondsSinceEpoch.toString() +
            Random().nextInt(9999).toString();

    final config = RemoteConfig(
      id: id,
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? _defaultPort,
      user: _userCtrl.text.trim(),
      path: _pathCtrl.text.trim().isEmpty ? '/' : _pathCtrl.text.trim(),
      type: _type,
      authMethod: _authMethod,
      keyFilePath: _authMethod == AuthMethod.keyFile
          ? _keyFileCtrl.text.trim()
          : null,
    );

    final session = context.read<SessionManager>();
    final pw = _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null;

    if (widget.existing == null) {
      await session.addRemote(config, password: pw);
    } else {
      await session.updateRemote(config, password: pw);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTypeSelector(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Connection'),
                      const SizedBox(height: 12),
                      _buildConnectionFields(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Authentication'),
                      const SizedBox(height: 12),
                      _buildAuthFields(),
                      const SizedBox(height: 32),
                      _buildActions(),
                    ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
            color: AppTheme.textSecondary,
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 20,
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.add_link_rounded,
              color: Colors.black,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'Add Remote' : 'Edit Remote',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                'rclone + Native NFS mount',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Protocol'),
        const SizedBox(height: 12),
        Row(
          children: RemoteType.values.map((t) {
            final selected = t == _type;
            return Expanded(
              child: GestureDetector(
                onTap: () => _onTypeChanged(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.accent.withOpacity(0.15)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(t.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(
                        t.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConnectionFields() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildField(
                controller: _nameCtrl,
                label: 'Name',
                hint: 'my-server',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name required';
                  if (RegExp(r'[^a-zA-Z0-9_\-]').hasMatch(v.trim())) {
                    return 'Use only letters, numbers, - or _';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildField(
                controller: _pathCtrl,
                label: 'Remote Path',
                hint: '/var/www',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildField(
                controller: _hostCtrl,
                label: 'Host',
                hint: _type == RemoteType.s3
                    ? 's3.amazonaws.com'
                    : '192.168.0.1',
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Host required' : null,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: _buildField(
                controller: _portCtrl,
                label: 'Port',
                hint: _defaultPort.toString(),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final p = int.tryParse(v);
                  if (p == null || p < 1 || p > 65535) return 'Invalid';
                  return null;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildField(
          controller: _userCtrl,
          label: _type == RemoteType.s3 ? 'Access Key ID' : 'User',
          hint: _type == RemoteType.s3 ? 'AKIAIOSFODNN7EXAMPLE' : 'ubuntu',
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'User required' : null,
        ),
      ],
    );
  }

  Widget _buildAuthFields() {
    final isS3 = _type == RemoteType.s3;
    if (isS3) {
      return _buildField(
        controller: _passwordCtrl,
        label: 'Secret Access Key',
        hint: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        obscureText: !_showPassword,
        suffixIcon: _showPasswordToggle(),
      );
    }

    return Column(
      children: [
        // Auth method toggle
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              _authTab('Password', AuthMethod.password),
              _authTab('Key File', AuthMethod.keyFile),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_authMethod == AuthMethod.password)
          _buildField(
            controller: _passwordCtrl,
            label: 'Password',
            hint: widget.existing != null
                ? '(leave blank to keep)'
                : '••••••••',
            obscureText: !_showPassword,
            suffixIcon: _showPasswordToggle(),
            validator: widget.existing == null
                ? (v) => v == null || v.isEmpty ? 'Password required' : null
                : null,
          )
        else
          _buildField(
            controller: _keyFileCtrl,
            label: 'Key File Path',
            hint: '~/.ssh/id_rsa',
          ),
      ],
    );
  }

  Widget _authTab(String label, AuthMethod method) {
    final selected = _authMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _authMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.black : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _showPasswordToggle() {
    return IconButton(
      icon: Icon(
        _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 18,
        color: AppTheme.textMuted,
      ),
      onPressed: () => setState(() => _showPassword = !_showPassword),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.existing == null ? 'Save Remote' : 'Update'),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
      validator: validator,
    );
  }
}
