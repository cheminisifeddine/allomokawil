// Proves the one figure a man needs in order to pay is the one he is shown.
//
// `POST /api/mobile/subscription` answers with the amount to transfer
// (`amount_dzd`), the term it filed (`period`) and the month count
// (`months`). `Repository.requestSubscription` returns that map and the
// subscription screen used to discard every field of it, showing only
// `S.planRequestOk` — «أرسلنا طلبك، ويُفعَّل بعد تأكيد الدفع».
//
// The follow-up `GET` cannot repair that: the pending row carries
// `amount_paid: 0` until a human confirms, and `pendingAmountLabelAr`
// correctly refuses to print a zero. So the transfer figure existed for the
// duration of one `await` and then vanished, on the screen standing between a
// contractor and his bank transfer.
//
// Verified against the live Worker on 26 Sep 2026 (request 42,
// `POST /api/mobile/subscription` with `plan: basic, period: year`):
//   {"ok":true,"request_id":42,"status":"pending",
//    "period":"year","months":12,"amount_dzd":15000}
//
// Two halves, because the first half alone is how the previous tick shipped a
// correct helper behind an unchanged screen: the pure rule, then the real
// screen driven through its own button and its own sheet.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/subscription_ack.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// The live answer, verbatim.
const _yearAnswer = {
  'ok': true,
  'request_id': 42,
  'status': 'pending',
  'period': 'year',
  'months': 12,
  'amount_dzd': 15000,
};

