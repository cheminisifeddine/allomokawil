// Rasterizes the price-mismatch band, because the step-5 rule is that a layout
// claim needs a picture and not an argument.
//
// The band is a visual change to a screen the suite has never photographed in
// this state: `stale_catalogue_shot_test.dart` proves the *other* band, the one
// about a failed re-read, and the two share a widget but not a moment. A
// widget test can find `Key('plan-price-mismatch')` on a band that drew as an
// empty amber bar with no Arabic in it, so the assertion here is scoped to the
// band's own rows and counts **dark** pixels on its wash — the sentence — the
// way the sibling file records.
//
// The frame is taken well past the point where the toast this replaced would
// have expired, so the picture is of the state the fix exists to create: the
// warning still up, next to the price it disputes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

const _out = '/tmp/shots';

/// Rows the amber wash occupies, and the dark pixels inside them.
///
/// Copied from `stale_catalogue_shot_test.dart` rather than shared: the two
/// files each measure their own band, and a shared helper here would be the
/// first thing to drift when a token changes.
Future<(int rows, int dark)> _scanBand(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final stride = (boundary.size.width.round() * 3.0).round();
  final total = (boundary.size.height.round() * 3.0).round();
  var rows = 0;
  var dark = 0;
  for (var y = 0; y < total; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    var wash = 0;
    var darkInRow = 0;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - 0xFD).abs() <= 3 &&
          (g - 0xF3).abs() <= 3 &&
          (b - 0xE3).abs() <= 3) {
        wash++;
      }
      if (r < 0xC0 && g < 0xA0 && b < 0x60) darkInRow++;
    }
    if (wash > stride ~/ 3) {
      rows++;
      dark += darkInRow;
    }
  }
  return (rows, dark);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('the price warning is drawn, in Arabic, after the toast would '
      'have gone', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
          // D1 charges 4500; the catalogue the app quoted from says 3000.
          return http.Response(
              '{"ok":true,"request_id":42,"status":"pending",'
              '"period":"month","months":1,"amount_dzd":4500,'
              '"plan":{"id":"pro"},'
              '"payment":{"methods":[{"id":"baridimob",'
              '"label_ar":"بريدي موب (تحويل)"}],"support_phone":null}}',
              200,
              headers: {'content-type': 'application/json'});
        }
        if (req.url.path.endsWith('/api/mobile/subscription')) {
          return http.Response(
              '{"currency":"DZD","note_ar":"x","auto_renew":false,'
              '"plans":[{"id":"pro","name_ar":"محترف","price_month":3000,'
              '"price_year":30000,"quote_limit":-1,"portfolio_limit":60,'
              '"features":[]}],'
              '"current":{"plan":"free_trial","status":"active"},'
              '"pending_request":{"id":42,"plan":"pro","amount_paid":0,'
              '"payment_method":"baridimob",'
              '"created_at":"2026-10-01 10:00:00"},'
              '"payment":{"methods":[{"id":"baridimob",'
              '"label_ar":"بريدي موب (تحويل)"}],"support_phone":null}}',
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: AuthState(api),
      child: RepaintBoundary(
        key: key,
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
          home: const SubscriptionScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('plan-pro-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('plan-submit')));
    // Past the default 4 s SnackBar duration. The ageing tick keeps a timer
    // alive, so this is a bounded loop rather than `pumpAndSettle`.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.byKey(const Key(planPriceMismatchKey)), findsOneWidget,
        reason: 'the band is not on screen at all');
    expect(find.text(subscriptionAmountMismatchAr(3000, 4500)!), findsOneWidget);

    final (rows, dark) = (await tester.runAsync(() => _scanBand(key)))!;
    // ignore: avoid_print
    print('MISMATCH-BAND rows=$rows dark=$dark');

    // The wash is really on screen, and it has Arabic in it. A band that drew
    // as an empty amber bar still satisfies "found one widget by key".
    expect(rows, greaterThan(20),
        reason: 'the amber wash is not on screen at the size it should be');
    expect(dark, greaterThan(300),
        reason: 'the band drew no readable Arabic: $dark dark pixels on the '
            'wash');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/17_subscription_price_mismatch.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
