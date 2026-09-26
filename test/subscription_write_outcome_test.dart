// Proves the sixth write got the contract the other five already had.
//
// `S.errWriteUnconfirmed` is «...تحقّق من القائمة قبل إعادة المحاولة» and five
// write screens answer it by re-reading the server. The subscription write did
// not: its `_request` showed `errorCopy(e)` and stopped, so a contractor told
// his payment request might not have arrived was never told which of the three
// things was true - and the only pending-request slot on the screen is the one
// thing that could have answered him.
//
// These tests cover the rule itself (pure, no widget) and then the screen that
// has to obey it, because a correct helper wired to an unchanged screen would
// pass the first half clean - the mistake the pricing-card tick made.
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
import 'package:allomokawil/src/data/subscription_write_outcome.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

PendingRequest _pending(int id, {String plan = 'pro', String? method}) =>
    PendingRequest.fromJson({
      'id': id,
      'plan': plan,
      'amount_paid': 30000,
      'payment_method': method,
      'created_at': '2026-09-26 10:00:00',
    });

/// The JSON body the server sends — the shape `BillingCatalogue.fromJson` is
/// written against. Deliberately not a model: the screen's first load goes
/// through `jsonEncode` on the wire, and a fixture that skipped that step is
/// how this test first failed with `errUnexpected` and a blank screen.
Map<String, dynamic> _catalogue({PendingRequest? pending}) => {
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
      'current': {'plan': 'free_trial', 'status': 'active'},
      'pending_request': pending == null
          ? null
          : {
              'id': pending.id,
              'plan': pending.plan,
              'amount_paid': pending.amountDzd,
              'payment_method': pending.method,
              'created_at': '2026-09-26 10:00:00',
            },
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
        ],
        'support_phone': null,
      },
};

