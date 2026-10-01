// The expired-plan card, as pixels, with the real Cairo faces.
//
// Found 1 Oct 2026 with 0 unchecked items, by reading the subscription card
// against the account row that renders the same `SubscriptionStatus`. The card
// printed its end-date line under a `paid` guard, so a plan that had already
// lapsed drew a «منتهي» pill and **no date at all**, while `profile_screen.dart`
// printed «انتهت في 2020-01-01» about the same row — two answers to one fact,
// differing by which tab the contractor was standing in.
//
// This is a `shot` file and not an assertion: the point is that the sentence
// *reaches the screen*, which a widget test proves and a human still has to
// look at. The Arabic must be rendered by Cairo, or the capture is a row of
// identical empty boxes — the failure mode the 29 Sep renewal shot recorded.
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

/// The same catalogue the assertions use, with `current` replaced per shot.
const String _shell = '''
{
 "currency": "DZD", "commission_percent": 0, "commission_per_order": 0,
 "note_ar": "الاشتراك فقط: بدون عمولة على الطلبات وبدون أي نسبة من سعر المشروع",
 "payment_style": "prepaid", "auto_renew": false,
 "renew_note_ar": "الدفع مسبق لعدد من الأشهر — لا يوجد خصم تلقائي من البطاقة",
 "plans": [
  {"id":"basic","name_ar":"أساسي","name_fr":"Basique","tagline_ar":"للمقاول الذي يبدأ عمله",
   "price_month":1500,"price_year":15000,"quote_limit":-1,"portfolio_limit":30,
   "search_boost":1,"wilaya_span":1,"features":[]}
 ],
 "current": __CURRENT__,
 "pending_request": null,
 "payment": {"methods":[{"id":"baridimob","label_ar":"بريدي موب (تحويل)","instructions":null}],
   "support_phone": null}
}
''';

String _catalogueWith(String current) =>
    _shell.replaceAll('__CURRENT__', current);

/// A paid plan that ran out on 1 Jan 2020 — the shape `_catalogue` builds.
const String _expired = '''{"plan":"basic","name_ar":"أساسي","status":"active",
   "starts_at":null,"expires_at":"2020-01-01 00:00:00","quote_limit":-1,
   "portfolio_limit":30,"quotes_used_this_month":2,"renews_in_days":null}''';

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
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  expect(icons.existsSync(), isTrue,
      reason: 'MaterialIcons-Regular.otf not found under $root');
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer))))
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
    File('/tmp/shots/expired_card_$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  stdout.writeln('SHOT: /tmp/shots/expired_card_$name.png');
  expect(tester.takeException(), isNull, reason: 'the screen threw');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('a paid plan that ended says the day, in the past tense',
      (tester) async {
    await _shoot(tester, '01_expired', payload: _catalogueWith(_expired));
  });

  testWidgets('the live control, so the shot above is not just the screen',
      (tester) async {
    // The same card with cover that still runs. Without this the first capture
    // proves nothing about *which* line changed — the renewal card and the plan
    // cards are below it and are identical in both shots.
    final live = DateTime.now().add(const Duration(days: 60));
    final payload = _catalogueWith(
      '{"plan":"basic","name_ar":"أساسي","status":"active",'
      '"starts_at":null,'
      '"expires_at":"${live.toUtc().toIso8601String()}",'
      '"quote_limit":-1,"portfolio_limit":30,'
      '"quotes_used_this_month":2,"renews_in_days":null}',
    );
    await _shoot(tester, '02_live', payload: payload);
  });
}
