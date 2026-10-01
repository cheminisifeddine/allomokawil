// The profile's two reads of "does this contractor have reviews" are allowed to
// disagree, and until this tick nothing in the app noticed when they did.
//
// Found 1 Oct 2026 by asking the live API about the same man twice — the only
// way to see it, because both answers are 200 and both are correct readings of
// what their own endpoint returned:
//
//   GET /api/mobile/workers/1            -> avg_rating 4.8, total_reviews 24
//   GET /api/mobile/workers/1/reviews    -> []
//
// `_worker` below is that profile, byte for byte. The screen then told a
// customer deciding between tradesmen that «عمر بن علي» had 4.8 stars over 24
// reviews at the top of the page and, a few scrolls down, «لا تقييمات بعد» —
// plus «التقييم يُكتب بعد إنجاز العمل — ابدأ بالتواصل معه», which is an
// instruction to go message a contractor who has already been reviewed 24
// times. Two claims about one man's reputation, one screen, both confident, and
// the second one tells the user to act on the first.
//
// This is the same lie `profile_section_failure_test.dart` already covers for a
// 500, and the distinction is only the status code: a failed read is not an
// answer, and a read that contradicts another answer about the same fact is not
// an answer either.
//
// The section is deliberately NOT told which one is stale. The aggregate can
// lag the list or the list can be scoped to what this viewer may see, and
// neither is knowable from inside the screen. So the contract asserted here is
// only the honest one: when the two disagree, the section stops claiming the
// man has no reviews, and it does not invent a number of its own either.
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

/// The live payload for worker 1 — «عمر بن علي», 4.8 over 24 reviews — whose
/// reviews endpoint answers `[]`. Taken from the running API on 1 Oct 2026, not
/// invented: a made-up disagreement would prove the widget can draw a branch,
/// and this file has to prove the disagreement is one the server really sends.
const _ratedWorker = {
  'id': 1, 'user_id': 11, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.8, 'total_reviews': 24,
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
            'full_name': 'زبون تجربة', 'type': 'customer', 'avatar_url': null,
            'wilaya': '16', 'commune': null,
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

Future<void> _pump(WidgetTester tester, ({ApiClient api, AuthState auth}) s) async {
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
  testWidgets('the two reads disagree: the section never claims he has none',
      (tester) async {
    await _pump(tester,
        await _boot(worker: _ratedWorker, reviews: <Object>[]));

    // The header's claim is on screen — otherwise this test would pass on a
    // screen that never drew the aggregate at all.
    expect(find.text('4.8'), findsOneWidget,
        reason: 'the header must really have printed the score');

    expect(find.byKey(const Key('profile-reviews-unbacked')), findsOneWidget,
        reason: 'a section that contradicts the header must say so');
    expect(find.byKey(const Key('profile-reviews-empty')), findsNothing);
    expect(find.text('لا تقييمات بعد'), findsNothing,
        reason: 'this is the defect: the customer is told a rated contractor '
            'has no reviews, and told to message him for his first one');
    expect(find.text('التقييم يُكتب بعد إنجاز العمل — ابدأ بالتواصل معه.'),
        findsNothing,
        reason: 'the instruction to write a first review is the part that '
            'sends him off to do something already done 24 times');
  });

  testWidgets('the contradiction names the count it cannot show',
      (tester) async {
    await _pump(tester,
        await _boot(worker: _ratedWorker, reviews: <Object>[]));

    final arm =
        tester.widget<Text>(find.text(reviewsSectionUnbackedTitle));
    expect(arm.data, reviewsSectionUnbackedTitle);
    expect(find.textContaining('24'), findsWidgets,
        reason: 'the aggregate above is the claim that has to be honoured, '
            'so the section must not quietly drop the number either');
  });

  testWidgets('the honest empty state is untouched when the two agree',
      (tester) async {
    // `avg_rating: 0` is the server's "nobody has rated me" sentinel and the
    // header prints no stars, so «لا تقييمات بعد» is true here and the
    // contradiction arm must not fire. A fix that keyed off the list alone
    // would blank this card.
    await _pump(
      tester,
      await _boot(
        worker: <String, Object?>{
          ..._ratedWorker,
          'avg_rating': 0,
          'total_reviews': 0,
        },
        reviews: <Object>[],
      ),
    );

    expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
    expect(find.byKey(const Key('profile-reviews-unbacked')), findsNothing);
    // **Two, not one** — and the two are the claim this whole file is about.
    // The header pill prints `noRatingAr()` when `hasRating` is false and the
    // empty section prints the same sentence, so an agreed profile shows the
    // same words twice. The first version of this test asserted
    // `findsOneWidget` and failed on correct code, which is the trap the
    // agreement tests elsewhere in this repo keep hitting: the duplicate is the
    // feature, not a defect. Counting one would have "fixed" a screen that was
    // right.
    expect(find.text(noRatingAr()), findsNWidgets(2),
        reason: 'both reads agree he has none, so both surfaces say it — one '
            'in the header pill, one in the empty section');
  });

  testWidgets('one review in the header is not two, and not twenty-four',
      (tester) async {
    // The disagreement is about *whether* the reads conflict, so the count has
    // to be an int and a zero has to mean absence. A gate written as
    // `headerCount != null` would report every contractor with a score as a
    // contradiction; written as `headerCount > 0` it does not.
    expect(reviewsSectionUnbackedAr(headerCount: 0), isNull);
    expect(reviewsSectionUnbackedAr(headerCount: -1), isNull);
    expect(reviewsSectionUnbackedAr(headerCount: 24), isNotNull);
    expect(reviewsSectionUnbackedAr(headerCount: 1), contains('تقييم واحد'));
    expect(reviewsSectionUnbackedAr(headerCount: 24), isNot(contains('تقييم واحد')));
  });
}
