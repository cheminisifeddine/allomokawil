// What happens to his money when the plan runs out.
//
// Found on 26 Sep 2026, third cycle down the same vein: the server publishes a
// fact and the app discards it. `renew_note_ar`, `payment_style` and
// `auto_renew` arrive on **both** the public catalogue and the authenticated
// subscription payload, and before this cycle `BillingCatalogue` read none of
// them — verified by grep, where the three names appeared only in the model
// and now in this test.
//
// Beside them, `note_ar` — «بدون عمولة» — was read and printed in full on the
// same card. So the screen made its most reassuring promise ("we never take a
// cut") and said nothing about the one an Algerian contractor is actually
// anxious about before handing over cash: **nobody is going to charge me again**.
// The founder sells prepaid months by BaridiMob and in cash; a man who is unsure
// does not buy.
//
// The wording under test is the founder's own, captured from the live API on
// 26 Sep 2026 (see [_liveSubscription]), not invented here.
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
import 'package:allomokawil/src/data/plan_renewal_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// What `GET /api/mobile/subscription` actually answered on 26 Sep 2026 for a
/// freshly registered worker: `auto_renew` is present and **false**, and the
/// Arabic note is the founder's own sentence.
const String _liveSubscription = '''
{
 "currency": "DZD", "commission_percent": 0, "commission_per_order": 0,
 "note_ar": "الاشتراك فقط: بدون عمولة على الطلبات وبدون أي نسبة من سعر المشروع",
 "payment_style": "prepaid", "auto_renew": false,
 "renew_note_ar": "الدفع مسبق لعدد من الأشهر — لا يوجد خصم تلقائي من البطاقة",
 "plans": [
  {"id":"free_trial","name_ar":"مجاني","name_fr":"Gratuit","tagline_ar":"جرّب المنصة بدون دفع",
   "price_month":0,"price_year":0,"quote_limit":3,"portfolio_limit":5,"search_boost":0,"wilaya_span":1,
   "features":["٣ عروض أسعار في الشهر","ملف شخصي أساسي"]},
  {"id":"pro","name_ar":"محترف","name_fr":"Pro","tagline_ar":"للمقاول الذي يعمل كل يوم",
   "price_month":3000,"price_year":30000,"quote_limit":-1,"portfolio_limit":60,"search_boost":3,"wilaya_span":2,
   "features":["ترتيب متقدّم في نتائج البحث"]}
 ],
 "current": {"plan":"free_trial","name_ar":"مجاني","status":"active",
   "starts_at":null,"expires_at":null,"quote_limit":3,"portfolio_limit":5,
   "quotes_used_this_month":0,"renews_in_days":null},
 "pending_request": null,
 "payment": {"methods":[{"id":"baridimob","label_ar":"بريدي موب (تحويل)","instructions":null}],
   "support_phone": null}
}
''';

Map<String, dynamic> _sub() => {
      ...jsonDecode(_liveSubscription) as Map<String, dynamic>,
    };

