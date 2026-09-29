// Rasterizes the stale-market band, because the step-5 rule is that a layout
// claim needs a picture and not an argument.
//
// Same path every other member of the failed-read family uses
// (`stale_home_strip_shot_test.dart`, `stale_projects_shot_test.dart`,
// `stale_directory_shot_test.dart`, `stale_inbox_shot_test.dart`,
// `stale_catalogue_shot_test.dart`, `stale_notifications_shot_test.dart`) and
// for the same reason: the real rasterizer with the real Cairo loaded through
// `FontLoader`, because a bare widget test draws Arabic as tofu and tofu still
// measures as "there is ink on screen". The web+CDP path needs a Chrome build
// this box does not have (`which chromium` -> nothing), so the capture is taken
// in-test instead of saying so and asserting nothing.
//
// **The measurement here is a y-ordering claim, like the notification centre's
// and unlike the five before it.** The band sits *above* a list of open
// projects, and those rows carry their own ink — a title, a specialty, a
// budget, a status pill. So a global ink count proves nothing: "there are dark
// pixels below the band" is true whether the band heads the list or replaced
// it. The only assertion that separates those two cases is that the wash ends
// *above* the first row:
//
//   * the wash is a band, not a sliver;
//   * dark ink sits inside the wash — the Arabic sentence, and a band that
//     drew as an empty amber bar passes every `find.byKey`;
//   * the first project row starts below the last wash row, so the band is a
//     header and not a page.
library;

import 'dart:convert';
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

const _out = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')..addFont(Future.value(reg))).load();
  await (FontLoader('Cairo')..addFont(Future.value(bold))).load();
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

http.Response _boom() => http.Response('<html>500</html>', 500,
    headers: const {'content-type': 'text/html'});

