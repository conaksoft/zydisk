import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/remote_config.dart';

class AppTheme {
  // Renk paleti — koyu, sakin, tek vurgu rengi
  static const Color bg = Color(0xFF0B0D10);
  static const Color surface = Color(0xFF13161B);
  static const Color surfaceElevated = Color(0xFF1A1E25);
  static const Color surfaceHover = Color(0xFF1F242C);
  static const Color border = Color(0xFF262B33);
  static const Color borderStrong = Color(0xFF353B45);

  static const Color accent = Color(0xFF4F8CFF);
  static const Color accentHover = Color(0xFF6A9DFF);
  static const Color onAccent = Colors.white;

  static const Color success = Color(0xFF2FCB71);
  static const Color danger = Color(0xFFF2555A);
  static const Color warning = Color(0xFFF5A524);

  static const Color textPrimary = Color(0xFFEDEFF3);
  static const Color textSecondary = Color(0xFF9AA3AF);
  static const Color textMuted = Color(0xFF5F6873);

  // Geriye dönük adlar
  static const Color mounted = success;
  static const Color unmounted = Color(0xFF3A404A);

  static const double radius = 10;

  static Color typeColor(RemoteType type) {
    switch (type) {
      case RemoteType.sftp:
        return const Color(0xFF4F8CFF);
      case RemoteType.ftp:
        return const Color(0xFFF5A524);
      case RemoteType.ftps:
        return const Color(0xFF2FCB71);
      case RemoteType.s3:
        return const Color(0xFFB77CFF);
    }
  }

  static IconData typeIcon(RemoteType type) {
    switch (type) {
      case RemoteType.sftp:
        return Icons.terminal_rounded;
      case RemoteType.ftp:
        return Icons.folder_shared_rounded;
      case RemoteType.ftps:
        return Icons.lock_rounded;
      case RemoteType.s3:
        return Icons.cloud_rounded;
    }
  }

  static TextStyle text(double size, {FontWeight weight = FontWeight.w400, Color color = textPrimary, double? height}) {
    return GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        error: danger,
        onSurface: textPrimary,
        outline: border,
      ),
      scaffoldBackgroundColor: bg,
      cardColor: surfaceElevated,
      splashFactory: NoSplash.splashFactory,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: textPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 13, color: textSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: textMuted),
        labelMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        labelStyle: GoogleFonts.inter(color: textSecondary, fontSize: 13),
        floatingLabelStyle: GoogleFonts.inter(color: accent, fontSize: 13),
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 13),
        errorStyle: GoogleFonts.inter(color: danger, fontSize: 11),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: accent.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : borderStrong,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        side: const BorderSide(color: borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border),
        ),
        textStyle: GoogleFonts.inter(fontSize: 13, color: textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        behavior: SnackBarBehavior.floating,
        width: 460,
        contentTextStyle: GoogleFonts.inter(fontSize: 13, color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 0),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        textStyle: GoogleFonts.inter(fontSize: 12, color: textPrimary),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderStrong),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
    );
  }
}
