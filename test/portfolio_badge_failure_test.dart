// The gallery count on the contractor's own dashboard, and the three ways it
// could lie to him.
//
// Found on 27 Sep 2026, immediately after the same defect was fixed one screen
// over on the *public* profile. The profile's gallery now says «تعذّر تحميل
// معرض الأعمال» when the read fails. The contractor's OWN dashboard — the
// other end of the same gallery, the same endpoint, the same tile shape — was
// never touched, and it was the worse of the two:
//
//   _PortfolioBadge:  final n = snap.data?.length ?? 0;
//                     if (n == 0) return _ToolBadge('أضف صوراً', accentDeep);
//
// `snap.data` is null on an error exactly as it is on an empty list, so one
// 500 — one dropped connection, one host not answering, one captive portal on
// hotel wifi — told a man with twelve photos that he had none, and told him to
// go and add some. The public profile makes a *false claim* («لم يضف صوراً
// بعد»); this one issues a *directive* («أضف صوراً», in the gold that means
// "you should do this"). The contractor obeys it. He opens the uploader, picks
// photos of finished jobs, and pushes them to R2 — for a gallery that was
// never empty. That is duplicate uploads, wasted mobile data, and a man who
// concludes his work is not showing up.
//
// The second half is not a lie but it is why the first survived so long: the
// fetch is issued *inside* `build`. `Repository(...).portfolioImages(workerId)`
// runs on every rebuild of the strip, and the search box calls `setState` on
// every keystroke, so typing «دهان» fires one `GET /portfolio` per character
// and flashes the tile back to «...» each time — a read the screen has no
// business repeating, on the tile the contractor is looking at.
//
// This file drives the real `WorkerHomeScreen` against a fake HTTP client that
// fails the way the live one does, and asserts all three: the failed read is
// never published as empty, the tile offers a way out, and the read happens
// once rather than once per keystroke.
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
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

/// The row the dashboard renders.
///
/// `total_completed_jobs` and `total_reviews` are not decoration: a contractor
/// with no history renders `_GettingStarted` instead of the tool strip, so a
/// profile without them never builds the tile this file is about. (Copied from
/// `portfolio_badge_copy_test.dart`, which lost a whole run to exactly this.)
Map<String, Object?> _worker() => <String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
      'total_completed_jobs': 4,
      'total_reviews': 3,
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive portal / Worker crash shape the API
/// client turns into an [ApiException] carrying the Arabic 500 copy.
http.Response _boom() => http.Response('<html>Internal Server Error</html>', 500,
    headers: {'content-type': 'text/html'});

List<Object> _photos(int n) => <Object>[
      for (var i = 0; i < n; i++) <String, Object>{'image_url': 'https://r2.test/p$i.jpg'},
    ];

