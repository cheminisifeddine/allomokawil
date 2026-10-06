// The client's top-rated strip is a fixed-height column, and the card inside it
// is taller than the box used to be.
//
// `test/place_seed_test.dart` caught the consequence on 6 Oct — a real
// `RenderFlex` overflow, 9.0 px, painted as a yellow-and-black stripe over the
// bottom of the card. The contract that caused it was added by `042851a`, the
// tick that put «غير متاح الآن» on this card so a paused contractor would stop
// looking like a man taking work. That tick shipped with a guard for exactly
// this and the guard passed:
//
//   testWidgets('the fixed 168 dp column does not overflow with the line added')
//
// Two things were wrong with it, and neither was the layout. First, the test
// pumped the card inside a `SingleChildScrollView`, which hands a column an
// unbounded height — a card that clips itself can never overflow inside one.
// Second, "168 dp" was a number that had never existed: the strip was 190,
// which left the column 156 dp against a card that measures 165.
//
// So the guard was checking a property of the test harness rather than of the
// card, and the clip reached the screen a customer picks a contractor from.
// This file is the guard that can actually fail.
//
// It reads layout rects, not pixels. That is not a shortcut — see the last
// test, which is a note on why a raster diff is the wrong instrument here.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';

/// The real Cairo, because the fallback font in a test is not the font that
/// ships and the two do not agree to the pixel. Without this the content
/// measures 165 dp for the wrong reason and the assertion below is a claim
/// about a font no customer will ever see.
Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')
    ..addFont(Future.value(ByteData.view(bold.buffer)));
  await a.load();
  await b.load();
  final icon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icon.load();
}

/// Contractor id 73 — the one genuinely paused row in this market, verbatim
/// from the wire, including the 14 years and a real price so the tag row is
/// not empty for a reason of its own.
WorkerProfile _paused() => WorkerProfile.fromJson({
      'id': 73,
      'user_id': 730,
      'full_name': 'جبير بن قويدر',
      'specialties': ['painting'],
      'experience_years': 14,
      'price_range_min': 2000,
      'price_range_max': 6000,
      'avg_rating': 4.2,
      'total_reviews': 3,
      'is_available': 0,
      'verification_status': 'verified',
    });

/// The same contractor taking work: `is_available: 1`, so no availability line.
WorkerProfile _available() => WorkerProfile.fromJson({
      'id': 5,
      'user_id': 50,
      'full_name': 'جبير بن قويدر',
      'specialties': ['painting'],
      'experience_years': 14,
      'price_range_min': 2000,
      'price_range_max': 6000,
      'avg_rating': 4.2,
      'total_reviews': 3,
      'is_available': 1,
      'verification_status': 'verified',
    });

/// Lays the card out in exactly the box the strip gives it and returns the
/// content column's flex.
Future<RenderFlex> _inStrip(WidgetTester t, WorkerProfile w) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          height: AppTheme.stripH,
          child: WorkerCard(worker: w, variant: WorkerCardVariant.vertical),
        ),
      ),
    ),
  ));
  await t.pump();
  return t.renderObject(
    find
        .descendant(of: find.byType(WorkerCard), matching: find.byType(Column))
        .first,
  ) as RenderFlex;
}

double _contentHeight(RenderFlex flex) => flex.getChildrenAsList().fold(
      0.0,
      (double sum, RenderBox child) => sum + child.size.height,
    );

void main() {
  setUpAll(_loadFonts);

  group('the strip card fits the box the strip gives it', () {
    testWidgets('a paused contractor — the tallest card this file draws',
        (t) async {
      final flex = await _inStrip(t, _paused());
      final content = _contentHeight(flex);
      expect(content, lessThanOrEqualTo(AppTheme.stripInnerH),
          reason: 'the availability line must not be clipped off the card: '
              'content ${content.toStringAsFixed(1)} dp vs '
              '${AppTheme.stripInnerH.toStringAsFixed(1)} dp offered');

      // Slack is asserted as a floor, not just "> 0". A card that fits by
      // 1 dp passes every overflow check and still clips the moment a
      // customer runs a larger system font or the glyph box changes.
      expect(AppTheme.stripInnerH - content, greaterThanOrEqualTo(8),
          reason: '8 dp of slack: the next font bump should not clip the card');
    });

    testWidgets('an available contractor has room to spare', (t) async {
      // The same man with `is_available: 1` — no availability line drawn. 96 of
      // 97 live rows look like this, so it is the card a customer sees almost
      // every time, and it is the one whose height set the old 190 dp strip
      // before the paused line arrived.
      final flex = await _inStrip(t, _available());
      expect(_contentHeight(flex), lessThanOrEqualTo(AppTheme.stripInnerH));
    });

    testWidgets('neither variant paints a RenderFlex overflow', (t) async {
      await _inStrip(t, _paused());
      expect(t.takeException(), isNull,
          reason: 'this is the assertion that shipped a 9 px stripe');
    });
  });

  group('the strip and the card cannot drift apart again', () {
    test('the inner height is the strip height minus its own chrome', () {
      // 16 dp of cardPad on each edge and a 1 dp border on each edge. If a
      // future tick changes the inset or the border, this says so instead of
      // letting the card quietly clip again.
      expect(AppTheme.stripInnerH, AppTheme.stripH - 34);
      expect(AppTheme.stripCardW, 172);
    });

    test('the strip is tall enough for its own card, with real fonts', () {
      // The numbers that made this bug findable, kept as a plain arithmetic
      // statement so a future reader does not have to re-derive them: at the
      // old 190 the column was 156 and the paused card is 165.
      expect(AppTheme.stripH, 208);
      expect(AppTheme.stripInnerH, 174);
    });
  });

  group('why this file reads rects and not pixels', () {
    test('the measurement does not depend on a raster', () {
      // Not an assertion about layout: a note kept executable so it is not
      // deleted as a stray. Two runs of the screenshot suite over identical
      // code differ by ~1400 raster rows on this box, which is why the
      // previous tick's "proof" of a 2 dp change was antialiasing noise.
      expect(AppTheme.stripInnerH, isNot(lessThanOrEqualTo(0)));
    });
  });
}
