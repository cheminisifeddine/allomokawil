// The pixels behind `wilaya_trap_test.dart`.
//
// The claim is visual and narrow: the wilaya sheet's search field now carries
// a clear control on the right, and the empty state under it names the
// situation. Both are asserted in the widget tests; this writes real PNGs so
// the claim can be *looked at* at a real 392x860 phone viewport with Cairo
// loaded — the Arabic in the capture is the glyphs a device draws, not tofu.
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
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

const _user = {
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'عميل تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': null,
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/login') ||
          req.url.path.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user});
      }
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Renders the wilaya sheet in the trapped state (a query that matches
/// nothing) and returns the path of the PNG it wrote.
Future<String> _shoot(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  // The boundary wraps the WHOLE MaterialApp, not `home`: a modal sheet is
  // pushed into the Navigator's overlay, which is a *sibling* of the home
  // route. A boundary on `home` photographs the dimmed form behind the sheet
  // and the capture quietly contains none of the thing under test.
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: RepaintBoundary(key: key, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const ProjectNewScreen(),
    )),
  ));
  await _settle(tester);

  // Scroll the form until the required wilaya row exists, then open the sheet.
  final opener = find.text('اختر الولاية');
  if (opener.evaluate().isEmpty) {
    await tester.scrollUntilVisible(opener, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(opener);
  await tester.tap(opener);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await tester.enterText(
    find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(TextField)),
    'alger',
  );
  await tester.pump(const Duration(milliseconds: 250));

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$shotName.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a shot this small means nothing rendered');
  return path;
}

const shotName = 'wilaya_trap_empty';

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  testWidgets('the trapped wilaya search rasterises with a clear control',
      (tester) async {
    final b = await _boot();
    final path = await _shoot(tester, b.api, b.auth);

    // In the tree...
    expect(find.text('لا توجد ولاية بهذا الاسم'), findsOneWidget);
    // ...and on screen, which is the only thing a picture can rule out.
    final clear = find.byIcon(Icons.close_rounded);
    expect(clear, findsOneWidget);
    final button = tester.widget<IconButton>(
      find.ancestor(of: clear, matching: find.byType(IconButton)),
    );
    expect(button.onPressed, isNotNull,
        reason: 'the clear control must be live in this state, or the shot '
            'shows a greyed-out decoration');
    // Geometry in LOGICAL px, so the pixel scan can be pointed at the exact
    // band the control occupies instead of guessing where "right-ish" is.
    final r = tester.getRect(find.ancestor(
      of: clear,
      matching: find.byType(IconButton),
    ));
    final field = tester.getRect(find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(TextField),
    ).first);
    // ignore: avoid_print
    print('SHOT=$path DPR=3.0');
    // ignore: avoid_print
    print('CLEAR_LOGICAL=$r');
    // ignore: avoid_print
    print('FIELD_LOGICAL=$field');
    // ignore: avoid_print
    print('CLEAR_PIXELS=x${(r.left * 3).round()}-${(r.right * 3).round()} '
        'y${(r.top * 3).round()}-${(r.bottom * 3).round()}');
  });
}
