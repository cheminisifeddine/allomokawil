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
// box, never by `rect.left`, so this file asserts the *horizontal* and says so
// rather than grading the whole rectangle. The vertical used to be excused
// here as off-grid tap arithmetic (`10 + 56 + 4`); that was inverted — the
// `SizedBox(height: tapMin)` holds the 56 dp — and it is `s8`/`s4` now, so the
// vertical group below measures it directly.
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

    testWidgets('the vertical band is on the ladder, not off it', (tester) async {
      // Both the tall and the short band, because they are different shapes and
      // only one of them carries a tap target.
      //
      // **This case used to assert `tapMin + 14` (70 dp) and cite the padding as
      // the reason the action stayed 56 dp. That was inverted, and it was the
      // reason the off-grid `10` survived two sweeps.** The 56 dp is
      // `SizedBox(height: AppTheme.tapMin)` inside the row; the padding only
      // wraps it. Zeroing this padding to 0 still measured the action at
      // exactly 56.0 dp, and `tap_target_test.dart` passed green with it gone.
      //
      // So the case now asserts what actually has to hold — the **action**,
      // not the band — plus the band arithmetic as arithmetic. The row is 25 dp
      // (a 19 dp icon beside 17.5 dp Cairo text at height 1.45), so the band is
      // `8 + 25 + 4` = 37 dp without an action and `8 + 56 + 4` = 68 with one.
      await _pump(tester);
      expect(tester.getSize(find.byType(SectionTitle)).height, 37.0,
          reason: 'no action: s8 + a 25 dp row + s4. Both paddings are on the '
              'ladder; the row height is the text/icon, not a literal');

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
      expect(withAction, AppTheme.tapMin + AppTheme.s8 + AppTheme.s4,
          reason: 's8 + 56 + s4. The band is the action plus the two steps');

      // The property the old comment claimed and nobody ever checked: the tap
      // target is the action's own height, and it holds **without** the band's
      // padding contributing anything to it.
      final action = find
          .ancestor(
              of: find.text('عرض الكل'), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(action).height, AppTheme.tapMin,
          reason: 'the 56 dp belongs to SizedBox(height: tapMin), not to the '
              'band padding — this is the reason the vertical was free to '
              're-grid');
    });

    testWidgets('the action is 56 dp however the band is padded', (tester) async {
      // The falsification, kept as a test so the old claim cannot come back as
      // a comment: wrap the widget in caller-owned vertical padding and the
      // action must measure the same. If it ever moves with the padding again,
      // something other than `SizedBox(height: tapMin)` is sizing it.
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
          body: Padding(
            padding: const EdgeInsets.only(top: 40, bottom: 24),
            child: SectionTitle('مقاولون موثوقون',
                actionText: 'عرض الكل', onAction: () {}),
          ),
        ),
      ));
      await tester.pump();

      final action = find
          .ancestor(
              of: find.text('عرض الكل'), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(action).height, AppTheme.tapMin,
          reason: 'the action is sized by its own SizedBox; band padding and '
              'caller padding are both external to it');
    });
  });
}
