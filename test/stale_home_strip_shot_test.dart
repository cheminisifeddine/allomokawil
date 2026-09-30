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
import 'package:allomokawil/src/core/location/locator.dart';
import 'package:allomokawil/src/core/location/place_state.dart';
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

/// Every dark pixel in the frame, whatever row it is on.
///
/// The counterpart to [_scanBand], for a frame that must have **no** band on
/// it: there is no wash to measure against, so the claim is that the strip's
/// cards are not drawn, and the count is taken over the whole frame.
Future<int> _countInk(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 3.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var dark = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    if (bytes[i] < 0xC0 && bytes[i + 1] < 0xA0 && bytes[i + 2] < 0x60) dark++;
  }
  return dark;
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

/// The API for this screen's shot, with the contractors read's liveness under
/// the test's control.
///
/// Extracted from the first shot's inline client so the dated case below can
/// drive the same reads without a second, drifting copy of the fixture — the
/// failure `stale_home_strip_test.dart` records as a harness that "starts lying
/// about a path it never walks".
///
/// [deadWorkers] is a callback rather than a bool so a test can kill the read
/// *after* the first load has been seen on screen, which is the shape of the
/// real event: the phone rendered fine, then the network died under it.
ApiClient _client(
    {required bool Function() deadWorkers,
    Duration timeout = const Duration(milliseconds: 200)}) {
  return ApiClient(
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
          if (deadWorkers()) {
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(
              jsonEncode(<Object?>[
                _worker(1, 'مقاول قديم'),
                _worker(2, 'مقاول ثانٍ'),
              ]),
              200,
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
      timeout: timeout);
}

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

    // The first read succeeds and the second dies: the phone rendered fine,
    // then the network went under it. `reads` rather than a plain bool because
    // the strip is re-read on the pull, and the shot is about the frame *after*
    // that failure.
    var reads = 0;
    final api = _client(deadWorkers: () => reads++ > 0);

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

  testWidgets('a DATED band is drawn above the cards, the age included',
      (tester) async {
    // The band carries a second sentence now — «قرأناها قبل 40 دقيقة» — and
    // the first shot above cannot see that at all, because a shot taken on a
    // real wall clock captures the one frame where the age is *deliberately*
    // silent: a read inside the minute. So the clock is injected and aged 40
    // minutes, and this picture proves the dated band rather than the wording
    // the app shipped before.
    //
    // The date is the number the user is actually missing. The band already
    // admits «هذه آخر نتيجة قرأناها»; what it could not say is whether that was
    // four seconds ago or four hours — and on this screen the two strips fail
    // for opposite reasons, so the gap is the decision: a project of the
    // user's own may already have been taken, while the contractors strip is
    // supply that «ابحث عن مقاول» duplicates one tap away.
    var now = DateTime(2026, 9, 29, 9, 0);
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    var dead = false;
    final api = _client(deadWorkers: () => dead);
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
          home: CustomerHomeScreen(clock: () => now),
        ),
      ),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('مقاول قديم'), findsOneWidget,
        reason: 'the first read worked, so the strip has cards on it');

    // The read lands at 09:00, the network then dies, and the phone is not
    // touched again for forty minutes.
    dead = true;
    now = DateTime(2026, 9, 29, 9, 40);
    await tester.fling(
        find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // Crossed by a whole minute, not a frame: the band is re-dated by the
    // once-a-minute age tick, so a test that only pumps frames is asserting on
    // the sentence as it stood when the failure landed.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('stale-workers')), findsOneWidget);
    // Asserted in the widget as well as in the pixels, because a band can be
    // *drawn* with the right colour and the wrong words and only the text
    // widget knows which one it is.
    final line = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('stale-workers')),
        matching: find.byType(Text))).data!;
    expect(line, contains('قبل 40 دقيقة'),
        reason: 'the shot must capture the dated band, not the undated one');
    // ignore: avoid_print
    print('BAND LINE: $line');

    final (rows, dark) = (await tester.runAsync(() => _scanBand(key)))!;
    // ignore: avoid_print
    print('BAND rows=$rows dark=$dark');

    expect(rows, greaterThan(20),
        reason: 'the amber wash is not on screen at the size it should be');
    // Higher than the undated shot's floor of 200, because the second
    // sentence is real ink: a band that drew the first sentence and dropped
    // the age would still clear 200 and pass the older assertion.
    expect(dark, greaterThan(30000),
        reason: 'the band drew no readable Arabic: $dark dark pixels on '
            'the wash');

    // The band is a header *on* the strip, so the contractors the user was
    // looking at have to still be in the same frame — the age is an addition,
    // not a replacement for the list.
    expect(find.text('مقاول قديم'), findsOneWidget);
    expect(find.text('تعذّر جلب المقاولين'), findsNothing,
        reason: 'the frame must show the doubt, not a blanked strip');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/20_home_workers_stale_dated.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('a failed WILAYA switch draws the error, not the old city\'s '
      'contractors', (tester) async {
    // The picture the two new widget cases only argue for.
    //
    // The shot exists because «the error card is on screen» and «the other
    // city's contractor is NOT on screen» are different claims and only one of
    // them is visible in a frame. The ink measurement settles the rest: the
    // strip behind the band is a horizontal row of contractor cards carrying
    // its own ink, so a global dark count would pass on the cards alone with
    // the error drawing nothing. So the contractor **names** are asserted as
    // widgets in the same frame, and the frame is captured for the record.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // Read 1 (the boot read, Algiers) succeeds; every read after it dies.
    var reads = 0;
    final api = _client(deadWorkers: () => reads++ > 0);

    // The phone already knows where it is — the stored fix from the last
    // launch, which is what makes the first read a *filtered* read at all.
    final place = PlaceState.detached()
      ..seed(const DetectedPlace(
        wilayaId: '16',
        wilayaName: 'الجزائر',
        lat: 36.7,
        lng: 3.0,
        seatKm: 4,
      ));

    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);

    final key = GlobalKey();
    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      place: place,
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

    // The phone moves. The strip re-reads for Oran and that read dies — the
    // everyday event on a train, and the one the two widget cases pin.
    place.seed(const DetectedPlace(
      wilayaId: '31',
      wilayaName: 'وهران',
      lat: 35.7,
      lng: -0.6,
      seatKm: 2,
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // The header followed the fix, so the rows under it would be wrong.
    expect(find.textContaining('وهران • موقعك'), findsWidgets);
    expect(find.byKey(const Key('stale-workers')), findsNothing,
        reason: 'the band qualifies rows; with no rows for THIS wilaya there '
            'is nothing to qualify');

    // **The frame.** A failed switch has nothing of its own to draw, so the
    // strip is gone — not a quiet blank: the error, with the button that is
    // the only action left.
    expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);
    expect(find.text('مقاول قديم'), findsNothing,
        reason: 'Algiers\'s contractor must not be listed to a client in Oran');
    expect(find.text('إعادة المحاولة'), findsOneWidget,
        reason: 'the honest screen offers the retry the failed read deserves');

    final total = (await tester.runAsync(() => _countInk(key)))!;
    // ignore: avoid_print
    print('SWITCH total dark=$total');

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/25_home_wilaya_switch_failed.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
