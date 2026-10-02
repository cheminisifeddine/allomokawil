// The plan card dates itself on the wall clock while the band above it dates
// itself on the clock the screen was handed.
//
// Direct continuation of `8480b42` (the chat tile) — the same fuse, found on
// the surface where it costs the most. `SubscriptionScreen` has carried a
// `clock` seam since the stale-catalogue tick, and `_StaleBanner` ages against
// it, but `_CurrentPlanCard` never received it: it builds from
// `SubscriptionStatus`, whose `isExpired`, `daysUntilExpiry` and
// `expiryCountdownAr` all reach `DateTime.now()` inside `models/plan.dart`.
//
// Why that matters beyond "a test could age it". The screen is the one a
// paying contractor opens to answer "how long do I have". It carries a
// once-a-minute ageing timer ([_SubscriptionScreenState._ageTimer]) that ages
// the band against the injected clock — so a contractor watching that screen
// across a midnight boundary sees the band move while the card under it keeps
// the answer computed at build time by whatever clock the process happens to
// hold. Two truths on one screen, one of them about money.
//
// **Left deliberately alone:** `profile_screen.dart:_planSummary` reads the
// same two getters, but that screen has no `clock` seam at all, so there is
// nothing to inject and changing it is a different (larger) item.
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
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

Map<String, Object?> _catalogue(String expiresAt) => <String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'note_ar': 'الاشتراك فقط',
      'plans': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'basic',
          'name_ar': 'أساسي',
          'price_month': 1500,
          'price_year': 15000,
          'quote_limit': -1,
          'portfolio_limit': 30,
          'search_boost': 1,
          'wilaya_span': 1,
          'features': <String>[],
        },
      ],
      'current': <String, Object?>{
        'plan': 'basic',
        'name_ar': 'أساسي',
        'status': 'active',
        'starts_at': null,
        'expires_at': expiresAt,
        'quote_limit': -1,
        'portfolio_limit': 30,
        'quotes_used_this_month': 2,
        'renews_in_days': null,
      },
      'pending_request': null,
      'payment': <String, Object?>{
        'methods': <Map<String, Object?>>[],
        'support_phone': null,
      },
};

void main() {
  group('the plan card answers with the screen clock, not the wall clock', () {
    /// Renders «اشتراكي» with the screen handed a clock that is **not** the
    /// wall clock, and returns every string the screen drew.
    Future<List<String>> draw(
      WidgetTester tester, {
      required String expiresAt,
      required DateTime Function() clock,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(_catalogue(expiresAt)), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(AppScope(
        api: api,
        auth: AuthState(api),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: SubscriptionScreen(clock: clock),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
    }

    testWidgets('a plan that ends on the injected clock\'s tomorrow counts 1 day',
        (tester) async {
      // **The clock sits a day short of the expiry**, so the honest answer is
      // the singular day arm: one whole midnight to cross.
      //
      // The first draft put both on the 30th and asserted the same thing, and
      // it failed against a *correct* card: `daysUntilExpiry` counts midnights,
      // so a plan ending on the same day as the clock is **0** and the card
      // deliberately drops to the date-only sentence. A boundary written from
      // the prose instead of from the arithmetic is a test of the writer's
      // memory — the same mistake `subscription_clock_test.dart` records twice.
      final texts = await draw(
        tester,
        expiresAt: '2026-09-30 21:00:00',
        // 29 Sep 2026, 10:00. One midnight out.
        clock: () => DateTime(2026, 9, 29, 10),
      );
      expect(
        texts.any((t) => t.contains('بعد يوم —')),
        isTrue,
        reason: 'the card did not count the day the screen was handed:\n'
            '$texts',
      );
    });

    testWidgets('the SAME row reads as finished on a clock past its expiry',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // server row is byte-identical to the case above; only the injected
      // clock moved, past the plan's end instant. Before the fix both cases
      // printed the wall clock's answer, so the difference this file exists to
      // prove was not observable at all — which is the definition of the fuse.
      final texts = await draw(
        tester,
        expiresAt: '2026-09-30 21:00:00',
        // 2 Oct 2026, 10:00 — the end instant (30 Sep) has gone by.
        clock: () => DateTime(2026, 10, 2, 10),
      );
      expect(
        texts.any((t) => t.contains('منتهي')),
        isTrue,
        reason: 'a plan past its expiry still rendered as live:\n$texts',
      );
    });
  });
}
