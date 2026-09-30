// Rasterizes the plan card with a disputed price, because the step-5 rule is
// that a layout claim needs a picture and not an argument.
//
// Two claims in this tick are visual and neither can be made from a widget
// test. The first is that the strike, the red and the amount are all *there* —
// a widget test finds a `Text` with the right style on a card that laid out as
// an overlapping smear. The second is the one that cost the tick a real
// failure: printing «المبلغ المعتمد 4500 دج» under the price made the plan
// card's `Row` **overflow by 53 px**, so a shot is the only honest proof the
// marked column sits inside the card and the plan name beside it is not pushed
// off the screen.
//
// The polarity is the sibling file's: the page behind is white, so a global ink
// count passes for any input at all. Scoped to the card's own rows, counting
// **danger red** on a white wash — a colour nothing else on this screen draws.
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

/// Danger-red pixels inside [target], in the boundary's own pixel space.
///
/// Two things this gets right that the first version did not, both found by
/// measuring rather than by reasoning:
///
///   · **It is scoped to the card's rect.** Scanning the whole page counted
///     568 rows of *some* card and could not say whether the plan card was
///     among them.
///   · **The amber band is not red.** The page holds two warm colours: the
///     band wash `#FDF3E3` with `#9B6415` text, and danger `#C33F39`. A loose
///     "reddish" test counted the band — 313,719 pixels of it — so the
///     predicate has to key on the **r-g delta** that only danger has: 132 for
///     `#C33F39` against 55 for the band's `#9B6415`.
Future<int> _countDanger(GlobalKey key, Rect target) async {
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
  var red = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final i = (y * stride + x) * 4;
      if (i + 3 > bytes.length) continue;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      // 100, chosen from the capture and not from a guess: the histogram
      // inside this rect is 60:135076 (navy text, `#101828`), 120:7052
      // (danger, `#C33F39`), 20:1587 and 40:1330 (antialiased edges). The
      // band is not in this rect at all, but it would sit at 55.
      if (r - g > 100 && r - b > 100) red++;
    }
  }
  return red;
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('the marked price is inside the card, in Arabic, after the toast '
      'would have gone', (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/subscription')) {
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
              '"features":["ترتيب متقدّم في نتائج البحث"]},'
              '{"id":"gold","name_ar":"ذهبي","price_month":6000,'
              '"price_year":60000,"quote_limit":-1,"portfolio_limit":120,'
              '"features":["صدارة النتاجات في ولايتك"]}],'
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

    await tester.scrollUntilVisible(find.byKey(const Key('plan-pro-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('plan-pro-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('plan-submit')));
    // Past the default 4 s SnackBar duration. The ageing tick keeps a timer
    // alive, so this is a bounded loop rather than `pumpAndSettle`.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Scrolled to the card *after* the write settled, and this is not
    // decoration. The first run of this file scanned the page and found
    // **rows=562 red=0**: the band is at the top and the plan card is a lazy
    // list child a long way below it, so the reload scrolled the marked card
    // back out of the built range and there was no red anywhere to count. A
    // picture of the top of the page is not a picture of this change.
    await tester.scrollUntilVisible(
        find.byKey(const Key('plan-price-pro-month')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const Key('plan-price-pro-month')), findsOneWidget);
    // And the card's *top*, not just the price: the price is the trailing
    // column of the first card, and the measurement below takes the band from
    // the price down to the button. On the first run of this rect the top came
    // out at **-205 dp**, i.e. above the viewport, because the scroll stopped
    // as soon as the price itself was on screen. The capture then measured a
    // region of the page that does not exist.
    await tester.ensureVisible(find.byKey(const Key('plan-pro-month')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.byKey(const Key('plan-price-pro-month'))).dy,
        greaterThan(0),
        reason: 'the marked price is above the top of the viewport, so the '
            'capture cannot see the thing it is taking a picture of');

    // The overflow this file exists to disprove, checked as a widget fact
    // first: a `RenderFlex` overflow is reported through the exception
    // handler, and this test file fails on any uncaught one, so reaching the
    // pixel scan at all is already half the proof.
    expect(tester.takeException(), isNull,
        reason: 'the marked price column overflowed its Row');

    // The card's own rect, from the button that is at the bottom of it. Not
    // the whole page: the proof is that the *marked card* is on screen with
    // danger red inside it, and a page-wide count cannot tell which card it
    // was looking at.
    // Read **both ends in global space** and take the span between them. The
    // first version measured the price's offset from the *button* with
    // `localToGlobal`, which points the wrong way — the price is above the
    // button, so the rect came out from -205 dp to 64 dp and counted a region
    // of the page that is not the card at all.
    final priceTop = tester.getTopLeft(
            find.byKey(const Key('plan-price-pro-month')))
        .dy;
    final buttonBottom = tester.getBottomLeft(
            find.byKey(const Key('plan-pro-month')))
        .dy;
    final width = tester.getSize(find.byKey(const Key('plan-pro-month'))).width;
    // The `RepaintBoundary` wraps the whole app, so global y is boundary y.
    final card = Rect.fromLTRB(
        0, priceTop - 48, width, buttonBottom + 8);
    // Both ends of the card must be inside the capture, or the count is
    // measuring a clipped sliver and passing for the whole thing.
    expect(card.top, greaterThanOrEqualTo(0),
        reason: 'the top of the marked card is above the capture');
    expect(card.bottom, lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio),
        reason: 'the bottom of the marked card is below the capture');

    final red = (await tester.runAsync(() => _countDanger(key, card)))!;
    // ignore: avoid_print
    print('DISPUTED-CARD rect=$card h=${card.height.round()} red=$red');

    expect(red, greaterThan(1500),
        reason: 'the mark drew no readable danger red inside the card: '
            '$red red pixels over ${card.height.round()} dp');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/18_plan_disputed_price.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
