// Renders the directory twice to look at it, because a search fix is a claim
// about what a customer SEES and only a picture settles that.
//
// Two shots of the **same** `BrowseScreen`, over the **same** two live-shaped
// rows, differing only in what is typed: the number its owner holds, and a
// number nobody holds. The first must draw the man; the second must draw the
// «لا نتائج مطابقة» state with its undo. A unit test can assert both, but only
// the render proves the directory still looks like a directory — that the
// filtered answer is one card on the same surface, with the same card, and that
// the empty state is the app's own and not a raw error.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

const _outDir = '/tmp/shots';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, Object?> _user() => {
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'عميل تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// Live shape, 5 Oct 2026: `phone` on 97 of 97 browse rows.
Map<String, Object?> _worker(int id, String name, String phone, String bio) => {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': bio,
      'specialties': <String>['painting'],
      'experience_years': 15,
      'price_range_min': 1500,
      'price_range_max': 4000,
      'service_radius_km': 35,
      'is_available': 1,
      'verification_status': 'verified',
      'is_identity_verified': 1,
      'is_certificate_verified': 1,
      'subscription_plan': 'gold',
      'avg_rating': 4.7,
      'total_reviews': 30,
      'total_completed_jobs': 55,
      'response_time_hours': 2,
      'commune': 'البليدة',
      'wilaya': '09',
      'phone': phone,
      'cover_image_url': null,
      'avatar_url': null,
      'created_at': '2026-03-09 05:37:22',
      'updated_at': '2026-03-09 05:37:22',
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
      if (p.endsWith('/api/mobile/workers/search')) {
        // The wire does NOT implement `q` — measured live, the payload is
        // byte-identical with and without it. So both shots below see these
        // exact rows and differ only in what the app does with them.
        return _json([
          _worker(5, 'رشيد خليفي', '0550000009',
              'حرفي في الطلاء الخارجي والعام. أقدم خدمات طلاء المنازل والمباني بأسعار تنافسية وجودة عالية.'),
          _worker(2, 'خالد رحماني', '0550000006',
              'فنان في الطلاء الديكوري وورق الجدران. أقدم خدمات الدهن مع جودة عالية.'),
        ]);
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

Future<void> _shoot(
  WidgetTester tester,
  String name,
  ApiClient api,
  AuthState auth,
  String typed,
) async {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;

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
      child: AppScope(api: api, auth: auth, child: const BrowseScreen()),
    ),
  ));

  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  if (typed.isNotEmpty) {
    await tester.enterText(find.byType(TextField), typed);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tester.takeException();
  FlutterError.onError = previous;
  if (errors.isNotEmpty) {
    File('$_outDir/$name.ERROR.txt').writeAsStringSync(
        errors.map((e) => e.toString()).join('\n════════\n'));
  }
}

void main() {
  testWidgets('shot: the number he was handed finds its owner', (tester) async {
    final b = await _boot();
    await _shoot(tester, '23_browse_phone_number_match', b.api, b.auth,
        '0550000009');
    expect(find.text('رشيد خليفي'), findsOneWidget,
        reason: 'the man holding the number is the answer');
    expect(find.text('خالد رحماني'), findsNothing);
  });

  testWidgets('shot: a number nobody holds, as the control', (tester) async {
    final b = await _boot();
    await _shoot(tester, '24_browse_phone_number_no_match', b.api, b.auth,
        '0770999999');
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget,
        reason: 'the state is the app\'s own and it offers the undo');
  });
}