void main() {
  group('SubscriptionAck.tryParse - the answer the app used to throw away', () {
    test('reads the live response off the wire', () {
      final ack = SubscriptionAck.tryParse(_yearAnswer);
      expect(ack, isNotNull);
      expect(ack!.requestId, 42);
      expect(ack.period, 'year');
      expect(ack.months, 12);
      expect(ack.amountDzd, 15000);
    });

    test('a string amount is read, because D1 has shipped both kinds', () {
      // `PendingRequest` already accepts a string amount for exactly this
      // reason. The same worker cannot be trusted to keep one JSON type.
      expect(
          SubscriptionAck.tryParse({'amount_dzd': '15000'})?.amountDzd, 15000);
    });

    test('the `amount` alias is honoured when `amount_dzd` is absent', () {
      expect(SubscriptionAck.tryParse({'amount': 4250})?.amountDzd, 4250);
    });

    test('a response that is not a JSON object is null, never a crash', () {
      // `Repository.requestSubscription` returns `const {}` when the body is
      // not a map, but it can also answer with a bare string or a list on a
      // proxy error. The card must survive it.
      expect(SubscriptionAck.tryParse('nope'), isNull);
      expect(SubscriptionAck.tryParse(null), isNull);
      expect(SubscriptionAck.tryParse([1, 2, 3]), isNull);
    });

    test('a missing amount is absent, never zero', () {
      // Zero is a number the app would print. An absent field is not a price.
      expect(SubscriptionAck.tryParse({'ok': true})?.amountDzd, isNull);
    });

    test('an unreadable term is kept as nothing, not coerced to a month', () {
      // The live Worker answers `6month` with `ok: true` and files a month, so
      // naming a term is naming what came back — never what was hoped for.
      expect(
          SubscriptionAck.tryParse({'period': '6month', 'amount_dzd': 8000})
              ?.period,
          '6month');
    });
  });

  group('subscriptionAckAr - what the man is actually told', () {
    test('names the amount to transfer and the term it buys', () {
      final said = subscriptionAckAr(SubscriptionAck.tryParse(_yearAnswer));
      expect(said, isNotNull);
      expect(said, contains('15000'));
      expect(said, contains('حوّل'),
          reason: 'a figure with no verb is not an instruction');
      expect(said, contains('سنوي'),
          reason: 'the term must be the one the toggle used');
    });

    test('a free plan answers «مجاناً»-shaped copy, never «حوّل 0 دج»', () {
      // Zero is treated as absent: the server sends `amount_dzd: 0` for a
      // request it accepted without charge, and "transfer 0 دج" is a sentence
      // no one can act on. The caller falls back to `S.planRequestOk`.
      expect(
        subscriptionAckAr(
            SubscriptionAck.tryParse({'amount_dzd': 0, 'period': 'month'})),
        isNull,
      );
      expect(
        subscriptionAckAr(SubscriptionAck.tryParse({'amount_dzd': -5})),
        isNull,
      );
    });

    test('no answer at all is null, so the screen keeps the old sentence', () {
      expect(subscriptionAckAr(null), isNull);
    });

    test('a term the server filed as something unnameable drops the clause',
        () {
      // Not «اشتراك شهري»: the app cannot evidence that from this payload, and
      // a money sentence is the last place to invent one.
      final said = subscriptionAckAr(
          SubscriptionAck.tryParse({'period': '6month', 'amount_dzd': 8000}));
      expect(said, contains('8000'));
      expect(said, isNot(contains('شهري')));
    });

    test('no period on the answer still states the amount', () {
      final said =
          subscriptionAckAr(SubscriptionAck.tryParse({'amount_dzd': 4250}));
      expect(said, contains('4250'));
    });
  });

  group('subscriptionAmountMismatchAr - the guard on the number', () {
    test('agreeing figures say nothing', () {
      expect(subscriptionAmountMismatchAr(15000, 15000), isNull);
    });

    test('a disagreement names both figures and asks support', () {
      final said = subscriptionAmountMismatchAr(15000, 8000);
      expect(said, isNotNull);
      expect(said, contains('15000'));
      expect(said, contains('8000'));
    });

    test('an unknown side is never a mismatch', () {
      // A null is "we do not know", and inventing a disagreement warning from
      // it would train the man to ignore the warning.
      expect(subscriptionAmountMismatchAr(null, 8000), isNull);
      expect(subscriptionAmountMismatchAr(15000, null), isNull);
      expect(subscriptionAmountMismatchAr(0, 8000), isNull);
      expect(subscriptionAmountMismatchAr(15000, 0), isNull);
    });
  });

  group('on the real screen', () {
    /// Renders `SubscriptionScreen` against a GET that answers [catalogue] and
    /// a POST that answers [postAnswer], then drives the real route: the plan
    /// card's own button, then the sheet's own submit. Returns every string
    /// the screen rendered, toasts included.
    Future<List<String>> purchase(
      WidgetTester tester, {
      required Map<String, dynamic> Function() catalogue,
      required Map<String, dynamic> postAnswer,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
            return http.Response(jsonEncode(postAnswer), 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(catalogue()), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
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

      await tester.tap(find.byKey(const Key('plan-basic-month')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const Key('plan-submit')), findsOneWidget,
          reason: 'the payment sheet never opened');
      await tester.tap(find.byKey(const Key('plan-submit')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
    }

    /// One paid plan at the live price, so the quoted figure is 1500 and a
    /// 3-month answer is a visible disagreement.
    Map<String, dynamic> catalogue() => {
          'currency': 'DZD',
          'note_ar': 'الاشتراك فقط: بدون عمولة',
          'auto_renew': false,
          'plans': [
            {
              'id': 'basic',
              'name_ar': 'أساسي',
              'price_month': 1500,
              'price_year': 15000,
              'quote_limit': -1,
              'portfolio_limit': 30,
              'features': ['عروض أسعار غير محدودة'],
            }
          ],
          'current': {'plan': 'free_trial', 'status': 'active'},
          'pending_request': null,
          'payment': {
            'methods': [
              {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
            ],
            'support_phone': null,
          },
        };

    testWidgets('the man is told what to transfer, not only that it arrived',
        (tester) async {
      // The whole defect. A monthly purchase whose answer names 1500 دج: the
      // old screen said «أرسلنا طلبك» and nothing else, and the pending card
      // that follows cannot repeat the figure (`amount_paid` is 0 until a human
      // confirms), so the number he has to transfer was never on screen.
      final texts = await purchase(
        tester,
        catalogue: catalogue,
        postAnswer: const {
          'ok': true,
          'request_id': 42,
          'period': 'month',
          'amount_dzd': 1500
        },
      );
      final said = texts.join(' | ');
      expect(said, contains('1500'),
          reason: 'the transfer figure never reached the user: $said');
      expect(said, contains('حوّل'),
          reason: 'no instruction, just a number: $said');
    });

    testWidgets('a server that names no amount falls back to the old sentence',
        (tester) async {
      // Not a blank snackbar and not «حوّل 0 دج»: the sentence the app always
      // had, which is honest about how little is known.
      final texts = await purchase(
        tester,
        catalogue: catalogue,
        postAnswer: const {'ok': true, 'request_id': 43},
      );
      final said = texts.join(' | ');
      expect(said, contains(S.planRequestOk));
      expect(said, isNot(contains('حوّل')));
    });

    testWidgets('a figure that disagrees with the price warns, and names both',
        (tester) async {
      // The sheet quoted 1500 (a month at the catalogue price) and the server
      // answered 4250 — a 3-month term. Both numbers are shown and neither is
      // called the truth, because only D1 knows which catalogue is stale.
      final texts = await purchase(
        tester,
        catalogue: catalogue,
        postAnswer: const {
          'ok': true,
          'request_id': 44,
          'period': 'month',
          'amount_dzd': 4250
        },
      );
      final said = texts.join(' | ');
      expect(said, contains('4250'));
      expect(said, contains('1500'));
      expect(said, contains('الدعم'));
    });

    testWidgets('a figure that agrees raises no warning', (tester) async {
      // The guard must not cry wolf: a matching price is the common case and a
      // warning on every purchase would train the man to skip it.
      final texts = await purchase(
        tester,
        catalogue: catalogue,
        postAnswer: const {
          'ok': true,
          'request_id': 45,
          'period': 'month',
          'amount_dzd': 1500
        },
      );
      final said = texts.join(' | ');
      expect(said, contains('1500'));
      expect(said, isNot(contains('الدعم')),
          reason: 'an agreeing figure must not warn: $said');
    });
  });
}