void main() {
  group('pendingRequestIsMine - the honest question', () {
    test('an empty slot that is now occupied is the write landing', () {
      expect(
        pendingRequestIsMine(before: null, fresh: _pending(7)),
        isTrue,
      );
    });

    test('a slot that moved to a different request is the write landing', () {
      expect(
        pendingRequestIsMine(before: _pending(7), fresh: _pending(8)),
        isTrue,
      );
    });

    test('the same request still waiting proves nothing either way', () {
      // The case a plan comparison would get wrong. The contractor already had
      // request 7 in flight, tapped pay, the POST was unconfirmed, and the slot
      // still holds 7. That is identical whether the server accepted the new
      // request or rejected it, so the app must not answer `landed` - the man
      // already paid for request 7 and would be told his new money arrived.
      expect(
        pendingRequestIsMine(before: _pending(7), fresh: _pending(7)),
        isFalse,
      );
    });

    test('the same plan on a different request is still a new request', () {
      // The trap in the other direction: matching on the plan would call this
      // "unchanged" and stay silent, hiding a real second payment.
      expect(
        pendingRequestIsMine(
            before: _pending(7, plan: 'pro'), fresh: _pending(9, plan: 'pro')),
        isTrue,
      );
    });

    test('an empty slot that is still empty is missing', () {
      expect(pendingRequestIsMine(before: null, fresh: null), isFalse);
    });

    test('a row the server sent no id for is never claimed', () {
      // `_int` turns an absent id into 0, so a row the payload lost is
      // unidentifiable. Claiming it would be the one mistake this file exists
      // to prevent: telling a man his money arrived about a row we cannot
      // name to support.
      final noId = PendingRequest.fromJson({'plan': 'pro'});
      expect(pendingRequestIsMine(before: null, fresh: noId), isFalse);
      expect(pendingRequestIsMine(before: _pending(7), fresh: noId), isFalse);
    });

    test('a request that disappeared is not mine', () {
      // The operator may have cleared the slot. Nothing of mine is there.
      expect(pendingRequestIsMine(before: _pending(7), fresh: null), isFalse);
    });
  });

  group('resolveSubscriptionWriteOutcome', () {
    test('reports landed when a fresh request is identifiable', () async {
      final outcome = await resolveSubscriptionWriteOutcome(
        before: null,
        fetch: () async => BillingCatalogue.fromJson(
            _catalogue(pending: _pending(7))),
      );
      expect(outcome, WriteOutcome.landed);
    });

    test('reports missing when the slot is still empty', () async {
      final outcome = await resolveSubscriptionWriteOutcome(
        before: null,
        fetch: () async => BillingCatalogue.fromJson(_catalogue()),
      );
      expect(outcome, WriteOutcome.missing);
    });

    test('an unchanged row is missing, never landed', () async {
      // A re-read that proves the slot did not change is a real "not found":
      // the predicate already refused the only case it cannot rule on, so this
      // is not a guess dressed as an answer.
      final outcome = await resolveSubscriptionWriteOutcome(
        before: _pending(7),
        fetch: () async => BillingCatalogue.fromJson(
            _catalogue(pending: _pending(7))),
      );
      expect(outcome, WriteOutcome.missing);
    });

    test('a failed re-read is unknown, never missing', () async {
      // The critical one, and the money case: the phone is still offline, so
      // the re-read proves nothing. Saying `missing` here tells a man who just
      // handed over 30000 دج that his payment did not arrive - which is how he
      // pays for the same plan twice.
      final outcome = await resolveSubscriptionWriteOutcome(
        before: null,
        fetch: () async => throw ApiException(S.errOffline),
      );
      expect(outcome, WriteOutcome.unknown);
    });

    test('re-reads once and does not retry on its own', () async {
      var calls = 0;
      await resolveSubscriptionWriteOutcome(
        before: null,
        fetch: () async {
          calls++;
          return BillingCatalogue.fromJson(
              _catalogue(pending: _pending(7)));
        },
      );
      expect(calls, 1);
    });
  });

  group('on the real screen', () {
    // The half a helper test cannot see: whether the screen asks the question
    // at all. The five-path contract is a behaviour of the screen, so it has to
    // be driven on the screen.

    /// Renders `SubscriptionScreen` against a POST that always fails the way an
    /// unconfirmed write fails, and a GET that answers with [catalogue].
    /// Returns every string the screen rendered, toasts included.
    Future<List<String>> unconfirmedWrite(
      WidgetTester tester, {
      required Map<String, dynamic> Function() catalogue,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
            // The real shape of an unconfirmed write, reproduced rather than
            // faked with a status code. `errWriteUnconfirmed` is thrown by the
            // transport layer refusing to retry a POST whose answer did not
            // arrive in time - the request may or may not have been filed. A
            // 5xx does NOT produce it (that decodes to `errServer`, which has
            // its own sentence and correctly skips the re-read), so a mock that
            // returned one was testing nothing. Slow answer, short timeout:
            // exactly what `test/api_client_failover_test.dart` does.
            await Future<void>.delayed(const Duration(milliseconds: 120));
            return http.Response(jsonEncode({'ok': true}), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(catalogue()), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        // The POST must outlast the client's own patience, so the failure is
        // ambiguous rather than a refusal.
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

      // Drive the real route: the plan card's own button, then the sheet's
      // own submit. Both carry stable keys, so this is the widget the
      // contractor actually presses rather than a label we guessed at.
      await tester.tap(find.byKey(const Key('plan-pro-month')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const Key('plan-submit')),
          findsOneWidget,
          reason: 'the payment sheet never opened');
      await tester.tap(find.byKey(const Key('plan-submit')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
    }

    testWidgets('an unconfirmed payment is re-read, not left undecided',
        (tester) async {
      // First GET: no pending request. The POST then fails unconfirmed, and
      // the re-read finds request 7 - so the write landed and the screen must
      // say so.
      var reads = 0;
      final texts = await unconfirmedWrite(
        tester,
        catalogue: () {
          reads++;
          return reads <= 1
              ? _catalogue()
              : _catalogue(pending: _pending(7));
        },
      );

      final snack = tester
          .widgetList<SnackBar>(find.byType(SnackBar))
          .map((s) => (s.content as Text).data ?? '')
          .toList();
      final said = [...texts, ...snack].join(' | ');

      expect(reads, greaterThanOrEqualTo(2),
          reason: 'the screen never re-read after the unconfirmed write');
      expect(said, contains(S.writeUnconfirmedLanded),
          reason: 'the money path did not report the landing: $said');
    });
  });
}
