import 'dart:convert';

import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Billing contract tests.
///
/// The JSON in [_liveCatalogue] is the response production actually returned
/// from `GET https://finili.medsaidkichene.workers.dev/api/mobile/plans`
/// (captured 2026-09-13). Pinning the real payload means a server-side shape
/// change breaks this test instead of silently rendering a price of "0 دج" in
/// the app.
const String _liveCatalogue = '''
{
 "currency": "DZD",
 "commission_percent": 0,
 "commission_per_order": 0,
 "note_ar": "الاشتراك فقط: بدون عمولة على الطلبات وبدون أي نسبة من سعر المشروع",
 "plans": [
  {"id":"free_trial","name_ar":"مجاني","name_fr":"Gratuit","tagline_ar":"جرّب المنصة بدون دفع",
   "price_month":0,"price_year":0,"quote_limit":3,"portfolio_limit":5,"search_boost":0,"wilaya_span":1,
   "features":["٣ عروض أسعار في الشهر","ملف شخصي أساسي"]},
  {"id":"basic","name_ar":"أساسي","name_fr":"Basique","tagline_ar":"للمقاول الذي يبدأ عمله على المنصة",
   "price_month":1500,"price_year":15000,"quote_limit":-1,"portfolio_limit":30,"search_boost":1,"wilaya_span":1,
   "features":["عروض أسعار غير محدودة","شارة «مقاول موثّق» بعد التحقق"]},
  {"id":"pro","name_ar":"محترف","name_fr":"Pro","tagline_ar":"للمقاول الذي يعمل كل يوم",
   "price_month":3000,"price_year":30000,"quote_limit":-1,"portfolio_limit":60,"search_boost":3,"wilaya_span":2,
   "features":["كل مزايا «أساسي»","ترتيب متقدّم في نتائج البحث"]},
  {"id":"gold","name_ar":"مؤسسة","name_fr":"Entreprise","tagline_ar":"للمقاول الذي يدير فريقاً",
   "price_month":6000,"price_year":60000,"quote_limit":-1,"portfolio_limit":120,"search_boost":5,"wilaya_span":3,
   "features":["كل مزايا «محترف»","حسابات متعددة لفريق العمل"]}
 ]
}
''';

Map<String, dynamic> _catalogueJson() => {
      ...jsonDecode(_liveCatalogue) as Map<String, dynamic>,
      'current': {
        'plan': 'free_trial',
        'name_ar': 'مجاني',
        'status': 'active',
        'starts_at': null,
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 1,
        'renews_in_days': null,
      },
      'pending_request': null,
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)', 'instructions': null},
        ],
        'support_phone': null,
      },
    };

void main() {
  group('price catalogue', () {
    test('the live payload parses with real prices and no commission', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      expect(cat.currency, 'DZD');
      expect(cat.plans.length, 4);
      expect(cat.commissionPercent, 0);
      expect(cat.commissionPerOrder, 0);
      expect(cat.noCommission, isTrue);
      // The promise is shown in Arabic, from the server, not from app copy.
      expect(cat.noteAr, contains('بدون عمولة'));
    });

    test('a yearly plan is ten months of a monthly one', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      final pro = cat.planById('pro')!;
      expect(pro.priceFor(BillingPeriod.month), 3000);
      expect(pro.priceFor(BillingPeriod.year), 30000);
      expect(pro.savingFor(BillingPeriod.year), 6000);
      expect(pro.savingFor(BillingPeriod.month), 0);
    });

    test('the free tier is free and capped; paid tiers are unlimited', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      final free = cat.planById('free_trial')!;
      expect(free.isFree, isTrue);
      expect(free.hasUnlimitedQuotes, isFalse);
      expect(free.quoteLimit, 3);
      expect(cat.planById('basic')!.hasUnlimitedQuotes, isTrue);
      expect(cat.planById('basic')!.isFree, isFalse);
    });

    test('the catalogue never offers the free plan for purchase', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      expect(cat.purchasable.map((p) => p.id), ['basic', 'pro', 'gold']);
    });

    test('price labels read as money, and free reads as free', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      final free = cat.planById('free_trial')!;
      final basic = cat.planById('basic')!;
      expect(cat.priceLabel(free, BillingPeriod.month), contains('مجان'));
      expect(cat.priceLabel(basic, BillingPeriod.month), contains('دج'));
      expect(cat.priceLabel(basic, BillingPeriod.year), contains('دج'));
    });
  });

  group('entitlement', () {
    test('a free contractor with 1 of 3 quotes used has 2 left', () {
      final cat = BillingCatalogue.fromJson(_catalogueJson());
      expect(cat.current.quotesUsedThisMonth, 1);
      expect(cat.current.quoteLimit, 3);
      expect(cat.current.quotesLeft, 2);
      expect(cat.current.isQuotaSpent, isFalse);
      expect(cat.current.isFree, isTrue);
    });

    test('3 of 3 quotes used spends the quota', () {
      final json = _catalogueJson();
      (json['current'] as Map)['quotes_used_this_month'] = 3;
      final cat = BillingCatalogue.fromJson(json);
      expect(cat.current.quotesLeft, 0);
      expect(cat.current.isQuotaSpent, isTrue);
    });

    test('an unlimited plan is never spent, whatever the count', () {
      final json = _catalogueJson();
      (json['current'] as Map)
        ..['plan'] = 'pro'
        ..['name_ar'] = 'محترف'
        ..['quote_limit'] = -1
        ..['quotes_used_this_month'] = 97;
      final cat = BillingCatalogue.fromJson(json);
      expect(cat.current.hasUnlimitedQuotes, isTrue);
      expect(cat.current.quotesLeft, isNull);
      expect(cat.current.isQuotaSpent, isFalse);
      expect(cat.current.isFree, isFalse);
    });

    test('an expired subscription is recognised without a cron', () {
      final json = _catalogueJson();
      (json['current'] as Map)
        ..['plan'] = 'basic'
        ..['expires_at'] = '2020-01-01 00:00:00';
      final cat = BillingCatalogue.fromJson(json);
      expect(cat.current.isExpired, isTrue);
    });
  });

  group('paywall copy', () {
    test('a 402 shows the server sentence when it has one', () {
      final e = ApiException('وصلت إلى حد 3 عروض في الشهر على خطة «مجاني».',
          statusCode: 402);
      final copy = errorCopy(e);
      expect(copy, contains('3 عروض'));
    });

    test('a 402 without a body still lands on the upgrade path', () {
      final copy = errorCopy(ApiException('', statusCode: 402));
      expect(copy, isNotEmpty);
      expect(copy, contains('اشتراكي'));
    });
  });
}
