// The warning that two prices disagree outlived nothing, on the one screen
// where a man is about to move money.
//
// `subscriptionAmountMismatchAr` exists because the price on the payment sheet
// is the app's own arithmetic over a catalogue it fetched earlier, while the
// amount in the answer is D1's, computed at the moment of the write. When they
// disagree the screen says so, naming **both** figures — and then said it in a
// [SnackBar].
//
// A toast is the wrong lifetime for that sentence. Measured on the real screen
// with a real stalled write: the band was on screen at 500 ms and gone by
// 5500 ms, the full default duration, and after it went the screen drew
// `3000 دج` — the quoted price — with nothing on it saying that number had
// just been contradicted. The one number a contractor acts on was left alone
// on the screen, and the sentence that challenged it was the shortest-lived
// thing in the whole view.
//
// The same line then did a second, quieter harm: it was drawn with `_say`,
// which hides the current snackbar first, so it also replaced the
// acknowledgement carrying «حوّل 4500 دج» — the figure D1 says to send. The
// man lost the amount and the warning in the same 4 seconds, and kept the
// price he was told not to pay.
//
// The warning is now a band above the plan card, beside the one that already
// admits a failed re-read, and it is held as state so a reload cannot clear it.
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
import 'package:allomokawil/src/data/subscription_ack.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// The catalogue the app fetches: `pro` is **3000 دج** a month.
Map<String, dynamic> _catalogue() => {
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
          'features': <String>['ترتيب متقدّم في نتائج البحث'],
        }
      ],
      'current': {'plan': 'free_trial', 'status': 'active'},
      'pending_request': {
        'id': 42,
        'plan': 'pro',
        'amount_paid': 0,
        'payment_method': 'baridimob',
        'created_at': '2026-10-01 10:00:00',
      },
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
        ],
        'support_phone': null,
      },
    };

/// Drives the real route on the real screen: the plan card's own button, the
/// sheet's own submit. [charged] is what D1 says to send, deliberately not the
/// price the app quoted.
Future<void> _pay(WidgetTester tester, {required int charged}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
        return http.Response(
          jsonEncode({
            'ok': true,
            'request_id': 42,
            'status': 'pending',
            'period': 'month',
            'months': 1,
            'amount_dzd': charged,
            'plan': {'id': 'pro'},
            'payment': {
              'methods': [
                {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
              ],
              'support_phone': null,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(jsonEncode(_catalogue()), 200,
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

  await tester.tap(find.byKey(const Key('plan-pro-month')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byKey(const Key('plan-submit')), findsOneWidget,
      reason: 'the payment sheet never opened');
  await tester.tap(find.byKey(const Key('plan-submit')));
  // Bounded, never `pumpAndSettle`: the ageing tick keeps a timer alive, so a
  // settling pump would time out rather than fail on the assertion below.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('the rule itself: a mismatch names both figures', () {
    // The pure half, so the widget tests below cannot pass by accident: if the
    // sentence were ever weakened to print only the charged price, the man
    // would no longer know what the app believed.
    final copy = subscriptionAmountMismatchAr(3000, 4500);
    expect(copy, isNotNull);
    expect(copy, contains('4500'), reason: 'the charged amount must be named');
    expect(copy, contains('3000'), reason: 'the quoted amount must be named');
  });

  test('an agreeing price is never a mismatch', () {
    expect(subscriptionAmountMismatchAr(3000, 3000), isNull);
  });

  testWidgets('a price disagreement is on screen while the quoted price is',
      (tester) async {
    await _pay(tester, charged: 4500);

    final warning = subscriptionAmountMismatchAr(3000, 4500);
    expect(warning, isNotNull);
    expect(find.text(warning!), findsOneWidget,
        reason: 'the only sentence naming two prices for the same plan is not '
            'on the screen at all');
  });

  testWidgets('the disagreement is still on screen after the toast would have '
      'expired', (tester) async {
    // The whole tick. Measured on the original screen: present at 500 ms, gone
    // by 5500 ms, leaving `3000 دج` alone with nothing disputing it.
    await _pay(tester, charged: 4500);
    final warning = subscriptionAmountMismatchAr(3000, 4500)!;

    // Well past the default 4 s SnackBar duration, and past the reload that
    // follows every write.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text(warning), findsOneWidget,
        reason: 'the price warning expired with its toast and left the quoted '
            'price standing alone on a money screen');
    expect(find.text('3000 دج'), findsWidgets,
        reason: 'the quoted figure is the one that stays on the card, so the '
            'band has to still be up when it is being read');
  });

  testWidgets('the transfer amount is not the line that carries the warning',
      (tester) async {
    // The second half of the old bug: the warning was drawn with `_say`, which
    // hides the current snackbar, so it also replaced «حوّل 4500 دج» — the
    // figure D1 says to send. Held here so the two sentences cannot be merged
    // back into one by a later tick.
    await _pay(tester, charged: 4500);
    final warning = subscriptionAmountMismatchAr(3000, 4500)!;

    final said = tester
        .widgetList<SnackBar>(find.byType(SnackBar))
        .map((s) => (s.content as Text).data ?? '')
        .join(' | ');
    expect(said, isNot(contains(warning)),
        reason: 'the warning is a band; putting it back in the snackbar queue '
            'puts it behind the acknowledgement again');
  });

  testWidgets('a purchase that agrees on price shows no band', (tester) async {
    // The counter-probe: without it the two tests above could pass because the
    // screen shouts a band at every purchase. Only a disagreement earns one.
    await _pay(tester, charged: 3000);

    expect(find.byKey(const Key(planPriceMismatchKey)), findsNothing,
        reason: 'a plan bought at the quoted price is not a mismatch');
    expect(find.text('3000 دج'), findsWidgets,
        reason: 'the sheet must still have shown the price it always showed');
  });
}
