// A paused contractor must not look like a man who is taking work.
//
// Found on 5 Oct 2026 by measuring the live browse payload, not by reading the
// card and wondering what it was missing. `GET /api/mobile/workers/search`
// returned 97 rows and **exactly one** with `is_available: 0` — id 73, a real
// September signup — and the API serves it in browse, so nothing upstream
// hides it. `isAvailable` had **no reader** in `lib/src/screens/browse/` or
// `lib/src/screens/customer/`: the only widget that drew it was the
// `_availabilityPill` on the worker's own home screen, which the paused man
// sees and no customer does.
//
// So the one row in this market that is genuinely not taking work drew the
// same verified avatar, the same stars and the same tap target as a man who
// is. A customer could message it and quote it and wait for a reply its owner
// had already said would not come.
//
// This file is the regression for that, and it is a widget test because the
// defect was never in the model — [WorkerProfile.isAvailable] parsed the flag
// correctly all along. The parser was fine and the card was blind.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';

/// The id-73 row exactly as the wire sends it: the four fields that decide
/// what the card prints, and nothing invented.
WorkerProfile _row({required int id, required Object? available}) =>
    WorkerProfile.fromJson({
      'id': id,
      'user_id': id * 10,
      'full_name': 'جبير بن قويدر',
      'specialties': ['painting'],
      // 14 years and a real price, so the tag row this card prints is not
      // empty for a reason of its own and a missing tag cannot be explained
      // away as "there was nothing to print".
      'experience_years': 14,
      'price_range_min': 2000,
      'price_range_max': 6000,
      'avg_rating': 4.2,
      'total_reviews': 3,
      'is_available': available,
      'verification_status': 'verified',
    });

/// Pumps [w] in the box the surface really gives it.
///
/// **The height constraint is the point, and it was missing for one release.**
/// The vertical card is only ever laid out inside a fixed-height strip, so a
/// `SingleChildScrollView` here (what this helper used to be) hands the column
/// an unbounded height: the card can never overflow and the guard below passes
/// on a card that clips 9 dp of its own content on the shipping screen. The
/// vertical arm therefore gets [AppTheme.stripH] — the number the strip
/// actually uses — and the row arm stays unbounded, because browse really does
/// let it size itself.
Future<void> _pump(WidgetTester t, WorkerProfile w, WorkerCardVariant v) =>
    t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: v == WorkerCardVariant.vertical
              ? SizedBox(
                  height: AppTheme.stripH,
                  child: WorkerCard(worker: w, variant: v),
                )
              : SingleChildScrollView(child: WorkerCard(worker: w, variant: v)),
        ),
      ),
    ));

void main() {
  group('availabilityAr — the words', () {
    test('an available contractor prints nothing at all', () {
      // The default is `is_available = 1` on 96 of 97 live rows, so a green
      // «متاح الآن» chip everywhere would be a wall of ink saying nothing. Only
      // the unusual state earns a tag — the same call the card already made for
      // a star score of 0.
      expect(availabilityAr(true), isNull);
    });

    test('a paused one is named, in Arabic, and it is not a measurement', () {
      expect(availabilityAr(false), 'غير متاح الآن');
    });
  });

  group('the parser was never the defect', () {
    test('the live wire value 0 is read as unavailable', () {
      expect(_row(id: 73, available: 0).isAvailable, isFalse);
    });

    test('1 is available', () {
      expect(_row(id: 5, available: 1).isAvailable, isTrue);
    });

    test("the app's own JSON bool write reads back false", () {
      // `repository.updateMyProfile` sends `'is_available': false` as a bool.
      expect(_row(id: 73, available: false).isAvailable, isFalse);
    });
  });

  group('browse row — the surface a customer picks from', () {
    testWidgets('a paused contractor is labelled on the row', (t) async {
      await _pump(t, _row(id: 73, available: 0), WorkerCardVariant.row);
      expect(find.text('غير متاح الآن'), findsOneWidget);
    });

    testWidgets('an available one is not labelled', (t) async {
      await _pump(t, _row(id: 5, available: 1), WorkerCardVariant.row);
      expect(find.text('غير متاح الآن'), findsNothing);
      // And the positive half is not printed either: the card states the
      // exception, it does not stamp every row «متاح الآن».
      expect(find.textContaining('متاح الآن'), findsNothing);
    });

    testWidgets('a paused contractor with no price and no years still gets the '
        'tag row — the wrap is not gated around a tag that exists', (t) async {
      // The empty-Wrap defect this card already carries one scar from: the tag
      // gate is `years || price || availability`, so availability alone is
      // enough to build the row. If someone narrows the gate back to the first
      // two, the tag disappears on exactly the rows that have nothing else to
      // print — and those are the newest contractors.
      final bare = WorkerProfile.fromJson({
        'id': 73,
        'user_id': 730,
        'full_name': 'جبير بن قويدر',
        'specialties': ['painting'],
        'is_available': 0,
      });
      await _pump(t, bare, WorkerCardVariant.row);
      expect(find.text('غير متاح الآن'), findsOneWidget);
    });
  });

  group('top-rated strip — the other customer-facing surface', () {
    testWidgets('a paused contractor is labelled on the strip card too',
        (t) async {
      await _pump(t, _row(id: 73, available: 0), WorkerCardVariant.vertical);
      expect(find.text('غير متاح الآن'), findsOneWidget);
    });

    testWidgets('an available one is not', (t) async {
      await _pump(t, _row(id: 5, available: 1), WorkerCardVariant.vertical);
      expect(find.text('غير متاح الآن'), findsNothing);
    });

    testWidgets('the strip column does not overflow with the line added',
        (t) async {
      // The strip card is a fixed-height column. This is the guard that was
      // supposed to catch it and did not, for two reasons that have both been
      // fixed: the test pumped the card unbounded (see `_pump`), and it was
      // named after a "168 dp" column that never existed — the strip was 190.
      // `_pump` now hands it [AppTheme.stripH], the height the strip uses.
      await _pump(t, _row(id: 73, available: 0), WorkerCardVariant.vertical);
      expect(t.takeException(), isNull);
    });
  });

  group('the tag does not lie in the other direction', () {
    testWidgets('a verified tick is untouched — availability is not the badge',
        (t) async {
      // Two different questions. This tick added the label for "is he taking
      // work"; it must not have started filtering on availability somewhere
      // that would drop a verified badge.
      final w = _row(id: 73, available: 0);
      expect(w.verificationStatus, VerificationStatus.verified);
      await _pump(t, w, WorkerCardVariant.row);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });
  });
}
