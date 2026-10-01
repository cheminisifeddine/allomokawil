// The pixels behind `notification_score_scale_test.dart`.
//
// The rule there is a **claim about text**, and a claim about text is exactly
// the kind a unit test cannot photograph: "the sentence says five stars, not
// seven" is provable from the string, but "the line a contractor reads under
// «تقييم جديد» says five stars" is a claim about what the card actually drew.
// This drives the **real** `NotificationsScreen` with a real out-of-scale row on
// the wire and photographs it, so the fix is backed by a picture and not by an
// argument — step 5 of the loop's protocol.
//
// Same in-test rasterizer path as `stale_notifications_shot_test.dart` and the
// rest of the shot family: the real Cairo through `FontLoader`, because a bare
// widget test draws Arabic as tofu and tofu still measures as "ink on screen".
// There is no Chrome and no `build_web.sh` on this host, so the capture is
// taken here rather than being claimed and asserted nowhere.
//
// **Both states are photographed, and one-sided is the trap.** A capture of the
// pinned state alone passes just as happily on a screen that draws *nothing* —
// which is what a guard that simply stopped printing numbers would produce. So
// the legal `5/5` the live API really sends is shot beside it, and the second
// shot asserts its own ink. The pin has to narrow what is printed without
// deleting what is true.
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

/// Dark-pixel count inside a horizontal band of an already-captured frame.
///
/// The image is **passed in** rather than rasterized here. The first version of
/// this file called `toImage` twice — once for the PNG on disk and once for the
/// measurement — on a `RepaintBoundary` 1200x2700 at `pixelRatio: 3.0`, and the
/// second test in the file simply never returned: it was still rasterizing at
/// 13 minutes when the file was killed, with nothing written and no error. One
/// capture, two uses. The cost of the raster belongs to the one place that
/// pays it.
Future<int> _darkInk(
  ui.Image img, {
  required int width,
  required int height,
  required double topFrac,
  required double bottomFrac,
}) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final stride = width;
  final total = height;
  final from = (total * topFrac).round();
  final to = (total * bottomFrac).round();
  var dark = 0;
  for (var y = from; y < to; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      if (bytes[i] < 0xC0 && bytes[i + 1] < 0xA0 && bytes[i + 2] < 0x60) dark++;
    }
  }
  return dark;
}

Map<String, Object?> _sessionUser() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'worker',
    };

Map<String, Object?> _row(int id, String body) {
  final t = DateTime.now().toUtc().subtract(Duration(hours: 1));
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'id': id,
    'type': 'review_received',
    'title': 'تقييم جديد',
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

Future<void> _shoot(
  WidgetTester tester,
  GlobalKey key,
  String name,
  String score,
) async {
  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_sessionUser()),
  });
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path == '/api/notifications') {
        return _json(<Object?>[_row(5, score)]);
      }
      return _json(<String, Object?>{});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  final trust = NotificationCountTrust();

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
  // **`pumpAndSettle` is not used here, and that is a finding rather than a
  // style choice.** This screen keeps a relative-time ticker alive, so the
  // tree never reaches a quiescent frame: the first version of this file called
  // `pumpAndSettle` and its *second* `testWidgets` sat there until the file was
  // killed at 13 minutes, while the first capture had already been written to
  // disk 20 seconds in. A settle-based capture is only as good as its ability to
  // finish, and a card that repaints its own timestamps never will. Bounded
  // pumps, in the same shape `stale_notifications_shot_test.dart` uses, so the
  // capture is a fixed amount of work rather than a race with a clock.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));

  expect(find.byKey(const Key('notification-5')), findsOneWidget,
      reason: 'the read worked, so the row is on screen');

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // **`tester.runAsync` is not optional here.** `toImage` resolves on the
  // engine's own schedule, and the fake-async zone a `testWidgets` body runs
  // in will not deliver it — so calling it bare returns a future that never
  // completes, and the test hangs with no failure and no output rather than
  // reporting anything. `stale_notifications_shot_test.dart` wraps its own scan
  // in `runAsync` for this reason; this file did not, and that is what made its
  // second test sit there for thirteen minutes.
  final png = await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 3.0);
    final out = (await img.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final ink = await _darkInk(
      img,
      width: (boundary.size.width * 3.0).round(),
      height: (boundary.size.height * 3.0).round(),
      topFrac: 0.08,
      bottomFrac: 0.40,
    );
    img.dispose();
    return (out, ink);
  });
  if (png == null) {
    throw StateError('the rasterizer returned no frame for "$name"');
  }
  final (bytes, ink) = png;
  Directory(_out).createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(bytes);

  // The body line sits under the headline, in the lower half of the card.
    // **The window is measured, not guessed.** The first version of this file
  // scanned 45–95% of the frame, on the assumption that a card sits in the
  // middle of a tall viewport. It does not: the capture it produced put every
  // dark pixel in the top 22% and the assertion window was empty. That is what
  // the ASCII pass over the real PNG was for — the ink was never missing, the
  // claim was looking in the wrong place.
  // ignore: avoid_print
  print('SHOT $name bodyInk=$ink score="$score" -> $_out/$name.png');
  expect(ink, greaterThan(200),
      reason: 'the body line drew no readable Arabic for "$score": $ink dark '
          'pixels');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('an out-of-scale score still draws its Arabic body line',
      (tester) async {
    tester.view.physicalSize = const Size(400, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await _shoot(tester, key, 'notification_score_pinned', '7/5');
  });

  testWidgets('the score the live API sends is drawn exactly as before',
      (tester) async {
    tester.view.physicalSize = const Size(400, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    // **Deliberately `3/5` and not `5/5`.** The control was `5/5` at first,
    // and the two captures came out **byte-identical** — which is the fix
    // working (a pinned `7/5` now renders exactly «5 نجوم») but is useless as
    // evidence: two files with one md5 cannot show that the capture responds to
    // the payload at all. A control that renders a *different* score is what
    // makes both files mean something: if `3/5` and the pinned row differ, the
    // shot is reading the wire, and the pin is what moved it.
    await _shoot(tester, key, 'notification_score_live', '3/5');
  });
}
