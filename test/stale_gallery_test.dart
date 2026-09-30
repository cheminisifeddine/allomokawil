// What «معرض أعمالي» says when the photos on screen are not the photos on the
// server — the tenth screen in the stale-read family, and the first whose data
// is a grid of images the contractor is the author of.
//
// The defect is the family's original mistake, untouched, at
// `my_portfolio_screen.dart:335`:
//
//     body: _loading ? const SkeletonGrid() : ...
//
// One boolean asked two questions. `_loading` means "is a read in flight?" and
// the builder used it to mean "is there anything to draw?", so a contractor
// who pressed «تحديث» on hotel wifi lost twelve photographs of finished jobs to
// a shimmer — for the length of a round trip if the read merely *failed*, and
// forever if it did.
//
// Two harness faults from earlier members of this family are designed out
// rather than rediscovered here:
//
//   * **Both reads failing.** The earlier race cases failed read 1 *and* read
//     2, so there was no cache to mislabel and nothing could be wrong. The gate
//     below answers per **request count**, so a case can park one read while
//     the other lands.
//   * **The shared 200 ms timeout.** That fires while a parked read is still
//     open and converts it into a failed read, which is a different case. The
//     parked case runs at 20 s — the same fault two siblings recorded.
import 'dart:async';
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
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/read_age_ar.dart';
import 'package:allomokawil/src/data/stale_gallery_copy.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

/// The instant the band's age is measured against, so a golden test pins words
/// and not a wall clock.
final DateTime kNow = DateTime(2026, 9, 30, 12, 0, 0);

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

/// How a request is answered, chosen by the caller rather than by a flag.
typedef Answer = Future<http.Response> Function(String path);

/// Mounts the screen on a client that answers by [answer].
Future<void> _mount(
  WidgetTester tester, {
  required Answer answer,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => answer(req.url.path)),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

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
        key: boundary,
        child: const MyPortfolioScreen(clock: _fixedClock),
      ),
    ),
  ));
}

DateTime _fixedClock() => kNow;

Future<http.Response> _ok(String body) => Future.value(http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    ));

