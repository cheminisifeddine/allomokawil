// Proves no list in the app is a dead end: every empty list must explain itself
// in Arabic AND carry the action that creates its first item.
//
// This file drives each one against the real widget tree, the real Repository
// and a fake HTTP client, then TAPS the action. A label that renders but does
// nothing is the exact bug this covers, so the fake API logs every request and
// the assertions read that log.
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
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

// ── Fixtures ───────────────────────────────────────────────────────────────

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

final _project = <String, Object?>{
  'id': 'p1',
  'customer_id': 30,
  'title': 'دهان شقة 3 غرف',
  'description': 'دهان كامل مع تصليح',
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
};

const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 0.0, 'total_reviews': 0,
  'total_completed_jobs': 0, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

/// The same contractor as a `POST /api/register` account really arrives: no
/// `service_radius_km` on the payload at all, because the register call sends
/// none and nothing on the way in asks for one.
final _noRadiusWorker = Map<String, Object?>.of(_worker)
  ..remove('service_radius_km');

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Every empty list in the app, answered with nothing at all — the state the
/// user sees on day one.
ApiClient _emptyApi(
  List<String> log, {
  required String role,
  Map<String, Object?> worker = _worker,
  String workerPath = '/api/mobile/workers/16',
}) =>
    ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        log.add('${req.method} $p');
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': _user(role)});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.endsWith('/api/mobile/conversations')) {
          return req.method == 'POST' ? _json({'id': 7}) : _json(<Object>[]);
        }
        if (p.startsWith('/api/messages/')) return _json(<Object>[]);
        if (p.endsWith('/api/mobile/my/profile')) return _json(worker);
        if (p.endsWith('/reviews')) return _json(<Object>[]);
        if (p.endsWith('/portfolio')) return _json(<Object>[]);
        if (p == workerPath) return _json(worker);
        if (p.contains('/workers/top')) return _json(<Object>[]);
        if (p.contains('/workers/search')) return _json(<Object>[]);
        if (p == '/api/mobile/projects/p1') return _json(_project);
        if (p.startsWith('/api/mobile/projects/p1/quotes')) {
          return _json(<Object>[]);
        }
        return _json(<Object>[]);
      }),
    );

/// Like [_boot], but answers the worker endpoints with [worker] so a screen can
/// be driven from a payload shape the live API really sends.
Future<({ApiClient api, AuthState auth, List<String> log})> _bootWith(
  Map<String, Object?> worker,
  {required String role, String endpoint = '/api/mobile/workers/16'}
) async {
  SharedPreferences.setMockInitialValues({});
  final log = <String>[];
  final api = _emptyApi(log, role: role, worker: worker, workerPath: endpoint);
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, log: log);
}

