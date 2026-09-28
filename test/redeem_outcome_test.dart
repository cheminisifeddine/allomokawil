// Proves the twelfth write got the contract, and that the money sentence it
// prints is backed by evidence.
//
// `_redeem` was the write the 26 Sep audit missed: it sat forty lines under the
// `_request` that audit fixed, in the same file, and had neither half of the
// contract. The half it did have was the dangerous one — `planCodeOk`,
// «تم تفعيل اشتراكك», printed whenever the server's answer carried no plan.
//
// Two halves are covered, because they fail differently: the rule (pure, no
// widget) and the screen that has to obey it. A correct helper wired to an
// unchanged `_redeem` would pass the first half clean — the exact mistake the
// pricing-card tick made.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/l10n/write_outcome.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/redeem_outcome.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// A `current` block as the server sends it.
Map<String, dynamic> _current({
  String plan = 'free_trial',
  String? expiresAt,
}) =>
    {'plan': plan, 'status': 'active', if (expiresAt != null) 'expires_at': expiresAt};

Map<String, dynamic> _catalogue({required Map<String, dynamic> current}) => {
      'currency': 'DZD',
      'note_ar': 'الاشتراك فقط: بدون عمولة',
      'auto_renew': false,
      'plans': [
        {
          'id': 'pro',
          'name_ar': 'محترف',
          'price_month': 3000,
          'price_year': 30000,
          'quote_limit': -1,
          'portfolio_limit': 60,
          'features': ['ترتيب متقدّم في نتائج البحث'],
        }
      ],
      'current': current,
      'pending_request': null,
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
        ],
        'support_phone': null,
      },
    };

SubscriptionStatus _status({
  String plan = 'free_trial',
  String? expiresAt,
}) =>
    SubscriptionStatus.fromJson(_current(plan: plan, expiresAt: expiresAt));

