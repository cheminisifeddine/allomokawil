// «0.0» out of five was printed on the card a customer picks a tradesman from.
//
// Found on 26 Sep 2026 by continuing the audit the last two cycles ran: the
// server sends `avg_rating: 0` for a contractor with no reviews, and every star
// row printed it unconditionally. This is the fifth unmeasured number, and the
// only one that is a **verdict on a person** rather than a measurement of his
// business — the other four were «0 سنة خبرة», «استجابة خلال 0h» and
// «نصف قطر الخدمة: 0 كم».
//
// On the live browse payload the day this was found, **15 of 26** contractors
// were in that state, every one of them pending verification: new tradesmen,
// shown as the worst-rated on the platform. The review form is 1–5, so a 0
// cannot be a mean — it is the server's "nobody has rated me" sentinel, and
// the app was rendering a sentinel as a score.
//
// The fix is [WorkerProfile.avgRating] being `double?` with a stored 0 folded
// to null, and the row saying the true thing: no ratings yet.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';

/// Copied from the live payload, with the review fields as the server sends
/// them for a contractor nobody has worked with.
Map<String, dynamic> _payload({
  double? avgRating = 0,
  int? totalReviews = 0,
  int totalJobs = 0,
  int? years = 5,
  String? wilaya = '16',
}) =>
    {
      'id': 73,
      'user_id': 316,
      'full_name': 'مقاول جديد',
      'bio': null,
      'specialties': ['painting'],
      'experience_years': years,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 0,
      'is_certificate_verified': 0,
      'verification_status': 'pending',
      'avg_rating': avgRating,
      'total_reviews': totalReviews,
      'total_completed_jobs': totalJobs,
      'response_time_hours': null,
      'cover_image_url': null,
      'avatar_url': null,
      'user_wilaya': wilaya,
    };

Future<void> _card(WidgetTester tester, WorkerProfile w, WorkerCardVariant v) async {
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
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: v == WorkerCardVariant.vertical ? 200 : 380,
            child: WorkerCard(worker: w, variant: v),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the parser never hands a sentinel to a screen', () {
    test('a stored 0 becomes null — it is "never rated", not a score', () {
      final w = WorkerProfile.fromJson(_payload());
      expect(w.avgRating, isNull);
      expect(w.hasRating, isFalse);
    });

    test('an absent avg_rating is null too', () {
      final w = WorkerProfile.fromJson(_payload(avgRating: null));
      expect(w.avgRating, isNull);
    });

    test('a real score survives exactly', () {
      final w = WorkerProfile.fromJson(
          _payload(avgRating: 4.7, totalReviews: 30));
      expect(w.avgRating, 4.7);
      expect(w.hasRating, isTrue);
    });

    test('the lowest score the 1-5 review form can produce is still a score', () {
      // 1 is a real rating and must not be folded away with the sentinel 0.
      final w =
          WorkerProfile.fromJson(_payload(avgRating: 1, totalReviews: 2));
      expect(w.avgRating, 1);
      expect(w.hasRating, isTrue);
    });

    test('hasRating and hasHistory are independent gates', () {
      // A contractor with jobs but no reviews: hasHistory true, hasRating false.
      final w = WorkerProfile.fromJson(_payload(totalJobs: 7));
      expect(w.hasHistory, isTrue);
      expect(w.hasRating, isFalse);
    });
  });

  group('the wording', () {
    test('it says nobody has rated him, and never contains a zero', () {
      expect(noRatingAr(), 'لا تقييمات بعد');
      expect(noRatingAr(), isNot(contains('0')));
    });
  });

  group('the browse card — vertical variant', () {
    testWidgets('an unrated contractor is not shown «0.0»', (tester) async {
      await _card(tester, WorkerProfile.fromJson(_payload()),
          WorkerCardVariant.vertical);
      expect(find.text('0.0'), findsNothing,
          reason: 'a sentinel printed as a score is the whole defect');
      expect(find.text(noRatingAr()), findsOneWidget);
      expect(find.text('(0)'), findsNothing);
    });

    testWidgets('a rated contractor still reads 4.7 (30)', (tester) async {
      await _card(
          tester,
          WorkerProfile.fromJson(
              _payload(avgRating: 4.7, totalReviews: 30)),
          WorkerCardVariant.vertical);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('(30)'), findsOneWidget);
      expect(find.text(noRatingAr()), findsNothing);
    });

    testWidgets('no star icon is drawn for a man with no score', (tester) async {
      await _card(tester, WorkerProfile.fromJson(_payload()),
          WorkerCardVariant.vertical);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    });
  });

  group('the browse card — row variant', () {
    testWidgets('an unrated contractor is not shown «0.0»', (tester) async {
      await _card(tester, WorkerProfile.fromJson(_payload()),
          WorkerCardVariant.row);
      expect(find.text('0.0'), findsNothing);
      expect(find.text(noRatingAr()), findsOneWidget);
    });

    testWidgets('losing the score does not cost the card its wilaya',
        (tester) async {
      // The location chip shares the rating row. If the row is gated on
      // hasRating, the wilaya disappears with it — and every Algerian customer
      // filters browse by it.
      await _card(tester, WorkerProfile.fromJson(_payload()),
          WorkerCardVariant.row);
      expect(find.text('الجزائر'), findsOneWidget);
    });

    testWidgets('a rated contractor still reads 4.7 (30)', (tester) async {
      await _card(
          tester,
          WorkerProfile.fromJson(
              _payload(avgRating: 4.7, totalReviews: 30)),
          WorkerCardVariant.row);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text(noRatingAr()), findsNothing);
    });
  });

  group('the card still lays out', () {
    testWidgets('no overflow in either variant, rated or not', (tester) async {
      for (final v in WorkerCardVariant.values) {
        for (final rated in [true, false]) {
          await _card(
              tester,
              WorkerProfile.fromJson(_payload(
                  avgRating: rated ? 4.5 : 0, totalReviews: rated ? 3 : 0)),
              v);
          expect(tester.takeException(), isNull,
              reason: '$v rated=$rated must not overflow');
        }
      }
    });
  });
}
