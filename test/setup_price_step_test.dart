// The contractor's own setup checklist, and the price step on it.
//
// Found 1 Oct 2026, immediately after the *browse card* was fixed for asking a
// third version of the question "does this contractor have a price?". That fix
// left this file's own subject recorded as the remaining sibling, and it is the
// same defect class a third time — one fact, two private answers, and the two
// surfaces are the two halves of the same man's listing:
//
//   worker_card.dart          ->  hasPriceRange(min, max)      (fixed 1 Oct)
//   worker_home_screen.dart   ->  min != null && max != null    (this file)
//
// A man who opened the profile editor and typed **only** the «حتى» box — which
// the editor explicitly permits, `_save()` only rejects a non-empty field that
// did not parse — was told on his own dashboard that he had not set his prices.
// The card customers browse said the opposite and printed it. So the screen
// whose entire job is "here is your next unfinished step" named a step that
// was already finished, and the row he is hired from proved it.
//
// The `(0, 0)` arm is the same error with a worse face: both boxes non-null
// satisfies `&&`, so a contractor whose two price fields are both zero — which
// `DzNumber.tryParse` accepts, the fields have no `min` bound, and `min > max`
// does not fire on zero — was ticked for a price that `priceRangeAr` folds to
// **no price at all**. The zero fold is already the app's rule everywhere else
// (see `price_range_zero_test.dart`); this call site was the one place that
// had not been told.
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
import 'package:allomokawil/src/data/price_range_copy.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

/// The contractor the checklist is on screen for.
///
/// `total_completed_jobs: 0` and `total_reviews: 0` are **load-bearing, not
/// decoration**: `WorkerHomeScreen` only builds `_GettingStarted` when
/// `!worker.hasHistory`, so a profile with any history never renders the
/// checklist at all and every assertion in this file would pass against a
/// screen that does not contain the step. (The same trap cost
/// `portfolio_badge_copy_test.dart` a whole run.) So the price cases here are
/// driven on a **new** contractor — which is also the ordinary case: a man
/// setting his prices is a man who has not been hired yet.
Map<String, Object?> _worker({int? min, int? max}) => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'bio': 'نجار منذ عشر سنوات',
      'specialties': <Object?>['carpentry'],
      'experience_years': 0,
      'price_range_min': min,
      'price_range_max': max,
      'is_available': 1,
      'verification_status': 'pending',
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'user_wilaya': '16',
    };

String _session() => jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'email': null,
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-10-01 09:00:00',
      },
    });

/// Boots the real dashboard against a fake API carrying [_worker].
///
/// The non-price endpoints are answered normally on purpose: a fake that broke
/// the whole screen would make a negative assertion pass for the wrong reason —
/// the checklist would simply not be on the page.
Future<({ApiClient api, AuthState auth})> _boot({int? min, int? max}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return http.Response(_session(), 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.contains('/my/profile')) {
        return http.Response(
            jsonEncode(_worker(min: min, max: max)), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  // The dashboard asks `AuthGate.isGuest(context)`, which is only
  // `auth.user == null`. Mounted over a bare AuthState the screen is a
  // signed-out visitor, never reads a profile, and the checklist is never built
  // — a draft of this file skipped the sign-in and every case below passed
  // vacuously against a page that did not contain the step.
  await auth.login(phone: '0773000000', password: 'secret123');
  expect(auth.user, isNotNull, reason: 'the dashboard stayed in guest mode');
  return (api: api, auth: auth);
}

/// Drives the dashboard and returns the text it rendered.
///
/// [tall] scrolls: the checklist sits under the identity card, the verification
/// strip and the tool strip, so on a phone-sized viewport the step can be
/// off-screen. `find.text` finds off-screen widgets anyway (it is not a
/// hit-test), so the default is enough for the *state*; the shot test scrolls
/// for the pixels.
Future<List<String>> _render(WidgetTester tester,
    {required int? min,
    required int? max,
    Size logical = const Size(392, 1400)}) async {
  final s = await _boot(min: min, max: max);
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: s.api,
    auth: s.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: const WorkerHomeScreen(),
    ),
  ));
  // Bounded pumps, not pumpAndSettle: the loading skeletons animate forever.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
}

/// The checklist's own copy, so a rename cannot make these assertions vacuous.
const _priceStep = 'حدّد أسعارك ونطاق خدمتك';
const _bioStep = 'اكتب نبذة تعريفية عنك';

