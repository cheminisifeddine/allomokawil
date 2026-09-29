// Rasterizes the stale-notification band, because the step-5 rule is that a
// layout claim needs a picture and not an argument.
//
// Same path every other member of the failed-read family uses
// (`stale_home_strip_shot_test.dart`, `stale_projects_shot_test.dart`,
// `stale_directory_shot_test.dart`, `stale_inbox_shot_test.dart`,
// `stale_catalogue_shot_test.dart`) and for the same reason: the real
// rasterizer with the real Cairo loaded through `FontLoader`, because a bare
// widget test draws Arabic as tofu and tofu still measures as "there is ink on
// screen". The web+CDP path needs a Chrome build this box does not have
// (`which chromium` -> nothing, no `build_web.sh` either), so the capture is
// taken in-test instead of saying so and asserting nothing.
//
// **The measurement this screen makes is the inverse of the ones before it,
// and the difference is the point.** The five shots that came before it are
// all the same claim: the band replaced a blank area, so a global ink count is
// useless and the dark pixels are counted *inside the wash rows*. This screen
// has rows **underneath** the band that carry their own ink — a title, a body,
// a relative timestamp — so "there are dark pixels below the band" proves
// nothing at all, and the assertion has to be a **y-ordering** claim rather
// than a counting one:
///
///   * the wash starts above every notification row, and
///   * the notification text starts *below* every wash row.
///
/// That is the only assertion that distinguishes "a header on the list" from
// "a banner that replaced the list", which is precisely the mistake the fix is
// guarding against. A count cannot separate the two cases; an ordering can.
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
import 'package:allomokawil/src/data/notification_count_trust.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

const _out = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')..addFont(Future.value(reg))).load();
  await (FontLoader('Cairo')..addFont(Future.value(bold))).load();
}

/// The band the amber wash occupies, and where the ink on this screen sits.
///
/// Four numbers, and each is a different claim:
///
///   * `washFirst`/`washLast` — the band's own rows, found by their wash
///     (`accentWash` = FDF3E3). This is how the other five shots locate it.
///   * `darkInBand` — **dark pixels inside those rows**, which is the Arabic
///     sentence. Counting it globally would be a mistake on this screen and
///     not on the others: the app-bar title is dark-on-white and sits *above*
///     the band, so a global first-ink lands on the title and says nothing
///     about the band at all. A band that drew as an empty amber bar returns
///     zero here, which is the picture this file exists to catch.
///   * `inkLast` — the last dark row in the frame, which is the notification
///     text **under** the band. Its being past `washLast` is the only thing
///     that proves the band is a header rather than a replacement.
Future<({int washFirst, int washLast, int darkInBand, int inkLast})> _scanBand(
    GlobalKey key) async {
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
      if ((r - 0xFD).abs() <= 3 && (g - 0xF3).abs() <= 3 && (b - 0xE3).abs() <= 3) {
        wash++;
      }
      if (r < 0xC0 && g < 0xA0 && b < 0x60) dark++;
    }
    if (dark > 0) inkLast = y;
    if (wash > stride ~/ 3) {
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

Map<String, Object?> _sessionUser() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

Map<String, Object?> _row(int id, String title, String body, int hoursAgo) {
  final t = DateTime.now().toUtc().subtract(Duration(hours: hoursAgo));
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'id': id,
    'type': 'new_quote',
    'title': title,
    'body': body,
    'link': null,
    'is_read': 0,
    'created_at':
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
  };
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('the stale band is a header ABOVE the rows, drawn in Arabic',
      (tester) async {
    // 400x1200 at 1.0: this screen has a header and a list and nothing else,
    // so the band and two rows fit without scrolling — which is what makes
    // the y-ordering assertion below meaningful. The five shots before it
    // needed 1080x2280 because those screens stack a hero, a search row and a
    // category grid above the surface being photographed; there is nothing
    // here to push the band off the top.
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_sessionUser()),
    });

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/notifications') {
          reads++;
          if (reads == 1) {
            return _json(<Object?>[
              _row(5, 'عرض على مشروع دهان', 'دهان شقة 3 غرف', 1),
              _row(6, 'قبول عرض السباكة', 'سباكة حمام', 3),
            ]);
          }
          return http.Response('', 503,
              headers: const {'content-type': 'application/json'});
        }
        return _json(<String, Object?>{});
      }),
    );

    final auth = AuthState(api);
    await auth.restore();
    final trust = NotificationCountTrust();

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      trust: trust,
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
          home: NotificationsScreen(
            repo: Repository(api),
            trust: trust,
            clock: () => DateTime.now(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Anchored on the row's own key, not on its title: a `new_quote` row
    // carries the type's Arabic label *and* the title the backend stored, and
    // when the two are the same string there are two widgets with that text —
    // a duplicate found by a text finder, not a duplicated row.
    expect(find.byKey(const Key('notification-5')), findsOneWidget,
        reason: 'the first read worked, so the rows are on screen');

    await tester.fling(
        find.byType(ListView), const Offset(0, 320), 1200);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('stale-notifications')), findsOneWidget);
    expect(trust.unconfirmed, isTrue,
        reason: 'the same read feeds the header pip, so the pip withdrew');

    final band = (await tester.runAsync(() => _scanBand(key)))!;
    // ignore: avoid_print
    print('BAND wash=${band.washFirst}..${band.washLast} '
        'darkInBand=${band.darkInBand} inkLast=${band.inkLast}');

    expect(band.washFirst, greaterThanOrEqualTo(0),
        reason: 'the amber wash is nowhere on screen');
    expect(band.washLast - band.washFirst, greaterThan(20),
        reason: 'the wash is a sliver, not a band: '
            '${band.washFirst}..${band.washLast}');
    // The band drew no readable Arabic. Zero ink inside the wash is the empty
    // amber bar that still passes "found one widget by key" — the exact
    // mistake the family's shots exist to catch.
    expect(band.darkInBand, greaterThan(200),
        reason: 'the band drew no readable Arabic: ${band.darkInBand} dark '
            'pixels on the wash');
    // And the rows below it still carry their own text, past the band.
    expect(band.inkLast, greaterThan(band.washLast),
        reason: 'nothing is drawn below the band, so it replaced the list '
            'instead of heading it');

    // **The claim this screen's picture has to make.** The rows carry their own
    // ink below the band, so the only thing separating "a header on the list"
    // from "a banner that ate the list" is that the band sits *above* them.
    // Asserted as an ordering, because a count cannot tell those two apart.
    final topRow = tester.getTopLeft(find.byKey(const Key('notification-5'))).dy;
    final bandTop = tester.getTopLeft(find.byKey(const Key('stale-notifications')))
        .dy;
    expect(bandTop, lessThan(topRow),
        reason: 'the band must be a header: above the rows, not over them');
    expect(bandTop + tester.getSize(find.byKey(const Key('stale-notifications'))).height,
        lessThanOrEqualTo(topRow),
        reason: 'the band must not overlap the first row it annotates');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/21_notifications_stale.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
