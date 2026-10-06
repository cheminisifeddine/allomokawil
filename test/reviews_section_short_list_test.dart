// A reviews list that is SHORTER than the count in the profile header drew
// nothing at all, and on production today that is the common case, not the
// rare one.
//
// Found 5 Oct 2026 by asking the live API about the same man twice for every
// rated row in the market — 17 of the 97 `GET /api/mobile/workers/search` rows
// carry `total_reviews > 0`, and for each of those the `/reviews` list was
// fetched and counted:
//
//   id 5  رشيد خليفي   header (30)   list 1 card   <-- never said anything
//   id 3  سعيد بوسعادة  header (15)   list 1 card   <-- never said anything
//   id 4  نبيل قاسمي   header (12)   list 1 card   <-- never said anything
//   id 1  عمر بن علي    header (24)   list 0 cards  <- the arm shipped 1 Oct
//   id 2, 6, 7, 8       header --      list 0 cards  <- the same arm
//   the remaining 9 rows              list >= claim  <- nothing owed
//
// `reviews_section_contradiction_test.dart` closed the **empty** half of this on
// 1 Oct, and it closed it well: «تقييماته غير معروضة الآن» replaces «لا تقييمات
// بعد» rather than sitting next to it. But its gate is `list.isEmpty`, and the
// three rows above are the same disagreement with a different number of cards.
//
// So the page a customer decides on reads:
//
//   ★★★★★  4.7  (30)          <- the header, honest, from /workers/:id
//   ┌──────────────────┐
//   │ ★★★★★  عمل ممتاز!  │        <- one real card, from /workers/:id/reviews
//   └──────────────────┘
//   (nothing else)
//
// One card under a claim of thirty. The section is not lying here, and that is
// the trap: it draws a true review and stays silent, so the page does not
// contradict itself anywhere a test can point. What it does is leave the reader
// to conclude the app dropped 29 of them — or, worse, that the «(30)» is
// invented. Neither is knowable from inside the app, and which read is stale
// is not this screen's business: the aggregate may lag, or the list may be
// scoped to what this viewer may read.
//
// So the fix is an **annotation**, and the distinction from the empty case is
// the design. Empty means the section was about to assert a reputation claim
// the header denies, so it had to be *replaced*. Here every card is real and is
// drawn exactly as before — all that is added is the sentence the section was
// silent about. And it names both numbers, so the reader can do the subtraction
// himself rather than trust the app's arithmetic about a man's reputation.
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
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

/// Live payload for worker 5 — «رشيد خليفي», 4.7 over **30** reviews — whose
/// reviews endpoint returns exactly **one** card. Taken from production on
/// 5 Oct 2026, not invented, for the reason `reviews_section_contradiction_
/// test.dart` gives: a disagreement this app never actually receives would
/// prove the widget can draw a branch and nothing about the wire.
const _truncatedWorker = {
  'id': 5, 'user_id': 14, 'bio': 'حرفي في الطلاء الخارجي والعام', 
  'specialties': ['painting'],
  'experience_years': 15, 'price_range_min': 1500, 'price_range_max': 4000,
  'service_radius_km': 35, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 1, 'verification_status': 'verified',
  'subscription_plan': 'gold', 'avg_rating': 4.7, 'total_reviews': 30,
  'total_completed_jobs': 55, 'response_time_hours': 2,
  'cover_image_url': null, 'created_at': '2026-03-09 05:37:22',
  'updated_at': '2026-03-09 05:37:22', 'full_name': 'رشيد خليفي',
  'phone': '0550000009', 'user_wilaya': '09', 'avatar_url': null,
};

