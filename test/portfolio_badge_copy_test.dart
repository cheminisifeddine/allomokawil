// The gallery tile on the contractor's own dashboard, saying how many photos
// he has.
//
// Found on 26 Sep 2026 while auditing what the portfolio header fix left. Same
// vein, four cycles running: a count is either delegated to `arabicCounted` or
// spelled out by hand, and every hand-written one so far has been wrong.
//
// The tile built its label as a two-way branch:
//
//     label: n == 1 ? 'صورة واحدة' : '$n صور',
//
// A two-way branch has no arm for the two ranges Arabic makes mandatory, and
// both of those were wrong on a live screen:
//   * **2 → «2 صور».** The dual is «صورتان», and Arabic takes no number with
//     it, so the branch printed a number the word already carries.
//   * **11 → «11 صور».** 11 and up are counted singular — the number is what
//     makes the noun singular — so it is «11 صورة».
//
// Only 1 and 3-10 were right, which is why it survived: the two ranges anyone
// checks first are the two that worked.
//
// The counts are driven from the payload D1 actually sends and the tile is read
// off the real `WorkerHomeScreen`, because "a contractor read «11 صور»" is a
// claim about a rendered screen, not about a function's return value.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

/// The worker row the dashboard renders, trimmed to what it parses.
/// `total_completed_jobs` and `total_reviews` are not decoration: a contractor
/// with no history renders `_GettingStarted` instead of the tool strip, so a
/// profile without them never builds the tile at all. A first draft of this
/// test omitted them, every assertion below passed vacuously, and the screen
/// under test was never on the page.
Map<String, Object?> _worker() => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
      'total_completed_jobs': 4,
      'total_reviews': 3,
    };

/// The free plan's `portfolio_limit: 5` is the value that makes «5 صور» an
/// ordinary state rather than a theoretical one.
List<String> _photos(int n) => List<String>.generate(
      n,
      (i) => 'https://r2.test/p$i.jpg',
      growable: false,
    );

/// The session the sign-in endpoint answers, so `auth.user` is non-null and
/// the dashboard is not in guest mode.
Map<String, Object?> _session() => <String, Object?>{
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
        'created_at': '2026-09-11 20:00:00',
      },
    };

/// One JSON body for the endpoints the dashboard hits on the way to the tile.
String _body(String path, int count) {
  if (path.endsWith('/api/login')) return jsonEncode(_session());
  if (path.contains('/portfolio')) {
    return jsonEncode(<Object>[
      for (final url in _photos(count)) <String, Object>{'image_url': url},
    ]);
  }
  if (path.contains('/my/profile')) return jsonEncode(_worker());
  // Order matters: `/my/profile` also contains `/profile`, and a generic
  // `/workers` arm placed above it would swallow the profile request and leave
  // the dashboard with no profile at all. This cost one run of this file.
  if (path.contains('/my/profile')) return jsonEncode(_worker());
  if (path.contains('/workers/')) return jsonEncode(_worker());
  if (path.contains('/workers')) {
    return jsonEncode(<Object>[_worker(), _worker(), _worker()]);
  }
  return jsonEncode(<Object>[]);
}

void main() {
  group('the tile label takes the form the count calls for', () {
    // The deleted branch produced 'صورة واحدة' for 1 and '$n صور' for
    // everything else. These are the four arms that branch could not express.
    test('1 / 2 / 3-10 / 11+ each take their own noun', () {
      expect(photosAr(1), 'صورة');
      expect(photosAr(2), 'صورتان');
      expect(photosAr(3), '3 صور');
      expect(photosAr(10), '10 صور');
      expect(photosAr(11), '11 صورة');
      expect(photosAr(40), '40 صورة');
    });

    test('the dual is never counted with a 2 — it already says two', () {
      // The old label at n == 2 was «2 صور».
      expect(photosAr(2), isNot(contains('2 ')));
    });

    test('11+ takes the singular and never the broken plural', () {
      // The old label at n == 11 was «11 صور».
      //
      // The negative assertion is on the WHOLE word with its trailing
      // boundary, not on the three letters 'صور': 'صورة' contains 'صور' as a
      // substring, so `isNot(contains('صور'))` forbids the very string this
      // fix is trying to produce. A one-directional mirror like that does not
      // just miss the defect, it asserts the opposite of the intent.
      for (final n in [11, 40, 101]) {
        expect(photosAr(n), isNot(contains('صور ')), reason: '$n');
        expect(photosAr(n), isNot(endsWith(' صور')), reason: '$n');
        expect(photosAr(n), endsWith(' صورة'), reason: '$n');
      }
    });

    test('the singular slot is the bare form, never «صورة واحدة»', () {
      // Reusing the old branch string at 11+ would have read «11 صورة واحدة».
      expect(photosAr(11), isNot(contains('واحدة')));
      expect(photosAr(1), isNot(contains('واحدة')));
    });
  });

  group('what the dashboard tile actually renders', () {
    // Pumping the same widget type into the same tree slot reuses its State,
    // so each count carries a key derived from the count. Without it the
    // second call in a test body would keep the first call's photo list and
    // assert against stale data — a test that passes for the wrong reason.
    Future<List<String>> tile(WidgetTester tester, int count) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          return http.Response(
            _body(req.url.path, count),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      // The dashboard reads `AuthGate.isGuest(context)`, which is just
      // `auth.user == null`. A screen mounted over a bare AuthState is a
      // signed-out visitor, it never asks for a profile, and the tool strip
      // this test is about is never built — so sign in first. A first draft
      // skipped this and every assertion below passed against a page that did
      // not contain the tile at all.
      final auth = AuthState(api);
      await auth.login(phone: '0773000000', password: 'secret123');
      expect(auth.user, isNotNull, reason: 'the dashboard stayed in guest mode');

      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const WorkerHomeScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      // Guard the guard: a dashboard stuck loading renders none of this, and a
      // test that "passes" because every assertion is false is worse than no
      // test at all.
      expect(texts, isNotEmpty, reason: 'the dashboard rendered no text');
      return texts;
    }

    testWidgets('a contractor on the free plan reads «5 صور»',
        (tester) async {
      final texts = await tile(tester, 5);
      expect(texts, contains('5 صور'), reason: '$texts');
    });

    testWidgets('2 photos read «صورتان», never «2 صور»', (tester) async {
      final texts = await tile(tester, 2);
      expect(texts, contains('صورتان'), reason: '$texts');
      expect(texts.any((t) => t.contains('2 صور')), isFalse, reason: '$texts');
    });

    testWidgets('11 photos read «11 صورة», never «11 صور»', (tester) async {
      final texts = await tile(tester, 11);
      expect(texts, contains('11 صورة'), reason: '$texts');
      // The negative arm is checked word-wise: '11 صورة' contains the letters
      // 'صور', so a bare substring test would reject the correct string.
      expect(
        texts.any((t) => t.trim() == '11 صور' || t.contains('11 صور ')),
        isFalse,
        reason: '$texts',
      );
    });

    testWidgets('the whole 1 / 2 / 3-10 / 11+ range is right on the tile',
        (tester) async {
      for (final n in [1, 2, 3, 5, 10, 11, 25]) {
        final texts = await tile(tester, n);
        expect(texts, contains(photosAr(n)), reason: '$n photos: $texts');
      }
    });

    testWidgets('an empty gallery keeps its own copy and prints no count',
        (tester) async {
      final texts = await tile(tester, 0);
      expect(texts, contains('أضف صوراً'), reason: '$texts');
      expect(texts.any((t) => t.contains('0 صور')), isFalse, reason: '$texts');
    });
  });
}
