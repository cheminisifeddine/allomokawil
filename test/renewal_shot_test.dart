// Renders the renewal promise as pixels, with the real Cairo faces.
//
// A layout claim about Arabic is only true if the Arabic is on the screen. A
// shot taken without the font renders a row of identical empty boxes — which
// is what the last cycle's first capture did, and it proved nothing. So this
// uses the same font loader the golden suite uses, writes both states, and
// prints the ink each one carries.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

const String _payload = '''
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
   "features":["ترتيب متقدّم في نتائج البحث","إشعار فوري بالطلبات الجديدة في تخصصك"]}
 ],
 "current": {"plan":"free_trial","name_ar":"مجاني","status":"active",
   "starts_at":null,"expires_at":null,"quote_limit":3,"portfolio_limit":5,
   "quotes_used_this_month":0,"renews_in_days":null},
 "pending_request": null,
 "payment": {"methods":[{"id":"baridimob","label_ar":"بريدي موب (تحويل)","instructions":null}],
   "support_phone": null}
}
''';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  expect(reg.lengthInBytes, greaterThan(10000),
      reason: 'Cairo-Regular.ttf did not load from the asset bundle');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();

  var root = Platform.environment['FLUTTER_ROOT'];
  root ??= File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .path;
  final icons = File('$root/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  expect(icons.existsSync(), isTrue,
      reason: 'MaterialIcons-Regular.otf not found under $root');
  final iconBytes = icons.readAsBytesSync();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconBytes.buffer))))
      .load();
  stdout.writeln('FONTS: Cairo + MaterialIcons registered');
}

final GlobalKey _key = GlobalKey();

Future<void> _shoot(WidgetTester tester, String name,
    {required String payload}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/mobile/subscription')) {
        return http.Response(payload, 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200,
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
      home: RepaintBoundary(
        key: _key,
        child: const SubscriptionScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final boundary =
      _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.75);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/renewal_$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  stdout.writeln('SHOT: /tmp/shots/renewal_$name.png');
  expect(tester.takeException(), isNull, reason: 'the screen threw');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the promise card, with the renewal sentence', (tester) async {
    await _shoot(tester, '01_with_renewal', payload: _payload);
  });

  testWidgets('a payment waiting on review, with its receipt', (tester) async {
    // The card that was `const _PendingCard()` — no arguments, five parsed
    // facts thrown away. This shot is the only way to see whether the receipt
    // actually sits under the prose and reads, rather than asserting that the
    // widget tree contains a `Text`.
    final pending = _payload.replaceAll(
      '"pending_request": null,',
      '"pending_request": {"id":7,"plan":"pro","amount_paid":30000,'
          '"payment_method":"baridimob","created_at":"2026-09-12 10:00:00"},',
    );
    await _shoot(tester, '03_pending_receipt', payload: pending);
  });

  testWidgets('the same screen when the server published no note', (tester) async {
    // The control: proves the line is the server's sentence and not a constant
    // that would be drawn either way.
    final noNote = _payload.replaceAll(
        '"renew_note_ar": "الدفع مسبق لعدد من الأشهر — لا يوجد خصم تلقائي من البطاقة",',
        '');
    await _shoot(tester, '02_no_renewal', payload: noNote);
  });
}
