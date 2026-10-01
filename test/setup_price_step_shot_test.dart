// Pixel proof for the price step on the contractor's setup checklist.
//
// The widget tests in `setup_price_step_test.dart` prove the *count* the
// checklist renders (`3 من 4` vs `2 من 4`), which is the state read as text.
// This file proves the two rows are **drawn** differently, because the step
// label is byte-identical in both states: what changes is the icon beside it —
// a muted empty circle versus a green check — and a tick that is only true in
// the model can still be drawn as an empty circle.
//
// Run:  flutter test test/setup_price_step_shot_test.dart  ->  /tmp/shots/
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

const _outDir = '/tmp/shots';

/// See `setup_price_step_test.dart` for why the zero history is load-bearing:
/// the checklist is only built when `!worker.hasHistory`.
Map<String, Object?> _worker({int? min, int? max}) => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'bio': 'نجار منذ عشر سنوات',
      'specialties': <Object?>['carpentry'],
      'experience_years': 0,
      'price_range_min': min,
      'price_range_max': max,
      'is_available': 1,
      'verification_status': 'pending',
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'user_wilaya': '16',
    };

String _session() => jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'email': null,
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-10-01 09:00:00',
      },
    });

Future<ApiClient> _api({int? min, int? max}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return http.Response(_session(), 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.contains('/my/profile')) {
        return http.Response(jsonEncode(_worker(min: min, max: max)), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');
  return api;
}

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  final a = FontLoader('Cairo')
    ..addFont(Future.value(ByteData.view(reg.buffer)));
  final b = FontLoader('Cairo')
    ..addFont(Future.value(ByteData.view(bold.buffer)));
  await a.load();
  await b.load();
  final icon = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icon.load();
}

/// Drives the real dashboard, scrolls the price step into view, and captures it.
Future<void> _shootPriceStep(WidgetTester tester, String name,
    {required int? min, required int? max}) async {
  tester.view.physicalSize = const Size(1080, 3860);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final api = await _api(min: min, max: max);
  final auth = AuthState(api);
  await auth.restore();

  final key = GlobalKey();
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;

  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: RepaintBoundary(
        key: key,
        child: const WorkerHomeScreen(),
      ),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  // The checklist lives under the identity card and the verification strip, so
  // on a phone it can be below the fold. `find.text` is not a hit-test and
  // finds it anyway, but a capture of an off-screen widget is a capture of
  // nothing, so it is scrolled into view first.
  final step = find.text('حدّد أسعارك ونطاق خدمتك');
  expect(step, findsOneWidget, reason: 'the price step is not on the page');
  await tester.ensureVisible(step);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    // 2.0 on a 2.75 dpr view: at 1.0 the capture came out 393 px wide, which
    // is a thumbnail of the phone screen and cannot answer a question about a
    // 19 px tick. (The `physicalSize` above sets the *logical* screen; the
    // boundary rasterises at whatever this ratio says.)
    final image = await boundary.toImage(pixelRatio: 2.0);
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

/// The colour of the icon drawn beside a step, read off the live widget tree.
///
/// The pixels are the shot; this is the number that says *which* colour, and it
/// is read from the `Icon` the step actually built rather than from a hardcoded
/// hex, so a theme change moves the number with it.
Color? _stepIconColor(WidgetTester tester) {
  final label = find.text('حدّد أسعارك ونطاق خدمتك');
  final row = find.ancestor(of: label, matching: find.byType(Row)).first;
  final icons = find.descendant(of: row, matching: find.byType(Icon));
  if (icons.evaluate().isEmpty) return null;
  return tester.widget<Icon>(icons.first).color;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shot: the price step, ticked — a maximum was typed',
      (tester) async {
    await _shootPriceStep(tester, 'setup_price_step_done',
        min: null, max: 9000);
    expect(_stepIconColor(tester), AppTheme.success,
        reason: 'a typed maximum is a done step and must be drawn as one');
  });

  testWidgets('shot: the price step, unticked — nothing was typed',
      (tester) async {
    await _shootPriceStep(tester, 'setup_price_step_todo',
        min: null, max: null);
    expect(_stepIconColor(tester), AppTheme.textMuted,
        reason: 'a contractor with no price is the man this step is for');
  });

  testWidgets('shot: the price step, unticked — a zero pair is not a price',
      (tester) async {
    await _shootPriceStep(tester, 'setup_price_step_zero', min: 0, max: 0);
    expect(_stepIconColor(tester), AppTheme.textMuted,
        reason: '(0, 0) folds to no price, so the step is still outstanding');
  });
}
