// A contractor's profile is the page a customer picks him from, and two of its
// sections — the gallery and the reviews — are the only evidence he has work.
// Both used to answer a *failed* fetch with a sentence asserting he has none:
//
//   _PortfolioGrid:  final urls = snap.data ?? const <String>[];
//   _ReviewsSection: final list  = snap.data ?? const <Review>[];
//
// `snap.data` is null on error exactly as it is on an empty list, so a 500 —
// or a dropped connection, or the one host that holds the photos not answering
// — printed «لم يضف صوراً بعد» and «لا تقييمات بعد» on a man with 12 photos and
// 40 five-star reviews. The customer scrolling his profile reads that as a fact
// and picks somebody else. Same class of lie the «نصف قطر الخدمة: 0 كم» row
// used to publish, one layer down.
//
// Worse, the lie was permanent. `_reviews` and `_portfolio` are `late final`,
// assigned once in `didChangeDependencies`; the screen's only retry, `_retry()`,
// re-fetches `_profile` alone. The one action a user has when a section fails
// re-renders the header and leaves both sections stuck on their first answer
// until he leaves the page and comes back.
//
// This file drives the real screen, the real Repository and a fake HTTP client
// that fails the way the live one does, and asserts both halves: the section
// says the fetch failed, and the retry it offers really re-issues the request.
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

const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.8, 'total_reviews': 2,
  'total_completed_jobs': 12, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

const _review = {
  'id': 5,
  'customer_id': 30,
  'worker_id': 16,
  'project_id': 'p1',
  'rating': 5,
  'comment': 'شغل نظيف وسريع',
  'customer_full_name': 'زبون تجربة',
  'created_at': '2026-09-11 21:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive portal / Worker crash shape the API
/// client turns into an [ApiException] carrying the Arabic 500 copy.
http.Response _boom() => http.Response('<html>Internal Server Error</html>', 500,
    headers: {'content-type': 'text/html'});

/// Boots a signed-in client against a fake API whose `/portfolio` and
/// `/reviews` calls answer whatever [portfolio] and [reviews] return, and logs
/// every request so a test can prove a retry re-issued one.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required http.Response Function() portfolio,
  required http.Response Function() reviews,
  http.Response Function()? profile,
}) async {
  SharedPreferences.setMockInitialValues({});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json({
          'token': 'tok',
          'user': {
            'id': 30,
            'phone': '0773000000',
            'email': null,
            'full_name': 'زبون تجربة',
            'type': 'customer',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/portfolio')) return portfolio();
      if (p.endsWith('/reviews')) return reviews();
      if (p == '/api/mobile/workers/16') {
        return (profile ?? () => _json(_worker))();
      }
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth,
) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

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
      home: screen,
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeletons animate forever, so pumpAndSettle
/// would never return.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<String> _shoot(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 1000),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

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
      home: RepaintBoundary(key: key, child: screen),
    ),
  ));
  await _settle(tester);

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

