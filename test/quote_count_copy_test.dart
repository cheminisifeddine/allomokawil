// How many quotes, said the way the number says it.
//
// Found on 26 Sep 2026. The monthly allowance was spelled out by hand in three
// screens with one fixed noun, and — the half that was live, not hypothetical
// — the unlimited branch printed a bare number with no noun at all:
//
//     'عروض أسعار غير محدودة — أرسلت ${used} هذا الشهر'
//
// Every paying contractor is on that branch (basic, pro and gold all ship
// `quote_limit: -1`), so «أرسلت 5 هذا الشهر» was on the revenue screen of every
// subscriber in the country, today, before this test existed.
//
// The counts are driven from the real parsed server payload rather than from
// hand-built ints, because "a paying contractor read a missing noun" is a claim
// about the shapes D1 actually sends.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/quote_count_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// The response production returned from `GET /api/mobile/plans` this cycle:
/// free is capped at 3, and every paid plan is unlimited.
const String _liveCatalogue = '''
{
 "currency": "DZD", "commission_percent": 0, "commission_per_order": 0,
 "plans": [
  {"id":"free_trial","name_ar":"مجاني","price_month":0,"price_year":0,
   "quote_limit":3,"portfolio_limit":5,"search_boost":0,"wilaya_span":1,
   "features":["٣ عروض أسعار في الشهر"]},
  {"id":"basic","name_ar":"أساسي","price_month":1500,"price_year":15000,
   "quote_limit":-1,"portfolio_limit":30,"search_boost":1,"wilaya_span":1,
   "features":["عروض أسعار غير محدودة"]},
  {"id":"pro","name_ar":"محترف","price_month":3000,"price_year":30000,
   "quote_limit":-1,"portfolio_limit":60,"search_boost":3,"wilaya_span":2,
   "features":[]}
 ]
}
''';

SubscriptionStatus _status({
  required String plan,
  required String nameAr,
  required int limit,
  required int used,
}) =>
    SubscriptionStatus.fromJson(<String, dynamic>{
      'plan': plan,
      'name_ar': nameAr,
      'status': 'active',
      'starts_at': null,
      'expires_at': null,
      'quote_limit': limit,
      'portfolio_limit': 5,
      'quotes_used_this_month': used,
      'renews_in_days': null,
    });


/// One `GET /api/mobile/subscription` response, the shape D1 sends.
Map<String, Object?> _subscription({
  required String plan,
  String nameAr = 'محترف',
  required int limit,
  required int used,
}) =>
    <String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'note_ar': 'الاشتراك فقط',
      'plans': jsonDecode(_liveCatalogue)['plans'],
      'current': <String, Object?>{
        'plan': plan,
        'name_ar': nameAr,
        'status': 'active',
        'starts_at': null,
        'expires_at': '2099-06-15 12:00:00',
        'quote_limit': limit,
        'portfolio_limit': 5,
        'quotes_used_this_month': used,
        'renews_in_days': null,
      },
      'pending_request': null,
      'payment': <String, Object?>{
        'methods': <Object?>[],
        'support_phone': null,
      },
    };

