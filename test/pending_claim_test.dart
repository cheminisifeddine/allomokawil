// The receipt for a payment he already sent sat four lines above a live button
// that asked for the same money again.
//
// Found 30 Sep 2026 while auditing the money screen after the band-scoping
// tick. The previous tick's note named `_PendingCard` as a likely third home
// for the two-figure problem; that note was **wrong** — the card already
// prints number, plan, term, amount, method and day. Reading the screen
// instead of trusting the note found something the note never looked at:
// `pendingClaimFor` did not exist, and the plan cards below the receipt never
// asked what the receipt was for.
//
// The state the screen held after one write:
//
//     ┌ طلبك قيد المراجعة ───────────────────────┐
//     │ رقم الطلب 49 · محترف · اشتراك سنوي · …    │
//     └───────────────────────────────────────────┘
//     …
//     ┌ محترف ─────────────────────────────┐
//     │ 3000 دج   تدفع شهرياً               │
//     │ [ ترقية الاشتراك — محترف ]          │  <- live, enabled, same plan,
//     └─────────────────────────────────────┘     same term he just paid for
//
// He has sent the money. The screen tells him the request was received, in a
// card drawn in the *info* colour, and then asks him for it again in an amber
// button. The first request is `pending` and nobody has confirmed it, so from
// the server's point of view this is a second, perfectly legal request — and
// the app is the only thing that knows the two are the same purchase.
//
// A man who does not read the small card carefully, or whose connection is
// poor enough that the receipt is above his fold, taps the amber button and
// pays twice. The most expensive class of bug on this screen, and it is one
// line of a condition: nothing on the plan card ever compared itself against
// the pending row.
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
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// `basic` is 1500 دج a month and `gold` 6000 — three plans, so a test cannot
/// pass by blocking the whole list, and the pending row names the **first**
/// one, which is the card nearest the receipt.
Map<String, dynamic> _catalogue({String pendingPlan = 'pro'}) => {
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
          'features': <String>['عارض أسعار غير محدودة'],
        },
        {
          'id': 'pro',
          'name_ar': 'محترف',
          'price_month': 3000,
          'price_year': 30000,
          'quote_limit': -1,
          'portfolio_limit': 60,
          'features': <String>['ترتيب متقدّم في نتائج البحث'],
        },
        {
          'id': 'gold',
          'name_ar': 'ذهبي',
          'price_month': 6000,
          'price_year': 60000,
          'quote_limit': -1,
          'portfolio_limit': 120,
          'features': <String>['صدارة النتاجات في ولايتك'],
        },
      ],
      'current': {'plan': 'free_trial', 'status': 'active'},
      'pending_request': {
        'id': 49,
        'plan': pendingPlan,
        'period': 'month',
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

/// Boots the real route against [payload] and settles it.
Future<void> _boot(WidgetTester tester, Map<String, dynamic> payload) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(jsonEncode(payload), 200,
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
}

/// Brings a plan card's button into the viewport of the lazy `ListView`.
///
/// `scrollUntilVisible` **then** `ensureVisible`, in that order: a card below
/// the fold is not in the tree at all, so `ensureVisible` alone finds zero
/// widgets and fails. The order is load-bearing, not tidiness.
Future<void> _showCard(WidgetTester tester, String plan, String term) async {
  // The term is chosen **before** the scroll, and this is not tidiness. The
  // yearly card is a *different widget* — the key is
  // `plan-pro-year`, not a `pro` card with another value in it — so on the
  // monthly term it is not in the tree at all and `scrollUntilVisible` fails
  // with `Bad state: No element`. Toggling first is what puts it in the tree
  // for the scroll to find.
  if (term == 'year') {
    await tester.tap(find.text('سنوي'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }
  final key = Key('plan-$plan-$term');
  await tester.scrollUntilVisible(find.byKey(key), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  // ── the rule, on its own, before the screen ─────────────────────────────
  group('the claim a pending request makes on the catalogue', () {
    test('it names the plan and the term, and nothing else', () {
      final c = pendingClaimFor(PendingRequest.fromJson({
        'id': 49,
        'plan': 'pro',
        'period': 'month',
        'amount_paid': 0,
        'payment_method': 'baridimob',
        'created_at': '2026-10-01 10:00:00',
      }));
      expect(c, isNotNull);
      expect(c!.plan, 'pro');
      expect(c.periodWire, 'month');
    });

    test('nothing pending means no claim at all', () {
      expect(pendingClaimFor(null), isNull);
      expect(pendingClaimFor(PendingRequest.fromJson({'id': 1, 'plan': ''})),
          isNull,
          reason: 'a row with no plan id cannot block any card');
    });

    test('it covers that plan at that term and nothing else', () {
      final c = pendingClaimFor(PendingRequest.fromJson(
          {'id': 49, 'plan': 'pro', 'period': 'month'}))!;
      expect(c.covers('pro', 'month'), isTrue);
      // The other two directions matter as much as the first: blocking the
      // yearly price of a plan he is already paying monthly would be a fix
      // that steals a product, and marking an unrelated plan would be a fix
      // that greys out the whole list.
      expect(c.covers('pro', 'year'), isFalse);
      expect(c.covers('gold', 'month'), isFalse);
      expect(c.covers('basic', 'month'), isFalse);
    });

    test('a padded plan id is the same plan, not a different one', () {
      final c = pendingClaimFor(PendingRequest.fromJson(
          {'id': 49, 'plan': '  pro  ', 'period': 'month'}))!;
      expect(c.covers('pro', 'month'), isTrue,
          reason: 'a payload that pads an id must not leave him free to pay '
              'for the same plan twice');
    });

    test('an unknown term blocks nothing, and never guesses a month', () {
      // The live Worker files an unrecognised period as a month and still
      // answers ok, so this is a shape this app really receives. Guessing
      // «month» here would lock a man out of the yearly plan he came for.
      final c = pendingClaimFor(PendingRequest.fromJson(
          {'id': 49, 'plan': 'pro', 'period': 'quarter'}))!;
      expect(c.covers('pro', 'month'), isFalse);
      expect(c.covers('pro', 'year'), isFalse);
    });

    test('a row with no term at all blocks nothing either', () {
      final c = pendingClaimFor(PendingRequest.fromJson(
          {'id': 49, 'plan': 'pro'}))!;
      expect(c.periodWire, isNull);
      expect(c.covers('pro', 'month'), isFalse);
      expect(c.covers('pro', 'year'), isFalse);
    });
  });

  // ── the screen, which is where the defect actually lived ────────────────
  group('the card that is already paid for', () {
    testWidgets('the plan the pending request names loses its button',
        (tester) async {
      await _boot(tester, _catalogue());
      await _showCard(tester, 'pro', 'month');

      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget,
          reason: 'the card is not on screen, so nothing was proved');

      // The button is there and it is **pressable**. Checking that it is
      // absent is enough; checking that the tap is refused as well is the
      // part that cannot be faked, because a button can be drawn grey and
      // still be wired to the POST.
      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-pro-month')));
      expect(btn.onPressed, isNull,
          reason: 'the plan he already paid for still files a second request');
      expect(btn.label, isNot('ترقية الاشتراك — محترف'),
          reason: 'a button that reads «upgrade» on a paid request is a lie '
              'in the app\'s own voice');
    });

    testWidgets('the other plans are untouched, because a fix that greys out '
        'the list is not a fix', (tester) async {
      await _boot(tester, _catalogue());
      await _showCard(tester, 'gold', 'month');

      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-gold-month')));
      expect(btn.onPressed, isNotNull,
          reason: 'a pending month on «pro» must not lock «gold»');
      expect(btn.label, 'ترقية الاشتراك — ${'ذهبي'}');
    });

    testWidgets('the yearly card of the same plan is still buyable',
        (tester) async {
      await _boot(tester, _catalogue());
      await _showCard(tester, 'pro', 'year');

      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-pro-year')));
      expect(btn.onPressed, isNotNull,
          reason: 'a monthly request does not block the yearly price of the '
              'same plan: those are two different products');
    });

    testWidgets('a pending row naming an unknown term blocks nothing',
        (tester) async {
      final payload = _catalogue();
      (payload['pending_request']! as Map<String, dynamic>)['period'] =
          'quarter';
      await _boot(tester, payload);
      await _showCard(tester, 'pro', 'month');

      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-pro-month')));
      expect(btn.onPressed, isNotNull,
          reason: 'an unknown term must not lock the man out of the product '
              'he came for');
    });

    testWidgets('a pending row with no period blocks nothing',
        (tester) async {
      final payload = _catalogue();
      (payload['pending_request']! as Map<String, dynamic>)
          .remove('period');
      await _boot(tester, payload);
      await _showCard(tester, 'pro', 'month');

      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-pro-month')));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('no pending row at all leaves every card live',
        (tester) async {
      final payload = _catalogue()..['pending_request'] = null;
      await _boot(tester, payload);
      await _showCard(tester, 'pro', 'month');

      final btn = tester.widget<PrimaryButton>(
          find.byKey(const Key('plan-pro-month')));
      expect(btn.onPressed, isNotNull);
    });
  });
}
