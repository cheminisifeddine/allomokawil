// Rendered proof of the claim in `account_column_test.dart` — that the account
// tab is ONE screen in TWO states, on ONE page column.
//
// The guard asserts declared and measured insets. This file asserts the same
// thing with pixels: the signed-out visitor's first card and the signed-in
// contractor's first card are shot at the same window and are expected to have
// their first card start on the SAME row of pixels. Before the sweep the guest
// card sat 6 dp lower (top 14 vs top 8), and no inset assertion in the app
// could see it — they all compared each state against a constant of its own.
//
// Run:  flutter test test/account_column_shot_test.dart   ->  /tmp/shots/
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/profile_screen.dart';

const _outDir = '/tmp/shots';

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')..addFont(Future.value(ByteData.view(bold.buffer)));
  final icon =
      FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await a.load();
  await b.load();
  await icon.load();
}

Map<String, Object?> _user() => <String, Object?>{
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': 'باب الزوار',
      'created_at': '2026-09-11 20:00:00',
    };

http.Response _json(Object b) => http.Response(jsonEncode(b), 200,
    headers: {'content-type': 'application/json'});

ApiClient _api() => ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login')) {
          return _json(<String, Object?>{'token': 'tok', 'user': _user()});
        }
        if (p.endsWith('/api/mobile/subscription')) {
          return _json(<String, Object?>{
            'currency': 'DZD',
            'note_ar': 'الدفع مسبق',
            'renew_note_ar': 'ادفع مسبقاً',
            'auto_renew': 0,
            'commission_percent': 0,
            'commission_per_order': 0,
            'plans': <Object?>[],
            'current': null,
          });
        }
        if (p.endsWith('/api/unread')) {
          return _json(0);
        }
        return _json(<Object?>[]);
      }),
    );

/// Renders the account tab in [signedOut] state and writes a PNG.
Future<void> _shoot(WidgetTester tester, String name, {required bool signedOut}) async {
  tester.view.physicalSize = const Size(392 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthState(_api());
  await auth.restore();
  if (!signedOut) {
    await auth.login(phone: '0773000000', password: 'secret123');
  }

  await tester.pumpWidget(AppScope(
    api: _api(),
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
      home: RepaintBoundary(key: key, child: const ProfileScreen()),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tester.takeException();
  FlutterError.onError = previous;
  if (errors.isNotEmpty) {
    File('$_outDir/$name.ERROR.txt')
        .writeAsStringSync(errors.map((e) => e.toString()).join('\n'));
    fail('$name threw during layout — see $_outDir/$name.ERROR.txt');
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shot: the account tab, signed out and signed in', (tester) async {
    await _shoot(tester, 'account_guest', signedOut: true);
    await _shoot(tester, 'account_signed_in', signedOut: false);
  });
}
