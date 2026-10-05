// The truncated reviews list, drawn on a real phone, with a control.
//
// `reviews_section_contradiction_test.dart` closed the EMPTY half of this on
// 1 Oct and `reviews_contradiction_shot_test.dart` photographed it. This is the
// other half, and it is the one production actually hits most often: measured
// over every rated row on 5 Oct, 5 rows have an empty reviews list and 3 more
// have a short one — one card under a header claiming twelve, fifteen or thirty.
//
// So this renders two shots of the **same** page, same worker, same reviews,
// differing only in what the header claims:
//
//   25_reviews_truncated  total_reviews 30, list 1  -> the annotation appears
//   26_reviews_whole_list  total_reviews  1, list 1  -> nothing added
//
// The second is the control that makes the first mean anything: a fix that
// painted an ink wash over every reviews section would pass a one-shot test and
// fail this pair.
//
// Run:  flutter test test/reviews_short_list_shot_test.dart  ->  /tmp/shots/
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

/// Live payload for worker 5 — «رشيد خليفي», 4.7 over **30** reviews, whose
/// reviews endpoint returns exactly one card. Production, 5 Oct 2026.
const _truncated = {
  'id': 5, 'user_id': 14, 'bio': 'حرفي في الطلاء الخارجي والعام',
  'specialties': ['painting'],
  'experience_years': 15, 'price_range_min': 1500, 'price_range_max': 4000,
  'service_radius_km': 35, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 1, 'verification_status': 'verified',
  'subscription_plan': 'gold', 'avg_rating': 4.7, 'total_reviews': 30,
  'total_completed_jobs': 55, 'response_time_hours': 2,
  'cover_image_url': null, 'created_at': '2026-03-09 05:37:22',
  'updated_at': '2026-03-09 05:37:22', 'full_name': 'رشيد خليفي',
  'phone': '0550000009', 'user_wilaya': '09', 'avatar_url': null,
};

/// The single live review for that worker, 20 Jan 2026.
const _oneReview = {
  'id': 2,
  'project_id': 'proj_005',
  'customer_id': 9,
  'worker_id': 5,
  'rating': 5,
  'comment': 'عمل ممتاز! الواجهة أصبحت مثل الجديدة. التزام بالموعد وجودة عالية.',
  'images': '[]',
  'is_visible': 1,
  'created_at': '2026-01-20 10:00:00',
  'customer_full_name': 'أمينة حداد',
  'customer_avatar_url': null,
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
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
      if (p.endsWith('/reviews')) {
        return http.Response(jsonEncode([_oneReview]), 200,
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

Future<void> _shootToReviews(
  WidgetTester tester,
  GlobalKey key,
  ({ApiClient api, AuthState auth}) s,
  String name,
) async {
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
        child: const WorkerProfileScreen(workerId: 5),
      ),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  // The section is below the fold, exactly as the 1 Oct shot had to scroll for
  // it: a customer is shown the header claim first and has to come to it.
  await tester.drag(find.byType(ListView), const Offset(0, -1400));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  await _capture(tester, key, name);
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('shots: the truncated list, and the whole one', (tester) async {
    final truncated = GlobalKey();
    await _shootToReviews(tester, truncated,
        await _boot(worker: _truncated), '25_reviews_truncated');
    expect(find.byKey(const Key('profile-reviews-partial')), findsOneWidget);
    expect(find.textContaining('عمل ممتاز!'), findsOneWidget,
        reason: 'the real review must survive: this is an annotation, not a '
            'replacement');

    final whole = GlobalKey();
    await _shootToReviews(
      tester,
      whole,
      await _boot(
          worker: <String, Object?>{..._truncated, 'total_reviews': 1}),
      '26_reviews_whole_list',
    );
    expect(find.byKey(const Key('profile-reviews-partial')), findsNothing,
        reason: 'the control: same page, same review, nothing added');
    expect(find.textContaining('عمل ممتاز!'), findsOneWidget);
  });
}
