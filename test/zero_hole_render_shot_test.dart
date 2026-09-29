// What the two changed sentences actually look like, drawn on a real phone.
//
// The copy fix is one line of text, and a one-line text change has exactly one
// visual risk: a shorter or longer Arabic sentence reflowing into a column
// that was laid out for the old one. A function-level assertion cannot see that
// — only pixels can. So the four states that changed are rendered on the real
// screens at the narrowest layout the app uses, and the double space is checked
// in the rendered text, not in the return value.
//
// Four states, because there are four:
//   * the gallery at its limit, with a limit the server stated (5);
//   * the gallery at its limit, with a limit the server did NOT state (0) —
//     the case that produced «بلغت حد صور خطتك: », a sentence pointing at
//     nothing;
//   * a free contractor who has sent nothing, the largest cohort in the app;
//   * a free contractor who has sent one, on a plan whose limit is 0 — the
//     case that produced «استعملت عرض واحد من  مجانية هذا الشهر».
//
// Same `repaintBoundary` → PNG mechanism `portfolio_allowance_shot_test.dart`
// and `design_shots_test.dart` use, at 392x850 with a 2.75 pixel ratio.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/quote_count_copy.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

String _body(String path, {required int used, required int limit}) {
  if (path.endsWith('/api/login')) {
    return jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'wilaya': '16',
        'created_at': '2026-09-11 20:00:00',
      },
    });
  }
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[
        <String, Object?>{
          'id': 'free_trial',
          'name_ar': 'مجاني',
          'price_month': 0,
          'price_year': 0,
          'quote_limit': 3,
          'portfolio_limit': 5,
          'search_boost': 0,
          'wilaya_span': 1,
          'features': <Object?>['٣ عروض أسعار في الشهر'],
        },
      ],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'quote_limit': limit,
        'portfolio_limit': 5,
        'quotes_used_this_month': used,
      },
      'payment': <String, Object?>{},
    });
  }
  return jsonEncode(<Object>[]);
}

/// Every string the rendered tree actually drew, joined for scanning.
String _drawn(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' ¦ ');

Future<String> _shoot(
  WidgetTester tester,
  String name, {
  required int used,
  required int limit,
}) async {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => http.Response(
          _body(req.url.path, used: used, limit: limit),
          200,
          headers: {'content-type': 'application/json'},
        )),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

  final key = GlobalKey();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(key: key, child: const SubscriptionScreen()),
    ),
  ));
  await _settle(tester);

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.75);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  return path;
}

void main() {
  testWidgets('a new free contractor reads a whole sentence, not a hole',
      (tester) async {
    // The live state of the largest cohort: a fresh registration is on
    // `free_trial` and has sent nothing. Rendered, not asserted on a string.
    final path = await _shoot(tester, '20_usage_zero_sent',
        used: 0, limit: 3);
    final drawn = _drawn(tester);
    expect(tester.takeException(), isNull, reason: 'rendered at 392x850');
    expect(drawn, isNot(contains('  ')),
        reason: 'the screen drew a double space somewhere: $drawn');
    expect(drawn, contains('لم تستعمل أي عرض بعد'),
        reason: 'the empty state must say so: $drawn');
    expect(drawn, contains('اشتراكك مجانية'));
    expect(File(path).existsSync(), isTrue);
  });

  testWidgets('a plan whose limit the server did not state reads whole',
      (tester) async {
    // `quote_limit: 0` — the value `_int()` produces for a field sent as 0,
    // and the only thing a literal `null` escapes (that gets the 3-default).
    // Before the fix this rendered «استعملت عرض واحد من  مجانية هذا الشهر».
    final path =
        await _shoot(tester, '21_usage_zero_limit', used: 1, limit: 0);
    final drawn = _drawn(tester);
    expect(tester.takeException(), isNull);
    expect(drawn, isNot(contains('  ')),
        reason: 'the screen drew a double space: $drawn');
    // Scoped to the usage line itself. A bare `contains('من ')` over the whole
    // screen is a false positive waiting to happen — the plan card's own copy
    // («بدون عمولة ولا نسبة») contains a preposition the test knows nothing
    // about, and an assertion that trips on unrelated copy is an assertion
    // that gets deleted rather than fixed.
    final usage = drawn
        .split('¦')
        .map((s) => s.trim())
        .firstWhere((s) => s.contains('اشتراكك') || s.contains('استعملت'));
    expect(usage, isNot(contains('من ')),
        reason: 'no allowance was stated, so none is claimed: [$usage]');
    expect(drawn, contains('أرسلت عرض واحد هذا الشهر'),
        reason: 'the claim that is still true: $drawn');
    expect(File(path).existsSync(), isTrue);
  });

  testWidgets('the ordinary capped line is unchanged on the screen',
      (tester) async {
    final path =
        await _shoot(tester, '22_usage_one_of_three', used: 1, limit: 3);
    final drawn = _drawn(tester);
    expect(tester.takeException(), isNull);
    expect(drawn, isNot(contains('  ')), reason: drawn);
    expect(drawn, contains('استعملت عرض واحد من 3 عروض مجانية هذا الشهر'),
        reason: 'the common case must read exactly as before: $drawn');
    expect(File(path).existsSync(), isTrue);
  });

  test('the four sentences the change owns, spelled out', () {
    // The copy itself, so a regression names the string it broke.
    expect(cappedQuotesUsageAr(0, 3, isFree: true),
        'اشتراكك مجانية — لم تستعمل أي عرض بعد');
    expect(cappedQuotesUsageAr(1, 0, isFree: true),
        'اشتراكك مجانية — أرسلت عرض واحد هذا الشهر');
    expect(cappedQuotesUsageAr(1, 3, isFree: true),
        'استعملت عرض واحد من 3 عروض مجانية هذا الشهر');
    expect(quotesLeftLineAr('محترف', 1, 0), 'محترف — بقي عرض واحد هذا الشهر');
  });
}