void main() {
  group('redeemLanded - the honest question', () {
    test('an upgrade is the write landing', () {
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(),
          fresh: _status(plan: 'pro', expiresAt: '2026-12-01 00:00:00'),
        ),
        isTrue,
      );
    });

    test('an upgrade with no answer is still the write landing', () {
      // The unconfirmed path: the code's answer never arrived, so the app does
      // not know which plan it named. The movement is still proof - the
      // redemption is the only write this screen makes at this moment.
      expect(
        redeemLanded(
          before: _status(),
          fresh: _status(plan: 'pro', expiresAt: '2026-12-01 00:00:00'),
        ),
        isTrue,
      );
    });

    test('a renewal that extended the expiry is the write landing', () {
      // The half an id-only rule gets wrong. `pro` on both sides, and the code
      // was burned - the only evidence is that the end date moved.
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(plan: 'pro', expiresAt: '2026-10-01 00:00:00'),
          fresh: _status(plan: 'pro', expiresAt: '2026-11-01 00:00:00'),
        ),
        isTrue,
      );
    });

    test('a renewal that did not move the expiry is a miss', () {
      // The case a bare equality would call a success. Same plan, same end
      // date, answer that names the plan: the row is the row that was already
      // there. Codes are single-use, so claiming `landed` here tells a man his
      // code was burned and did nothing.
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(plan: 'pro', expiresAt: '2026-10-01 00:00:00'),
          fresh: _status(plan: 'pro', expiresAt: '2026-10-01 00:00:00'),
        ),
        isFalse,
      );
    });

    test('an unchanged trial after an upgrade is a miss', () {
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(),
          fresh: _status(),
        ),
        isFalse,
      );
    });

    test('an upgrade onto a plan the code did not name is a miss', () {
      // A code for `pro` that moved him to `basic` is not this code working.
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(),
          fresh: _status(plan: 'basic', expiresAt: '2026-12-01 00:00:00'),
        ),
        isFalse,
      );
    });

    test('a downgrade is still the write landing', () {
      // The code is what he bought; the plan the server picked is the answer.
      // Refusing to report it would leave a man who genuinely redeemed a code
      // believing it failed.
      expect(
        redeemLanded(
          codePlan: 'basic',
          before: _status(plan: 'pro', expiresAt: '2026-12-01 00:00:00'),
          fresh: _status(plan: 'basic', expiresAt: '2027-01-01 00:00:00'),
        ),
        isTrue,
      );
    });

    test('a renewal with no expiry to compare is never claimed', () {
      // A payload the server sent without an end date cannot prove the
      // extension happened. Claiming it is the mistake this file exists to
      // prevent; a miss is retryable and costs the user nothing.
      expect(
        redeemLanded(
          codePlan: 'pro',
          before: _status(plan: 'pro'),
          fresh: _status(plan: 'pro'),
        ),
        isFalse,
      );
    });

    test('a missing snapshot is never claimed', () {
      expect(redeemLanded(before: null, fresh: _status(plan: 'pro')), isFalse);
      expect(redeemLanded(before: _status(), fresh: null), isFalse);
      expect(redeemLanded(before: null, fresh: null), isFalse);
    });

    test('a free trial cannot be renewed by a code', () {
      // A trial carries no expiry at all, so there is nothing to move - and
      // the commonest redemption in the app is trial -> paid, which is an
      // *upgrade* and is proven by the id moving, not by the expiry.
      expect(
        redeemLanded(
          codePlan: 'free_trial',
          before: _status(),
          fresh: _status(),
        ),
        isFalse,
      );
    });
  });

  group('resolveRedeemWriteOutcome', () {
    test('reports landed on a movement', () async {
      final outcome = await resolveRedeemWriteOutcome(
        codePlan: 'pro',
        before: _status(),
        fetch: () async => _status(plan: 'pro', expiresAt: '2026-12-01 00:00:00'),
      );
      expect(outcome, WriteOutcome.landed);
    });

    test('reports missing when nothing moved', () async {
      final outcome = await resolveRedeemWriteOutcome(
        codePlan: 'pro',
        before: _status(),
        fetch: () async => _status(),
      );
      expect(outcome, WriteOutcome.missing);
    });

    test('a failed re-read is unknown, never missing', () async {
      // The money case. The phone is still offline, so «the code did not work»
      // is a guess - and it is the guess that makes a man buy a second
      // single-use code for a plan he already paid for.
      final outcome = await resolveRedeemWriteOutcome(
        codePlan: 'pro',
        before: _status(),
        fetch: () async => throw ApiException(S.errOffline),
      );
      expect(outcome, WriteOutcome.unknown);
    });

    test('re-reads once and does not retry on its own', () async {
      var calls = 0;
      await resolveRedeemWriteOutcome(
        codePlan: 'pro',
        before: _status(),
        fetch: () async {
          calls++;
          return _status(plan: 'pro', expiresAt: '2026-12-01 00:00:00');
        },
      );
      expect(calls, 1);
    });
  });

  group('on the real screen', () {
    // The half a helper test cannot see: whether `_redeem` asks the question at
    // all, and whether it prints a money claim it cannot back up.
    /// Drives `_redeem` against a POST that answers [redeemBody] and a GET that
    /// answers with [catalogue]. When [unconfirmed] is set the POST is instead
    /// made to outlast the client's patience, which is how the transport layer
    /// produces `errWriteUnconfirmed`.
    Future<List<String>> redeem(
      WidgetTester tester, {
      required Map<String, dynamic> Function() catalogue,
      required Map<String, dynamic> redeemBody,
      bool unconfirmed = false,
    }) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/subscription/redeem')) {
            if (unconfirmed) {
              // The real shape of an unconfirmed write, reproduced rather than
              // faked with a status code: `errWriteUnconfirmed` is thrown by
              // the transport refusing to retry a POST whose answer did not
              // arrive. A 5xx does NOT produce it - that decodes to
              // `errServer`, which has its own sentence and correctly skips
              // the re-read.
              await Future<void>.delayed(const Duration(milliseconds: 120));
              return http.Response(jsonEncode({'ok': true}), 200,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response(jsonEncode(redeemBody), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(catalogue()), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 25),
      );

      await tester.pumpWidget(AppScope(
        api: api,
        auth: AuthState(api),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const SubscriptionScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The real route: the code field and its own button, by their stable
      // keys, rather than a label we guessed at.
      expect(find.byKey(const Key('plan-code')), findsOneWidget,
          reason: 'the redemption card never rendered');
      await tester.enterText(find.byKey(const Key('plan-code')), 'ALOMOK-2026');
      await tester.tap(find.byKey(const Key('plan-redeem')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      return [
        ...tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
        ...tester
            .widgetList<SnackBar>(find.byType(SnackBar))
            .map((s) => (s.content as Text).data ?? ''),
      ];
    }

    testWidgets('an answer that names no plan is never reported as activated',
        (tester) async {
      // The defect. A response with no `plan` object used to print
      // «تم تفعيل اشتراكك» - a money claim with nothing behind it, on the one
      // screen where the man has just handed over 30000 دج. The answer below is
      // a perfectly ordinary 200: the server filed the request and sent a body
      // this app cannot read a plan out of.
      final said = await redeem(
        tester,
        catalogue: () => _catalogue(current: _current()),
        redeemBody: {'ok': true},
      );

      expect(said.any((s) => s == S.planCodeNoPlan), isTrue,
          reason: 'a plan-less answer printed no honest sentence: $said');
      expect(said.where((s) => s.contains(S.planCodeOk)), isEmpty,
          reason: 'a redemption with no evidence claimed activation: $said');
    });

    testWidgets('an answer that names a plan still claims activation',
        (tester) async {
      // The control for the test above: the same screen, an answer the server
      // did name a plan on. The money sentence has to survive - the fix is not
      // "stop saying it", it is "say it when it is earned".
      final said = await redeem(
        tester,
        catalogue: () =>
            _catalogue(current: _current(plan: 'pro', expiresAt: '2026-12-01 00:00:00')),
        redeemBody: {
          'plan': {'id': 'pro'},
        },
      );

      // Substring, not element: the screen prints the plan id with the
      // sentence («تم تفعيل اشتراكك — PRO»), so an exact-element match would
      // pass on a screen that claims nothing and fail on the one that works.
      expect(said.any((s) => s.contains(S.planCodeOk)), isTrue,
          reason: 'a real redemption stopped claiming activation: $said');
      expect(said.any((s) => s == S.planCodeNoPlan), isFalse,
          reason: 'a real redemption asked the man to check a subscription: $said');
    });

    testWidgets('an unconfirmed redemption is re-read, not left undecided',
        (tester) async {
      var reads = 0;
      final said = await redeem(
        tester,
        // First read: still on the trial. The POST then fails unconfirmed, and
        // the re-read finds the plan the code bought - so the write landed.
        catalogue: () {
          reads++;
          return reads <= 1
              ? _catalogue(current: _current())
              : _catalogue(
                  current: _current(plan: 'pro', expiresAt: '2026-12-01 00:00:00'));
        },
        redeemBody: {'ok': true},
        unconfirmed: true,
      );

      expect(reads, greaterThanOrEqualTo(2),
          reason: 'the screen never re-read after the unconfirmed write');
      expect(said, contains(S.writeUnconfirmedLanded),
          reason: 'the redemption did not report the landing: $said');
      // And the honest sentence, not the money claim it replaced.
      expect(said.where((s) => s == S.planCodeOk), isEmpty,
          reason: 'an unconfirmed redemption claimed activation: $said');
    });
  });
}
