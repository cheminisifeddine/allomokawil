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
  /// Deep navy — brand, headers, the hero panel, and the primary text ink.
  /// On the white canvas it is never a *background* for a card (that is
  /// `surface`), only for the hero panel and for the ink that sits **on gold**.
  static const Color navy = Color(0xFF16213E);
  static const Color navyDeep = Color(0xFF0F1830);
  static const Color navySoft = Color(0xFF243457);

  /// Warm gold — the single call-to-action colour (board palette).
  static const Color accent = Color(0xFFE8A33D);
  static const Color accentDeep = Color(0xFF9B6415);
  static const Color accentWash = Color(0xFFFDF3E3);

  // ── Neutrals — white canvas ────────────────────────────────────────────
  static const Color bg = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF6F7F9);
  static const Color line = Color(0xFFE8E8EC);
  static const Color lineSoft = Color(0xFFF2F2F5);

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

  /// The rating star glyph — a meaningful graphic, so WCAG 1.4.11 asks it to
  /// clear 3:1 against whatever it is drawn on. This is the nearest gold that
  /// clears it on *every* surface the app uses: white 3.68, `surfaceAlt` 3.43,
  /// `accentWash` 3.35 (the worker-home stat tile and the landing promise row
  /// both put it on the wash), while staying legible on `navy` (4.32).
  /// The previous #F2B01E measured 1.91 on white and 1.74 on the wash — the
  /// star lost its silhouette and a filled row read as a smudge.
  static const Color star = Color(0xFFB5790B);

  /// Unselected stars of the rating input. This is the *track* of a control,
  /// not a decorative divider: `line` (1.22:1) made the scale a user picks
  /// from almost invisible, so it gets its own visible neutral. 3.43 on white,
  /// 3.20 on `surfaceAlt`.
  static const Color starEmpty = Color(0xFF8A8A91);

  /// Boundary of an outlined control (secondary/outline button, unselected
  /// chip). `line` is right for a card hairline but too faint to mark a tap
  /// target — 1.22:1 made the button read as floating text. 3.25 on white,
  /// 3.03 on `surfaceAlt`.
  static const Color controlLine = Color(0xFF8A8F99);

  // ── Geometry ───────────────────────────────────────────────────────────
  /// Radii. A screen names a step; it never types a number.
  static const double rXs = 6;
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 28;

  /// Fully rounded ends — pills, chips, badges, progress tracks.
  static const double rPill = 999;

  // ── Spacing — one 4 dp grid ────────────────────────────────────────────
  /// Every gap and inset comes off this ladder. There is exactly one blessed
  /// exception, [gutter], because it is a *screen margin*, not a component gap.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;

  static const double gap = s16;
  static const double tapMin = 56;

  /// The page gutter. Deliberately 18 — it is the one value that is not a
  /// component gap, so it lives alone and never gets reused as one.
  static const double gutter = 18;

  static const EdgeInsets pagePad =
      EdgeInsets.fromLTRB(gutter, s8, gutter, s28);

  // ── THE CARD RECIPE ────────────────────────────────────────────────────
  //  One shape for every card in the app: fill, radius, hairline border,
  //  inner padding — and no shadow. A screen builds cards through
  //  [cardDecoration] / [AppCard] and never by hand; `test/card_recipe_test.dart`
  //  fails the build if a screen writes its own surface+border BoxDecoration or
  //  types a numeric radius. That drift (radius 14 here, 13 dp of inset there)
  //  is exactly what this item exists to end.
  static const Color cardFill = surface;
  static const Color cardLine = line;
  static const double cardLineWidth = 1;
  static const double cardRadius = rLg;

  /// Standard card inset.
  static const EdgeInsets cardPad = EdgeInsets.all(s16);

  /// Compact variant for tiles and 92-172 dp squares, where 16 dp of inset
  /// would squeeze the label. On the grid, and still one token.
  static const EdgeInsets cardPadRail = EdgeInsets.all(s12);

  /// Rows card: children are full-width rows that carry their own dividers
  /// (profile menu, verification list). Same horizontal inset as [cardPad],
  /// half the vertical, because every row already has its own breathing room.
  static const EdgeInsets cardPadRows =
      EdgeInsets.symmetric(horizontal: s16, vertical: s8);

  /// No shadow, on purpose: a drop shadow on a #0B0E13 canvas reads as a grey
  /// smear, and the hairline [cardLine] border already does the separating.
  /// The token exists so a screen cannot add "just a little" elevation.
  static const List<BoxShadow> cardShadow = <BoxShadow>[];

  static BoxDecoration get cardDecoration => cardDecorationOf();

  /// The recipe with named overrides, for the few real cards that carry a
  /// semantic tint (the danger banner, the chosen document). The shape stays
  /// the recipe's shape; only the colours move.
  static BoxDecoration cardDecorationOf({
    Color? fill,
    Color? border,
    double? radius,
    double? borderWidth,
    List<BoxShadow>? shadow,
  }) {
    return BoxDecoration(
      color: fill ?? cardFill,
      borderRadius: BorderRadius.circular(radius ?? cardRadius),
      border: Border.all(
        color: border ?? cardLine,
        width: borderWidth ?? cardLineWidth,
      ),
      boxShadow: shadow ?? cardShadow,
    );
  }

  // ── THE FIELD RECIPE ───────────────────────────────────────────────────
  //  Anything typed into — a TextField, and the tappable select tiles that
  //  stand in for one — wears this shape, so a picker and a text field read as
  //  the same control.
  static const Color fieldFill = surfaceAlt;
  static const Color fieldLine = line;
  static const double fieldRadius = rMd;
  static const double fieldLineWidth = 1;
  static const EdgeInsets fieldPad =
      EdgeInsets.symmetric(horizontal: s16, vertical: 18);

  static BoxDecoration fieldDecorationOf({
    Color? fill,
    Color? border,
    double? borderWidth,
    double? radius,
  }) {
    return BoxDecoration(
      color: fill ?? fieldFill,
      borderRadius: BorderRadius.circular(radius ?? fieldRadius),
      border: Border.all(
        color: border ?? fieldLine,
        width: borderWidth ?? fieldLineWidth,
      ),
    );
  }

  /// The one shadow left in the system: floating chrome (menus, sheets,
  /// snackbars) may lift off the canvas. Cards may not.
  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x0F101828),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ];

  // ── Type scale (Cairo) ─────────────────────────────────────────────────
  // One ladder. Every font size the app renders is one of these eleven steps:
  // a screen picks a step, it never types a number. Two sizes are *derived*
  // from a measurement rather than chosen (the monogram inside an avatar disc,
  // the rating number beside its star glyph) — those derivations live here
  // too, and `test/type_scale_test.dart` fails the build if any other file
  // types a `fontSize:` number.
  //
  // Why a ladder: 121 call sites were typing their own number next to a scale
  // entry — `AppTheme.caption.copyWith(fontSize: 12)` next to a label at
  // `fontSize: 11.5` — so "how big is a caption?" had no answer, and the same
  // caption rendered at four different sizes across the app. The steps sit 1 dp
  // apart through the reading band because Arabic text in this app lives
  // between 11 and 19 dp, where a half-dp difference is invisible but still a
  // difference; above that the steps are for figures, not prose.
  static const double fsBadge = 11; // count pips, stat labels, overlines
  static const double fsCaption = 12.5; // captions, dense metadata
  static const double fsMeta = 13.5; // list metadata, secondary lines
  static const double fsSmall = 14.5; // secondary body, control labels
  static const double fsBody = 15.5; // the default reading size
  static const double fsLead = 16.5; // card titles, leading body
  static const double fsH2 = 17.5; // panel and section titles
  static const double fsBar = 18.5; // app-bar titles, money figures
  static const double fsH1 = 21; // screen heads
  static const double fsDisplay = 23; // the hero figure
  static const double fsHero = 30; // the landing promise

  /// The ladder in order — for tests, and for the next person who needs a size.
  static const List<double> scale = <double>[
    fsBadge,
    fsCaption,
    fsMeta,
    fsSmall,
    fsBody,
    fsLead,
    fsH2,
    fsBar,
    fsH1,
    fsDisplay,
    fsHero,
  ];

  /// The ladder step closest to [size] — the only legal way to ask for a size
  /// that is derived from a measurement rather than chosen.
  static double nearest(double size) {
    var best = scale.first;
    for (final step in scale) {
      if ((step - size).abs() < (best - size).abs()) best = step;
    }
    return best;
  }

  /// The monogram inside an avatar disc: [ratio] of the disc's diameter. 0.42
  /// for a bare disc, 0.40 where the disc carries a ring.
  static double monogram(double disc, {double ratio = 0.42}) => disc * ratio;

  /// The rating number beside a star glyph, and the review count after it:
  /// two and three steps under the glyph, snapped to the ladder.
  static TextStyle ratingValue(double star) =>
      label.copyWith(fontSize: nearest(star - 2), color: textPrimary);

  static TextStyle ratingCount(double star) =>
      caption.copyWith(fontSize: nearest(star - 3));

  static const TextStyle display = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsDisplay,
      fontWeight: FontWeight.w800,
      height: 1.35,
      color: textPrimary);
  static const TextStyle h1 = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsH1,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: textPrimary);
  static const TextStyle h2 = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsH2,
      fontWeight: FontWeight.w700,
      height: 1.45,
      color: textPrimary);
  static const TextStyle body = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsBody,
      fontWeight: FontWeight.w400,
      height: 1.65,
      color: textPrimary);
  static const TextStyle bodySoft = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsSmall,
      fontWeight: FontWeight.w400,
      height: 1.65,
      color: textSecondary);
  static const TextStyle label = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsSmall,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: textPrimary);
  static const TextStyle caption = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsCaption,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: textMuted);
  static const TextStyle button = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsH2,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: navy);

  /// An app-bar title: a role, not a size. Screens that put a title in the bar
  /// use this instead of shrinking `h1` by hand.
  static const TextStyle bar = TextStyle(
      fontFamily: 'Cairo',
      decoration: TextDecoration.none,
      fontSize: fsBar,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: textPrimary);

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
          fontSize: fsBar,
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
          textStyle: button.copyWith(fontSize: fsLead),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: navy,
          // Size.fromHeight(tapMin) is Size(infinity, 56): the infinite *min
          // width* is fine in a stretched Column, but a TextButton parked in an
          // unbounded Row -- the notifications AppBar trailing slot -- throws
          // "BoxConstraints forces an infinite width" and takes the whole
          // toolbar layout down with it. A text link gets 56 tall and at least
          // 56 wide, and nothing else. (flutter test 13 Sep: 8 red tests.)
          minimumSize: const Size(tapMin, tapMin),
          textStyle: label.copyWith(fontSize: fsBody),
        ),
      ),
      // Every IconButton in the app is 56 dp, not the Material default of a
      // 40 dp box with a 48 dp hit area. This is the one place that can say so
      // for all of them; a per-site `padding:` would have to be repeated 8
      // times and would be forgotten by the next screen.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(tapMin, tapMin),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),

      // ── Inputs ─────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: fieldPad,
        hintStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: fsSmall,
            color: textMuted,
            fontWeight: FontWeight.w400),
        labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: fsSmall,
            color: textSecondary,
            fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: fsSmall,
            color: navy,
            fontWeight: FontWeight.w700),
        errorStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: fsMeta, color: danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: fieldLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: fieldLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: navy, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
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
            borderRadius: BorderRadius.circular(rPill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: label.copyWith(fontSize: fsSmall, color: textPrimary),
        secondaryLabelStyle: label.copyWith(fontSize: fsSmall, color: onNavy),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),

      // ── Cards ──────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: cardFill,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: cardLine, width: cardLineWidth),
        ),
      ),

      dividerTheme: const DividerThemeData(
          color: lineSoft, thickness: 1, space: 1),

      listTileTheme: const ListTileThemeData(
        iconColor: navy,
        textColor: textPrimary,
        titleTextStyle: TextStyle(
            fontFamily: 'Cairo',
            fontSize: fsBody,
            fontWeight: FontWeight.w600,
            color: textPrimary),
        subtitleTextStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: fsMeta, color: textSecondary),
        contentPadding: cardPadRows,
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
            fontFamily: 'Cairo', fontSize: fsCaption, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: fsCaption, fontWeight: FontWeight.w500),
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
              fontSize: fsCaption,
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
            fontSize: fsSmall,
            color: onNavy,
            fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rSm)),
        insetPadding: const EdgeInsets.all(s16),
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
        tilePadding: EdgeInsets.symmetric(horizontal: s16),
        childrenPadding: EdgeInsets.fromLTRB(s16, 0, s16, s16),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: navy,
        unselectedLabelColor: textMuted,
        labelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: fsBody, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: 'Cairo', fontSize: fsBody, fontWeight: FontWeight.w500),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: lineSoft,
      ),
    );
  }
}
