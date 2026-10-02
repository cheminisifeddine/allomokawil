// A contractor's review dates are the evidence a customer picks him on, and
// this page had them frozen from the single frame it opened on.
//
// **[WorkerProfileScreen.clock] was already here.** It was added so the profile
// golden would stop drifting on an hour boundary and taking the whole
// `flutter test` gate red with it — exactly as it was to `NotificationsScreen`
// in `a87647e`. So this screen was one that *looked* like it had solved
// wall-clock rendering, and it had solved only the test's half of the problem.
//
// `_ReviewCard` composes `relativeTimeAr(review.createdAt, now: clock?.call())`
// **at build time** (`worker_profile_screen.dart:817`), and the screen rebuilds
// on exactly three things: the first pair of reads in `didChangeDependencies`,
// «إعادة المحاولة» on the header, and either section's own retry. None of them
// is "a minute passed."
//
// So a customer comparing two contractors on a phone — this is the page he
// picks one from, and the reviews are the evidence he weighs — left the profile
// open, came back twenty minutes later, and read «قبل 12 دقيقة» on reviews
// that were now forty minutes old. Every card frozen from one build, while the
// header's own review count beside them kept claiming the page was current.
//
// This is the **last** screen in the family: the census in the previous tick
// put it at three (`project_detail`, `my_portfolio`, `worker_profile`) with
// this one last. It is the last one with a shape worth recording, because the
// two ticks before it disagreed about what it is:
//
//  * `my_portfolio` keeps its rows as **parsed fields**, so its tick is derived
//    from a `_stale` predicate — the thing being aged is born in a *failure*,
//    and the healthy state holds zero timers.
//  * `project_detail` and **this screen** keep theirs inside a `Future` a
//    `FutureBuilder` consumes, so the State cannot ask "did a row land?" without
//    duplicating the parse. The tick is armed from the lifecycle instead, and
//    a minute spent over a skeleton costs one free redraw.
//
// The mutation gate is the point of this file. A test that only looks for «الآن»
// passes just as happily against the old code, because the old code had a
// *different* sentence rather than no sentence. What is pinned is the
// behaviour: one fixture, two clocks, and a timer that moves the label with
// nothing rebuilding it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.8, 'total_reviews': 1,
  'total_completed_jobs': 12, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

/// One review stamped exactly **12 minutes** before the clock this file injects.
///
/// 12 is chosen so the two clocks land on sentences a glance can tell apart —
/// «قبل 12 دقيقة» inside the minute band, «قبل ساعتين» past the hour — and so
/// neither is «الآن», which would make the fixture pass against any build that
/// rendered no time at all.
const _review = {
  'id': 5,
  'customer_id': 30,
  'worker_id': 16,
  'project_id': 'p1',
  'rating': 5,
  'comment': 'شغل نظيف وسريع',
  'customer_full_name': 'زبون تجربة',
  'created_at': '2026-10-02 09:48:00',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: const {'content-type': 'application/json'});

/// Boots a visitor against a profile holding exactly one dated review.
///
/// Unauthenticated on purpose: this screen is reachable by anyone browsing, and
/// the sticky «مراسلة» CTA is the only thing that needs an identity, so the
/// ageing path must not depend on a signed-in session.
Future<ApiClient> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p == '/api/mobile/workers/16') return _json(_worker);
      if (p.endsWith('/reviews')) return _json([_review]);
      if (p.endsWith('/portfolio')) return _json(<Object?>[]);
      return _json(<Object?>[]);
    }),
  );
  return api;
}

