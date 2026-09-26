// The star row said two things at once when a score arrived without a count.
//
// Found on 26 Sep 2026 by the audit the last four cycles ran. The gate on a
// rating row is the **score** ([WorkerProfile.hasRating] / [Quote.hasRating]),
// not the review count — a stored `avg_rating: 0` is the server's "nobody has
// rated me yet" sentinel, and the count is a different field that can say 0
// while the score is real.
//
// That split is deliberate and is covered on both sides: a payload with 7
// reviews and no score must print no stars, and a payload with a score and no
// count must print the stars. The second case is where the row lies to itself.
//
// [RatingStars] renders the count verbatim — `'($count)'` — and takes an
// `int?` precisely so a caller can pass null. Both live star rows pass a
// non-nullable `int` (`totalReviews` / `workerTotalReviews`, which the parser
// defaults to 0), so the combination a test above already calls legitimate
// draws **four gold stars, «4.8 من 5» and «(0)»** in one row: a man
// somebody rated, scored, next to a claim that nobody rated him at all.
//
// The screen reader is already honest here — [A11y.rating] folds a zero count
// to «لا مراجعات», and `a11y_semantics_test.dart` asserts that sentence for
// exactly this case, `A11y.rating(5, count: 0)`. So one row was lying in two
// directions at once: the pixels said «(0)», the label said «لا مراجعات».
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/a11y.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';
import 'package:allomokawil/src/widgets/ui.dart';

Map<String, dynamic> _payload({
  double? avgRating = 4.8,
  int? totalReviews = 0,
}) =>
    {
      'id': 3,
      'user_id': 9,
      'full_name': 'سعيد بوسعادة',
      'bio': null,
      'specialties': ['painting'],
      'experience_years': 5,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 1,
      'is_certificate_verified': 1,
      'verification_status': 'verified',
      'avg_rating': avgRating,
      'total_reviews': totalReviews,
      'total_completed_jobs': 7,
      'response_time_hours': 2,
      'cover_image_url': null,
      'avatar_url': null,
      'user_wilaya': '16',
    };

Future<void> _stars(WidgetTester tester) async {
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
      home: const Scaffold(
        body: Center(child: RatingStars(rating: 4.8, count: 0)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a score with no count must not print «(0)»', () {
    testWidgets('the count is dropped, not printed as a zero', (tester) async {
      await _stars(tester);
      expect(find.text('(0)'), findsNothing,
          reason: 'four stars and 4.8 next to «(0)» is two verdicts at once');
    });

    testWidgets('the score itself is untouched', (tester) async {
      await _stars(tester);
      expect(find.text('4.8'), findsOneWidget,
          reason: 'the score is real and must still be printed');
    });

    test('a zero count is treated as "no count at all"', () {
      // The same rule the screen reader already follows, in the same place:
      // A11y.rating(5, count: 0) == 'التقييم 5.0 من 5، لا مراجعات'. The pixels
      // have to agree with the label, so the zero is dropped rather than
      // rendered as a number.
      expect(A11y.rating(4.8, count: 0), isNot(contains('(')));
      expect(A11y.rating(4.8, count: 0), contains('لا مراجعات'));
    });

    test('a real count is still printed', () {
      expect(A11y.rating(4.8, count: 15), contains('15 مراجعة'));
    });
  });

  group('the two card variants that print their own count', () {
    testWidgets('the vertical card drops «(0)» beside a real score',
        (tester) async {
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
                width: 200,
                child: WorkerCard(
                  worker: WorkerProfile.fromJson(
                      _payload(avgRating: 4.8, totalReviews: 0)),
                  variant: WorkerCardVariant.vertical,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('(0)'), findsNothing);
      expect(find.text('4.8'), findsOneWidget);
    });
  });
}
