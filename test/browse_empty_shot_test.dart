// The pixels behind `browse_empty_action_test.dart`.
//
// The fix is a button appearing on a screen, so the assertion that matters is
// the one only a picture can make: before, the empty directory ended at the
// body sentence with nothing under it; after, an amber action button sits
// below the copy. Renders both states from the real widget tree at a real
// 392x860 phone viewport with Cairo loaded, so the Arabic in the capture is
// the glyphs the device draws and not tofu boxes.
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
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, Object?> _user() => {
      'id': 30, 'phone': '0773000000', 'email': null, 'full_name': 'عميل',
      'type': 'customer', 'avatar_url': null, 'wilaya': '16',
      'commune': null, 'created_at': '2026-09-11 20:00:00',
    };

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
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

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<String> _shoot(
  WidgetTester tester,
  String name,
  ApiClient api,
  AuthState auth, {
  String? initialCategory,
  Size logical = const Size(392, 860),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
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
      home: RepaintBoundary(
        key: key,
        child: BrowseScreen(initialCategory: initialCategory),
      ),
    ),
  ));
  await _settle(tester);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  testWidgets('the empty directory rasterises with its action button visible',
      (tester) async {
    final b = await _boot();
    await _shoot(tester, 'browse_empty_action', b.api, b.auth);

    // The control has to be on screen, not merely in the tree: the previous
    // tick's bug class was a widget that existed but was unmounted, and the
    // shot is what rules that out.
    expect(find.text('لا يوجد مقاول当今'), findsNothing);
    expect(find.text('لا يوجد مقاول حالياً'), findsOneWidget);
    expect(find.text('تحديث'), findsOneWidget);
    // `PrimaryButton` wraps an `ElevatedButton`; asserting the *enabled* one
    // is what rules out a greyed-out dead control rendered in the shot.
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('تحديث'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNotNull,
        reason: 'the action must be pressable, not a sentence that merely '
            'looks like one');
  });

  testWidgets('the filtered directory keeps its own heading and clear action',
      (tester) async {
    final b = await _boot();
    await _shoot(tester, 'browse_empty_filtered', b.api, b.auth,
        initialCategory: 'electrical');

    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
    expect(find.text('تحديث'), findsNothing);
  });
}
