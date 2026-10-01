// The contradiction arm quoted a number the page never printed.
//
// Found 2 Oct 2026, one tick after the arm itself shipped. The first version
// was handed `WorkerProfile.totalReviews` — the raw column — under a comment
// calling it "the aggregate the header already printed above this section".
// It is not that, and the gap is a payload shape the model layer already
// documents as real:
//
//   avg_rating: 0, total_reviews: 24
//
// `avg_rating: 0` is the server's "nobody has rated me yet" sentinel
// (`worker.dart` / `review_count.dart`), so `hasRating` is false, the header
// pill draws `noRatingAr()` — «لا تقييمات بعد», **no stars, no count** — and
// nothing at all about 24 is on screen. The empty reviews list then meets a
// section that was told 24 and prints:
//
//   لا تقييمات بعد                    <- the header, the whole claim
//   يظهر أعلاه 24 تقييماً              <- the section, about a number
//
// So the section contradicts the sentence directly above it *and* cites
// evidence that is not there. Both halves are wrong, in opposite directions,
// on a profile the customer is deciding on.
//
// **This is not a regression the fix introduced; it is one it removed.** The
// arm's whole purpose is to refuse a contradiction. Handed a count the header
// never printed, it detects a contradiction that does not exist and answers
// it with a number nobody can see on the page — the defect it was built to
// kill, wearing the fix's own name.
//
// The rule is now [headerPrintedReviewCount]: the arm may only compare against
// a claim the customer can actually see. `review_count.dart` lists this exact
// disagreement ("7 reviews, no score") as one of the two directions the two
// fields drift apart, and that file closed the *other* one — a score beside a
// zero count. This is the half it did not reach.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/reviews_section_copy.dart';
import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

/// The worker-1 profile of the sibling test, with its two rating fields set to
/// the disagreement this file is about: the **sentiment-free** score the server
/// sends before anything has been rated, and a count that says otherwise.
const _noScoreButCounted = {
  'id': 1, 'user_id': 11, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 0, 'total_reviews': 24,
  'total_completed_jobs': 12, 'response_time_hours': 2,
  'cover_image_url': null, 'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45', 'full_name': 'عمر بن علي',
  'phone': '077442495', 'user_wilaya': '16', 'avatar_url': null,
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Future<({ApiClient api, AuthState auth})> _boot({
  required Object worker,
  required Object reviews,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json({
          'token': 'tok',
          'user': {
            'id': 30, 'phone': '0773000000', 'email': null,
            'full_name': 'زبون تجربة', 'type': 'customer',
            'avatar_url': null, 'wilaya': '16', 'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/reviews')) return _json(reviews);
      if (p.endsWith('/portfolio')) return _json(<Object>[]);
      if (p == '/api/mobile/workers/1') return _json(worker);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pump(WidgetTester tester,
    ({ApiClient api, AuthState auth}) s) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: s.api,
    auth: s.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const WorkerProfileScreen(workerId: 1),
    ),
  ));
  // Bounded: the skeletons animate forever, so pumpAndSettle never returns.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('a count the header never printed cannot arm the section',
      (tester) async {
    await _pump(
      tester,
      await _boot(worker: _noScoreButCounted, reviews: <Object>[]),
    );

    // The precondition, asserted rather than assumed: this profile really did
    // make the header print no count. Without it the test below would pass on
    // a screen that never reached the disagreement at all.
    expect(find.text('4.8'), findsNothing);
    expect(find.text('24'), findsNothing,
        reason: 'no score means the header pill prints noRatingAr(), so a raw '
            '24 anywhere on this page would be the defect itself');

    expect(find.byKey(const Key('profile-reviews-unbacked')), findsNothing,
        reason: 'there is nothing to reconcile — the header claimed no reviews '
            'and the list agrees, so this is an honest empty section');
    expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
    // Both surfaces say the same true sentence, twice. See the sibling file:
    // the duplicate is the agreement, not a defect.
    expect(find.text(noRatingAr()), findsNWidgets(2));
  });

  testWidgets('the page never quotes a number it did not print',
      (tester) async {
    await _pump(
      tester,
      await _boot(worker: _noScoreButCounted, reviews: <Object>[]),
    );

    expect(find.textContaining('24'), findsNothing,
        reason: '24 is the count the header suppressed; quoting it anywhere '
            'would cite evidence the customer cannot see on this page');
  });

  group('headerPrintedReviewCount follows the header, not the column', () {
    test('no score means no claim, however many reviews the column claims', () {
      expect(
        headerPrintedReviewCount(hasRating: false, totalReviews: 24),
        0,
      );
      expect(
        headerPrintedReviewCount(hasRating: false, totalReviews: 1),
        0,
      );
    });

    test('a real score with a real count is the claim the arm may compare to',
        () {
      expect(
        headerPrintedReviewCount(hasRating: true, totalReviews: 24),
        24,
      );
      expect(headerPrintedReviewCount(hasRating: true, totalReviews: 1), 1);
    });

    test('a score with no count prints no count, so the claim is 0', () {
      // The other direction `review_count.dart` documents: real stars, no
      // reviews. `printableReviewCount` turns the stored 0 into an absence, so
      // the header draws the stars and *no* "(0)" — and the arm must not
      // invent a claim from the raw 0 either.
      expect(headerPrintedReviewCount(hasRating: true, totalReviews: 0), 0);
      expect(
        headerPrintedReviewCount(hasRating: true, totalReviews: -1),
        0,
      );
    });

    test('the gate that fired for a real contradiction still fires', () {
      // Without this the whole file would pass on a change that disabled the
      // arm outright, which is a "fix" that deletes the feature.
      expect(
        reviewsSectionUnbackedAr(
          headerCount: headerPrintedReviewCount(
              hasRating: true, totalReviews: 24),
        ),
        isNotNull,
      );
      expect(
        reviewsSectionUnbackedAr(
          headerCount: headerPrintedReviewCount(
              hasRating: false, totalReviews: 24),
        ),
        isNull,
        reason: 'this is the defect: the header printed no count, so there is '
            'no claim above for the section to contradict');
    });
  });
}
