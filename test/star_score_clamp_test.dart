// Five full gold stars beside the number 7.5.
//
// Found on 30 Sep 2026 by the audit that closed the two defect families the
// star row had. `star_row_shape.dart` was opened on 26 Sep to kill one specific
// lie — `RatingStars` branched on `rating.round()` first, so at 4.5 all five
// positions drew a FULL star next to the text «4.5». It fixed the glyphs. It did
// not fix the number, because the number was never in that file: the row printed
// the caller's `rating.toStringAsFixed(1)`, `A11y.rating` printed the same raw
// value, and the clamp lived *only* inside `starIconFor`.
//
// So the same contradiction the file was opened for came straight back through
// the other door. An `avg_rating` outside 0..5 — a 7.5 off the API, or a
// negative, or a NaN — drew five full stars (the clamp, working) next to the
// digits **7.5** (the clamp, absent), and announced «التقييم 7.5 من 5» to a
// screen reader. **The row that can only draw five stars just told you it was
// rated 7.5 out of 5.** "Never overstate" was true of the shapes and false of
// the sentence and the text.
//
// One clamp, three call sites: [clampRating] is now what the glyphs, the
// printed digits and the spoken label each ask. This file exists to hold all
// three to it — a widget-level assertion on the actual `RatingStars`, because
// the bug was never in the arithmetic, it was in which copies of the arithmetic
// had been told about the clamp.
//
// Reachability, stated honestly: no fixture on the platform carries a score
// outside 0..5 and `GET /api/mobile/workers` answers «غير مصرح» without a
// token, so this was latent behind a server trust boundary. That is the whole
// argument for fixing it: it is the one input the server controls and this app
// does not.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/star_row_shape.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/a11y.dart';
import 'package:allomokawil/src/widgets/ui.dart';

Future<void> _row(WidgetTester tester, double score) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Center(child: RatingStars(rating: score))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the digits follow the glyphs', () {
    testWidgets('a 7.5 prints 5.0, not 7.5', (tester) async {
      await _row(tester, 7.5);
      expect(find.text('7.5'), findsNothing,
          reason: 'the row draws five stars; a 7.5 beside them is the lie');
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('a negative score prints 0.0, not the negative', (tester) async {
      await _row(tester, -2.0);
      expect(find.text('-2.0'), findsNothing);
      expect(find.text('0.0'), findsOneWidget);
    });

    testWidgets('NaN prints 0.0, not «NaN»', (tester) async {
      await _row(tester, double.nan);
      expect(find.text('NaN'), findsNothing);
      expect(find.text('0.0'), findsOneWidget);
    });

    testWidgets('an infinite score prints 5.0', (tester) async {
      await _row(tester, double.infinity);
      expect(find.text('Infinity'), findsNothing);
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('a score inside the scale is untouched', (tester) async {
      await _row(tester, 4.5);
      expect(find.text('4.5'), findsOneWidget,
          reason: 'the fix must not move every score, only the impossible ones');
    });

    testWidgets('the spoken label cannot claim 7.5 either', (tester) async {
      await _row(tester, 7.5);
      final node = tester.getSemantics(find.byType(RatingStars));
      expect(node.label, isNot(contains('7.5')),
          reason: 'a screen reader must hear the same score the glass shows');
      expect(node.label, contains('5.0'));
    });
  });

  group('clampRating is the one rule all three ask', () {
    test('it pins to the ends', () {
      expect(clampRating(7.5), 5.0);
      expect(clampRating(-2), 0.0);
      expect(clampRating(double.nan), 0.0);
      expect(clampRating(double.infinity), 5.0);
      expect(clampRating(double.negativeInfinity), 0.0);
    });

    test('it leaves a real score exactly as it was', () {
      for (var t = 0; t <= 5000; t++) {
        final r = t / 1000.0;
        expect(clampRating(r), r, reason: 'the clamp moved a legal score at $r');
      }
    });

    test('it is a pure function of the score, in both directions', () {
      expect(clampRating(3.7), 3.7);
      expect(clampRating(3.7), clampRating(3.7));
    });

    test('every score the row can hold leaves it able to draw', () {
      for (var t = -2000; t <= 8000; t++) {
        final r = t / 1000.0;
        expect(() => starRowShape(r), returnsNormally,
            reason: 'the row must never throw on a server number at $r');
      }
    });
  });

  group('the row and its number agree at every score on the scale', () {
    test('no score prints a number its own row cannot back', () {
      // The property the 26 Sep file states as "never overstate", checked on the
      // printed digits rather than the glyph value: the number beside the row
      // must never exceed the scale the row is drawn on.
      for (var t = -500; t <= 6000; t++) {
        final r = t / 1000.0;
        final printed = double.parse(clampRating(r).toStringAsFixed(1));
        expect(printed, lessThanOrEqualTo(A11y.scale.toDouble()),
            reason: 'a score of $r printed a number off the scale');
      }
    });
  });
}