Map<String, Object?> _user() => {
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'أعمال جافة',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'باب الوادي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

/// The band the amber wash occupies, and the ink on this screen.
///
/// Four numbers, each a different claim:
///
///   * `washFirst`/`washLast` — the band's own rows, found by their wash
///     (`accentWash` = FDF3E3).
///   * `darkInBand` — **dark pixels inside those rows**, the Arabic sentence.
///     Counting globally would be a mistake here: the contractor header and
///     the navy section title are dark-on-white and sit *above* the band, so a
///     global first-ink lands on the header and says nothing about the band.
///   * `inkLast` — the last dark row in the frame, which is the market's own
///     text *under* the band.
///
/// **[top, bottom] is the band's own box in the frame, and it is a parameter
/// for a reason that cost this file two runs.** The other six shots scan the
/// whole frame for the wash and take the first and last rows that match, which
/// is exact on their screens because the band is the *only* `accentWash`
/// widget in the picture. It is not exact here: this screen wears the same
/// wash in three other places — the **selected filter chip**
/// (`worker_home_screen.dart:1697`) and the **status pill on every project
/// card** (`project_card.dart:92`). A whole-frame scan therefore reported
/// `wash=216..2414` and a `darkInBand` of 45123, which is the band plus two
/// chips plus a pill, and `inkLast` landed *inside* the band so the
/// "something is drawn below the band" ordering assertion failed at 2391 < 2414.
///
/// The lesson is the transferable one and it generalises past this file: on a
/// screen that reuses the stale tone for ordinary UI, a **whole-frame colour
/// scan cannot measure the band at all**, no matter how the thresholds are
/// tuned. The band has to be located by its own geometry — the render box of
/// the widget under test — and the pixels counted inside it.
Future<({int washFirst, int washLast, int darkInBand, int inkLast})>
    _scanBand(GlobalKey key, {required int top, required int bottom}) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final stride = (boundary.size.width * 3.0).round();
  final total = (boundary.size.height * 3.0).round();
  var washFirst = -1, washLast = -1, darkInBand = 0, inkLast = -1;
  for (var y = 0; y < total; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    var wash = 0;
    var dark = 0;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - 0xFD).abs() <= 3 &&
          (g - 0xF3).abs() <= 3 &&
          (b - 0xE3).abs() <= 3) {
        wash++;
      }
      if (r < 0xC0 && g < 0xA0 && b < 0x60) dark++;
    }
    if (dark > 0) inkLast = y;
    // Scoped to the band's own box. `inkLast` deliberately is **not**: it is
    // the claim about what is drawn below the band, so it has to see the whole
    // frame.
    if (wash > stride ~/ 3 && y >= top && y <= bottom) {
      if (washFirst < 0) washFirst = y;
      washLast = y;
      darkInBand += dark;
    }
  }
  return (
    washFirst: washFirst,
    washLast: washLast,
    darkInBand: darkInBand,
    inkLast: inkLast
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('the market band is a header ABOVE the projects, in Arabic',
      (tester) async {
    // 1176x2550 @3.0, the real device geometry the pull-to-refresh sibling
    // uses — and it is not a taste choice. This screen stacks a branded
    // header, a filter strip, a search field and a section title above the
    // surface being photographed, so a short window pushes the band off the
    // top entirely and the y-ordering assertion below measures nothing.
    tester.view.physicalSize = const Size(1176, 2550);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object?>{'token': 'tok', 'user': _user()});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.endsWith('/api/mobile/my/profile')) {
          return _json(<String, Object?>{'worker': <String, Object?>{}});
        }
        if (p.endsWith('/api/mobile/my/subscription')) {
          return _json(<String, Object?>{
            'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
            'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
            'payment': <String, Object?>{'methods': <Object?>[]},
          });
        }
        if (p == '/api/mobile/projects') {
          reads++;
          if (reads == 1) {
            return _json(<Object>[
              _project('p1', 'دهان شقة 3 غرف'),
              _project('p2', 'سباكة حمام جديد'),
              _project('p3', 'بناء جدار حامل'),
            ]);
          }
          return _boom();
        }
        return _json(<Object>[]);
      }),
    );

    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    // A frozen clock, so the band has an **age** to draw. Without it this shot
    // would capture the band a contractor sees for the first minute after a
    // failed pull, and the second sentence this tick added would never appear
    // in a picture — the same "the test passes but never looked at it" hole
    // the ink scan below exists to close, one level up.
    var now = DateTime(2026, 9, 29, 14, 0);

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
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
          // The Scaffold is not optional here: `MarketplaceView` is a tab
          // *body* and the shell supplies it. Without it the search field
          // throws «No Material widget found» and the capture is an exception.
          home: Scaffold(
              body: MarketplaceView(
                  repo: Repository(api), clock: () => now)),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    // The market is a lazy sliver under the header, so it is scrolled into
    // the built range rather than assumed to be there.
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -900));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
        reason: 'the first read worked, so the market is on screen');
    expect(find.byKey(const Key('stale-market')), findsNothing);

    // Pull to the top, then pull to refresh: the gesture that failed.
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 2400));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.fling(
        find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, -900));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('stale-market')), findsOneWidget);
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
        reason: 'the rows must still be there under the band');

    // Age the read by 40 minutes and let the screen's own one-minute tick fire.
    // This is the frame the shot is *for*: before this tick the band admitted
    // the rows were the last ones read but not how stale they were, which is
    // the only question a contractor about to bid on them is asking.
    now = now.add(const Duration(minutes: 40));
    await tester.pump(const Duration(minutes: 1, milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    final aged = tester.widget<Text>(find.byKey(const Key('stale-market-line')));
    // ignore: avoid_print
    print('MARKET AGED line="${aged.data?.replaceAll('\n', ' | ')}"');
    expect(aged.data, contains('قبل 40 دقيقة'),
        reason: 'the captured frame must be the one that carries an age');
    // Still a header, still not a page over the list: the extra sentence must
    // not have pushed the band on top of the rows it annotates.
    expect(
        tester.getTopLeft(find.byKey(const Key('stale-market'))).dy +
            tester.getSize(find.byKey(const Key('stale-market'))).height,
        lessThanOrEqualTo(tester.getTopLeft(find.text('دهان شقة 3 غرف')).dy),
        reason: 'a second line must not make the band overlap the first row');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/22_worker_market_stale.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // The band's own box, in the same frame the raster is taken in. Taken from
    // the widget rather than guessed from a threshold, which is the whole point
    // of the parameter above.
    final bandBox = tester.getRect(find.byKey(const Key('stale-market')));
    final frameBox = tester.getRect(find.byType(MaterialApp));
    final band = (await tester.runAsync(() => _scanBand(key,
        top: ((bandBox.top - frameBox.top) * 3.0 - 6).round(),
        bottom: ((bandBox.bottom - frameBox.top) * 3.0 + 6).round())))!;
    // ignore: avoid_print
    print('MARKET BAND box=${bandBox.top.toStringAsFixed(0)}..'
        '${bandBox.bottom.toStringAsFixed(0)} logical');
    // ignore: avoid_print
    print('MARKET BAND wash=${band.washFirst}..${band.washLast} '
        'darkInBand=${band.darkInBand} inkLast=${band.inkLast}');

    expect(band.washFirst, greaterThanOrEqualTo(0),
        reason: 'the amber wash is nowhere on screen');
    expect(band.washLast - band.washFirst, greaterThan(20),
        reason: 'the wash is a sliver, not a band: '
            '${band.washFirst}..${band.washLast}');
    // The band drew no readable Arabic. Zero ink inside the wash is the empty
    // amber bar that still passes "found one widget by key" — the exact
    // mistake this shot exists to catch.
    expect(band.darkInBand, greaterThan(200),
        reason: 'the band drew no readable Arabic: ${band.darkInBand} dark '
            'pixels on the wash');
    // **The claim this picture has to make.** The rows carry their own ink, so
    // a count cannot separate "a header on the list" from "a banner that ate
    // the list". Only an ordering can.
    expect(band.inkLast, greaterThan(band.washLast),
        reason: 'nothing is drawn below the band, so it replaced the market '
            'instead of heading it');
    final topRow = tester.getTopLeft(find.text('دهان شقة 3 غرف')).dy;
    final bandTop = tester.getTopLeft(find.byKey(const Key('stale-market'))).dy;
    expect(bandTop, lessThan(topRow),
        reason: 'the band must be a header: above the rows, not over them');
    expect(
        bandTop +
            tester.getSize(find.byKey(const Key('stale-market'))).height,
        lessThanOrEqualTo(topRow),
        reason: 'the band must not overlap the first row it annotates');

  });
}
