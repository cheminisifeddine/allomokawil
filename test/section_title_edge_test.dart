// `SectionTitle`'s own inset, measured — the shared widget's half of R4.
//
// Why this file exists. Every other geometry guard in this repo asks "which
// column does this screen sit on", and the answer for a *shared widget* is the
// wrong question: `SectionTitle` has **25 call sites across eight screens** and
// no column of its own. So the question has to be the other one the sweep
// needs answered — **which caller's column would break if this inset moved** —
// and the answer, measured, is "all of them, and none of them had asked".
//
// The widget carried `EdgeInsets.fromLTRB(2, 10, 2, 4)` since the design
// overhaul. That `2` is an optical guess: it is not a column edge, not an
// alignment against an icon, and not a caller's inset — it is 2 dp of nothing,
// typed inside a shared widget, that pushed the heading 2 dp *inside* the band
// it introduces on every one of the 25 call sites. Four of those callers wrap it
// in their own `Padding` and the other 21 inherit a list's `pagePad`, so in both
// shapes the caller already owns the edge and the widget was adding to it.
//
// **The two guards that already covered this widget could not have caught it,
// and that is the reason this file is not a duplicate of them.** Both
// `worker_home_inset_test.dart` and `customer_home_column_test.dart` measure
// `SectionTitle`'s **outer** rect — the `Padding` widget's box, which a
// `Padding` lays out at its parent's full width. So they compare the widget's
// edge with the caller's edge and pass for *any* inset, including this one.
// This file reads the **inner** edge: the row's own box, i.e. the place the
// heading's glyphs actually start.
//
// The second trap, inherited and re-paid: `Padding` is measured by its content
// box, never by `rect.left`, and the vertical `10`/`4` are deliberately left
// off-grid (they are the arithmetic that keeps a 56 dp tap target inside a
// 70 dp band — see `tap_target_test.dart`), so this file asserts the
// *horizontal* and says so rather than grading the whole rectangle.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// The x at which the heading's own row starts — the widget's inner edge.
///
/// `SectionTitle`'s `Padding` lays out at its parent's full width, so its rect
/// is the *outer* edge and `rect.left + padding.left` is the answer. Reading
/// the rect alone is what the two existing guards do, and it is why they
/// cannot fail for this bug.
double _rowLeft(WidgetTester tester) {
  final row = find.descendant(
    of: find.byType(SectionTitle),
    matching: find.byType(Row),
  ).first;
  return tester.getTopLeft(row).dx;
}

/// The widget's outer edge, for the before/after comparison.
double _bandLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(SectionTitle)).dx;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: SectionTitle('التخصصات', icon: Icons.grid_view_rounded),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('SectionTitle sits on the edge its caller already owns', () {
    testWidgets('the heading adds no inset of its own', (tester) async {
      await _pump(tester);

      // The caller's padding is 18 — `AppTheme.gutter`, the house page inset,
      // and the shape 21 of the 25 call sites actually have.
      expect(_bandLeft(tester), AppTheme.gutter,
          reason: 'sanity: the band takes the caller\'s left edge');

      expect(_rowLeft(tester), AppTheme.gutter,
          reason: 'the heading was 2 dp inside the band it introduces. This is '
              'the number the two existing guards cannot see: they read the '
              'Padding\'s outer rect, which is the caller\'s edge either way, '
              'so they pass for any inset at all');
    });

    testWidgets('the same holds with no action and no caller padding',
        (tester) async {
      // The other shape: a bare `SectionTitle` in a body with no padding at all,
      // which is what the 21 list-borne callers reduce to once `pagePad` is
      // peeled off. The widget must not re-introduce an edge of its own.
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(
          body: SectionTitle('مشاريعي الأخيرة', icon: Icons.folder_outlined),
        ),
      ));
      await tester.pump();

      expect(_rowLeft(tester), _bandLeft(tester),
          reason: 'with nothing wrapping it the band IS the screen edge, and '
              'the heading must start there');
      expect(_rowLeft(tester), 0.0);
    });

    testWidgets('the vertical band is unchanged by this slice',
        (tester) async {
      // Both the tall and the short band, because they are different shapes and
      // only one of them is the a11y one.
      //
      // **My first version of this case asserted 70 dp and it was wrong — the
      // fixture has no action, so there is no 56 dp `SizedBox` inside it.** The
      // band is `10 + text + 4` = 39 dp without an action and `10 + 56 + 4` =
      // 70 with one. That is the a11y tick's arithmetic and it is load-bearing:
      // `tap_target_test.dart` measures the 56 dp action directly. So this case
      // pins the *short* band here and the tall one below, and the off-grid
      // `10` stays counted on purpose in both.
      await _pump(tester);
      expect(tester.getSize(find.byType(SectionTitle)).height, 39.0,
          reason: 'no action: 10 + heading + 4. This must not move under a '
              'slice about the horizontal');

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SectionTitle('مقاولون موثوقون',
              actionText: 'عرض الكل', onAction: () {}),
        ),
      ));
      await tester.pump();

      final withAction = tester.getSize(find.byType(SectionTitle)).height;
      expect(withAction, AppTheme.tapMin + 14,
          reason: '10 + 56 + 4. This is the band that has to keep a 56 dp tap '
              'target whole, and it is why the off-grid `10` is still here');
    });
  });
}