/// Every line the page drew. Context for a failure message only — **never**
/// the thing an assertion is made about, and the first version of this file
/// learned why the hard way.
///
/// _ReviewCard puts `Key('review-when')` on the exact [Text] that renders
/// `relativeTimeAr`, so the date line can be read directly. A page-wide
/// substring scan is not equivalent, and this page proves it: the work-facts
/// row prints «12 مشروع منجز • استجابة خلال ساعتين» from
/// `response_time_hours: 2`, which contains «ساعتين». So `any((t) =>
/// t.contains('ساعتين'))` was **true on the very first build**, and the case
/// that exists to prove the timer fires passed against a screen with no timer
/// at all — it was measuring the response-time promise, not the review date.
///
/// A sentinel that also appears elsewhere on the page is not a sentinel.
List<String> _whenLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.byKey(const Key('review-when')))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// The single review date on screen — the fixture carries exactly one, so
/// "is the list empty" and "is the answer wrong" stay distinguishable.
String _when(WidgetTester tester) {
  final labels = _whenLabels(tester);
  expect(labels, hasLength(1),
      reason: 'expected exactly one dated review card:\n$labels');
  return labels.single;
}

/// Everything the page drew, quoted in a failure so the reader can see the
/// competing text that made a loose scan wrong.
String _dump(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .join(' | ');

/// A phone-shaped viewport tall enough that the review row is built.
Future<void> _pump(WidgetTester tester, DateTime Function() now) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = await _boot();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: await _authOf(api),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: WorkerProfileScreen(workerId: 16, clock: now),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<AuthState> _authOf(ApiClient api) async {
  final auth = AuthState(api);
  await auth.restore();
  return auth;
}

void main() {
  group('the contractor profile dates its reviews with the clock it was handed',
      () {
    testWidgets('a review 12 minutes old is labelled 12 minutes', (tester) async {
      await _pump(tester, () => DateTime(2026, 10, 2, 10));

      expect(_when(tester), 'قبل 12 دقيقة',
          reason: 'the page drew:\n${_dump(tester)}');
    });

    testWidgets('the SAME review reads as two hours old once the clock moves',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // server payload is byte-identical to the case above; only the injected
      // clock moved from 10:00 to 12:05. Before the fix both cases printed the
      // real wall clock's answer, so the difference this file exists to prove
      // was not observable at all — which is the definition of the fuse.
      await _pump(tester, () => DateTime(2026, 10, 2, 12, 5));

      expect(_when(tester), 'قبل ساعتين',
          reason: 'the page drew:\n${_dump(tester)}');
    });

    testWidgets('the minute tick re-labels the review without a rebuild',
        (tester) async {
      // The half no screenshot can show, and the half the two cases above
      // cannot reach. Both of those pump a fresh tree. A customer does not do
      // that: he opens a profile once and reads it while he thinks. So this
      // case moves **only** the clock — no `pumpWidget`, no key change, no
      // `setState` — because that is the actual defect.
      //
      // Before the fix there was no timer at all, so this pump was a no-op and
      // the card kept the first frame's sentence for as long as the page sat
      // open.
      var now = DateTime(2026, 10, 2, 10);
      await _pump(tester, () => now);
      expect(_when(tester), 'قبل 12 دقيقة',
          reason: 'setup did not reach the minute sentence:\n${_dump(tester)}');

      // Only the clock moves, the way a real minute moves while the app sits in
      // a pocket and the customer is halfway down the page.
      now = DateTime(2026, 10, 2, 12, 5);
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));

      expect(_when(tester), 'قبل ساعتين',
          reason: 'the review date did not age with the clock it was handed; '
              'this screen rebuilds only on load and on retry, so nothing else '
              'can move the label. The page drew:\n${_dump(tester)}');
    });

    testWidgets('the ageing timer is cancelled when the profile leaves the tree',
        (tester) async {
      // A `Timer.periodic` left armed after `dispose` keeps a live handle.
      // Cancel-first is also what makes «إعادة المحاولة» safe — it is pressed
      // up to three times on this page.
      await _pump(tester, () => DateTime(2026, 10, 2, 10));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      // Reaching here without "A Timer is still pending even after the widget
      // tree was disposed" *is* the assertion.
    });
  });
}