void main() {
  group('the four forms', () {
    test('1 / 2 / 3-10 / 11+ each take their own noun', () {
      expect(quotesAr(1), 'عرض واحد');
      expect(quotesAr(2), 'عرضان');
      expect(quotesAr(3), '3 عروض');
      expect(quotesAr(10), '10 عروض');
      expect(quotesAr(11), '11 عرض');
      expect(quotesAr(40), '40 عرض');
    });

    test('the singular is not counted with a 1', () {
      expect(quotesAr(1), isNot(contains('1 ')));
    });

    test('the dual is not counted with a 2 — it already says two', () {
      expect(quotesAr(2), isNot(contains('2 ')));
    });

    test('11+ never takes the «واحد» form with its number', () {
      // The trap: passing «عرض واحد» in as the singular makes 11 read
      // «11 عرض واحد». This is the exact mistake the commune fix hit.
      expect(quotesAr(11), isNot(contains('واحد')));
      expect(quotesAr(40), isNot(contains('واحد')));
    });

    test('a zero is silence, not «0 عروض»', () {
      expect(quotesAr(0), '');
      expect(quotesAr(-1), '');
    });
  });

  group('the unlimited plan names what was sent — the live defect', () {
    test('one quote sent reads «أرسلت عرض واحد»', () {
      final s = _status(plan: 'pro', nameAr: 'محترف', limit: -1, used: 1);
      final line = unlimitedQuotesUsageAr(s.quotesUsedThisMonth);
      expect(line, 'عروض أسعار غير محدودة — أرسلت عرض واحد هذا الشهر');
      // The old line was «… أرسلت 1 هذا الشهر»: a number with no noun.
      expect(line, isNot(contains('أرسلت 1')));
    });

    test('every paid plan in the live catalogue loses its bare number', () {
      final cat = BillingCatalogue.fromJson(jsonDecode(_liveCatalogue)
          as Map<String, dynamic>);
      final paid = cat.plans.where((p) => p.hasUnlimitedQuotes).toList();
      expect(paid.map((p) => p.id), ['basic', 'pro']);
      for (final plan in paid) {
        for (final used in [1, 2, 3, 7, 11]) {
          final line = unlimitedQuotesUsageAr(used);
          expect(line, isNot(contains('$used هذا')),
              reason: '${plan.id} sent $used: $line');
          expect(line, contains(quotesAr(used)), reason: line);
        }
      }
    });

    test('a zero on an unlimited plan is not «0 عروض»', () {
      final s = _status(plan: 'basic', nameAr: 'أساسي', limit: -1, used: 0);
      // Nothing sent yet, so the honest sentence is the limit alone.
      expect(unlimitedQuotesUsageAr(s.quotesUsedThisMonth),
          'عروض أسعار غير محدودة');
    });
  });

  group('the capped plan agrees with itself', () {
    test('the free plan: «من 3 عروض» with both counts counted', () {
      final s = _status(plan: 'free_trial', nameAr: 'مجاني', limit: 3, used: 1);
      expect(cappedQuotesUsageAr(s.quotesUsedThisMonth, s.quoteLimit,
          isFree: s.isFree),
          'استعملت عرض واحد من 3 عروض مجانية هذا الشهر');
    });

    test('a 1-quote trial — the value that broke it — reads correctly', () {
      expect(cappedQuotesUsageAr(1, 1, isFree: true),
          'استعملت عرض واحد من عرض واحد مجانية هذا الشهر');
    });

    test('a 20-quote plan takes the 11+ singular, not the plural', () {
      expect(cappedQuotesUsageAr(7, 20, isFree: false),
          'استعملت 7 عروض من 20 عرض هذا الشهر');
    });

    test('the number after «من» and its noun cannot disagree', () {
      // The old widget carried two fixed nouns one line apart: «عروض» on the
      // free branch and «عرضاً» on the paid one, for the same construction.
      for (final limit in [1, 2, 3, 11, 20]) {
        final line = cappedQuotesUsageAr(0, limit, isFree: false);
        expect(line, contains('من ${quotesAr(limit)}'), reason: line);
      }
    });
  });

  group('the plan row on the home screen', () {
    test('two left of three', () {
      expect(quotesLeftLineAr('مجاني', 2, 3), 'مجاني — بقي عرضان من 3 عروض هذا الشهر');
    });

    test('one left reads the singular', () {
      expect(quotesLeftLineAr('مجاني', 1, 3),
          'مجاني — بقي عرض واحد من 3 عروض هذا الشهر');
    });

    test('a 20-quote plan takes the 11+ form', () {
      expect(quotesLeftLineAr('محترف', 8, 20),
          'محترف — بقي 8 عروض من 20 عرض هذا الشهر');
    });
  });


  group('the sentence on the real screen', () {
    // A string function can be right while the screen still prints the old
    // line. These drive SubscriptionScreen itself and read what build()
    // produced, because "every paying contractor read a bare number" is a
    // claim about a rendered screen and not about a function's return value.

    /// Mounts the screen against one subscription row and returns every
    /// string it rendered.
    Future<List<String>> rendered(
      WidgetTester tester, {
      required String plan,
      required String nameAr,
      required int limit,
      required int used,
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
              jsonEncode(_subscription(
                  plan: plan, nameAr: nameAr, limit: limit, used: used)),
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

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      // Guard the guard: a screen stuck on its error state renders none of
      // this, and a test that "passes" because every `any()` is false is worse
      // than no test at all.
      expect(texts.any((t) => t.contains('أعد المحاولة')), isFalse,
          reason: 'the screen never loaded, so the copy was never rendered: '
              '$texts');
      return texts;
    }

    testWidgets('a paid contractor reads «أرسلت 5 عروض», not a bare number',
        (tester) async {
      final texts = await rendered(tester,
          plan: 'pro', nameAr: 'محترف', limit: -1, used: 5);
      // The live defect, on glass: 5 sent under an unlimited plan.
      expect(texts.any((t) => t.contains('أرسلت 5 هذا')), isFalse,
          reason: 'the bare number reached the screen: $texts');
      expect(texts.any((t) => t.contains('أرسلت 5 عروض')), isTrue,
          reason: 'the counted form is missing from the screen: $texts');
    });

    testWidgets('a paid contractor with one quote reads the singular',
        (tester) async {
      final texts = await rendered(tester,
          plan: 'basic', nameAr: 'أساسي', limit: -1, used: 1);
      expect(texts.any((t) => t.contains('أرسلت عرض واحد')), isTrue,
          reason: '$texts');
    });

    testWidgets('a free contractor reads «من 3 عروض», counted',
        (tester) async {
      final texts = await rendered(tester,
          plan: 'free_trial', nameAr: 'مجاني', limit: 3, used: 1);
      expect(
          texts.any((t) => t.contains('من 3 عروض') && t.contains('مجانية')),
          isTrue,
          reason: texts.toString());
    });
  });

  group('nothing grew a fifth hand-written copy', () {
    test('no screen interpolates a quote count into its own Arabic', () {
      // The shape every other file in this repo drifted into. If a screen
      // starts spelling a quote count again, this fails before a user does.
      final offenders = <String>[];
      for (final f in Directory('lib/src/screens').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        for (final m
            in RegExp(r'\$(?:\{)?(quoteLimit|quotesUsedThisMonth)\}?')
                .allMatches(src)) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'a quote count is being printed by hand here — route it '
              'through quote_count_copy.dart:\n${offenders.join('\n')}');
    });

    test('the dead getter is gone rather than fixed in place', () {
      final src = File('lib/src/models/plan.dart').readAsStringSync();
      expect(src, isNot(contains('String get quoteAllowanceAr')));
    });
  });
}
