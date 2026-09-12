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
  /// Deep navy — brand, headers, navigation, primary text on light cards.
  static const Color navy = Color(0xFF16213E);
  static const Color navyDeep = Color(0xFF0F1830);
  static const Color navySoft = Color(0xFF243457);

  /// Warm amber — the single call-to-action colour.
  static const Color accent = Color(0xFFE8A33D);
  static const Color accentDeep = Color(0xFF9B6415);
  static const Color accentWash = Color(0xFFFDF3E3);

  // ── Neutrals ───────────────────────────────────────────────────────────
  static const Color bg = Color(0xFFF5F4F1);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFFAF9F7);
  static const Color line = Color(0xFFE6E4DE);
  static const Color lineSoft = Color(0xFFF0EEE9);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF475065);
  static const Color textMuted = Color(0xFF6C707A);
  static const Color onNavy = Color(0xFFFFFFFF);
  static const Color onNavyMuted = Color(0xFFB9C2D6);

  // ── Semantic ───────────────────────────────────────────────────────────
  static const Color success = Color(0xFF1B7E50);
  static const Color successWash = Color(0xFFE7F5EE);
  static const Color danger = Color(0xFFC33F39);
  static const Color dangerWash = Color(0xFFFCEDEC);
  static const Color info = Color(0xFF2C6FBB);
  static const Color infoWash = Color(0xFFEAF2FB);
  static const Color star = Color(0xFFF2B01E);

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
      brightness: Brightness.light,
      primary: navy,
      onPrimary: onNavy,
      primaryContainer: navySoft,
      onPrimaryContainer: onNavy,
      secondary: accent,
      onSecondary: navy,
      secondaryContainer: accentWash,
      onSecondaryContainer: navy,
      tertiary: info,
      onTertiary: onNavy,
      error: danger,
      onError: onNavy,
      errorContainer: dangerWash,
      onErrorContainer: danger,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: textSecondary,
      outline: line,
      outlineVariant: lineSoft,
      shadow: Color(0x1A101828),
      scrim: Color(0x66000000),
      inverseSurface: navy,
      onInverseSurface: onNavy,
      inversePrimary: accent,
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
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 60,
        iconTheme: IconThemeData(color: navy, size: 24),
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
          foregroundColor: navy,
          minimumSize: const Size.fromHeight(tapMin),
          side: const BorderSide(color: line, width: 1.5),
          textStyle: button.copyWith(fontSize: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: navy,
          textStyle: label.copyWith(fontSize: 15),
        ),
      ),

      // ── Inputs ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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
            color: navy,
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
          borderSide: const BorderSide(color: navy, width: 2),
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
        selectedColor: navy,
        disabledColor: lineSoft,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: label.copyWith(fontSize: 14.5, color: textPrimary),
        secondaryLabelStyle: label.copyWith(fontSize: 14.5, color: onNavy),
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
        iconColor: navy,
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

      iconTheme: const IconThemeData(color: navy, size: 24),
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
        selectedItemColor: navy,
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
              color: states.contains(WidgetState.selected) ? navy : textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 25,
              color: states.contains(WidgetState.selected) ? navy : textMuted,
            )),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        contentTextStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14.5,
            color: onNavy,
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
        iconColor: navy,
        collapsedIconColor: textSecondary,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
        tilePadding: EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: navy,
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
