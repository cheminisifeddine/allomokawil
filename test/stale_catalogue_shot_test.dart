// Rasterizes the stale-catalogue banner, because the step-5 rule is that a
// layout claim needs a picture and not an argument.
//
// The web+CDP path in the protocol needs Chrome and a JDK; the Flutter SDK is
// restored but `/usr/lib/jvm` and the Android SDK are not on this box, so the
// bundle cannot be built here. This goes through the same
// `tester.runAsync` + `toImage` capture `design_shots_test.dart` and
// `subscription_ack_shot_test.dart` use, which is the real rasterizer with the
// real Cairo loaded through `FontLoader` — a bare widget test draws Arabic as
// tofu, and tofu still measures as "there is ink on screen".
//
// The measurement is scoped to the banner's own rows rather than the whole
// capture, for the reason `subscription_ack_shot_test.dart` records: the page
// behind is white, so a global ink count passes for any input at all. The
// banner is found by its own wash (`accentWash` = FDF3E3) and the assertion
// counts *dark* pixels inside those rows — the Arabic sentence. A capture that
// drew the card and no text at all returns zero.
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
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

const _out = '/tmp/shots';

/// Rows the amber wash occupies, and the dark pixels inside them.
///
/// The wash is the banner's own surface (`AppTheme.accentWash`, FDF3E3), and
/// the sentence is `AppTheme.accentDeep` (9B6415) on it. So: rows that are
/// mostly wash carry the banner, and the dark pixels on those rows are its
/// text. Counting light pixels here would count the page, which is why the
/// polarity is dark-on-wash and not the reverse.
Future<(int rows, int dark)> _scanBanner(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final width = boundary.size.width.round();
  final height = boundary.size.height.round();
  const scale = 3.0;
  final stride = (width * scale).round();
  final total = (height * scale).round();
  var bannerRows = 0;
  var dark = 0;
  for (var y = 0; y < total; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    var wash = 0;
    var darkInRow = 0;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - 0xFD).abs() <= 3 && (g - 0xF3).abs() <= 3 && (b - 0xE3).abs() <= 3) {
        wash++;
      }
      if (r < 0xC0 && g < 0xA0 && b < 0x60) darkInRow++;
    }
    // A row the banner actually occupies: most of its width is the wash.
    if (wash > stride ~/ 3) {
      bannerRows++;
      dark += darkInRow;
    }
  }
  return (bannerRows, dark);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('a failed refresh is drawn above the numbers, in Arabic',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2532);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/api/mobile/subscription')) {
          reads++;
          if (reads == 1) {
            return http.Response(
                '{"currency":"DZD","note_ar":"x","auto_renew":false,'
                '"plans":[],"current":{"plan":"free_trial","status":"active"}}',
                200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('', 503,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }),
      timeout: const Duration(milliseconds: 200),
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
    await tester.tap(find.byTooltip(S.planRetry));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byKey(const Key('stale-catalogue')), findsOneWidget);

    final (rows, dark) = (await tester.runAsync(() => _scanBanner(key)))!;
    // ignore: avoid_print
    print('BANNER rows=$rows dark=$dark');

    // The card is on screen and it has text in it. Zero dark pixels on the
    // wash means the banner drew as an empty amber bar — which still passes
    // "found one widget by key" and is the mistake the shot exists to catch.
    expect(rows, greaterThan(20),
        reason: 'the amber wash is not on screen at the size it should be');
    expect(dark, greaterThan(300),
        reason: 'the banner drew no readable Arabic: $dark dark pixels on '
            'the wash');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/16_subscription_stale.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
