// The band said the price was wrong. The card kept drawing it, unmarked.
//
// The tick before this one made the price-mismatch warning a band instead of a
// toast, and stopped it from replacing the acknowledgement that named the
// transfer figure. That fixed the *lifetime* of the sentence. It left the
// other half untouched: the price printed on the plan card is
// `catalogue.priceLabel(plan, _period)` — the app's own arithmetic over a
// catalogue it read earlier — and it was drawn in the same navy, at the same
// size, with the same «تدفع شهرياً» under it, as a price the app was sure of.
//
// So after a write where D1 charged 4500 and the app quoted 3000, the screen
// held **both** of these at the same moment:
//
//     ┌ band ────────────────────────────────┐
//     │ تنبيه: المبلغ المطلوب 4500 دج مختلف │
//     │ عن السعر المعروض 3000 دج — تأكّد …    │
//     └──────────────────────────────────────┘
//     …
//                   3000 دج        <- struck through, in danger red, and
//                   تدفع شهرياً        immediately under it, the amount D1
//                   المبلغ المعتمد 4500 دج   actually used.
//
// The band was right, four lines up, and the number a man reads at the bottom
// of his eye was the wrong one, drawn as though it were the one to pay. Two
// halves of one screen, contradicting, with nothing on the figure saying which
// side to believe.
//
// The fix is not another sentence. It is holding the dispute as **data** — the
// four numbers — and deriving both halves from it, so the strike, the red and
// the amount D1 used are the same fact the band is built from and cannot be
// reworded apart from each other by a later tick.
//
// The payment sheet is in here for the same reason and is the harder case: it
// is a modal route over the screen, it quotes the price again under a heading,
// with the submit button directly underneath. The man reading it while moving
// the money is reading the one screen that repeated the wrong figure.
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

/// `pro` is **3000 دج** a month here; the second plan is the control, and it
/// is priced the same way so a test cannot pass by the screen marking every
/// card.
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