/// Scrolls an action into the viewport, then taps it. The error state is a
/// centred column that can sit below the fold, so an untargeted tap would miss
/// — and a missed tap would "pass" on a button no user could reach either.
Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  // ── The gallery ──────────────────────────────────────────────────────────
  testWidgets('a failed gallery is never reported as an empty one',
      (tester) async {
    final s = await _boot(portfolio: _boom, reviews: () => _json([_review]));
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    // The claim that must NOT be on screen: he has no photos.
    expect(find.byKey(const Key('profile-portfolio-empty')), findsNothing,
        reason: 'a failed fetch is not an empty gallery — this sentence is '
            'about a man who really does have the photos');
    expect(find.text('لم يضف صوراً بعد'), findsNothing);

    // The truth, and a way out of it.
    expect(find.byKey(const Key('profile-portfolio-error')), findsOneWidget);
    expect(find.text('تعذّر تحميل معرض الأعمال'), findsOneWidget);
  });

  // ── The reviews ──────────────────────────────────────────────────────────
  testWidgets('a failed review list is never reported as no reviews',
      (tester) async {
    final s = await _boot(
        portfolio: () => _json(['https://cdn.test/a.jpg']), reviews: _boom);
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.byKey(const Key('profile-reviews-empty')), findsNothing,
        reason: '«لا تقييمات بعد» on a 500 is a lie about his reputation');
    expect(find.text('لا تقييمات بعد'), findsNothing);

    expect(find.byKey(const Key('profile-reviews-error')), findsOneWidget);
    expect(find.text('تعذّر تحميل التقييمات'), findsOneWidget);
  });

  // ── Both at once, which is what one dead host looks like ─────────────────
  testWidgets('both sections report the failure, and the header still renders',
      (tester) async {
    final s = await _boot(portfolio: _boom, reviews: _boom);
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    // The rest of the profile is intact — the screen is degraded, not broken.
    expect(find.byKey(const Key('profile-portfolio-error')), findsOneWidget);
    expect(find.byKey(const Key('profile-reviews-error')), findsOneWidget);
    expect(find.text('مقاول تجربة'), findsOneWidget);
    expect(find.text('الخبرة'), findsOneWidget);
  });

  // ── The half that was permanent: the retry must really re-fetch ──────────
  testWidgets('the retry in a failed section re-issues that request',
      (tester) async {
    var portfolioDown = true;
    final s = await _boot(
      portfolio: () => portfolioDown ? _boom() : _json(['https://cdn.test/a.jpg']),
      reviews: () => _json([_review]),
    );
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.byKey(const Key('profile-portfolio-error')), findsOneWidget);

    // The host comes back. Tapping the section's own retry must re-ask.
    portfolioDown = false;
    final before = s.log.where((r) => r.endsWith('/portfolio')).length;

    final retry = find.byKey(const Key('profile-portfolio-retry'));
    expect(retry, findsOneWidget, reason: 'a failed section needs its own action');
    await tester.ensureVisible(retry);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(retry);
    await _settle(tester);

    final after = s.log.where((r) => r.endsWith('/portfolio')).length;
    expect(after, greaterThan(before),
        reason: 'the action must issue a real request, not just redraw');
    expect(find.byKey(const Key('profile-portfolio-error')), findsNothing);
  });

  // ── The header's own retry must drag the sections with it ───────────────
  //
  // `_reviews` and `_portfolio` are `late final`, assigned once in
  // `didChangeDependencies`, while `_retry()` re-fetches `_profile` alone. So
  // a user who opened the page on the header's error state, watched the whole
  // profile come back, and then scrolled to a gallery that had failed a moment
  // earlier was shown the old answer forever. One retry, one page: the three
  // reads are the same page.
  testWidgets('retrying the header also re-fetches the sections', (tester) async {
    var down = true;
    final s = await _boot(
      portfolio: () => down ? _boom() : _json(['https://cdn.test/a.jpg']),
      reviews: () => _json([_review]),
      // The host that holds this contractor is down when the page opens and
      // back when the user presses the retry.
      profile: () => down ? _boom() : _json(_worker),
    );
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    // Opens on the header's error state, with nothing else rendered yet.
    expect(find.text('تعذّر تحميل الملف'), findsOneWidget);
    down = false;
    final portfoliosBefore =
        s.log.where((r) => r.endsWith('/portfolio')).length;
    final reviewsBefore = s.log.where((r) => r.endsWith('/reviews')).length;

    await _tap(tester, 'إعادة المحاولة');
    await _settle(tester);

    // The profile recovered...
    expect(find.text('تعذّر تحميل الملف'), findsNothing);
    expect(find.text('مقاول تجربة'), findsOneWidget);
    // ...and so did the two sections that failed with it, rather than
    // re-reading the futures captured before the host came back.
    expect(s.log.where((r) => r.endsWith('/portfolio')).length,
        greaterThan(portfoliosBefore));
    expect(s.log.where((r) => r.endsWith('/reviews')).length,
        greaterThan(reviewsBefore));
    expect(find.byKey(const Key('profile-portfolio-error')), findsNothing);
    expect(find.byKey(const Key('profile-reviews-error')), findsNothing);
  });

  // ── A section retry must not drag the rest of the page down ─────────────
  testWidgets('retrying one section leaves the other alone', (tester) async {
    var portfolioDown = true;
    final s = await _boot(
      portfolio: () => portfolioDown ? _boom() : _json(['https://cdn.test/a.jpg']),
      reviews: () => _json([_review]),
    );
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.byKey(const Key('profile-reviews-error')), findsNothing);
    final reviewsBefore = s.log.where((r) => r.endsWith('/reviews')).length;

    portfolioDown = false;
    final retry = find.byKey(const Key('profile-portfolio-retry'));
    await tester.ensureVisible(retry);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(retry);
    await _settle(tester);

    expect(s.log.where((r) => r.endsWith('/reviews')).length,
        reviewsBefore,
        reason: 'recovering the gallery must not re-read a list that was fine');
  });

  // ── An empty gallery is still an empty gallery ──────────────────────────
  testWidgets('a genuinely empty gallery still says he has no photos',
      (tester) async {
    final s = await _boot(
        portfolio: () => _json(<Object>[]),
        reviews: () => _json([_review]));
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.byKey(const Key('profile-portfolio-empty')), findsOneWidget);
    expect(find.text('لم يضف صوراً بعد'), findsOneWidget);
    expect(find.byKey(const Key('profile-portfolio-error')), findsNothing,
        reason: 'an empty list is not a failure and must not be dressed as one');
  });

  // ── A genuinely empty review list still says it ─────────────────────────
  testWidgets('a genuinely empty review list still says no reviews',
      (tester) async {
    // **The header has to agree for this to be the honest empty state.**
    // `_worker` carries `avg_rating: 4.8, total_reviews: 2`, so pairing it
    // with an empty list is the contradiction `reviews_section_copy.dart`
    // exists for — the screen now refuses to say «لا تقييمات بعد» over it,
    // which is correct. This test means "he has no reviews", so the profile it
    // loads has to mean that too.
    //
    // It asserted `findsOneWidget` on the old screen because the screen drew
    // the contradiction: a man rated twice, described as never rated. The test
    // passed by pinning the defect.
    final s = await _boot(
        portfolio: () => _json(['https://cdn.test/a.jpg']),
        reviews: () => _json(<Object>[]),
        profile: () => _json(<String, Object?>{
              ..._worker,
              'avg_rating': 0,
              'total_reviews': 0,
            }));
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
    expect(find.text('لا تقييمات بعد'), findsNWidgets(2),
        reason: 'header pill and empty section say the same thing — the '
            'duplicate is the agreement, not a defect');
    expect(find.byKey(const Key('profile-reviews-error')), findsNothing);
  });

  // ── A failed review list is not re-answered with a half-truth either ────
  testWidgets('a failed section offers a retry, not the contact prompt',
      (tester) async {
    final s = await _boot(
        portfolio: () => _json(['https://cdn.test/a.jpg']), reviews: _boom);
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    // «ابدأ بالتواصل معه» is advice for an empty list. On a failure the user
    // cannot tell there are no ratings, so the row must not tell him to go
    // start a conversation as though a rating were the thing missing.
    expect(find.text('التقييم يُكتب بعد إنجاز العمل — ابدأ بالتواصل معه.'),
        findsNothing);
  });

  // ── The pixels, for the gate ────────────────────────────────────────────
  testWidgets('a profile with both sections failed rasterises', (tester) async {
    final s = await _boot(portfolio: _boom, reviews: _boom);
    final path = await _shoot(
        tester, 'profile_sections_failed',
        WorkerProfileScreen(workerId: 16), s.api, s.auth,
        logical: const Size(392, 1400));
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });

  testWidgets('a profile with an empty gallery rasterises', (tester) async {
    final s = await _boot(
        portfolio: () => _json(<Object>[]),
        reviews: () => _json(<Object>[]));
    final path = await _shoot(
        tester, 'profile_sections_empty',
        WorkerProfileScreen(workerId: 16), s.api, s.auth,
        logical: const Size(392, 1400));
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });
}
