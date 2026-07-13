import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/setup_service.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  String _statusText = 'Başlatılıyor...';
  double? _progress;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  Future<void> _startSetup() async {
    try {
      await SetupService.ensureRcloneInstalled((status, progress) {
        if (mounted) {
          setState(() {
            _statusText = status;
            _progress = progress;
          });
        }
      });
      
      // Delay slightly for visual completion
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Icon(
                  Icons.cloud_download_rounded,
                  color: AppTheme.textPrimary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Sistem Gereksinimleri Yükleniyor',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_hasError)
                Column(
                  children: [
                    Text(
                      'Hata oluştu:\n$_errorMessage',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFF5F57),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _hasError = false;
                          _errorMessage = '';
                          _statusText = 'Yeniden deneniyor...';
                        });
                        _startSetup();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.textPrimary,
                      ),
                      child: const Text('Tekrar Dene'),
                    )
                  ],
                )
              else
                Column(
                  children: [
                    Text(
                      _statusText,
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: AppTheme.surface,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.textPrimary),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
