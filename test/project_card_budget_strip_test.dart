// The budget strip was not the app's pill.
//
// `card_recipe_test.dart`'s R4 has been counting this site for weeks —
// `symmetric(horizontal: 10, vertical: 7)` at `project_card.dart:90` — and
// priced it at one line among 22, the same price as the tap-floor `6 x 2` on
// the auth checkbox row and the `14 x 12` on the trade filter, every one of
// which carries a paragraph saying why it is off the ladder on purpose. This
// one carries none. It was not a decision.
//
// **What the number hid.** The kit already has the answer written down:
// `AppTheme.pillPad` = `symmetric(horizontal: 10, vertical: 6)` with
// `AppTheme.pillGap` = 6 and a 14 dp glyph, and `StatusPill` and
// `CategoryBadge` both use them. This strip is the same idea drawn at a
// second size, and it is drawn *in the same card*, ~40 dp apart:
//
//   * `CategoryBadge` (the trade, line 1) .. 10 x 6 inset, 14 dp glyph, 6 dp gap
//   * `StatusPill`    (line 3, 9 dp above) 10 x 6 inset, 14 dp glyph, 6 dp gap
//   * this budget strip ..................... 10 x 7 inset, 14 dp glyph, 5 dp gap
//
// One card, three capsules, two of them agreeing with each other and the third
// off by a dp on both halves. The horizontal already matched, which is exactly
// what hid it: `10` is on the ladder and reads as deliberate, and the two dp
// that were wrong — the vertical and the gap — are the ones a reader sees as
// "unfinished" rather than as a defect.
//
// **It is a label, not a tap target**, which is the only reason `pillPad`
// binds rather than `_FilterPill`'s larger `14 x 12`. Nothing wraps this strip
// in a `GestureDetector` or an `InkWell` and it takes no `onTap`; the card's
// only tap is `AppCard`'s, on the row itself. The test asserts that rather
// than assuming it, so the exemption is earned rather than assumed — the same
// check slice 24 wrote for the header pill.
//
// **What R4 structurally cannot see**, which is why this is a test and not a
// decrement. R4 counts literals inside `EdgeInsets.*`; `AppTheme.pillPad` is an
// *identifier* and `_literals()` skips identifiers by design, so moving this
// site onto the token takes the ratchet 22 -> 20 while changing nothing about
// whether the capsules agree. That is slice 23's lesson and slice 24's, in
// order: the numbers that were wrong were spelled as an identifier and never
// appeared in source for R4 to read.
//
// **So the assertions are equality, not constants.** The expected inset is
// resolved from `AppTheme.pillPad` and compared against the padding actually
// on the widget, and the icon-word gap is read off the *built tree* — between
// the two painted rects, because a `SizedBox` gap has no rect of its own in
// some builds. Nothing here transcribes 10, 6, 7, 14 or 5: a test that wrote
// the expected numbers down would have passed before the fix and after it, and
// would keep passing through any future drift — the stale-constant trap
// `tile_label_fit_test.dart` records.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/widgets/project_card.dart';
import 'package:allomokawil/src/widgets/ui.dart' show AppCard;

Project _project({int? min = 60000, int? max = 600000}) => Project(
      id: '7',
      customerId: 30,
      title: 'تтомуيم شقة',
      category: 'plumbing',
      images: const <String>[],
      wilaya: '16',
      budgetMin: min,
      budgetMax: max,
      urgency: UrgencyLevel.flexible,
      status: ProjectStatus.open,
    );

/// The `Container` that draws the budget strip.
///
/// Narrowed by a predicate rather than by "the nearest ancestor", and the
/// predicate needs *two* conditions, not one. The strip sits inside `AppCard`,
/// and `find.ancestor` walks up through the card's own padded `Container`
/// first — so `padding != null` alone matches **two** widgets and the
/// assertion reads whichever the engine hands back. That is the same trap
/// slice 24 recorded for the header pill, and it produces a confident-looking
/// measurement of the wrong box rather than an error.
///
/// So the finder discriminates on the strip's own identity: it is the only
/// padded `Container` painted in [AppTheme.accentWash] (the card paints
/// [AppTheme.cardFill]). `cardFill == surface`, so checking the fill is what
/// separates the two without hard-coding a radius or an inset.
Finder _budgetStrip() => find.ancestor(
      of: find.byIcon(Icons.payments_rounded),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.padding != null &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).color == AppTheme.accentWash,
      ),
    );