void main() {
  group('the price step agrees with the card he is chosen from', () {
    testWidgets('a contractor who typed only a maximum has his step ticked',
        (tester) async {
      // The regression. `min` is null, so the old `min != null && max != null`
      // said "not done", and the man was told on his own dashboard to go and
      // set the prices he had already set — while the browse card printed
      // «حتى 9000 دج» for the same profile.
      final texts = await _render(tester, min: null, max: 9000);

      // Guard the guard: a dashboard stuck loading renders none of this, and
      // every assertion below would then be quietly true.
      expect(texts, contains(_bioStep), reason: 'the checklist is not on the '
          'page: $texts');
      expect(texts, contains(_priceStep), reason: '$texts');

      // The step is rendered as a tick or an empty circle; the two differ in
      // colour, so the row that carries the step is located by its own label
      // and read through the icon beside it rather than through the text,
      // which is identical either way. 1 done step out of 4 -> "1 من 4" is
      // the simplest honest read: the bio is set, the price is set, the
      // trades are set, the papers are not.
      expect(texts, contains('3 من 4'),
          reason: 'specialties, bio and a typed maximum are all done, so the '
              'checklist is at 3 of 4 — the price step is not outstanding: '
              '$texts');
    });

    testWidgets('a contractor with no price at all still has it unticked',
        (tester) async {
      // The other direction, so the fix cannot be read as "always ticked": the
      // step exists to say a man has not set his prices, and this is the man it
      // is for. Trades and bio set, nothing else -> 2 of 4.
      final texts = await _render(tester, min: null, max: null);

      expect(texts, contains(_priceStep), reason: '$texts');
      expect(texts, contains('2 من 4'),
          reason: 'only trades and bio are set: $texts');
    });

    testWidgets('a (0, 0) price pair is not a price, on this step either',
        (tester) async {
      // Both boxes non-null satisfies `&&`, and both are zero — a row the
      // editor can produce (`DzNumber.tryParse` accepts `0`, the field has no
      // lower bound, and `min > max` does not fire on equal numbers).
      // `priceRangeAr` folds `(0, 0)` to null, so the card shows no money tag;
      // the step used to be ticked anyway.
      expect(hasPriceRange(0, 0), isFalse,
          reason: 'the app-wide gate: a zero pair carries no price');
      final texts = await _render(tester, min: 0, max: 0);
      expect(texts, contains('2 من 4'),
          reason: 'a (0, 0) pair is the same as no price, so the step is still '
              'outstanding: $texts');
    });

    testWidgets('both boxes typed ticks the step, and a min-only pair does too',
        (tester) async {
      // The two ends the old `&&` happened to get right, asserted so the fix is
      // not a loosening of anything: both typed -> 3 of 4, and min-only (the
      // «من» box) -> 3 of 4 as well, because the editor accepts one box.
      for (final pair in <(int?, int?)>[(2500, 8000), (2500, null)]) {
        final texts = await _render(tester, min: pair.$1, max: pair.$2);
        expect(texts, contains('3 من 4'),
            reason: '(${pair.$1}, ${pair.$2}) is a price: $texts');
      }
    });
  });

  group('the step is the same fact the card prints', () {
    // The two surfaces of one man, asserted in one place so they cannot drift
    // again. `hasPriceRange` is the single gate; the checklist and the card
    // both read it, and this is the table that would notice if a third copy
    // appeared.
    test('every pair reads the same as the card, in both directions', () {
      const pairs = <(int?, int?)>[
        (null, null),
        (null, 9000),
        (2500, null),
        (2500, 8000),
        (0, 0),
        (0, null),
        (null, 0),
        (0, 8000),
        (8000, 0),
        (7000, 7000),
      ];
      // The step is done exactly when the card has a money tag to draw, so the
      // two columns must agree on every pair — including the ones where the
      // answer is "no price", which is the half a one-sided table never
      // checks. (An earlier draft of this test asserted `isTrue` for all ten
      // pairs, which would have passed while `(null, null)` was broken.)
      for (final p in pairs) {
        expect(hasPriceRange(p.$1, p.$2), priceRangeAr(p.$1, p.$2) != null,
            reason: '(${p.$1}, ${p.$2}): the card tag and the checklist step '
                'must come from the same fact');
      }
      // Named explicitly as well, so a failure says which pair broke and not
      // merely that two columns differed.
      expect(hasPriceRange(null, 9000), isTrue,
          reason: 'a typed maximum is a price');
      expect(hasPriceRange(2500, null), isTrue,
          reason: 'a typed minimum is a price');
      expect(hasPriceRange(null, null), isFalse,
          reason: 'nothing typed is not a price');
      expect(hasPriceRange(0, 0), isFalse,
          reason: 'a zero pair is the server/form sentinel, not a price');
      expect(hasPriceRange(0, null), isFalse);
      expect(hasPriceRange(null, 0), isFalse);
      expect(hasPriceRange(0, 8000), isTrue);
      expect(hasPriceRange(8000, 0), isTrue);
    });
  });
}