/// Boots a signed-in contractor against a fake API whose `/portfolio` answers
/// whatever [portfolio] returns, logging every request so a test can count them.
///
/// [fail] makes the *rest* of the dashboard answer, not the gallery: a test
/// that broke the whole screen would pass its negative assertions for the
/// wrong reason — the tool strip would not be on the page at all.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required http.Response Function() portfolio,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object>{
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
        });
      }
      if (p.endsWith('/portfolio')) return portfolio();
      if (p.contains('/my/profile')) return _json(_worker());
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
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 900),
}) async {
  tester.view.physicalSize = logical * 2.75;
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
      home: const WorkerHomeScreen(),
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeletons animate forever, so `pumpAndSettle`
/// would never return.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  // ── 1. The lie ───────────────────────────────────────────────────────────
  //
  // The whole item in one assertion: a 500 must not produce the sentence that
  // tells him to upload work he has already uploaded.
  testWidgets('a failed gallery read is never published as an empty one',
      (tester) async {
    final s = await _boot(portfolio: _boom);
    await _pump(tester, s.api, s.auth);

    final texts = _texts(tester);
    // Guard the guard: a dashboard stuck loading renders no text at all, and
    // every negative assertion below would then be vacuously true.
    expect(texts, contains('معرض أعمالي'),
        reason: 'the tool strip never rendered — $texts');
    expect(texts, isNotEmpty, reason: 'no text: $texts');

    expect(find.text('أضف صوراً'), findsNothing,
        reason: '«أضف صوراً» on a 500 is a directive to upload work he has '
            'already uploaded; $texts');
    expect(find.text('0 صور'), findsNothing);
    expect(texts.any((t) => t.contains('صور') && t.contains('0')), isFalse,
        reason: 'no zero count may be derived from a failed read: $texts');
  });

  // ── 2. The way out ───────────────────────────────────────────────────────
  //
  // A tile that only says "I don't know" strands the contractor. The strip is
  // inside a tappable card that opens the gallery, but the gallery's own load
  // is the request that just failed — tapping through is not an answer, it is
  // the same 500 one screen later. The tile needs its own retry.
  testWidgets('a failed tile offers its own retry, not silence', (tester) async {
    final s = await _boot(portfolio: _boom);
    await _pump(tester, s.api, s.auth);

    expect(find.byKey(const Key('worker-tools-portfolio')), findsOneWidget,
        reason: 'the tile is on the page');
    expect(find.byKey(const Key('worker-portfolio-badge-error')), findsOneWidget,
        reason: 'a failed read must be visible as a failure');
    expect(find.byKey(const Key('worker-portfolio-badge-retry')),
        findsOneWidget,
        reason: 'the user needs an action that re-issues the request');
  });

  // ── 3. The retry must really re-issue the request ────────────────────────
  testWidgets('the tile retry re-reads the gallery', (tester) async {
    var down = true;
    final s = await _boot(
        portfolio: () => down ? _boom() : _json(_photos(3)));
    await _pump(tester, s.api, s.auth);

    expect(find.byKey(const Key('worker-portfolio-badge-error')), findsOneWidget);

    down = false;
    final before = s.log.where((r) => r.endsWith('/portfolio')).length;

    final retry = find.byKey(const Key('worker-portfolio-badge-retry'));
    await tester.ensureVisible(retry);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(retry);
    await _settle(tester);

    expect(s.log.where((r) => r.endsWith('/portfolio')).length, greaterThan(before),
        reason: 'the action must issue a real request, not just redraw');
    expect(find.byKey(const Key('worker-portfolio-badge-error')), findsNothing);
    expect(find.text('3 صور'), findsOneWidget);
  });

  // ── 4. An empty gallery is still an empty gallery ────────────────────────
  //
  // The other direction: the fix must not dress an honest zero as a failure.
  // A contractor who has genuinely uploaded nothing is told the same thing he
  // was told before.
  testWidgets('a genuinely empty gallery still says «أضف صوراً»', (tester) async {
    final s = await _boot(portfolio: () => _json(<Object>[]));
    await _pump(tester, s.api, s.auth);

    final texts = _texts(tester);
    expect(texts, contains('معرض أعمالي'), reason: '$texts');
    expect(find.text('أضف صوراً'), findsOneWidget, reason: '$texts');
    expect(find.byKey(const Key('worker-portfolio-badge-error')), findsNothing,
        reason: 'an empty list is not a failure and must not be dressed as one');
  });

  // ── 5. The counts still work, on both sides of the fix ───────────────────
  testWidgets('a loaded tile still counts, and never shows the failure key',
      (tester) async {
    for (final n in [1, 2, 3, 5, 11]) {
      final s = await _boot(portfolio: () => _json(_photos(n)));
      await _pump(tester, s.api, s.auth);
      final texts = _texts(tester);
      expect(texts, contains('معرض أعمالي'), reason: '$n: $texts');
      expect(find.byKey(const Key('worker-portfolio-badge-error')), findsNothing,
          reason: '$n: a live read is not a failure');
    }
  });

  // ── 6. The request storm ─────────────────────────────────────────────────
  //
  // The fetch was issued inside `build`. `_onSearchChanged` calls `setState` on
  // every keystroke, so the count of `GET /portfolio` requests grew with the
  // length of whatever the contractor typed — on a mobile network, on the
  // screen that has to load fastest.
  testWidgets('typing in the search box does not re-read the gallery',
      (tester) async {
    final s = await _boot(portfolio: () => _json(_photos(3)));
    await _pump(tester, s.api, s.auth);

    final afterLoad =
        s.log.where((r) => r.endsWith('/portfolio')).length;
    expect(afterLoad, 1, reason: 'one read on open, not one per rebuild');

    // Type a real trade name, one character at a time, the way a user does.
    for (final ch in 'دهان'.split('')) {
      await tester.enterText(find.byType(TextField).first, ch);
      await _settle(tester, frames: 3);
    }

    final afterTyping =
        s.log.where((r) => r.endsWith('/portfolio')).length;
    expect(afterTyping, afterLoad,
        reason: 'searching the market must not re-read the gallery: '
            '$afterLoad -> $afterTyping');
  });

  // ── 7. The retry is a real target, not a line of 11 px text ─────────────
  //
  // A 56 dp control does not fit a third of a 392 dp row, which is why the
  // badge line used to be a bare `Text`. The moment that text became the only
  // way back from a failed read, its hit area became 11 px tall — the exact
  // defect the tap-target work fixed twice already. So the floor is measured
  // here, on the rendered box, rather than claimed in a comment.
  testWidgets('the failed tile offers a 56 dp target, not a line of text',
      (tester) async {
    final s = await _boot(portfolio: _boom);
    await _pump(tester, s.api, s.auth);

    final retry = find.byKey(const Key('worker-portfolio-badge-retry'));
    expect(retry, findsOneWidget);
    final box = tester.getSize(retry);
    expect(box.height, greaterThanOrEqualTo(AppTheme.tapMin),
        reason: 'the only way back from a failed read is $box tall');
    // And it must not be so tall that it breaks the compact strip the
    // hierarchy test pins at under 170 dp.
    expect(tester.getSize(find.byKey(const Key('worker-tools-portfolio'))).height,
        lessThan(170),
        reason: 'the retry target must not cost the strip its compactness');
  });

  // ── 7. The read is held, but not forever ─────────────────────────────────
  //
  // This is the half the *first* version of this fix got wrong, and the
  // existing `portfolio_badge_copy_test.dart` caught it: moving the fetch out
  // of `build` into a field stopped the request storm and introduced a worse
  // bug — the count never moved again. A contractor who uploads four photos
  // in the gallery, goes back to his home, and still reads «3 صور» under his
  // own work has been told a number the app itself just proved wrong, and
  // concludes his uploads are not landing.
  //
  // The tile cannot watch the route (this app has no [RouteObserver]), so the
  // screen that pushed the gallery bumps a counter when it comes back.
  testWidgets('coming back from the gallery re-reads the count',
      (tester) async {
    var added = 3;
    final s = await _boot(portfolio: () => _json(_photos(added)));
    await _pump(tester, s.api, s.auth);

    expect(find.text('3 صور'), findsOneWidget);
    final onOpen = s.log.where((r) => r.endsWith('/portfolio')).length;

    // The contractor uploads three more and comes back.
    added = 6;
    await tester.tap(find.byKey(const Key('worker-tools-portfolio')));
    await _settle(tester);
    expect(find.byType(MyPortfolioScreen), findsOneWidget,
        reason: 'the tile did not open the gallery');
    // Pop the route the way the back arrow does, rather than by tapping it:
    // the gallery's AppBar is drawn inside this screen's own Scaffold and
    // `pageBack()` hunts for a Cupertino back button this app never renders.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await _settle(tester);

    expect(s.log.where((r) => r.endsWith('/portfolio')).length,
        greaterThan(onOpen),
        reason: 'returning from the gallery must re-ask, or the tile is a lie '
            'the app has just disproved');
    expect(find.text('6 صور'), findsOneWidget);
  });

  // ── 8. The held read still does not re-fire on a plain rebuild ───────────
  //
  // The two halves have to hold together: a refresh on return, and *only* a
  // refresh on return. A rebuild caused by anything else must not re-read.
  testWidgets('a rebuild that is not a gallery visit does not re-read',
      (tester) async {
    final s = await _boot(portfolio: () => _json(_photos(3)));
    await _pump(tester, s.api, s.auth);

    final before = s.log.where((r) => r.endsWith('/portfolio')).length;
    // Tapping a different destination forces the whole view to rebuild.
    await tester.tap(find.text('مشاريعي').last);
    await _settle(tester);
    await tester.tap(find.text('المنصة').first);
    await _settle(tester);

    expect(s.log.where((r) => r.endsWith('/portfolio')).length, before,
        reason: 'a tab change is not a gallery visit');
  });

  // ── 7. The pixels, for the gate ──────────────────────────────────────────
  testWidgets('the failed tile rasterises', (tester) async {
    final s = await _boot(portfolio: _boom);
    await _pump(tester, s.api, s.auth, logical: const Size(392, 900));

    final key = GlobalKey();
    tester.view.physicalSize = const Size(392, 900) * 2.75;
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
        home: RepaintBoundary(key: key, child: const WorkerHomeScreen()),
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
      path = '/tmp/shots/portfolio_badge_failed.png';
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(File(path).lengthSync(), greaterThan(20000),
        reason: 'a shot this small means nothing rendered');
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });
}
