// Rasterizes the card that is already paid for, because the claim this tick
// ships is two visual things and neither can be proved by a widget test: the
// button is **dead** (a null callback) and the sentence naming the request
// number is on the card with it.
//
// A widget test answers "is the callback null" and nothing about what the man
// sees. The failure this guards against is a card that greys out into something
// unreadable, or a sentence that collides with the button — the same class of
// overflow the disputed-price tick measured at 53 px on this very card, and on
// this very Row.
//
// The polarity, as in the sibling file: the page behind is white, so a global
// count proves nothing. What is measured here is the **disabled grey** of
// `AppTheme.line` (#E8E8EC) against the card's white, which no other state on
// this card paints, plus a whole-card check that the new caption row did not
// push the card past its own edge.
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
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

const _out = '/tmp/shots';

/// Pixels of [target] whose colour is within 6/255 of AppTheme.line (#E8E8EC),
/// the disabled `PrimaryButton` fill — in the boundary's pixel space.
///
/// The tolerance is not decoration: the button is `ElevatedButton` with
/// `elevation: 0` over a white card, and the capture is taken at 3x, so the
/// interior is flat and the tolerance only absorbs antialiasing at the rounded
/// corners and the 1.5 dp edges.
Future<({int grey, int total})> _countDisabled(GlobalKey key, Rect target) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  const ratio = 3.0;
  final stride = (boundary.size.width.round() * ratio).round();
  final total = (boundary.size.height.round() * ratio).round();
  final x0 = (target.left * ratio).round().clamp(0, stride - 1);
  final x1 = (target.right * ratio).round().clamp(0, stride - 1);
  final y0 = (target.top * ratio).round().clamp(0, total - 1);
  final y1 = (target.bottom * ratio).round().clamp(0, total - 1);
  var grey = 0;
  var count = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * stride + x) * 4;
      if (i + 3 > bytes.length) continue;
      count++;
      if ((bytes[i] - 0xE8).abs() <= 6 &&
          (bytes[i + 1] - 0xE8).abs() <= 6 &&
          (bytes[i + 2 - 0] - 0xEC).abs() <= 6) grey++;
    }
  }
  return (grey: grey, total: count);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('the card already paid for is dead, and says why, in Arabic',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const payload = '{"currency":"DZD","note_ar":"x","auto_renew":false,'
        '"plans":[{"id":"basic","name_ar":"أساسي","price_month":1500,'
        '"price_year":15000,"quote_limit":-1,"portfolio_limit":30,'
        '"features":["عارض أسعار غير محدودة"]},'
        '{"id":"pro","name_ar":"محترف","price_month":3000,'
        '"price_year":30000,"quote_limit":-1,"portfolio_limit":60,'
        '"features":["ترتيب متقدّم في نتائج البحث"]},'
        '{"id":"gold","name_ar":"ذهبي","price_month":6000,'
        '"price_year":60000,"quote_limit":-1,"portfolio_limit":120,'
        '"features":["صدارة النتاجات في ولايتك"]}],'
        '"current":{"plan":"free_trial","status":"active"},'
        '"pending_request":{"id":49,"plan":"pro","period":"month",'
        '"amount_paid":0,"payment_method":"baridimob",'
        '"created_at":"2026-10-01 10:00:00"},'
        '"payment":{"methods":[{"id":"baridimob",'
        '"label_ar":"بريدي موب (تحويل)"}],"support_phone":null}}';

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

    // The plan card is a lazy list child, so it has to be brought into
    // existence before any rect below means anything.
    await tester.scrollUntilVisible(find.byKey(const Key('plan-pro-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.ensureVisible(find.byKey(const Key('plan-pro-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(const Key('plan-already-requested')), findsOneWidget,
        reason: 'the card is dead with no sentence saying why');
    expect(find.textContaining('رقم الطلب 49'), findsOneWidget,
        reason: 'the number support will ask for is not on the card');

    // The overflow check, as a widget fact first: a RenderFlex overflow is
    // reported through the exception handler, so reaching the pixel scan is
    // already half the proof. The new caption row sits under a full-width
    // button on a card that once overflowed by 53 px.
    expect(tester.takeException(), isNull,
        reason: 'the new sentence overflowed the card');

    // The rect runs from the top of the card down to the bottom of the
    // **sentence**, not the button. The first version stopped at the button's
    // bottom + 8, which measured the dead fill and quietly left the new
    // caption row outside the picture — the one line this tick added. The
    // bottom is read from the sentence when it exists, so the two can never be
    // measured apart.
    final top = tester.getTopLeft(find.byKey(const Key('plan-pro-month'))).dy;
    final width = tester.getSize(find.byKey(const Key('plan-pro-month'))).width;
    final note = find.byKey(const Key('plan-already-requested'));
    final noteBottom = tester.getBottomLeft(note).dy;
    final buttonBottom =
        tester.getBottomLeft(find.byKey(const Key('plan-pro-month'))).dy;
    expect(noteBottom, greaterThan(buttonBottom),
        reason: 'the sentence is drawn above the button, so this rect is not '
            'measuring the card this tick changed');
    final card = Rect.fromLTRB(0, top - 48, width, noteBottom + 8);
    expect(card.top, greaterThanOrEqualTo(0),
        reason: 'the top of the card is above the capture');
    expect(card.bottom,
        lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio),
        reason: 'the bottom of the card is below the capture');

    final counted =
        await tester.runAsync(() => _countDisabled(key, card));
    final grey = counted!.grey;
    final total = counted.total;
    // ignore: avoid_print
    print('ALREADY-PAID rect=$card h=${card.height.round()} grey=$grey/$total');
    expect(grey, greaterThan(2000),
        reason: 'the button is dead in the widget tree but still painted '
            'amber on screen: only $grey disabled-grey pixels in the card');

    // The counter-probe, and it is what makes the number above mean anything.
    // Grey is a colour this page can also produce for other reasons, so the
    // same measurement is taken on a card whose button is **live** and is
    // required to be near zero. Without it, «there is grey here» could be
    // passing for «the button is disabled» on a card that is fully amber.
    await tester.scrollUntilVisible(find.byKey(const Key('plan-gold-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.ensureVisible(find.byKey(const Key('plan-gold-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    final liveTop = tester.getTopLeft(find.byKey(const Key('plan-gold-month'))).dy;
    final liveBottom =
        tester.getBottomLeft(find.byKey(const Key('plan-gold-month'))).dy;
    final liveWidth = tester.getSize(find.byKey(const Key('plan-gold-month'))).width;
    final live = Rect.fromLTRB(0, liveTop - 48, liveWidth, liveBottom + 8);
    final liveCounted = await tester.runAsync(() => _countDisabled(key, live));
    // ignore: avoid_print
    print('LIVE-CARD rect=$live h=${live.height.round()} '
        'grey=${liveCounted!.grey}/${liveCounted.total}');
    expect(liveCounted!.grey, lessThan(grey ~/ 4),
        reason: 'a live button painted the same grey as the dead one, so the '
            'count above is not measuring the disabled state');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/21_already_requested_card.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
