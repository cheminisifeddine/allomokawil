// The contractor's own header, and the one sentence it must never print on a
// failed read.
//
// Found on 27 Sep 2026, the fourth screen in the "a failed read is published as
// a settled one" family. The other three hid a photo count or, at worst, made
// a false claim about demand. This one is worse on a different axis, and it is
// the first defect in this family that does not merely *say* the wrong thing —
// it **removes the navigation**:
//
//   final loading = profile != null && snap.connectionState != done;
//   final worker = snap.data;                       // null on error AND on
//                                                    // a not-yet-answered read
//   if (loading) …_skeletonRows()
//   else if (worker == null && guest) …_guestBody(context)
//   else if (worker == null) Text('تعذّر جلب ملفك')   // ← the dead end
//   else … _identity / _StatsLine / _ToolStrip / _PlanEntry
//
// One 500 on `GET /api/mobile/my/profile` and `worker` is null, so a signed-in
// contractor loses **all four** of the things that header exists to hold:
//
//   * his name and specialty — the identity row, so the app opens anonymously;
//   * his stats line (experience, completed jobs, reviews);
//   * his three tool tiles — «معرض أعمالي», «المستندات», «ملفي المهني» — and so
//     the whole contractor half of the product: he cannot upload the work he
//     did, cannot see where his verification papers stand, cannot edit his
//     commercial profile;
//   * his subscription row («بقي عرضان من 3 عروض هذا الشهر»), the only place a
//     paying contractor can see his plan.
//
// Every one of those is gated on `worker != null` (lines 616, 691, 694, 704), so
// the single read that failed is the single read that decides all of them.
//
// The sentence itself is the dead end that the rest of this backlog has been
// closing for weeks: «تعذّر جلب ملفك» is printed as a bare `Text` with **no
// button at all**, inside a navy card, on a `CustomScrollView` that has no
// `RefreshIndicator`. The contractor's only recovery — leave the tab, come
// back — is the one thing the UI gives him no affordance for and no prompt to
// do. Four taps to reach «حسابي» → «ملفي المهني», and nothing on screen says
// that is possible.
//
// The market feed right below it, read by the same widget tree, *does* have
// this fixed: `snap.hasError` → `EmptyView` with `onAction: _reload`. This
// header is the only read on the screen that never learned it, and it is the
// read that gates the most.
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

Map<String, Object?> _user(String type) => {
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

const _worker = {
  'id': 16,
  'user_id': 31,
  'bio': 'دهان وديكور',
  'specialties': ['painting'],
  'experience_years': 5,
  'price_range_min': 20000,
  'price_range_max': 60000,
  'service_radius_km': 30,
  'is_available': 1,
  'is_identity_verified': 1,
  'is_certificate_verified': 0,
  'verification_status': 'verified',
  'subscription_plan': 'free_trial',
  'avg_rating': 0.0,
  'total_reviews': 0,
  'total_completed_jobs': 0,
  'response_time_hours': 2,
  'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة',
  'phone': '077442495',
  'user_wilaya': '16',
  'avatar_url': null,
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape the API
/// client turns into an [ApiException] rather than into an empty profile.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
        headers: {'content-type': 'text/html'});

/// Boots a signed-in contractor against a fake API whose `my/profile` answers
/// [profile], logging every request so a test can count the reads.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required http.Response Function() profile,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(
            <String, Object?>{'token': 'tok', 'user': _user('worker')});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/api/mobile/my/profile')) return profile();
      if (p.endsWith('/api/mobile/my/subscription')) {
        return _json(<String, Object?>{
          'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
          'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
          'payment': <String, Object?>{'methods': <Object?>[]},
        });
      }
      if (p.endsWith('/portfolio')) return _json(<Object>[]);
      if (p.endsWith('/documents')) return _json(<Object>[]);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'worker', reason: 'the fixture must land on the pro');
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 2200),
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

/// Bounded pumps: the loading skeleton animates forever, so pumpAndSettle
/// would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Renders the screen to a PNG so a layout claim about the failure state can be
/// looked at rather than asserted about.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 1100),
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
      home: RepaintBoundary(key: key, child: const WorkerHomeScreen()),
    ),
  ));
  await _settle(tester);

  final target = find.text('تعذّر جلب ملفك');
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
  }

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

