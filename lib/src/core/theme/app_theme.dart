import 'package:flutter/material.dart';

import 'motion.dart';

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

  /// The outline of a control that must read as tappable: the secondary and
  /// outline buttons, the photo-picker box, the verified badge ring. It is
  /// **1.5, not 1** — at 1 the boundary of a button stopped separating it from
  /// the card it sits on, which is the one thing an outline exists to do.
  ///
  /// It was a literal typed into five widgets and one theme before this, so
  /// "how thick is a control outline?" had no answer and changing it meant
  /// finding all five by hand. A screen names the token, never the number.
  static const double hairline = 1.5;











































































  /// The outline of a control that is **currently selected** — a chosen trade
  /// chip, the category tile you tapped, an unread row.
  ///
  /// It was `selected ? 2 : 1` in five widgets and `unread ? 1.4 : 1` in a
  /// sixth. Two different pairs for the same idea ("this one is picked"), so a
  /// design change meant finding all six by hand and none of them agreed. The
  /// pair is now one name: [hairlineSelected] over [hairlineResting].
  static const double hairlineSelected = 2;

  /// The outline of a field that is **being typed in**, or in error.
  ///
  /// It is deliberately thicker than [hairline] — that is what separates "I am
  /// typing here" from a resting field, and a focus ring the same weight as the
  /// resting outline is not a focus ring.
  ///
  /// The phone field was `1.8` while the input theme (639/647), the auth
  /// checkbox and the passcode field all said `2`, so the one field a user
  /// types their phone number into — the highest-stakes input in the app — had
  /// the thinnest focus ring in it. Named here so that drift cannot come back.
  static const double hairlineFocus = 2;

  /// The outline of a control that is **not** selected. See [hairlineSelected].
  ///
  /// Note this is [hairline] (1.5) and not 1, where the six all sat. 1 was the
  /// same value the old literals used, but those literals were a *pair* whose
  /// resting half nobody owned; aligning the resting outline onto [hairline]
  /// makes a selected control read as `hairlineSelected` against a
  /// `hairline` background rather than as 2 against 1.
  static const double hairlineResting = hairline;

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

  // ── The small pill — one inset, one icon gap ────────────────────────────
  /// The tiny metadata pill: a 14 dp icon, a one-word caption, fully rounded
  /// ends. [CategoryBadge], [StatusPill] and the project page's place chip are
  /// all this widget, and **they are drawn side by side** — the worker's
  /// filter strip is a `StatusPill`, the wilaya pill, then a `CategoryBadge`
  /// for every trade; the project page puts the status pill, every trade badge
  /// and the place chip in one `Wrap`. A pill is judged against the pill it
  /// sits next to, so their insets have to be one number.
  ///
  /// **The bug this token exists to prevent, measured:** all three wrote
  /// `symmetric(horizontal: 10, vertical: 6)` — byte-identical — and then
  /// disagreed on the gap between the icon and the word: the two siblings used
  /// `6` and [StatusPill] used `5`. So on the worker's filter strip the first
  /// pill («الكل») sat 1 dp tighter to its icon than «كل الولايات» beside it,
  /// and the trade badge after it. Same padding, same radius, same font, one
  /// pixel of slop between neighbours that are supposed to read as one row.
  /// Nobody sees 1 dp as a *defect*; everybody sees it as *unfinished*.
  ///
  /// Neither number is on the 4 dp ladder and both are deliberate: 10 x 2 + a
  /// 14 dp icon is the width a two-Arabic-word caption needs to sit inside a
  /// card without wrapping, and the inset is held at 6 so pill height
  /// (14 + 6x2 = 26) stays clear of [tapMin] — these are **labels, not
  /// targets**. The `14 x 12` insets elsewhere in the app are three unrelated
  /// components, not one chip inset -- see the note where `chipTheme` used to
  /// be declared, and `test/card_recipe_test.dart` R4.
  static const EdgeInsets pillPad =
      EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  /// The numeral inside a **count pip** — the small round capsule that carries a
  /// number and nothing else: the unread count on a tab bar, the bell's count,
  /// a thread's unresolved-message count, and the two pips an inbox row draws
  /// in its trailing column.
  ///
  /// A count pip is judged against the count pip **stacked beside it**. An
  /// inbox row draws two of them — messages this phone still owes (the cloud
  /// pip) and messages the server has not acknowledged (the accent pip) — in
  /// the same column, `minWidth` [pipMinW] apart, with byte-identical padding.
  ///
  /// **The bug this token exists to prevent, measured.** Both pips in that
  /// column wrote the same box and then disagreed about the number *inside* it:
  /// the cloud pip at [fsBadge] (11 dp) and the accent pip at [fsCaption]
  /// (12.5 dp). Two capsules of 19 dp and 21 dp, one on top of the other, on
  /// the one row that carries both — which is the row a user reaches on a
  /// dropped connection, the exact situation the queued pip exists to warn
  /// about. Nothing else in the app is inconsistent about this: the tab-bar pip
  /// and the bell's are both [fsBadge], so the inbox was the only place a count
  /// was drawn at a second size.
  ///
  /// [fsBadge] is the count numeral app-wide. [pillPad] and [pillGap] are the
  /// *word* pills and stay separate — those carry an icon and a label, this
  /// carries a digit.
  static const double pipNumeral = fsBadge;

  /// The gap between a pill's icon and its word. One number for every pill,
  /// so a new pill cannot arrive with its own idea of the spacing.
  ///
  /// Off the 4 dp ladder on purpose, like [pillPad]: it is optical spacing
  /// between a 14 dp glyph and [fsCaption] text at 1.4 line-height, not a
  /// column edge. `R4` counts it and is wrong to — see
  /// `test/pill_inset_test.dart`, which asserts the *equality* between the
  /// writers instead.
  static const double pillGap = 6;

  /// The width a count pip never draws narrower than, so a one-digit count and
  /// a `99+` count are both a pill and not a lozenge.
  static const double pipMinW = 24;

  /// A count pip's inset, both edges.
  ///
  /// **The `vertical: 3` is off the 4 dp ladder on purpose**, exactly like
  /// [pillPad] and [pillGap]: it is the capsule's own proportion around an
  /// 11 dp numeral rather than a component gap, and it is held so a pip
  /// reading 19 dp stays clear of [tapMin]. These are **labels, not targets** —
  /// the tap target around them is the whole row.
  ///
  /// R4 counts the `3` and is wrong to, the same way it is wrong to about
  /// [pillPad] and [pillGap]; see `test/pill_inset_test.dart` for the argument
  /// that the *equality* of the writers is the property worth asserting.
  /// This file puts the number somewhere it is written down once.
  static const EdgeInsets pipPad =
      EdgeInsets.symmetric(horizontal: 8, vertical: 3);

  /// The white ring drawn around an avatar or a selected chip, so the thing
  /// inside it separates from the thing behind it.
  ///
  /// Not a gap and not on the 4 dp grid, and deliberately so: at 4 dp it eats
  /// 1 dp of the icon it is supposed to frame, and at 2 dp it does not separate
  /// a navy avatar from a navy header. It is a hairline with a job, the same
  /// kind of exception [gutter] is, and like [gutter] it now has a name — two
  /// writers had each typed their own `3`.
  static const double ring = 3;

  /// The page gutter. Deliberately 18 — it is the one value that is not a
  /// component gap, so it lives alone and never gets reused as one.
  static const double gutter = 18;

  /// The width and height of one card in the client's horizontal contractor
  /// strip, and the reason the strip is as tall as it is.
  ///
  /// A layout bound, not a component gap, and it exists because of a
  /// measurement rather than a preference. The vertical card draws up to six
  /// stacked lines — avatar row, name, specialty, rating row, years, and
  /// «غير متاح الآن» when the man is paused — and the tallest real card
  /// measures **165 dp** of content with the real Cairo font loaded, not the
  /// test fallback.
  ///
  /// At the old strip height of 190 the column was handed 190 - 34 = 156 dp,
  /// so that card overflowed by 9 dp and Flutter painted the yellow-and-black
  /// stripe over it. The one genuinely paused contractor in this market —
  /// id 73 — had his "not taking work" line clipped off the bottom of the
  /// card on the very screen a customer picks him from, which is the opposite
  /// of what that label was added to say.
  ///
  /// At 208 the column gets 174 dp: 9 dp of slack against real content, so a
  /// card that fits by 1 dp is not what ships.
  static const double stripCardW = 172;
  static const double stripH = 208;

  /// `cardPad` is 16 dp on each edge and [cardLine] a 1 dp border, so the
  /// inner height the strip actually offers the card.
  static const double stripInnerH = stripH - 34;

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

  /// The widest the trailing price column of a plan card may draw.
  ///
  /// A layout bound, not a type size, and it exists because of a measurement:
  /// printing «المبلغ المعتمد 4500 دج» under a price made the Row overflow by
  /// 53 px on a 392 dp phone. The marked figure is the whole point of the
  /// card, so the column takes a fixed share of the card and the amount wraps
  /// rather than pushing the plan name out of the view.
  static const double priceColW = 132;

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

  /// The line-height ladder — the second half of the type scale, and for a
  /// long time the half nobody named.
  ///
  /// The font sizes above got a ladder on their own; the **spacing between
  /// lines** did not, so "how loose is this paragraph?" had no answer and the
  /// answer was typed by hand into **41 sites across 21 files**. Measured on
  /// this tree, by AST rather than by grep: 1.5 x19, 1.6 x13, 1.25 x2, 1.2 x4,
  /// and one each of 1.15, 1.1 and 1.45. A grep counted 46, because it also
  /// counted five mentions inside comments -- which is the same trap as the
  /// font ladder's `fontSize: 11.5`, where a comment read as a writer.
  ///
  /// These are **exactly** the numbers that were already in the widgets. A
  /// screen names the token and the rendering is byte-identical, so this is a
  /// rename with no visual delta: changing any of these is now a one-line
  /// decision instead of a sweep across 21 files.
  static const double lhTightest = 1.1; // a number pip on the tab bar
  static const double lhBadge = 1.15; // the tab bar's own count
  static const double lhTile = 1.25; // a category tile label, capped at 2 lines
  static const double lhProse = 1.5; // the default for running Arabic prose
  static const double lhRoomy = 1.6; // dense metadata that must breathe
  static const double lhList = 1.2; // single-line rows, chat bubbles
  static const double lhSubtle = 1.45; // muted one-liners under a caption

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
      // One tempo for every push. Without this, Material decides: a 300 ms zoom
      // on Android, a fade-forwards on the newest Android, a horizontal slide
      // on iOS — three different speeds for the same screen, none of them the
      // 200 ms a revealed list row uses. The app's own transition runs on
      // AppMotion.screen everywhere.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
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
          side: const BorderSide(color: line, width: hairline),
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

      // ── Chips ──────────────────────────────────────────────────────────
      // **There is no `chipTheme`, and that is deliberate.** This app builds
      // its own chips (`TradeFilterBar`'s `_FilterPill`, `CategoryGrid`'s
      // `SelectableTile`, `ui.dart`'s `CategoryBadge`/`StatusPill`) and the
      // kit's hard rule at the top of `ui.dart` forbids Material chips: they
      // inherit colour and rendered white-on-white before.
      //
      // A `ChipThemeData` used to sit here anyway, declaring an inset
      // `symmetric(horizontal: 14, vertical: 12)` that three *unrelated*
      // components also spelled by hand. Measured 7 Oct: it was consumed
      // **zero** times — no `Chip`/`RawChip`/`ChoiceChip`/`FilterChip`/
      // `ActionChip`/`InputChip` anywhere in `lib/` or `test/`, no subclass,
      // no chip package in `pubspec.yaml`. So the one field that made those
      // three look like "one inset written four times" was the one field that
      // rendered nothing, and a token built on it would have been three
      // renames and zero pixels.
      //
      // Deleting it also removes a trap: a live `chipTheme` invites exactly
      // the Material `Chip` the kit's own rule bans, and the next person to
      // add one would inherit an inset measured against nothing. If a chip is
      // ever needed here it arrives with its component and its own token
      // (`pillPad` for the small pill, which is 10x6, not 14x12).

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