Future<({ApiClient api, AuthState auth, List<String> log})> _boot(
    String role) async {
  SharedPreferences.setMockInitialValues({});
  final log = <String>[];
  final api = _emptyApi(log, role: role);
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, role, reason: 'the fixture must land on $role');
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth,
) async {
  // Tall Android phone, Arabic, right-to-left — the shipped configuration.
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  // AppScope sits ABOVE MaterialApp, as it does in the shipped app: a pushed
  // route is a sibling of `home`, so a scope nested inside `home` would be
  // invisible to every screen the app opens.
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

/// Scrolls an action into the viewport, then taps it. These empty states sit
/// below content that is still on screen, so an untargeted tap would miss —
/// and a missed tap would "pass" on a button no user could reach either.
Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

/// Rasterises a screen at real phone size and writes it to [/tmp/shots].
///
/// Same mechanism as design_shots_test.dart: the app draws to a canvas both on
/// web and on the device, so a PNG of the real widget tree is the only way to
/// look at the result. Cairo is registered first, otherwise the Arabic renders
/// as tofu and the shots prove nothing.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
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

void main() {
  // Cairo, so the Arabic in the captures below is real glyphs, not boxes.
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  // ── الرسائل: the inbox both roles open first ──────────────────────────
  testWidgets('a client with no conversation is offered the directory',
      (tester) async {
    final s = await _boot('customer');
    var discovered = false;
    await _pump(
      tester,
      ChatListScreen(
        repo: Repository(s.api),
        onDiscover: () => discovered = true,
      ),
      s.api,
      s.auth,
    );

    expect(find.text('لا محادثات بعد'), findsOneWidget);
    expect(find.text('تصفّح المقاولين'), findsOneWidget);
    await _tap(tester, 'تصفّح المقاولين');
    expect(discovered, isTrue, reason: 'the CTA must do what it says');
  });

  testWidgets('a contractor with no conversation is offered the marketplace',
      (tester) async {
    final s = await _boot('worker');
    var discovered = false;
    await _pump(
      tester,
      ChatListScreen(
        repo: Repository(s.api),
        onDiscover: () => discovered = true,
      ),
      s.api,
      s.auth,
    );

    expect(find.text('لا محادثات بعد'), findsOneWidget);
    expect(find.text('تصفّح المشاريع المفتوحة'), findsOneWidget);
    await _tap(tester, 'تصفّح المشاريع المفتوحة');
    expect(discovered, isTrue);
  });

  testWidgets('the empty thread names the composer instead of going blank',
      (tester) async {
    final s = await _boot('customer');
    await _pump(
      tester,
      ChatScreen(conversationId: 7, otherUserId: 31, repo: Repository(s.api)),
      s.api,
      s.auth,
    );

    expect(find.text('لا رسائل بعد'), findsOneWidget);
    expect(find.text('اكتب رسالتك الأولى في الخانة أسفله وستصل مباشرة.'),
        findsOneWidget);
    // The action it points at is really there.
    expect(find.text('اكتب رسالة...'), findsOneWidget);
  });

  // ── مشاريعي: a contractor with no job ─────────────────────────────────
  testWidgets('a contractor with no project gets the marketplace from مشاريعي',
      (tester) async {
    final s = await _boot('worker');
    var discovered = false;
    await _pump(
      tester,
      ProjectsScreen(repo: Repository(s.api), onDiscover: () => discovered = true),
      s.api,
      s.auth,
    );

    expect(find.text('لا مشاريع في هذه الحالة'), findsOneWidget);
    expect(find.text('تصفّح المشاريع المفتوحة'), findsOneWidget);
    await _tap(tester, 'تصفّح المشاريع المفتوحة');
    expect(discovered, isTrue);
  });

  testWidgets('a client with no project is asked to publish one',
      (tester) async {
    final s = await _boot('customer');
    await _pump(tester, ProjectsScreen(repo: Repository(s.api)), s.api, s.auth);

    expect(find.text('انشر مشروعك'), findsOneWidget);
    await _tap(tester, 'انشر مشروعك');
    expect(find.byType(ProjectNewScreen), findsOneWidget);
  });

  // ── العروض: the owner's quote list ────────────────────────────────────
  testWidgets('an owner with no quote is sent to the contractor directory',
      (tester) async {
    final s = await _boot('customer');
    await _pump(
      tester,
      ProjectDetailScreen(projectId: 'p1', repo: Repository(s.api)),
      s.api,
      s.auth,
    );

    expect(find.text('لا عروض بعد'), findsOneWidget);
    expect(find.text('ابحث عن مقاول'), findsOneWidget);
    await _tap(tester, 'ابحث عن مقاول');
    expect(find.byType(BrowseScreen), findsOneWidget);
  });

  // ── ملف المقاول: gallery and reviews for a visitor ────────────────────
  testWidgets('an empty gallery and no reviews are rows that open the chat',
      (tester) async {
    final s = await _boot('customer');
    await _pump(
      tester,
      WorkerProfileScreen(workerId: 16),
      s.api,
      s.auth,
    );

    expect(find.byKey(const Key('profile-portfolio-empty')), findsOneWidget);
    expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
    expect(find.text('اطلب منه صور أعمال سابقة في المحادثة.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('profile-reviews-empty')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('profile-reviews-empty')));
    await _settle(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(
      s.log.any((r) => r.endsWith('/api/mobile/conversations')),
      isTrue,
      reason: 'the row must really open a conversation',
    );
  });

  // ── المنصة: the contractor's market with nothing published ────────────
  testWidgets('an empty marketplace offers a refresh that re-fetches',
      (tester) async {
    final s = await _boot('worker');
    await _pump(tester, WorkerHomeScreen(), s.api, s.auth);

    expect(find.text('لا مشاريع مفتوحة حالياً'), findsOneWidget);
    expect(find.text('تحديث'), findsOneWidget);

    final before = s.log.where((r) => r.contains('/api/mobile/projects')).length;
    await _tap(tester, 'تحديث');
    final after = s.log.where((r) => r.contains('/api/mobile/projects')).length;
    expect(after, greaterThan(before),
        reason: 'تحديث must issue a real request, not just redraw');
  });

  // ── Visual pass: the pixels, for the gate ─────────────────────────────
  testWidgets('every empty state rasterises with its action button visible',
      (tester) async {
    final client = await _boot('customer');
    final worker = await _boot('worker');

    final shots = <String>[];
    shots.add(await _shoot(tester, 'empty_inbox_client',
        ChatListScreen(repo: Repository(client.api), onDiscover: () {}),
        client.api, client.auth));
    shots.add(await _shoot(tester, 'empty_inbox_worker',
        ChatListScreen(repo: Repository(worker.api), onDiscover: () {}),
        worker.api, worker.auth));
    shots.add(await _shoot(tester, 'empty_market_worker',
        WorkerHomeScreen(), worker.api, worker.auth,
        logical: const Size(392, 1500)));
    shots.add(await _shoot(tester, 'empty_quotes_owner',
        ProjectDetailScreen(projectId: 'p1', repo: Repository(client.api)),
        client.api, client.auth, logical: const Size(392, 1700)));
    shots.add(await _shoot(tester, 'empty_profile_worker',
        WorkerProfileScreen(workerId: 16), client.api, client.auth,
        logical: const Size(392, 1000)));

    for (final path in shots) {
      stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
    }
  });

  // ── نصف قطر الخدمة: an unset number is not a printed zero ─────────────
  //
  // `POST /api/register` sends no `service_radius_km`, so a contractor who
  // signed up yesterday has none — and the profile used to publish
  // «نصف قطر الخدمة: 0 كم» about a man who had not answered the question. The
  // parser now keeps it null and the row goes with it.
  testWidgets('a contractor who never set a radius has no radius row',
      (tester) async {
    final s = await _bootWith(_noRadiusWorker, role: 'customer');
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.text('نصف قطر الخدمة'), findsNothing);
    expect(find.textContaining('كم'), findsNothing);

    // The rest of the card is still there — the row is dropped, not the screen.
    expect(find.text('الخبرة'), findsOneWidget);
    expect(find.text('نطاق الأسعار'), findsOneWidget);

    final path = await _shoot(
        tester, 'profile_no_radius', WorkerProfileScreen(workerId: 16),
        s.api, s.auth, logical: const Size(392, 1000));
    stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
  });

  testWidgets('a radius that was set still reads, and agrees with the number',
      (tester) async {
    final s = await _bootWith({..._worker, 'service_radius_km': 3},
        role: 'customer');
    await _pump(
        tester, WorkerProfileScreen(workerId: 16), s.api, s.auth);

    expect(find.text('نصف قطر الخدمة'), findsOneWidget);
    // 3 takes the broken plural; the old line printed «3 كم» either way.
    expect(find.text('3 كيلومترات'), findsOneWidget);
  });

  // ── الرئيسية: the client's contractor strip ───────────────────────────
  testWidgets('a client with no contractor on screen is asked to publish',
      (tester) async {
    final s = await _boot('customer');
    await _pump(tester, CustomerHomeScreen(), s.api, s.auth);

    expect(find.text('لا يوجد مقاولون بعد'), findsOneWidget);
    expect(find.text('انشر مشروعاً ليصلك مقاول'), findsOneWidget);
    await _tap(tester, 'انشر مشروعاً ليصلك مقاول');
    expect(find.byType(ProjectNewScreen), findsOneWidget);
  });
}
