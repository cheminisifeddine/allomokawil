// Rasterizes the stale home strips, because the step-5 rule is that a layout
// claim needs a picture and not an argument.
//
// Same path `stale_projects_shot_test.dart`, `stale_directory_shot_test.dart`,
// `stale_inbox_shot_test.dart` and `stale_catalogue_shot_test.dart` use and for
// the same reason: the real rasterizer with the real Cairo loaded through
// `FontLoader`, because a bare widget test draws Arabic as tofu and tofu still
// measures as "there is ink on screen". The web+CDP path needs a Chrome build
// this box does not have, so the capture is taken in-test instead of saying so
// and asserting nothing.
//
// The measurement is scoped to each band's own rows, for the reason
// `stale_inbox_shot_test.dart` records: the page behind it is white, so a
// global ink count passes for any input at all. Each band is found by its own
// wash (`accentWash` = FDF3E3) and the assertion counts *dark* pixels inside
// those rows — the Arabic sentence. A capture that drew the card and no text at
// all returns zero, and that is the mistake this shot exists to catch.
//
// And this screen is the one member of the family whose picture has to prove
// something the others did not: the strip behind the band is a *horizontal*
// row of contractor cards, which carries its own ink (avatars, names, ratings).
// A global dark count would pass on the cards alone with the band drawing
// nothing, so the dark pixels are counted inside the wash rows and the cards
// are asserted as separate widgets in the same frame.
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
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';

const _out = '/tmp/shots';

/// Rows the amber wash occupies, and the dark pixels inside them.
///
/// The wash is the band's own surface (`AppTheme.accentWash`, FDF3E3) and the
/// sentence is `AppTheme.accentDeep` (9B6415) on it, so the polarity is
/// dark-on-wash and not the reverse.
Future<(int rows, int dark)> _scanBand(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final width = boundary.size.width.round();
  final height = boundary.size.height.round();
  const scale = 3.0;
  final stride = (width * scale).round();
  final total = (height * scale).round();
  var bandRows = 0;
  var dark = 0;
  for (var y = 0; y < total; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    var wash = 0;
    var darkInRow = 0;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - 0xFD).abs() <= 3 && (g - 0xF3).abs() <= 3 && (b - 0xE3).abs() <= 3) {
        wash++;
      }
      if (r < 0xC0 && g < 0xA0 && b < 0x60) darkInRow++;
    }
    if (wash > stride ~/ 3) {
      bandRows++;
      dark += darkInRow;
    }
  }
  return (bandRows, dark);
}

Map<String, Object?> _worker(int id, String name) => {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': 'دهان وتشطيب',
      'specialties': <String>['painting'],
      'experience_years': 9,
      'price_range_min': 20000,
      'price_range_max': 90000,
      'service_radius_km': 15,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_rib_exported': 0,
      'rating_avg': 4.6,
      'rating_count': 12,
      'response_time_hours': 3,
      'commune': 'باب الزوار',
      'wilaya': '16',
      'completed_jobs': 40,
      'avatar_url': null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('a failed contractors refresh is drawn above the cards, in Arabic',
      (tester) async {
    // 1080x2280, not the taller 2532 the «مشاريعي» shot uses: this screen
    // stacks the header, a search row, a category grid and two section titles
    // above the contractors strip, so a taller viewport puts the strip below
    // the fold and the first read's cards are never built. Found by asserting
    // the cards before the gesture.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var reads = 0;
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
          return http.Response(
              jsonEncode(<String, Object?>{
                'token': 'tok',
                'user': <String, Object?>{
                  'id': 30,
                  'phone': '0773000000',
                  'email': null,
                  'full_name': 'سمية',
                  'type': 'customer',
                },
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        if (path.contains('/api/unread')) {
          return http.Response('{"unread":0}', 200,
              headers: {'content-type': 'application/json'});
        }
        if (path.contains('/api/mobile/workers/top')) {
          reads++;
          if (reads == 1) {
            return http.Response(
                jsonEncode(<Object?>[
                  _worker(1, 'مقاول قديم'),
                  _worker(2, 'مقاول ثانٍ'),
                ]),
                200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('', 503,
              headers: {'content-type': 'application/json'});
        }
        // NOT empty: an account with no projects and no conversations shows
        // the first-run guide, and that card sits above the contractors strip
        // and pushes it off the viewport — so the strip is never built and the
        // shot captures an empty page. A returning client is also the honest
        // subject of this picture: he has projects, and he can still see them.
        if (path.contains('/my/projects')) {
          return http.Response(
              '[${jsonEncode(<String, Object?>{
                'id': 'p1',
                'customer_id': 30,
                'title': 'مشروع قديم',
                'description': 'دهان كامل',
                'category': 'painting',
                'images': <String>[],
                'wilaya': '16',
                'commune': 'حسين داي',
                'latitude': null,
                'longitude': null,
                'budget_min': 60000,
                'budget_max': 90000,
                'urgency': 'within_week',
                'status': 'open',
                'selected_worker_id': null,
                'created_at': '2026-09-11 20:23:44',
                'updated_at': '2026-09-11 20:23:44',
              })}]',
              200,
              headers: {'content-type': 'application/json'});
        }
        if (path.contains('/conversations')) {
          return http.Response(
              '[${jsonEncode(<String, Object?>{
                'id': 1,
                'customer_id': 30,
                'worker_user_id': 31,
                'project_id': null,
                'last_message_at': '2026-09-11 20:23:47',
                'created_at': '2026-09-11 20:23:47',
                'other_user_name': 'مقاول تجربة',
                'other_user_avatar': null,
                'last_message_content': 'مرحبا',
                'unread_count': 0,
              })}]',
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }),
      timeout: const Duration(milliseconds: 200),
    );

    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
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
          home: const CustomerHomeScreen(),
        ),
      ),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('مقاول قديم'), findsOneWidget,
        reason: 'the first read worked, so the strip has cards on it');

    await tester.fling(
        find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('stale-workers')), findsOneWidget);

    final (rows, dark) = (await tester.runAsync(() => _scanBand(key)))!;
    // ignore: avoid_print
    print('BAND rows=$rows dark=$dark');

    // The card is on screen and it has text in it. Zero dark pixels on the
    // wash means the band drew as an empty amber bar — which still passes
    // "found one widget by key" and is the mistake the shot exists to catch.
    expect(rows, greaterThan(20),
        reason: 'the amber wash is not on screen at the size it should be');
    expect(dark, greaterThan(200),
        reason: 'the band drew no readable Arabic: $dark dark pixels on '
            'the wash');

    // The band is a header *on* the strip, so the contractors the user was
    // looking at have to still be in the same frame. This is the claim the
    // whole fix rests on and the one the unfixed screen cannot make at all.
    expect(find.text('مقاول قديم'), findsOneWidget);
    expect(find.text('تعذّر جلب المقاولين'), findsNothing,
        reason: 'the frame must show the doubt, not a blanked strip');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/20_home_workers_stale.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