void main() {
  group('the budget strip is the app\'s pill', () {
    testWidgets('it sits on the shared token, not its own numbers',
        (tester) async {
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
        home: Scaffold(body: ProjectCard(project: _project())),
      ));

      expect(find.byIcon(Icons.payments_rounded), findsOneWidget,
          reason: 'the budget strip is what is under test');

      final strip = _budgetStrip();
      expect(strip, findsOneWidget);
      final box = tester.widget<Container>(strip);
      const want = AppTheme.pillPad;

      // Resolved from the token on both sides: the failure prints the two
      // EdgeInsets, so the message is the disagreement itself rather than a
      // re-typing of either number.
      expect(box.padding, want,
          reason: 'the budget strip is a label, so it is the pill the other '
              'labels use — AppTheme.pillPad. It shares a card with a '
              'CategoryBadge and a StatusPill, both already on that token.');

      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppTheme.rSm),
          reason: 'the strip is a full-width band, not a capsule: rSm is '
              'deliberate and unchanged. Only the inset and the gap were '
              'wrong.');
    });

    testWidgets('it is a label, so it is not a tap target', (tester) async {
      // The reason the trade filter's bigger 14 x 12 does not bind here is
      // that that one IS tappable. If this strip ever grows an onTap the
      // argument above stops applying, so it is written down where the next
      // reader will hit it.
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
        home: Scaffold(body: ProjectCard(project: _project())),
      ));

      final taps = find.descendant(
          of: _budgetStrip(), matching: find.byType(GestureDetector));
      final ink = find.descendant(
          of: _budgetStrip(), matching: find.byType(InkWell));
      expect(taps, findsNothing,
          reason: 'a tappable pill is held to the tap recipe, not pillPad');
      expect(ink, findsNothing);
    });

    testWidgets('the icon sits a pillGap from the word, measured off layout',
        (tester) async {
      // The inset is one half of a pill; the gap between the glyph and the
      // word is the other, and it is the half a reader sees as "unfinished".
      // This site drew it at 5 while `StatusPill` and `CategoryBadge` draw
      // `AppTheme.pillGap` — the same 1 dp disagreement slice 11 fixed inside
      // the kit, arriving again on a card nobody had compared.
      //
      // Measured between the two *painted* boxes, not from the source text.
      // RTL: the glyph leads on the START edge, which is the RIGHT one, so the
      // near edge of the glyph is its `left` and the near edge of the word is
      // its `right`; read the other way round and this returns a large
      // negative number that looks like a real measurement of something else.
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
        home: Scaffold(body: ProjectCard(project: _project())),
      ));

      final iconRect = tester.getRect(find.byIcon(Icons.payments_rounded));
      final textRect = tester.getRect(find.descendant(
        of: _budgetStrip(),
        matching: find.text('الميزانية'),
      ));
      final gap = iconRect.left - textRect.right;

      expect(gap, closeTo(AppTheme.pillGap, 0.01),
          reason: 'measured from the icon\'s far edge to the word\'s near '
              'edge; the engine said $gap, the kit says ${AppTheme.pillGap}');
    });

    testWidgets('the strip is drawn, and its box is the token\'s box',
        (tester) async {
      // The pixel gate for the fix. A padding assertion can be satisfied by a
      // widget that is never laid out, and this band is *below the fold* on the
      // customer home at 392x850 — so none of the nine `design_shots_test.dart`
      // baselines move when this changes, which is exactly why the numbers need
      // a picture of their own.
      //
      // The size is compared against `pillPad` rather than typed out, so this
      // reads the token rather than restating it. `tapMin` is the floor a
      // tappable capsule is held to; a label is not, and this band is a label.
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
        home: Scaffold(body: ProjectCard(project: _project())),
      ));

      final stripRect = tester.getRect(_budgetStrip());
      final rowRect = tester.getRect(find.descendant(
          of: _budgetStrip(), matching: find.byType(Row)).first);

      // **The band's height is not the glyph's height.** The row is as tall as
      // its tallest child, and the tallest child is the *text line box* — the
      // Arabic caption at `fsCaption` on a 1.4 line-height measures 19 dp
      // against the 14 dp glyph beside it. Writing the assertion as
      // "glyph + pad" and expecting a token-derived number read **31 against
      // 26** here, which looks exactly like a 5 dp regression and is not one.
      // Measured off the tree instead: whatever the row is, the padding on the
      // box around it must be the token's, and that is the property.
      final painted = stripRect.height - rowRect.height;
      expect(painted, closeTo(AppTheme.pillPad.top + AppTheme.pillPad.bottom,
          0.01),
          reason: 'the content row measures ${rowRect.height}, so the box '
              'around it contributes $painted; the token says '
              '${AppTheme.pillPad.top + AppTheme.pillPad.bottom}');
      // The band is full-bleed *within the column it sits in*, not within the
      // card: the card is a Row of [thumb, gap, Expanded(column)], so the
      // column is the card minus the thumb and its gap. Measured against that
      // column rather than against a typed constant, because the thumb's
      // width is not something this test should be restating.
      final columnRect = tester.getRect(find.descendant(
              of: find.byType(AppCard), matching: find.byType(Column))
          .first);
      expect(stripRect.width, closeTo(columnRect.width, 0.01),
          reason: 'the band spans its whole column, so a short budget range '
              'cannot leave a ragged gap on the right');
      expect(stripRect.right, closeTo(columnRect.right, 0.01),
          reason: 'and it is flush with that column\'s trailing edge');
      expect(stripRect.height, lessThan(AppTheme.tapMin),
          reason: 'it is a label, so it is not held to the tap floor — if a '
              'future change makes it tappable this is the line that says so');
    });

    testWidgets('a project with no budget draws no strip at all',
        (tester) async {
      // The band is conditional on a budget existing. A strip that fell back
      // to a placeholder would put a fourth geometry on the same card, so the
      // "one idea, one size" claim above is only true while this holds.
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
        home: Scaffold(body: ProjectCard(project: _project(min: null, max: null))),
      ));

      expect(find.byIcon(Icons.payments_rounded), findsNothing);
      expect(find.text('الميزانية'), findsNothing);
    });
  });
}
