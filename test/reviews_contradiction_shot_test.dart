// The reviews section drawn on a real 392x844 phone, in both states it can be
// in after this tick's fix, so the copy is measured rather than reasoned about.
//
// The screen the app used to ship is not a hypothetical: `/workers/1` answers
// `avg_rating 4.8, total_reviews 24` while `/workers/1/reviews` answers `[]`,
// both 200. The shot on the left is that man today — one page saying he is
// rated four stars over twenty-four reviews, and a few scrolls down a card
// telling the customer he has none and to go write his first.
//
// Run:  flutter test test/reviews_contradiction_shot_test.dart  ->  /tmp/shots/
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
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

const _outDir = '/tmp/shots';
const _phone = Size(392, 844);

/// The live payload for worker 1 — 4.8 over 24 reviews, empty reviews list.
const _rated = {
  'id': 1, 'user_id': 11, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.8, 'total_reviews': 24,
  'total_completed_jobs': 12, 'response_time_hours': 2,
  'cover_image_url': null, 'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45', 'full_name': 'عمر بن علي',
  'phone': '077442495', 'user_wilaya': '16', 'avatar_url': null,
};

Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')
        ..addFont(Future.value(ByteData.view(reg.buffer))))
      .load();
  await (FontLoader('Cairo')
        ..addFont(Future.value(ByteData.view(bold.buffer))))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<({ApiClient api, AuthState auth})> _boot({
  required Map<String, Object?> worker,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return http.Response(
            jsonEncode({
              'token': 'tok',
              'user': {
                'id': 30, 'phone': '0773000000', 'email': null,
                'full_name': 'زبون تجربة', 'type': 'customer',
                'avatar_url': null, 'wilaya': '16', 'commune': null,
                'created_at': '2026-09-11 20:00:00',
              },
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (p.endsWith('/api/unread')) {
        return http.Response('0', 200,
            headers: {'content-type': 'application/json'});
      }
      // The disagreement, exactly as the live API returns it.
      if (p.endsWith('/reviews')) {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.endsWith('/portfolio')) {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(worker), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    stdout.writeln('SHOT: $_outDir/$name.png');
  });
}

Future<void> _pump(WidgetTester tester, GlobalKey key, ({ApiClient api, AuthState auth}) s) async {
  tester.view.physicalSize = _phone * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: s.api,
    auth: s.auth,
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
        child: const WorkerProfileScreen(workerId: 1),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shots: the contradicted section, and the agreed one',
      (tester) async {
    // ── The contradiction, on a real phone ──────────────────────────────────
    final contradicted = GlobalKey();
    await _pump(tester, contradicted, await _boot(worker: _rated));
    // The section is below the fold on a 844dp phone, which is the point: the
    // customer has to scroll from the header he was shown first.
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await _capture(tester, contradicted, 'reviews_contradicted');

    // ── The two reads agreeing, on the same phone ───────────────────────────
    final agreed = GlobalKey();
    await _pump(
      tester,
      agreed,
      await _boot(
        worker: <String, Object?>{..._rated, 'avg_rating': 0, 'total_reviews': 0},
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await _capture(tester, agreed, 'reviews_agreed');
  });
}