void main() {
  group('the renewal promise is parsed off the payload', () {
    test("the live payload says prepaid, and the app now knows it", () {
      final cat = BillingCatalogue.fromJson(_sub());
      // The whole defect in one line: this was null, then false, then absent.
      expect(cat.renewNoteAr, contains('لا يوجد خصم تلقائي'));
      expect(cat.autoRenew, isFalse);
      expect(cat.isPrepaid, isTrue);
    });

    test('an absent flag is not a promise that nothing renews', () {
      // A server that predates the field must not be read as "prepaid". This
      // is the trap: defaulting the missing value to false would print
      // «لن يُخصم تلقائياً» off a field nobody sent, and a man who is told his
      // card will not be charged is a man who will not check.
      final json = _sub()..remove('auto_renew');
      final cat = BillingCatalogue.fromJson(json);
      expect(cat.autoRenew, isNull);
      expect(cat.isPrepaid, isFalse);
    });

    test('a server that auto-renews is never described as prepaid', () {
      final json = _sub()..['auto_renew'] = true;
      final cat = BillingCatalogue.fromJson(json);
      expect(cat.isPrepaid, isFalse);
    });

    test('an absent note is missing, not a blank line', () {
      final json = _sub()..remove('renew_note_ar');
      expect(BillingCatalogue.fromJson(json).renewNoteAr, isNull);

      final blank = _sub()..['renew_note_ar'] = '   ';
      expect(BillingCatalogue.fromJson(blank).renewNoteAr, isNull);
      expect(renewalNoteAr('   '), isNull);
      expect(renewalNoteAr(null), isNull);
    });

    test('the note is trimmed, not re-worded', () {
      // The founder edits this in D1; the app must print it verbatim rather
      // than "normalising" a promise into its own words.
      final cat = BillingCatalogue.fromJson(
          _sub()..['renew_note_ar'] = '  الدفع مسبق  ');
      expect(cat.renewNoteAr, 'الدفع مسبق');
      expect(renewalNoteAr(cat.renewNoteAr), 'الدفع مسبق');
    });
  });

  group('a prepaid term, counted the way Arabic counts', () {
    test('the four lengths the server actually sells', () {
      expect(prepaidTermsAr(1), 'شهراً');
      expect(prepaidTermsAr(3), '3 أشهر');
      expect(prepaidTermsAr(6), '6 أشهر');
      expect(prepaidTermsAr(12), '12 شهراً');
    });

    test('the dual takes no number', () {
      expect(prepaidTermsAr(2), 'شهران');
    });

    test('11 and up are counted singular again', () {
      // The rule this file exists to not re-break: 11–99 take the singular with
      // the number, exactly like «بعد 100 يوماً».
      expect(prepaidTermsAr(11), '11 شهراً');
      expect(prepaidTermsAr(24), '24 شهراً');
    });

    test('zero months is not a term and prints nothing', () {
      expect(prepaidTermsAr(0), isNull);
      expect(prepaidTermsAr(-3), isNull);
    });
  });

  group('saving copy', () {
    test('a real saving names the amount', () {
      expect(termSavingLabel(500), 'توفّر 500 دج');
    });

    test('no saving means no line, not «توفّر 0 دج»', () {
      // A line announcing that nothing was saved, on the screen whose job is to
      // talk someone into paying, reads as a broken calculation.
      expect(termSavingLabel(0), isNull);
      expect(termSavingLabel(-250), isNull);
    });
  });

  group('the sentence on the real screen', () {
    // A model field can be parsed and never shown. These drive
    // SubscriptionScreen itself and read what build() produced, because
    // "every paying contractor was told nothing about renewal" is a claim about
    // a rendered screen, not about a getter.

    Future<List<String>> rendered(
      WidgetTester tester, {
      Map<String, dynamic>? payload,
      bool openPaymentSheet = false,
    }) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            return http.Response(
              jsonEncode(payload ?? _sub()),
              200,
              headers: {'content-type': 'application/json'},
            );
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

      // Guard the guard: an error state renders none of this, and a test that
      // "passes" because every `any()` is false is worse than no test.
      var texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.any((t) => t.contains('أعد المحاولة')), isFalse,
          reason: 'the screen never loaded, so the copy was never rendered: '
              '$texts');

      if (openPaymentSheet) {
        // The sheet is the last thing before a BaridiMob transfer.
        await tester.tap(find.byKey(const Key('plan-pro-month')));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .toList();
      }
      return texts;
    }

    testWidgets('the renewal sentence is on the subscription card',
        (tester) async {
      final texts = await rendered(tester);
      expect(
          texts.any((t) => t.contains('لا يوجد خصم تلقائي من البطاقة')),
          isTrue,
          reason: 'the server published the note and the screen dropped it: '
              '$texts');
    });

    testWidgets('it is repeated under the price in the payment sheet',
        (tester) async {
      // The sheet is the screenshot a contractor forwards with his receipt, so
      // the promise has to be in it, not only on the card above.
      final texts = await rendered(tester, openPaymentSheet: true);
      expect(
          texts.where((t) => t.contains('لا يوجد خصم تلقائي')).length,
          greaterThanOrEqualTo(1),
          reason: 'the sheet is where money moves and the note is absent: '
              '$texts');
    });

    testWidgets('no note from the server means no line, never a blank row',
        (tester) async {
      final payload = _sub()..remove('renew_note_ar');
      final texts = await rendered(tester, payload: payload);
      expect(texts.any((t) => t.contains('خصم تلقائي')), isFalse,
          reason: 'an absent note was invented: $texts');
    });

    testWidgets('the other half of the promise still renders beside it',
        (tester) async {
      // The card's job is to say both things: no cut of the job, and no
      // automatic charge later. Shipping one without the other would be a
      // regression in the opposite direction.
      final texts = await rendered(tester);
      expect(texts.any((t) => t.contains('بدون عمولة')), isTrue,
          reason: '$texts');
      expect(texts.any((t) => t.contains('لا يوجد خصم تلقائي')), isTrue,
          reason: '$texts');
    });
  });

  // ── The yearly discount must come from the prices, not from a constant ──
  //
  // `S.planYearlyHint` was «سنة كاملة بسعر عشرة أشهر», printed under the
  // yearly arm of the period toggle on **every** plan, whatever the server had
  // priced. The live catalogue on 26 Sep 2026 prices all three paid plans at
  // exactly ten months, so the sentence was true on the day it was written and
  // the defect was invisible — the worst kind: a promise that is right today
  // and cannot survive a D1 UPDATE, on the pricing screen, about money.
  group('the yearly term hint', () {
    // A plan priced however this test likes, so the rule is exercised on the
    // shapes that are not true today and would have been wrong on arrival.
    Plan priced(int month, int year) => Plan.fromJson({
          'id': 'x',
          'name_ar': 'x',
          'price_month': month,
          'price_year': year,
        });

    test('a year priced at ten months says ten months', () {
      // The live shape: 1500/mo, 15000/yr. Written as 10 rather than
      // «عشرة» because this is a price tag, not prose: every other amount on
      // this screen is Latin digits, and the count is [prepaidTermsAr]'s to
      // say, not a second hand-written Arabic to keep in step.
      final ten = 'سنة كاملة بسعر ${prepaidTermsAr(10)}';
      expect(yearlyTermHintAr(priced(1500, 15000)), ten);
      // Every other paid tier is the same ratio, so the sentence is not tuned
      // to one plan's numbers.
      expect(yearlyTermHintAr(priced(3000, 30000)), ten);
      expect(yearlyTermHintAr(priced(6000, 60000)), ten);
    });

    test('the hint follows the price instead of the other way round', () {
      // The whole point. An 11-month year is the case the constant got wrong,
      // and it is a perfectly normal price a founder would set.
      expect(yearlyTermHintAr(priced(1500, 16500)),
          'سنة كاملة بسعر ${prepaidTermsAr(11)}');
      // Two plans on one screen, priced differently, described by two
      // sentences — which the single global constant could not do at all.
      expect(yearlyTermHintAr(priced(1500, 15000)),
          contains(prepaidTermsAr(10)));
      expect(yearlyTermHintAr(priced(1500, 18000)),
          contains(prepaidTermsAr(12)));
    });

    test('a year that is not a whole number of months prints nothing', () {
      // 10.5 months. Rounding puts a discount on screen the server never sent.
      expect(yearlyTermHintAr(priced(2000, 21000)), isNull);
      expect(yearlyTermHintAr(priced(1500, 14500)), isNull);
    });

    test('a surcharge is not a discount', () {
      // A year costing MORE than twelve months: 14 months. The months-left
      // arithmetic would be negative, and the naive line would print a saving
      // the contractor does not get.
      expect(yearAsMonths(priced(1000, 14000)), isNull);
      expect(yearlyTermHintAr(priced(1000, 14000)), isNull);
    });

    test('a free plan has no month to be a fraction of', () {
      expect(yearAsMonths(priced(0, 0)), isNull);
      expect(yearlyTermHintAr(priced(0, 0)), isNull);
    });

    test('a plan with no yearly price prints nothing', () {
      expect(yearAsMonths(priced(1500, 0)), isNull);
      expect(yearlyTermHintAr(priced(1500, 0)), isNull);
    });

    test('the count is said the way Arabic counts, not by hand', () {
      // The number inside the sentence is the same [prepaidTermsAr] the term
      // costs elsewhere, so the hint and the term cannot disagree.
      expect(yearlyTermHintAr(priced(1000, 2000)),
          'سنة كاملة بسعر ${prepaidTermsAr(2)}');
      expect(yearlyTermHintAr(priced(1000, 12000)),
          'سنة كاملة بسعر ${prepaidTermsAr(12)}');
      // 11+ reuses the counted singular: «11 شهراً», never «11 أشهر».
      expect(yearlyTermHintAr(priced(1000, 11000)), contains('11 شهراً'));
      expect(yearlyTermHintAr(priced(1000, 11000)), isNot(contains('11 أشهر')));
    });
  });

  // ── The discount sentence, on the real screen, from the real prices ──────
  //
  // The string helper can be right while the card still prints the old
  // constant — that is exactly how the previous cycle's card-guard mutation
  // passed a first pass of unit tests clean. So these drive
  // `SubscriptionScreen` itself, switch the toggle to «سنوي», and read the
  // text the plan cards actually produced.
  group('the yearly discount on the real screen', () {
    // A catalogue carrying one paid plan at whatever year/month ratio the
    // case is about. The live payload's own plan shape, with the two prices
    // swapped, so nothing else in the card has to be re-derived.
    Map<String, dynamic> priced(int month, int year) {
      final json = jsonDecode(_liveSubscription) as Map<String, dynamic>;
      final plans = (json['plans'] as List).cast<Map<String, dynamic>>();
      final pro = plans.firstWhere((p) => p['id'] == 'pro');
      pro['price_month'] = month;
      pro['price_year'] = year;
      return json;
    }

    Future<List<String>> yearlyTexts(
      WidgetTester tester,
      Map<String, dynamic> payload,
    ) async {
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

      final before = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(before.any((t) => t.contains('أعد المحاولة')), isFalse,
          reason: 'the screen never loaded, so nothing below proves anything: '
              '$before');

      // Switch to the yearly arm. The toggle is an unnamed GestureDetector,
      // so it is found by the label it prints rather than by a key.
      await tester.tap(find.text('سنوي').first);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
    }

    testWidgets('the hint under the yearly option follows the price',
        (tester) async {
      // The case the constant got wrong: an 11-month year, on the real card.
      final texts = await yearlyTexts(tester, priced(3000, 33000));
      expect(
        texts.any((t) => t == 'سنة كاملة بسعر ${prepaidTermsAr(11)}'),
        isTrue,
        reason: 'the card did not say the year is 11 months for a plan priced '
            'at 11 months: $texts',
      );
    });

    testWidgets('a year that is not a whole number of months prints no hint',
        (tester) async {
      // 10.5 months. The constant would have claimed ten months here.
      final texts = await yearlyTexts(tester, priced(2000, 21000));
      expect(
        texts.any((t) => t.startsWith('سنة كاملة بسعر')),
        isFalse,
        reason: 'the card invented a whole-month discount for a year that is '
            '10.5 months of the monthly price: $texts',
      );
    });

    testWidgets('the old fixed sentence is gone from the toggle',
        (tester) async {
      // The regression that matters: the constant itself. Even at the live
      // 10-month price the sentence must be *computed*, and a screen that
      // re-added `S.planYearlyHint` would render this twice — once as the
      // constant, once per plan card.
      final texts = await yearlyTexts(tester, priced(3000, 30000));
      final hints = texts.where((t) => t.startsWith('سنة كاملة بسعر')).toList();
      expect(hints, isNotEmpty, reason: 'no hint at all was rendered: $texts');
      // One plan is purchasable in this payload, so one hint — not two, which
      // is what a returned constant under the toggle would have produced.
      expect(hints, hasLength(1), reason: 'the hint is printed twice: $hints');
    });
  });
}