void main() {
  group('the copy', () {
    test('a failure says the photos survived an earlier read', () {
      final line = staleGalleryLineAr('تعذّر الاتصال');
      expect(line, contains('لم نتمكن من تحديث معرض أعمالك'));
      expect(line, contains('تعذّر الاتصال'),
          reason: 'the reason is appended, not substituted');
    });

    test('a bare failure still produces a sentence', () {
      // Unreachable in the app — `errorCopy` always produces one — and the
      // guard exists so a band can never explain nothing.
      expect(staleGalleryLineAr('   '), isNotEmpty);
      expect(staleGalleryLineAr('   '), isNot(contains('  ')));
    });

    test('the age is appended, and a fresh read keeps the old line', () {
      final stale = DateTime(2026, 9, 30, 9, 0);
      final withAge =
          staleGalleryLineWithAgeAr('تعذّر الاتصال', stale, now: kNow);
      expect(withAge, contains('لم نتمكن من تحديث معرض أعمالك'),
          reason: 'the reason is never traded for a timestamp');
      expect(withAge.split('\n').length, 2);
      // Under a minute, clock skew and null are silence.
      final fresh = kNow.subtract(const Duration(seconds: 20));
      expect(staleGalleryLineWithAgeAr('تعذّر الاتصال', fresh, now: kNow),
          staleGalleryLineAr('تعذّر الاتصال'),
          reason: 'a read that is still current keeps its own words');
      expect(
          staleGalleryLineWithAgeAr('x', kNow.add(const Duration(hours: 2)),
              now: kNow),
          staleGalleryLineAr('x'));
      expect(staleGalleryLineWithAgeAr('x', null, now: kNow),
          staleGalleryLineAr('x'));
    });

    test('the age rule is the app-wide one, not a second opinion', () {
      final at = DateTime(2026, 9, 30, 11, 0);
      expect(staleGalleryAgeAr(at, now: kNow), readAgeAr(at, now: kNow));
    });
  });

  group('the screen', () {
    testWidgets('a first read that failed keeps the full-screen error',
        (tester) async {
      await _mount(tester, answer: (path) {
        if (path.contains('/portfolio')) {
          return Future.value(http.Response('boom', 500));
        }
        return _ok(_body(path, photos: 3, limit: 5));
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('stale-gallery')), findsNothing,
          reason: 'a first read has no photos to keep');
      expect(find.byType(SkeletonGrid), findsNothing,
          reason: 'a settled first read is an error, not a shimmer');
      // A body-less 500 is diagnosed as `errUnexpected` by `errorCopy`, and
      // the copy is asserted from the app's own constant rather than a guessed
      // sentence: a test that names words the app never prints is vacuous in
      // the worst way, because it fails for a reason that has nothing to do
      // with the defect. A *first* read failing with no rows is the state that
      // has to stay loud, and loud is whatever `S.errUnexpected` says.
      // A body-less 500 is diagnosed as `S.errServer` by `errorCopy`, and the
      // copy is asserted **from the app's own constant** rather than a guessed
      // sentence. This file's first version guessed `S.errUnexpected` and
      // failed: a test that names words the app never prints is vacuous in the
      // worst way, because it fails for a reason that has nothing to do with
      // the defect. A *first* read failing with no rows is the state that has
      // to stay loud, and loud is whatever the shared copy says.
      expect(find.textContaining(S.errServer), findsWidgets,
          reason: 'the failure is still said out loud');
    });

    testWidgets('a failed RE-READ keeps the photos and says they may be old',
        (tester) async {
      var reads = 0;
      await _mount(tester, answer: (path) {
        if (path.contains('/portfolio')) {
          reads++;
          if (reads > 1) return Future.value(http.Response('boom', 500));
        }
        return _ok(_body(path, photos: 3, limit: 5));
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const Key('stale-gallery')), findsNothing);

      await tester.tap(find.byTooltip('تحديث'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('stale-gallery')), findsOneWidget,
          reason: 'the photos under it are real, so it is a band not an error');
      expect(find.byType(SkeletonGrid), findsNothing,
          reason: 'a failed re-read must not shimmer over the work');
      // The grid itself: three photos plus the add tile.
      expect(find.byType(GridView), findsOneWidget);
      // `portfolioCountLineAr` prints Arabic-Indic digits, so the header is
      // «٣ صور في معرض أعمالك» — the count on screen is still the count the
      // server sent, which is the thing a blanked screen used to destroy.
      expect(find.textContaining(portfolioCountLineAr(3)), findsOneWidget,
          reason: 'the header still counts the photos on screen');
    });

    testWidgets('a PENDING re-read keeps the photos on screen', (tester) async {
      var reads = 0;
      final held = Completer<http.Response>();
      await _mount(tester, answer: (path) {
        if (path.contains('/portfolio')) {
          reads++;
          if (reads > 1) return held.future;
        }
        return _ok(_body(path, photos: 3, limit: 5));
      });
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('تحديث'));
      // Pump frames but do **not** settle: the second read is still open.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(SkeletonGrid), findsNothing,
          reason: 'the user pressed refresh and did nothing wrong');
      expect(find.byType(GridView), findsOneWidget,
          reason: 'the photos do not wait for a round trip to be visible');
      expect(find.byKey(const Key('stale-gallery')), findsNothing,
          reason: 'nothing has failed yet, so nothing is claimed');

      held.complete(http.Response('boom', 500));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const Key('stale-gallery')), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  // The change is visual, so a widget assertion that a Key is absent is not
  // enough: the claim a contractor would make is «the photos are still there
  // AND the screen says they might be old», and only a capture of the real
  // widget tree answers it. Both states are shot — a one-sided capture passes
  // just as happily on a band that never draws.
  group('the pixels', () {
    testWidgets('the band above a gallery that kept its photos',
        (tester) async {
      var reads = 0;
      final key = GlobalKey();
      await _mount(tester, answer: (path) {
        if (path.contains('/portfolio')) {
          reads++;
          if (reads > 1) return Future.value(http.Response('boom', 500));
        }
        return _ok(_body(path, photos: 3, limit: 5));
      }, boundary: key);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('تحديث'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The band is on screen and the grid is too — that is the whole claim.
      expect(find.byKey(const Key('stale-gallery')), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);

      await _shoot(tester, key, '26_gallery_stale');
    });
  });
}

/// Writes the real widget tree to `/tmp/shots/<name>.png`.
///
/// The same `repaintBoundary` -> PNG mechanism `design_shots_test.dart` and
/// `portfolio_allowance_shot_test.dart` already use, at 392x850 — the
/// narrowest column the app lays out for, so a band that overflows here would
/// be visible rather than inferred.
Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
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
  // ignore: avoid_print
  print('SHOT $path');
}