/// Boots the real route, pays with the real card button and the real sheet
/// submit, with D1 charging [charged] — deliberately not the quoted price.
///
/// Returns once the screen has settled past the write.
Future<void> _pay(WidgetTester tester,
    {required int charged, String plan = 'pro'}) async {
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
            'plan': {'id': plan},
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

  await tester.tap(find.byKey(Key('plan-$plan-month')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byKey(const Key('plan-submit')), findsOneWidget,
      reason: 'the payment sheet never opened');
  await tester.tap(find.byKey(const Key('plan-submit')));
  // Bounded, never `pumpAndSettle`: the ageing tick keeps a timer alive, so a
  // settling pump would time out rather than fail on the assertion below.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Brings a plan card's button into the viewport and taps it.
///
/// `ensureVisible` rather than a bare `tap`, and it is not politeness: the plan
/// list is a lazy `ListView`, so the **second** card is not in the tree at all
/// until it is scrolled near, and the **first** card's button sits below the
/// fold once the band and the amount line have pushed the page down. Both
/// looked like app defects on the first run of this file and neither was.
Future<void> _openSheet(WidgetTester tester, String plan) async {
  // Two steps, in this order, and the order is the whole thing. `ensureVisible`
  // needs the widget to already exist, and a card below the fold of a lazy
  // `ListView` does not: so scroll it into existence first, then bring it
  // fully on screen, then tap. Doing only the second step is what made the
  // `gold` sheet fail on the first run with "found 0 widgets".
  await tester.scrollUntilVisible(find.byKey(Key('plan-$plan-month')), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.ensureVisible(find.byKey(Key('plan-$plan-month')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  await tester.tap(find.byKey(Key('plan-$plan-month')));
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.byKey(const Key('plan-submit')), findsOneWidget,
      reason: 'the payment sheet for $plan never opened');
}

/// Past the default 4 s SnackBar duration and past the reload after the write.
Future<void> _settlePastToast(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// The style of the price figure, read off the rendered widget.
TextStyle _priceStyle(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).style!;

void main() {
  // ── the rule, on its own, before the screen ─────────────────────────────
  group('the dispute as data', () {
    test('two different positive prices are a dispute; the rest are not', () {
      final d = PlanPriceDispute.between(
        planId: 'pro',
        periodWire: 'month',
        quotedDzd: 3000,
        chargedDzd: 4500,
      );
      expect(d, isNotNull);
      expect(d!.quotedDzd, 3000);
      expect(d.chargedDzd, 4500);

      // The four refusals the sentence already made, kept so the data cannot
      // be built around a price nobody has heard of.
      expect(
        PlanPriceDispute.between(
            planId: 'pro', periodWire: 'month', quotedDzd: 3000, chargedDzd: 0),
        isNull,
        reason: 'a zero is not a price D1 asked for',
      );
      expect(
        PlanPriceDispute.between(
            planId: 'pro', periodWire: 'month', quotedDzd: 3000, chargedDzd: null),
        isNull,
      );
      expect(
        PlanPriceDispute.between(
            planId: 'pro', periodWire: 'month', quotedDzd: null, chargedDzd: 4500),
        isNull,
      );
      expect(
        PlanPriceDispute.between(
            planId: 'pro', periodWire: 'month', quotedDzd: 3000, chargedDzd: 3000),
        isNull,
      );
    });

    test('a dispute belongs to one plan at one term, and no other', () {
      // The reason `periodWire` is carried at all: the card list re-renders
      // with whatever term the toggle is on, so a monthly disagreement must
      // not paint a strike through the yearly figure, which was never in
      // dispute.
      final d = PlanPriceDispute.between(
        planId: 'pro',
        periodWire: 'month',
        quotedDzd: 3000,
        chargedDzd: 4500,
      )!;
      expect(d.appliesTo('pro', 'month'), isTrue);
      expect(d.appliesTo('pro', 'year'), isFalse);
      expect(d.appliesTo('gold', 'month'), isFalse);
    });

    test('both copies of the fact are derived, so neither can be reworded '
        'alone', () {
      final d = PlanPriceDispute.between(
        planId: 'pro',
        periodWire: 'month',
        quotedDzd: 3000,
        chargedDzd: 4500,
      )!;
      // The band, unchanged from the previous tick's sentence.
      expect(d.lineAr, subscriptionAmountMismatchAr(3000, 4500));
      // The mark on the card: the amount, named once, and not a second copy
      // of the band.
      expect(d.amountLineAr, 'المبلغ المعتمد 4500 دج');
      expect(d.amountLineAr, isNot(contains('3000')),
          reason: 'the figure under dispute belongs to the band alone; '
              'printing it again on the card is the contradiction this test '
              'exists to stop');
    });
  });

  // ── the card ────────────────────────────────────────────────────────────
  testWidgets('the disputed price on the card is struck through and marked',
      (tester) async {
    await _pay(tester, charged: 4500);
    await _settlePastToast(tester);

    final style = _priceStyle(tester, 'plan-price-pro-month');
    expect(style.decoration, TextDecoration.lineThrough,
        reason: 'the figure the band calls wrong is still drawn as payable');
    expect(style.color, AppTheme.danger,
        reason: 'it is still the same navy as a price the app is sure of, so '
            'it is still what the eye lands on');

    expect(find.text('المبلغ المعتمد 4500 دج'), findsOneWidget,
        reason: 'the card is read without the band more often than with it: '
            'the band can be scrolled off, the card cannot');
  });

  testWidgets('the card and the band are on screen together, both correct',
      (tester) async {
    // The whole item. The previous tick made the band outlive the toast; this
    // one makes the figure it disputes stop being drawn as payable while it is
    // up. Both halves, at the same instant, from the same four numbers.
    await _pay(tester, charged: 4500);
    await _settlePastToast(tester);

    expect(find.byKey(const Key(planPriceMismatchKey)), findsOneWidget);
    expect(find.text(subscriptionAmountMismatchAr(3000, 4500)!), findsOneWidget);
    // `3000 دج` is still on the card — the figure is not hidden, it is
    // marked. Hiding it would lose the fact that this is the number the app
    // believed, which is half of what the band is about.
    expect(find.text('3000 دج'), findsWidgets);
    expect(
        _priceStyle(tester, 'plan-price-pro-month').decoration,
        TextDecoration.lineThrough);
  });

  testWidgets('a plan the dispute is not about is drawn exactly as before',
      (tester) async {
    // The control that stops the screen marking every card. `gold` was never
    // bought and never disputed, and it is priced from the same catalogue.
    await _pay(tester, charged: 4500);

    // The second card is not in the tree until it is scrolled near: a lazy
    // `ListView` only builds what is close to the viewport.
    await tester.scrollUntilVisible(find.byKey(const Key('plan-price-gold-month')),
        200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('المبلغ المعتمد 4500 دج'), findsWidgets);
    // `AppTheme.bar` sets `decoration: none` rather than leaving it null, so
    // "not struck through" reads `none` here. Asserting `null` was my error on
    // the first run of this test, not a defect in the card.
    expect(
        _priceStyle(tester, 'plan-price-gold-month').decoration,
        TextDecoration.none,
        reason: 'the strike went on a price that was never in dispute');
    expect(find.text('6000 دج'), findsWidgets);
    expect(_priceStyle(tester, 'plan-price-gold-month').color,
        AppTheme.textPrimary);
  });

  testWidgets('a purchase at the quoted price marks nothing at all',
      (tester) async {
    // The counter-probe, the second one. Without it the three screen tests
    // above could pass because the screen shouts at every purchase.
    await _pay(tester, charged: 3000);

    expect(find.byKey(const Key(planPriceMismatchKey)), findsNothing);
    expect(find.text('المبلغ المعتمد 4500 دج'), findsNothing);
    expect(_priceStyle(tester, 'plan-price-pro-month').decoration,
        TextDecoration.none);
    expect(_priceStyle(tester, 'plan-price-pro-month').color,
        AppTheme.textPrimary);
  });

  testWidgets('a dispute on the monthly term does not mark the yearly figure',
      (tester) async {
    // The reason the dispute carries its term. The toggle redraws both cards
    // with the other term, and `30000 دج` was never the number in dispute.
    await _pay(tester, charged: 4500);
    await _settlePastToast(tester);

    await tester.tap(find.text('سنوي'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(_priceStyle(tester, 'plan-price-pro-year').decoration,
        TextDecoration.none,
        reason: 'the yearly price was never disputed; striking it would be a '
            'second, different falsehood');
    expect(find.text('30000 دج'), findsWidgets);

    // And back: the mark belongs to the term it was found on.
    await tester.tap(find.text('شهري'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(_priceStyle(tester, 'plan-price-pro-month').decoration,
        TextDecoration.lineThrough);
  });

  // ── the sheet ───────────────────────────────────────────────────────────
  testWidgets('the payment sheet repeats the mark, not the quoted price alone',
      (tester) async {
    await _pay(tester, charged: 4500);
    await _settlePastToast(tester);

    await _openSheet(tester, 'pro');

    // A separate key from the card's, because a modal sheet does not remove
    // the screen behind it: both instances are in the tree at once and one
    // shared key would make `findsOneWidget` fail for the wrong reason.
    expect(find.byKey(const Key(planDisputedSheetAmountKey)), findsOneWidget,
        reason: 'the sheet is the last thing between the man and the money, '
            'and it is repeating the figure the band called wrong');
    expect(find.text('المبلغ المعتمد 4500 دج'), findsNWidgets(2),
        reason: 'both instances of the fact are on screen at once: the card '
            'behind and the sheet in front');

    // `Text.rich` builds a **`Text`** widget carrying a `textSpan`, not a
    // `RichText`. Casting to `RichText` was my error on the first run and it
    // failed with a type error rather than a wrong number, which is the
    // cheapest kind of failure to read.
    final heading = tester.widget<Text>(find.byKey(const Key('sheet-price')));
    final spans = (heading.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, '3000 دج');
    expect(spans.first.style!.decoration, TextDecoration.lineThrough,
        reason: 'the heading under the title repeats the wrong price, at the '
            'size of a heading, with the submit button underneath it');
    // The term beside it was never in dispute and is not impeached.
    expect(spans.last.style!.decoration, isNull,
        reason: 'the span carries only a colour, so it has no strike at all');
  });

  testWidgets('a sheet for a plan with no dispute quotes plainly',
      (tester) async {
    await _pay(tester, charged: 4500);
    await _settlePastToast(tester);

    await _openSheet(tester, 'gold');

    expect(find.byKey(const Key(planDisputedSheetAmountKey)), findsNothing);
    final heading = tester.widget<Text>(find.byKey(const Key('sheet-price')));
    final spans = (heading.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, '6000 دج');
    // `null` here and not `TextDecoration.none`: the undisputed span is
    // written with no style override at all, so it inherits the heading.
    expect(spans.first.style, isNull,
        reason: 'the sheet for a plan that was not disputed is byte-for-byte '
            'what it always was');
  });
}
