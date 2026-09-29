// Rasterizes the stale-projects band, because the step-5 rule is that a layout
// claim needs a picture and not an argument.
//
// Same path `stale_directory_shot_test.dart`, `stale_inbox_shot_test.dart` and
// `stale_catalogue_shot_test.dart` use and for the same reason: the real
// rasterizer with the real Cairo loaded through `FontLoader`, because a bare
// widget test draws Arabic as tofu and tofu still measures as "there is ink on
// screen". The web+CDP path needs a Chrome build this box does not have, so
// the capture is taken in-test instead of saying so and asserting nothing.
//
// The measurement is scoped to the band's own rows, for the reason
// `stale_inbox_shot_test.dart` records: the list behind it is white, so a
// global ink count passes for any input at all. The band is found by its own
// wash (`accentWash` = FDF3E3) and the assertion counts *dark* pixels inside
// those rows — the Arabic sentence. A capture that drew the card and no text
// at all returns zero, and that is the mistake this shot exists to catch.
//
// The second thing the picture has to prove is specific to this screen: the
// band sits above **project cards**, which are dense with their own ink and
// their own budget text. A global dark-pixel count would pass on the cards
// alone with the band drawing nothing, so the dark pixels are counted *inside
// the wash rows* and the cards are asserted as separate widgets in the frame.
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
import 'package:allomokawil/src/screens/project/projects_screen.dart';

const _out = '/tmp/shots';

/// Rows the amber wash occupies, and the dark pixels inside them.
///
/// The wash is the band's own surface (`AppTheme.accentWash`, FDF3E3) and the
/// sentence is `AppTheme.accentDeep` (9B6415) on it, so the polarity is
/// dark-on-wash and not the reverse.
Future<(int rows, int dark)> _scanBand(GlobalKey key) async {
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
  var bandRows = 0;
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
    if (wash > stride ~/ 3) {
      bandRows++;
      dark += darkInRow;
    }
  }
  return (bandRows, dark);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('a failed refresh is drawn above the projects, in Arabic',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2532);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    String job(String id, String title) => '{"id":"$id","customer_id":391,'
        '"title":"$title","description":"دهان غرفة","category":"painting",'
        '"categories":["painting"],"images":[],"wilaya":"16",'
        '"commune":"باب الزوار","budget_min":20000,"budget_max":40000,'
        '"urgency":"within_week","status":"open","selected_worker_id":null,'
        '"created_at":"2026-09-19 20:39:41","updated_at":"2026-09-19 20:39:41"}';

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
          return http.Response(
              '{"token":"tok","user":{"id":391,"phone":"0773000000",'
              '"email":null,"full_name":"سمية","type":"customer"}}',
              200,
              headers: {'content-type': 'application/json'});
        }
        if (path.contains('/api/mobile/my/projects')) {
          reads++;
          if (reads == 1) {
            return http.Response(
                '[${job("p1", "دهان فيلا")},${job("p2", "سباكة حمام")}]',
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

    final auth = AuthState(api);
    await auth.restore();
    await auth.login(phone: '0773000000', password: 'secret123',
        rememberMe: true);

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
          home: ProjectsScreen(repo: Repository(api)),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.drag(find.text('دهان فيلا'), const Offset(0, 340));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byKey(const Key('stale-projects')), findsOneWidget);

    final (rows, dark) = (await tester.runAsync(() => _scanBand(key)))!;
    // ignore: avoid_print
    print('BAND rows=$rows dark=$dark');

    // The card is on screen and it has text in it. Zero dark pixels on the
    // wash means the band drew as an empty amber bar — which still passes
    // "found one widget by key" and is the mistake the shot exists to catch.
    expect(rows, greaterThan(20),
        reason: 'the amber wash is not on screen at the size it should be');
    expect(dark, greaterThan(300),
        reason: 'the band drew no readable Arabic: $dark dark pixels on '
            'the wash');

    // The band is a header *on* the list, so the user's own projects have to
    // still be in the same frame. This is the claim the whole fix rests on and
    // the one the unfixed screen cannot make at all.
    expect(find.text('دهان فيلا'), findsOneWidget);
    expect(find.text('سباكة حمام'), findsOneWidget);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/19_projects_stale.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
