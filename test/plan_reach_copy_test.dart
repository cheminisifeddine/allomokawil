// How far a plan's work reaches, in counted Arabic.
//
// Found on 27 Sep 2026, eighth in the "server sends it, model parses it, screen
// drops it" series that `quote_limit`, `portfolio_limit`, the renewal fields,
// `categories`, `worker_avatar_url` and `worker_verification_status` were each
// opened for. `wilaya_span` is parsed on `Plan` and was read by nothing:
// verified by grep across `lib/`, where the name appeared only in the model.
//
// The values under test are the live ones, read from
// `GET /api/mobile/plans` on 27 Sep 2026, not invented here:
//   1 (free) · 1 (basic) · 2 (pro) · 3 (gold)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/plan_reach_copy.dart';
import 'package:allomokawil/src/models/plan.dart';

/// The plan object the screen actually holds, so the line is tested through the
/// model it is read from rather than through a bare integer.
Plan _planWithSpan(Object? span) => Plan.fromJson({
      'id': 'pro',
      'name_ar': 'محترف',
      'price_month': 3000,
      'price_year': 30000,
      'quote_limit': -1,
      'portfolio_limit': 60,
      'search_boost': 3,
      'wilaya_span': span,
      'features': const ['ترتيب متقدّم في نتائج البحث'],
    });

void main() {
  group('wilayaSpanAr', () {
    test('the singular says one in the word, and takes no number', () {
      // «ولاية واحدة» and never «1 ولاية» — the same contract
      // `communeCountAr` has, and the reason 1 branches before the rule.
      expect(wilayaSpanAr(1), 'ولاية واحدة');
    });

    test('the dual is ولايتان and is not counted', () {
      expect(wilayaSpanAr(2), 'ولايتان');
    });

    test('3-10 take the broken plural with the number in front', () {
      // This is the range the live catalogue is one pricing change away from:
      // free and basic are both 1, so 2 is reachable today and 3-10 is the
      // first range a new tier lands in.
      expect(wilayaSpanAr(3), '3 ولايات');
      expect(wilayaSpanAr(7), '7 ولايات');
      expect(wilayaSpanAr(10), '10 ولايات');
    });

    test('11 and up are counted singular, never the plural', () {
      expect(wilayaSpanAr(11), '11 ولاية');
      expect(wilayaSpanAr(58), '58 ولاية');
    });

    test('a span of zero or less is silence, not «0 ولايات»', () {
      // A span of one is already the floor — a plan cannot reach fewer wilayas
      // than the one the contractor lives in — so a stored 0 is a server
      // default, and printing it would tell a paying man his plan reaches
      // nowhere.
      expect(wilayaSpanAr(0), '');
      expect(wilayaSpanAr(-1), '');
    });
  });

  group('planReachLineAr', () {
    test('the live values produce the live sentences', () {
      expect(planReachLineAr(1), 'وصول في ولاية واحدة');
      expect(planReachLineAr(2), 'وصول في ولايتان');
      expect(planReachLineAr(3), 'وصول في 3 ولايات');
    });

    test('a missing span drops the row rather than printing a gap', () {
      // Null, not '' — the card gates on null the way it gates on
      // `yearlyTermHintAr` and `termSavingLabel`, so an absent field can never
      // leave a heading over nothing.
      expect(planReachLineAr(null), isNull);
    });

    test('a server default of 0 drops the row too', () {
      expect(planReachLineAr(0), isNull);
    });
  });

  group('the field is read off the model, not guessed', () {
    test('Plan.fromJson keeps wilaya_span', () {
      expect(_planWithSpan(3).wilayaSpan, 3);
    });

    test('an absent wilaya_span falls back to 1, the floor', () {
      // The parser's own default, not this file's: a plan with no span set
      // reaches the one wilaya the contractor lives in.
      expect(_planWithSpan(null).wilayaSpan, 1);
      expect(planReachLineAr(_planWithSpan(null).wilayaSpan),
          'وصول في ولاية واحدة');
    });
  });

  test('the live catalogue wires every tier to a different sentence', () {
    // The exact payload `GET /api/mobile/plans` answered on 27 Sep 2026. The
    // point of the test is the last two lines: without this row the app cannot
    // tell «محترف» from «مؤسسة» on anything but the price.
    const live = '''
    {"currency":"DZD","commission_percent":0,"commission_per_order":0,
     "note_ar":"","payment_style":"prepaid","auto_renew":false,
     "renew_note_ar":"","current":{"plan":"free_trial","status":"active",
     "quote_limit":3,"portfolio_limit":5,"quotes_used_this_month":0},
     "plans":[
      {"id":"free_trial","name_ar":"مجاني","price_month":0,"price_year":0,
       "quote_limit":3,"portfolio_limit":5,"search_boost":0,"wilaya_span":1,
       "features":["ظهور في نتائج البحث"]},
      {"id":"basic","name_ar":"أساسي","price_month":1500,"price_year":15000,
       "quote_limit":-1,"portfolio_limit":30,"search_boost":1,"wilaya_span":1,
       "features":["عروض أسعار غير محدودة"]},
      {"id":"pro","name_ar":"محترف","price_month":3000,"price_year":30000,
       "quote_limit":-1,"portfolio_limit":60,"search_boost":3,"wilaya_span":2,
       "features":["ترتيب متقدّم في نتائج البحث"]},
      {"id":"gold","name_ar":"مؤسسة","price_month":6000,"price_year":60000,
       "quote_limit":-1,"portfolio_limit":120,"search_boost":5,"wilaya_span":3,
       "features":["صدارة النتائج في ولايتك"]}]}
    ''';
    final cat = BillingCatalogue.fromJson(
        jsonDecode(live) as Map<String, dynamic>);

    final lines = {
      for (final p in cat.plans) p.id: planReachLineAr(p.wilayaSpan),
    };
    expect(lines['free_trial'], 'وصول في ولاية واحدة');
    expect(lines['basic'], 'وصول في ولاية واحدة');
    expect(lines['pro'], 'وصول في ولايتان');
    expect(lines['gold'], 'وصول في 3 ولايات');

    // The two paid tiers are no longer the same sentence. That is the whole
    // fix: «محترف» at 3000 دج and «مؤسسة» at 6000 دج used to differ only by
    // price and a paragraph of prose.
    expect(lines['pro'], isNot(lines['gold']));
  });
}
