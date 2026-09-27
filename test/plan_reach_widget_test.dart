// Does the reach line actually reach the pricing card?
//
// The unit tests in `plan_reach_copy_test.dart` prove the Arabic. This one
// proves the screen: `wilaya_span` was parsed, had a getter nobody called, and
// a test that only exercised the getter would have passed on a build where the
// line was never drawn. A model field can be parsed and never shown — that is
// the whole defect this cycle was opened for, so the assertion has to be
// against rendered pixels, not against a return value.
//
// The payload is the live `GET /api/mobile/subscription` catalogue read on
// 27 Sep 2026, so the spans under test are 1 / 1 / 2 / 3 and not invented.
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
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

const String _liveSubscription = '''
{
 "currency":"DZD","commission_percent":0,"commission_per_order":0,
 "note_ar":"الاشتراك فقط: بدون عمولة على الطلبات","payment_style":"prepaid",
 "auto_renew":false,"renew_note_ar":"الدفع مسبق لعدد من الأشهر",
 "plans":[
  {"id":"free_trial","name_ar":"مجاني","tagline_ar":"جرّب المنصة بدون دفع",
   "price_month":0,"price_year":0,"quote_limit":3,"portfolio_limit":5,
   "search_boost":0,"wilaya_span":1,"features":["ظهور في نتائج البحث"]},
  {"id":"pro","name_ar":"محترف","tagline_ar":"للمقاول الذي يعمل كل يوم",
   "price_month":3000,"price_year":30000,"quote_limit":-1,"portfolio_limit":60,
   "search_boost":3,"wilaya_span":2,"features":["ترتيب متقدّم في نتائج البحث"]},
  {"id":"gold","name_ar":"مؤسسة","tagline_ar":"للفرق التي تنمو",
   "price_month":6000,"price_year":60000,"quote_limit":-1,"portfolio_limit":120,
   "search_boost":5,"wilaya_span":3,"features":["صدارة النتائج في ولايتك"]}],
 "current":{"plan":"free_trial","name_ar":"مجاني","status":"active",
   "starts_at":null,"expires_at":null,"quote_limit":3,"portfolio_limit":5,
   "quotes_used_this_month":0,"renews_in_days":null},
 "pending_request":null,
 "payment":{"methods":[{"id":"baridimob","label_ar":"بريدي موب (تحويل)",
   "instructions":null}],"support_phone":null}
}
''';

Future<List<String>> _rendered(WidgetTester tester,
    {Map<String, dynamic>? payload}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(
          jsonEncode(payload ?? jsonDecode(_liveSubscription)),
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
  // Guard the guard: a test that "passes" because every matcher is false on an
  // error screen is worse than no test.
  expect(texts.any((t) => t.contains('أعد المحاولة')), isFalse,
      reason: 'the screen never loaded, so nothing was rendered: $texts');
  return texts;
}

void main() {
  testWidgets('«محترف» shows the span the server priced it at',
      (tester) async {
    final texts = await _rendered(tester);
    expect(texts, contains('وصول في ولايتان'),
        reason: 'the parser kept wilaya_span=2 and the card dropped it: '
            '$texts');
  });

  testWidgets('«مؤسسة» shows three, so the two paid tiers stop reading alike',
      (tester) async {
    // The fix, stated as a test: before this line, a contractor comparing
    // «محترف» at 3000 دج with «مؤسسة» at 6000 دج had the price and a paragraph
    // of prose and nothing else. `gold`'s own feature says «صدارة النتائج في
    // ولايتك» — one wilaya — while the server prices three.
    final texts = await _rendered(tester);
    expect(texts, contains('وصول في 3 ولايات'), reason: '$texts');
  });

  testWidgets('a plan whose span the server sent as 0 shows no reach line',
      (tester) async {
    // A stored 0 is a server default rather than a claim, and printing it
    // would tell a paying man his plan reaches nowhere — the same contract
    // `photosAr` and `quotesAr` already have.
    final payload = jsonDecode(_liveSubscription) as Map<String, dynamic>;
    for (final p in (payload['plans'] as List)) {
      (p as Map)['wilaya_span'] = 0;
    }
    final texts = await _rendered(tester, payload: payload);
    expect(texts.any((t) => t.contains('وصول في')), isFalse,
        reason: 'a span of 0 must not be printed as a reach: $texts');
  });

  testWidgets('an absent span falls back to the floor, not to a blank line',
      (tester) async {
    // `Plan.fromJson` defaults a missing `wilaya_span` to 1, and one is the
    // honest floor: a plan cannot reach fewer wilayas than the one the
    // contractor lives in. So a server that stops sending the field degrades
    // to «وصول في ولاية واحدة» rather than to a gap or to a number
    // nobody sent. The first version of this test asserted the opposite and
    // failed, which is what pinned the parser's real behaviour.
    final payload = jsonDecode(_liveSubscription) as Map<String, dynamic>;
    for (final p in (payload['plans'] as List)) {
      (p as Map).remove('wilaya_span');
    }
    final texts = await _rendered(tester, payload: payload);
    expect(texts, contains('وصول في ولاية واحدة'), reason: '$texts');
  });
}
