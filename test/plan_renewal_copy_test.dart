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
}
