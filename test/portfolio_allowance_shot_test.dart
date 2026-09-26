// Renders the portfolio gate at real phone size, in both states.
//
// The change is visual, so a widget assertion that a `Key` is absent is not
// enough: the claim a contractor would make is "the button is gone and the
// screen says why, and it does not look broken". Only a capture of the real
// widget tree can answer that, and both states have to be shot — a one-sided
// capture passes just as happily on a gate that never opens.
//
// These are the same `repaintBoundary` → PNG mechanism `design_shots_test.dart`
// and `empty_states_test.dart` already use, at 392x850 (the narrowest column
// the app lays out for) so an overflow would be visible rather than inferred.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

String _body(String path, {required int photos, required int limit}) {
  if (path.endsWith('/api/login')) {
    return jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'wilaya': '16',
        'created_at': '2026-09-11 20:00:00',
      },
    });
  }
  if (path.contains('/portfolio')) {
    return jsonEncode(<Object>[
      for (var i = 0; i < photos; i++)
        <String, Object>{'image_url': 'https://r2.test/p$i.jpg'},
    ]);
  }
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
    });
  }
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'quote_limit': 3,
        'portfolio_limit': limit,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

Future<String> _shoot(
  WidgetTester tester,
  String name, {
  required int photos,
  required int limit,
}) async {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => http.Response(
          _body(req.url.path, photos: photos, limit: limit),
          200,
          headers: {'content-type': 'application/json'},
        )),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

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
      home: RepaintBoundary(key: key, child: const MyPortfolioScreen()),
    ),
  ));
  await _settle(tester);

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.75);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

/// Registers the real Cairo faces so the Arabic in the capture is glyphs.
///
/// Without this the Arabic renders as tofu boxes and the shot is evidence of
/// nothing but the fact that a box was drawn — a first run of this file did
/// exactly that, and the header band came back as a row of identical empty
/// rectangles. A capture that cannot be read is not a check.
Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the gallery with room, and the gallery at its limit', (tester) async {
    final open = await _shoot(tester, 'allowance_01_open',
        photos: 2, limit: 5);
    final full = await _shoot(tester, 'allowance_02_full',
        photos: 5, limit: 5);
    // ignore: avoid_print
    print('SHOT $open\nSHOT $full');
  });
}
