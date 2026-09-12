import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  ALLO MOKAWIL — DESIGN SYSTEM
/// ─────────────────────────────────────────────────────────────────────────
///  Principles (Algerian market, low digital literacy):
///   1. NEVER rely on inherited colour. Every text style sets `color:`
///      explicitly — this is what killed the old "white text on white card"
///      specialty tiles.
///   2. Big, obvious tap targets (>= 56dp) and generous spacing.
///   3. One accent colour = one action. Amber = "do this".
///   4. Arabic RTL first, Cairo typeface, roomy line-height for diacritics.
///   5. Calm neutrals so photos of real work are the loudest thing on screen.
/// ─────────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  // ── Brand ──────────────────────────────────────────────────────────────
  /// Deep ink. Plays two roles that both stay dark in the dark theme: it is a
  /// *surface* (headers, heroes, snackbars) and the ink that sits **on gold**
  /// (button labels, selected chips). Never use it as text on a card — that is
  /// what `textPrimary` is for.
  static const Color navy = Color(0xFF12161D);
  static const Color navyDeep = Color(0xFF0B0E13);
  static const Color navySoft = Color(0xFF1E242E);

  /// Warm gold — the single call-to-action colour (board palette).
  static const Color accent = Color(0xFFF2B23E);
  static const Color accentDeep = Color(0xFF9B6415);
  static const Color accentWash = Color(0xFF2A2213);

  // ── Neutrals — dark canvas from the approved board ─────────────────────
  static const Color bg = Color(0xFF0B0E13);
  static const Color surface = Color(0xFF141922);
  static const Color surfaceAlt = Color(0xFF1A1F27);
  static const Color line = Color(0xFF242A33);
  static const Color lineSoft = Color(0xFF1B212A);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F6F8);
  static const Color textSecondary = Color(0xFFC3C9D4);
  static const Color textMuted = Color(0xFF9AA1AC);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color onNavyMuted = Color(0xFFB9C2D6);

  // ── Semantic — lifted for legibility on a dark canvas ──────────────────
  static const Color success = Color(0xFF3FBF6F);
  static const Color successWash = Color(0xFF10231A);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerWash = Color(0xFF2A1618);
  static const Color info = Color(0xFF6BA8F5);
  static const Color infoWash = Color(0xFF14202E);
  static const Color star = Color(0xFFF2B23E);

  // ── Geometry ───────────────────────────────────────────────────────────
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double gap = 16;
  static const double tapMin = 56;

  static const EdgeInsets pagePad = EdgeInsets.fromLTRB(18, 8, 18, 28);

  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x0F101828),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];

  // ── Type scale (Cairo) ─────────────────────────────────────────────────
  static const TextStyle display = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 27,
      fontWeight: FontWeight.w800,
      height: 1.35,
      color: textPrimary);
  static const TextStyle h1 = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 21,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: textPrimary);
  static const TextStyle h2 = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 17.5,
      fontWeight: FontWeight.w700,
      height: 1.45,
      color: textPrimary);
  static const TextStyle body = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.65,
      color: textPrimary);
  static const TextStyle bodySoft = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      height: 1.65,
      color: textSecondary);
  static const TextStyle label = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: textPrimary);
  static const TextStyle caption = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: textMuted);
  static const TextStyle button = TextStyle(
      fontFamily: 'Cairo',
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: navy);

  // ── ThemeData ──────────────────────────────────────────────────────────
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: navy,
      primaryContainer: accentWash,
      onPrimaryContainer: accent,
      secondary: accent,
      onSecondary: navy,
      secondaryContainer: accentWash,
      onSecondaryContainer: accent,
      tertiary: info,
      onTertiary: navy,
      error: danger,
      onError: navy,
      errorContainer: dangerWash,
      onErrorContainer: danger,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: textSecondary,
      outline: line,
      outlineVariant: lineSoft,
      shadow: Color(0x66000000),
      scrim: Color(0xCC000000),
      inverseSurface: textPrimary,
      onInverseSurface: bg,
      inversePrimary: accentDeep,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Cairo',
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: const TextTheme(
        displayLarge: display,
        displayMedium: display,
        headlineLarge: h1,
        headlineMedium: h1,
        headlineSmall: h2,
        titleLarge: h1,
        titleMedium: h2,
        titleSmall: label,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: label,
        labelMedium: caption,
        labelSmall: caption,
      ),

      // ── App bar: flat, white, hairline ─────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 60,
        iconTheme: IconThemeData(color: textPrimary, size: 24),
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: textPrimary,
        ),
      ),

      // ── Buttons ────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: navy,
          disabledBackgroundColor: line,
          disabledForegroundColor: textMuted,
          elevation: 0,
          minimumSize: const Size.fromHeight(tapMin),
          textStyle: button,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: navy,
          disabledBackgroundColor: line,
          disabledForegroundColor: textMuted,
          minimumSize: const Size.fromHeight(tapMin),
          textStyle: button,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(tapMin),
          side: const BorderSide(color: line, width: 1.5),
          textStyle: button.copyWith(fontSize: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: label.copyWith(fontSize: 15),
        ),
      ),

      // ── Inputs ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14.5,
            color: textMuted,
            fontWeight: FontWeight.w400),
        labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14.5,
            color: textSecondary,
            fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            color: accent,
            fontWeight: FontWeight.w700),
        errorStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 13, color: danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),

      // ── Chips — explicit colours, never inherited ──────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent,
        disabledColor: lineSoft,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: label.copyWith(fontSize: 14.5, color: textPrimary),
        secondaryLabelStyle: label.copyWith(fontSize: 14.5, color: navy),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Cards ──────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: const BorderSide(color: line),
        ),
      ),

      dividerTheme: const DividerThemeData(
          color: lineSoft, thickness: 1, space: 1),

      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            color: textPrimary),
        subtitleTextStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 13.5, color: textSecondary),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      iconTheme: const IconThemeData(color: textSecondary, size: 24),
      dividerColor: line,

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rLg)),
        titleTextStyle: h2,
        contentTextStyle: bodySoft,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w500),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentWash,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? accent : textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 25,
              color: states.contains(WidgetState.selected) ? accent : textMuted,
            )),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceAlt,
        contentTextStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14.5,
            color: textPrimary,
            fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rSm)),
        insetPadding: const EdgeInsets.all(16),
      ),

      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: accent, linearMinHeight: 5),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? navy : surface),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : line),
        trackOutlineColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),

      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: textSecondary,
        collapsedIconColor: textMuted,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
        tilePadding: EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textMuted,
        labelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.w500),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: lineSoft,
      ),
    );
  }
}
