import 'package:flutter/material.dart';

/// Minimalist, mobile-first, large-touch-target theme tuned for
/// low-digital-literacy users. Deep navy primary, warm sand accent,
/// high contrast, roomy hit areas (>= 56px).
class AppTheme {
  AppTheme._();

  static const Color navy = Color(0xFF16213E);
  static const Color accent = Color(0xFFE0A458); // warm sand/gold
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF6F5F2);
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF6E6E73);

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: navy,
        primary: navy,
        secondary: accent,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'Cairo',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
        fontFamily: 'Cairo',
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: textPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: navy,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: navy, width: 2),
        ),
        hintStyle: const TextStyle(color: textMuted, fontFamily: 'Cairo'),
        labelStyle: const TextStyle(color: textMuted, fontFamily: 'Cairo'),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 15),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
      ),
    );
  }
}