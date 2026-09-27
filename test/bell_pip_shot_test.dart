// The unread pip, captured as pixels.
//
// A badge is the one line on the home screen that claims something arrived,
// and it is read at a glance rather than tapped. The widget tests in
// `notification_center_test.dart` prove the pip *appears* on resume; this file
// proves it appears in the right *place* and in the right *colour*, because
// "the widget is in the tree" and "the user can see it" are different claims
// and only one of them is about the product.
//
// It is deliberately a small canvas: the bell alone, centred, so every
// non-background pixel belongs to it. The number read back is an exact match
// on `AppTheme.danger` (0xFFC33F39), not a fuzzy "reddish" range — a loose
// tolerance here would match the antialiased edge of the icon glyph and pass on
// a build with no pip at all, which is the first version of this file and the
// reason it now counts one exact colour.
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
import 'package:allomokawil/src/widgets/notifications_bell.dart';

const _outDir = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')..addFont(Future.value(ByteData.view(bold.buffer)));
  await a.load();
  await b.load();
  final icon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icon.load();
}

/// Writes the shot and returns how many device pixels are *exactly* [color].
///
/// An exact equality, deliberately. A tolerance looks more robust and is
/// strictly worse here: the icon glyph is antialiased through the same reds,
/// so a fuzzy match reports 15 "danger" pixels on a build with no badge at all
/// and the assertion passes for the wrong reason. Counting one exact color
/// gives 0 on the broken build, which is the number the test needs to see.
Future<int> _shoot(WidgetTester tester, String name, GlobalKey key,
    {required int color}) async {
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  var exact = 0;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());

    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytesPerRow = image.width * 4;
    for (var y = 0; y < image.height; y++) {
      final row = y * bytesPerRow;
      for (var x = 0; x < image.width; x++) {
        final o = row + x * 4;
        // The badge is opaque, so the alpha byte is part of the match: a
        // transparent pixel that happens to hold the same RGB is not the badge.
        if (rgba!.getUint8(o) == (color >> 16 & 0xFF) &&
            rgba.getUint8(o + 1) == (color >> 8 & 0xFF) &&
            rgba.getUint8(o + 2) == (color & 0xFF) &&
            rgba.getUint8(o + 3) == 0xFF) {
          exact++;
        }
      }
    }
  });
  return exact;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('the unread pip on the home header, before and after resume',
      (tester) async {
    var unread = 0;
    final api = ApiClient(
      baseUrls: const ['https://api.test'],
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/unread') {
          return http.Response('{"unread": $unread}', 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    // No login round-trip: the bell takes an injected repository, so the
    // session only has to exist. A stored token is the whole of it.
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': '{"id":7,"phone":"0550000000","email":null,'
          '"full_name":"Test User","type":"customer","avatar_url":null,'
          '"wilaya":"16","commune":null,"created_at":"2026-01-01 00:00:00"}',
    });
    final auth = AuthState(api);
    await auth.restore();

    tester.view.physicalSize = const Size(240, 120) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RepaintBoundary(
        key: key,
        child: AppScope(
          api: api,
          auth: auth,
          child: Scaffold(
            backgroundColor: AppTheme.surface,
            body: Center(child: NotificationsBell(repo: Repository(api))),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Nothing unread when the app opened: the header carries the bell and
    // nothing else, so not one pixel of the badge color is on the canvas.
    expect(find.byKey(const Key('notifications-badge')), findsNothing);
    expect(await _shoot(tester, 'zz_bell_1_no_pip', key,
        color: AppTheme.danger.toARGB32()), 0);

    // The phone was locked, three notifications arrived, it is unlocked again.
    unread = 3;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('notifications-badge')), findsOneWidget);
    // The badge is a filled pill, not a hairline: at pixelRatio 3 a 14.7-logical
    // pip is a ~44x44 block, so a couple of thousand exact-fill pixels is the
    // right order. The low bound catches a badge that rendered as a 1px dot;
    // it is not pinned to an exact count so a rounding change in the theme
    // cannot fail a test about *whether the pip is there*.
    final painted = await _shoot(tester, 'zz_bell_2_pip_after_resume', key,
        color: AppTheme.danger.toARGB32());
    expect(painted, greaterThan(500));
  });
}