void main() {
  // Cairo, so the Arabic in the capture below is real glyphs, not boxes.
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  testWidgets('a failed header read never prints the dead-end sentence alone',
      (tester) async {
    final s = await _boot(profile: _boom);
    await _pump(tester, s.api, s.auth);

    // The failure is stated, not implied by a missing name.
    expect(find.text('تعذّر جلب ملفك'), findsOneWidget,
        reason: 'the screen must say what happened');
    expect(find.textContaining('تعذّر'), findsWidgets);

    // And — the whole point — it is a state, not a bare sentence. Before the
    // fix this was a lone `Text` inside the navy card with no control of any
    // kind attached, on a scroll view with no pull-to-refresh.
    expect(find.byKey(const Key('worker-header-retry')), findsOneWidget,
        reason: 'a failed read must carry a retry the contractor can press');
    final retry = tester
        .widget<FilledButton>(find.byKey(const Key('worker-header-retry')));
    expect(retry.onPressed, isNotNull,
        reason: 'the retry must be a live control, not a dead label');
  });

  testWidgets('the retry re-issues the profile read, and the header comes back',
      (tester) async {
    var fail = true;
    final s = await _boot(profile: () => fail ? _boom() : _json(_worker));
    await _pump(tester, s.api, s.auth);

    final before = s.log.where((r) => r.endsWith('/my/profile')).length;
    expect(before, greaterThan(0), reason: 'the fixture must have read once');

    final retry = find.byKey(const Key('worker-header-retry'));
    await tester.ensureVisible(retry);
    await tester.pump(const Duration(milliseconds: 100));
    // The server comes back **before** the tap: `_retryProfile` issues the read
    // synchronously inside the handler, so a flag flipped afterwards would be
    // too late to be the read that button triggers.
    fail = false;
    await tester.tap(retry);
    await _settle(tester, frames: 14);

    final after = s.log.where((r) => r.endsWith('/my/profile')).length;
    expect(after, greaterThan(before),
        reason: 'the retry must issue a real request, not just redraw');

    // And the header is back: name, and the three doors that were all gone.
    expect(find.text('مقاول تجربة'), findsOneWidget);
    expect(find.byKey(const Key('worker-tools-portfolio')), findsOneWidget,
        reason: 'the gallery tile was gated on the failed read');
    expect(find.byKey(const Key('worker-tools-documents')), findsOneWidget);
    expect(find.byKey(const Key('worker-tools-edit')), findsOneWidget);
  });

  testWidgets('a successful read is untouched: no error card, tools present',
      (tester) async {
    final s = await _boot(profile: () => _json(_worker));
    await _pump(tester, s.api, s.auth);

    expect(find.textContaining('تعذّر'), findsNothing,
        reason: 'the fix must not turn a real profile into a failure');
    expect(find.text('مقاول تجربة'), findsOneWidget);
    expect(find.byKey(const Key('worker-tools-portfolio')), findsOneWidget);
    expect(find.byKey(const Key('worker-tools-edit')), findsOneWidget);
  });

  testWidgets('a signed-out visitor still gets the guest body, not an error',
      (tester) async {
    // The guest branch is the one place «no profile» is a true statement, so
    // the fix must not swallow it: a visitor has no account to read.
    final s = await _boot(profile: _boom);
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
        // `MarketplaceView` is a tab *body*, not a page: `WorkerHomeScreen`
        // supplies the Scaffold it sits in, so the test does the same.
        home: Scaffold(
            body: MarketplaceView(repo: Repository(s.api), guest: true)),
      ),
    ));
    await _settle(tester);

    expect(find.textContaining('تعذّر'), findsNothing,
        reason: 'nothing failed for a guest — he has no profile to fetch');
    expect(find.text('سوق المقاولين'), findsOneWidget);
  });

  testWidgets('a failed header read still shows the market below it',
      (tester) async {
    // The header must not take the rest of the screen down with it. A
    // contractor whose profile read 500 can still bid on the open projects.
    final s = await _boot(profile: _boom);
    await _pump(tester, s.api, s.auth);

    expect(find.text('مشاريع مفتوحة للعروض'), findsOneWidget,
        reason: 'the feed is a separate read and must survive');
  });

  testWidgets('the failure state rasterises with its retry visible',
      (tester) async {
    final s = await _boot(profile: _boom);
    final path =
        await _shoot(tester, 'worker_header_read_failed', s.api, s.auth);
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });
}