/// The single live review row for that worker, 20 Jan 2026, 5 stars.
Map<String, Object?> _oneReview() => {
      'id': 2,
      'project_id': 'proj_005',
      'customer_id': 9,
      'worker_id': 5,
      'rating': 5,
      'comment': 'عمل ممتاز! الواجهة أصبحت مثل الجديدة. التزام بالموعد وجودة عالية.',
      'images': '[]',
      'is_visible': 1,
      'created_at': '2026-01-20 10:00:00',
      'customer_full_name': 'أمينة حداد',
      'customer_avatar_url': null,
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Future<({ApiClient api, AuthState auth})> _boot({
  required Object worker,
  required Object reviews,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
      if (p == '/api/mobile/workers/5') return _json(worker);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pump(
    WidgetTester tester, ({ApiClient api, AuthState auth}) s) async {
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
      home: const WorkerProfileScreen(workerId: 5),
    ),
  ));
  // Bounded: the skeletons animate forever, so pumpAndSettle never returns.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('the gate', () {
    test('a list shorter than the claim answers a sentence', () {
      // The measured production shape: 30 claimed, 1 shown.
      expect(reviewsSectionPartialAr(headerCount: 30, shownCount: 1),
          isNotNull);
      expect(reviewsSectionPartialAr(headerCount: 15, shownCount: 1),
          isNotNull);
    });

    test('a list as long as the claim owes the reader nothing', () {
      expect(reviewsSectionPartialAr(headerCount: 12, shownCount: 12),
          isNull);
      expect(reviewsSectionPartialAr(headerCount: 5, shownCount: 9),
          isNull,
          reason: 'the list may be longer than the aggregate — both reads can '
              'legitimately say this, and it is not a contradiction');
    });

    test('an empty list is the OTHER arm, not this one', () {
      // Collapsing the two shapes would replace the empty-list card that
      // shipped on 1 Oct with an annotation under zero cards — which is a
      // worse state, because that screen is about to say «لا تقييمات بعد».
      expect(reviewsSectionPartialAr(headerCount: 30, shownCount: 0), isNull);
    });

    test('no claim on the header means nothing to reconcile', () {
      // `avg_rating: 0` folds `hasRating` false, so the header printed no
      // count at all. Quoting a number the page never showed is the exact
      // defect `reviews_unprinted_count_test.dart` was written for.
      expect(reviewsSectionPartialAr(headerCount: 0, shownCount: 1), isNull);
    });
  });

  group('the sentence', () {
    test('names both numbers so the reader can subtract them himself', () {
      final s = reviewsSectionPartialAr(headerCount: 30, shownCount: 1)!;
      expect(s, contains('30 تقييم'));
      expect(s, contains('تقييم'),
          reason: 'a count of one is not counted: «تقييم» here, never '
              '«1 تقييم» — the same rule `reviewCountAr` applies everywhere');
      expect(s, isNot(contains('!')),
          reason: 'the sentence is a statement about the read, not an error');
    });

    test('agrees with the count rather than spelling the grammar again', () {
      // 3-10 takes the broken plural, 11+ the counted singular. Both come from
      // `reviewCountAr`, so this sentence cannot drift from the stats line that
      // prints the same noun three files up.
      //
      // The form is nominative, not accusative, and that is deliberate: the
      // count is the **subject** of يَظهر — «يظهر 30 تقييم أعلاه», "thirty
      // ratings appear above" — not its object, so «تقييماً» would be the wrong
      // case here even though the same helper would print it in an object slot.
      expect(reviewsSectionPartialAr(headerCount: 12, shownCount: 3),
          contains('3 تقييمات'));
      expect(reviewsSectionPartialAr(headerCount: 12, shownCount: 3),
          contains('12 تقييم'));
      expect(reviewsSectionPartialAr(headerCount: 12, shownCount: 3),
          isNot(contains('تقييماً')));
    });
  });

  group('the screen', () {
    testWidgets('one card under a claim of thirty says something',
        (tester) async {
      await _pump(tester,
          await _boot(worker: _truncatedWorker, reviews: [_oneReview()]));

      // The claim really is on screen, or this test proves nothing.
      expect(find.text('4.7'), findsOneWidget);

      expect(find.byKey(const Key('profile-reviews-partial')), findsOneWidget,
          reason: 'a truncated list with no truncation is indistinguishable '
              'from a wrong one');

      // The real review is still drawn. This is an annotation, never a
      // replacement: the cards that arrived are true and must survive.
      expect(find.textContaining('عمل ممتاز!'), findsOneWidget);

      expect(find.byKey(const Key('profile-reviews-empty')), findsNothing);
      expect(find.byKey(const Key('profile-reviews-unbacked')), findsNothing,
          reason: 'the list is not empty, so the 1 Oct arm must not fire');
      expect(find.text('لا تقييمات بعد'), findsNothing);
    });

    testWidgets('a list that matches the claim is untouched',
        (tester) async {
      await _pump(
        tester,
        await _boot(
          worker: <String, Object?>{
            ..._truncatedWorker,
            'total_reviews': 1,
          },
          reviews: [_oneReview()],
        ),
      );

      expect(find.byKey(const Key('profile-reviews-partial')), findsNothing);
      expect(find.textContaining('عمل ممتاز!'), findsOneWidget,
          reason: 'the ordinary case must draw exactly what it always drew');
    });

    testWidgets('the empty-list arm still owns the empty list',
        (tester) async {
      await _pump(
          tester, await _boot(worker: _truncatedWorker, reviews: <Object>[]));

      expect(find.byKey(const Key('profile-reviews-unbacked')), findsOneWidget,
          reason: 'regression guard: the arm shipped 1 Oct must survive');
      expect(find.byKey(const Key('profile-reviews-partial')), findsNothing);
    });

    testWidgets('the annotation sits on the 4pt grid above the last card',
        (tester) async {
      // `top: 2` shipped with this annotation on 5 Oct and was the only
      // off-grid literal it added: it took the 8pt ratchet in
      // `card_recipe_test.dart` from 197 to 198, and the tick that added it ran
      // only its own two files, so the red suite went out unnoticed. The
      // ratchet already guards the *number*; nothing guards the *gap*, and a
      // refactor that moved this card back to 2 would not turn it red.
      //
      // Measured from the rendered rects rather than from the screenshot: two
      // runs of this harness on this host differ by ~1400 raster rows of font
      // antialiasing at identical geometry, so a pixel diff cannot see a 2 dp
      // change. The layout engine's own numbers can.
      await _pump(
          tester, await _boot(worker: _truncatedWorker, reviews: [_oneReview()]));

      // The annotation's OWN top inset: the Padding box it sits in minus the
      // card it wraps. Measuring the gap between two cards instead would also
      // catch the review row's own `bottom: 10`, which is a pre-existing
      // literal and not what this test is about — that one belongs to the 8pt
      // sweep, not to a guard that would fail on every screen at once.
      // AppCard paints its own padding on a `Container`, not a `Padding`
      // widget, so the nearest ancestor `Padding` is the wrapper this gap
      // lives in. Verified against the rendered tree, not assumed: it is
      // `EdgeInsets(0, 4, 0, 0)` and its rect starts exactly 4 dp above the
      // card's.
      final pad = tester.getRect(find
          .ancestor(
              of: find.byKey(const Key('profile-reviews-partial')).first,
              matching: find.byType(Padding))
          .first);
      final card = tester.getRect(
          find.byKey(const Key('profile-reviews-partial')).first);

      final inset = card.top - pad.top;
      expect(inset, AppTheme.s4,
          reason: 'the annotation clears the last review by exactly one grid '
              'step — `2` shipped here on 5 Oct and took the 8pt ratchet to 198');
      expect(inset % 4, 0,
          reason: 'whatever the value, it belongs to the 4pt scale');
    });
  });
}
