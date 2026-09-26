// Design QA harness — renders every screen to a real PNG so the UI can be
// inspected visually instead of guessed at.
//
// Run with:  flutter test test/design_shots_test.dart
// Output:    /tmp/shots/<screen>.png
//
// Why this exists: the app renders to a canvas on web and to a device on
// Android, so neither is inspectable from CI or from a headless box. Widget
// tests already know how to build every screen against a mock API; this file
// simply also rasterises what they built. Real Cairo fonts are loaded so the
// Arabic text is legible in the captures — without that, text renders as boxes
// and the shots would be worthless for spotting colour/contrast defects.
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
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/screens/landing/landing_screen.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/profile_screen.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

// ── Golden gate ────────────────────────────────────────────────────────────
// `_shoot` below writes to /tmp so a human can look at a screen. That is not a
// regression gate: nobody but the tick that ran it ever sees /tmp. `_golden`
// asserts the same screen against a committed baseline in `test/goldens/`, so
// the default `flutter test` goes red the moment a tile loses its accent, a CTA
// drops below the fold or a row starts overflowing. Regenerate deliberately,
// after reading the diff:
//     flutter test --update-goldens test/design_shots_test.dart
// See test/goldens/README.md for why a Flutter upgrade is a regeneration.

const _outDir = '/tmp/shots';

// ── Realistic payloads (captured from the live API) ────────────────────────
const _worker = {
  'id': 16,
  'user_id': 31,
  'bio': 'دهان وديكور، خبرة طويلة في التشطيب الداخلي والخارجي',
  'specialties': ['painting', 'plaster_drywall', 'venetian_plaster'],
  'experience_years': 5,
  'price_range_min': 20000,
  'price_range_max': 60000,
  'service_radius_km': 30,
  'is_available': 1,
  'is_identity_verified': 1,
  'is_certificate_verified': 0,
  'verification_status': 'verified',
  'subscription_plan': 'free_trial',
  'avg_rating': 4.5,
  'total_reviews': 3,
  'total_completed_jobs': 7,
  'response_time_hours': 2,
  'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة',
  'phone': '077442495',
  'user_wilaya': '16',
  'avatar_url': null,
};

const _project = {
  'id': 'b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551',
  'customer_id': 30,
  'title': 'دهان شقة 3 غرف',
  'description': 'دهان كامل للشقة مع إصلاح الجدران المتضررة',
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

const _conversation = {
  'id': 5,
  'customer_id': 30,
  'worker_user_id': 31,
  'project_id': null,
  'last_message_at': '2026-09-11 20:23:47',
  'created_at': '2026-09-11 20:23:47',
  'other_user_name': 'مقاول تجربة',
  'other_user_avatar': null,
  'last_message_content': 'مرحبا، متى يمكنك البدء؟',
  'unread_count': 0,
};

const _review = {
  'id': 5,
  'project_id': null,
  'customer_id': 30,
  'worker_id': 16,
  'rating': 5,
  'comment': 'عمل ممتاز ونظيف، أنصح به بشدة',
  'images': '[]',
  'is_visible': 1,
  'created_at': '2026-09-11 20:23:50',
  'customer_full_name': 'زبون تجربة',
  'customer_avatar_url': null,
};

const _quote = {
  'id': 13,
  'project_id': null,
  'worker_id': 16,
  'amount': 75000,
  'message': 'جاهز للبدء فوراً، السعر يشمل المواد',
  'estimated_days': 5,
  'status': 'pending',
  'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45',
  'worker_full_name': 'مقاول تجربة',
  'worker_avatar_url': null,
  'worker_avg_rating': 4.5,
  'worker_total_reviews': 3,
  'worker_verification_status': 'verified',
};

const _message = {
  'id': 1,
  'conversation_id': 5,
  'sender_id': 31,
  'content': 'مرحبا، متى يمكنك البدء؟',
  'type': 'text',
  'image_url': null,
  'is_read': 1,
  'created_at': '2026-09-11 20:23:47',
};

/// Notifications exactly as the API stores them: the server writes the Arabic
/// title, the client only chooses the icon and the accent for the type.
const _notifications = [
  {
    'id': 41,
    'type': 'new_quote',
    'title': 'عرض جديد على مشروعك',
    'body': '75000 دج',
    'link': '/dashboard/projects/1',
    'is_read': 0,
    'created_at': '2026-09-13 01:12:00',
  },
  {
    'id': 40,
    'type': 'new_message',
    'title': 'رسالة جديدة',
    'body': 'جاهز للبدء فوراً، السعر يشمل المواد',
    'is_read': 0,
    'created_at': '2026-09-12 21:40:00',
  },
  {
    'id': 39,
    'type': 'quote_accepted',
    'title': 'قُبل عرضك',
    'body': 'مبارك! تم اختيارك لتنفيذ المشروع',
    'is_read': 1,
    'created_at': '2026-09-12 10:05:00',
  },
  {
    'id': 38,
    'type': 'review_received',
    'title': 'تقييم جديد',
    'body': '5/5',
    'is_read': 1,
    'created_at': '2026-09-11 09:05:00',
  },
  {
    'id': 37,
    'type': 'project_update',
    'title': 'تم نشر مشروعك',
    'body': 'دهان شقة 3 غرف',
    'is_read': 1,
    'created_at': '2026-09-10 18:44:00',
  },
];

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

ApiClient _fakeApi({
  bool emptyNotifications = false,
  /// Overrides the contractor profile the screens read back. The verification
  /// screen has more than one real state (fresh / filed / half-accepted /
  /// verified) and each one is a different screen, so a shot needs to choose.
  Map<String, Object?>? profile,
}) =>
    ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
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
        if (p.contains('/unread')) return _json({'unread': 2});
        if (p.endsWith('/notifications/read')) return _json({'unread': 0});
        if (p.contains('/notifications')) {
          return _json(emptyNotifications ? <Object>[] : _notifications);
        }
        if (p.contains('/messages')) return _json([_message]);
        if (p.contains('/reviews')) return _json([_review]);
        if (p.contains('/portfolio')) return _json(<Object>[]);
        if (p.contains('/quotes')) return _json([_quote]);
        if (p.contains('/projects/')) return _json(_project);
        if (p.endsWith('/projects') || p.contains('/my/projects')) {
          return _json([_project]);
        }
        if (p.contains('/workers/search')) return _json([_worker]);
        if (p.contains('/workers/top')) return _json([_worker]);
        if (p.contains('/workers/')) return _json(_worker);
        if (p.contains('/workers')) return _json([_worker]);
        if (p.contains('/conversations')) return _json([_conversation]);
        if (p.contains('/my/profile')) return _json(profile ?? _worker);
        return _json(<Object>[]);
      }),
    );

/// Register the real Cairo faces so Arabic renders as glyphs, not tofu.
Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  stdout.writeln(
      'FONTS: regular=${reg.lengthInBytes}b bold=${bold.lengthInBytes}b');
  expect(reg.lengthInBytes, greaterThan(10000),
      reason: 'Cairo-Regular.ttf did not load from the asset bundle');
  final loader = FontLoader('Cairo')
    ..addFont(Future.value(reg))
    ..addFont(Future.value(bold));
  await loader.load();

  // The icon font too: without it every Icon() renders as an empty square, so
  // the shots could not show whether an icon exists, is the right one, or sits
  // on a background it disappears into.
  // `flutter test` exports FLUTTER_ROOT for us, so this normally takes the
  // first branch. The fallback is only for running the file some other way,
  // and it is derived from the running Dart binary rather than hardcoded to
  // a path on one machine -- the old absolute path died with its host and
  // the shots silently stopped checking the icon font.
  //
  // resolvedExecutable is <root>/bin/cache/artifacts/engine/<plat>/flutter_tester,
  // so six .parent hops are the root. Two, as an earlier version of this
  // assumed, lands in .../artifacts/engine and looks correct right up until
  // FLUTTER_ROOT is unset -- then the icon font is missing and every Icon()
  // would silently render as a blank square.
  var root = Platform.environment['FLUTTER_ROOT'];
  root ??= File(Platform.resolvedExecutable)
      .parent // <plat>
      .parent // engine
      .parent // artifacts
      .parent // cache
      .parent // bin
      .parent
      .path; // <root>
  final icons = File('$root/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  expect(icons.existsSync(), isTrue,
      reason: 'MaterialIcons-Regular.otf not found under $root');
  final iconBytes = icons.readAsBytesSync();
  expect(iconBytes.length, greaterThan(100000),
      reason: 'the icon font looks truncated');
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconBytes.buffer))))
      .load();
  stdout.writeln('FONTS: MaterialIcons registered (${iconBytes.length}b)');
  stdout.writeln('FONTS: Cairo family registered');
}

/// Pump a screen at real phone dimensions and write it to [_outDir].
Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
  Future<void> Function(WidgetTester tester)? act,
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();

  // Capture full FlutterErrorDetails (not just the one-line summary) so the
  // written report names the exact widget that overflowed.
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
      child: AppScope(api: api, auth: auth, child: screen),
    ),
  ));

  // Let the screens' futures settle without waiting on infinite animations.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  // An optional interaction before the capture — how a state that only exists
  // after a tap (a half-picked rating) gets its own shot.
  if (act != null) {
    await act(tester);
    for (var i = 0; i < 4; i++) {
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

  // Surface any layout overflow the screen produced, with the widget chain.
  tester.takeException();
  FlutterError.onError = previous;
  if (errors.isNotEmpty) {
    File('$_outDir/$name.ERROR.txt').writeAsStringSync(
        errors.map((e) => e.toString()).join('\n════════\n'));
  }
}

/// The same screen [_shoot] captures, compared against a committed baseline.
///
/// A golden rasterises the real widget tree with the real Cairo and
/// MaterialIcons faces at a fixed 392x850 logical canvas, devicePixelRatio 1.0,
/// Arabic locale — so it pins layout and colour, which is what regresses, while
/// staying small enough that a diff image is readable.
///
/// Pixel comparison is only valid for the engine that produced the baseline, so
/// a Flutter upgrade fails every golden exactly once, on purpose: look at the
/// diff, then re-baseline. A screen that throws is failed *before* the capture,
/// otherwise the golden would pin a broken layout as correct.
/// Builds one main screen the way the app builds it, and settles it.
///
/// Shared by the pixel gate and the accessibility sweep below, so the two can
/// never disagree about what a "main screen" is: a screen added to
/// [_mainScreens] gets a baseline *and* a named-control check, or neither.
Future<GlobalKey> _pumpScreen(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
}) async {
  tester.view.physicalSize = logical;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
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
      child: AppScope(api: api, auth: auth, child: screen),
    ),
  ));

  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }

  expect(tester.takeException(), isNull,
      reason: '$name threw while building — fix the layout before re-baselining');

  return key;
}

Future<void> _golden(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
}) async {
  final key =
      await _pumpScreen(tester, name, screen, api, auth, logical: logical);
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
}

/// The nine screens a user actually lands on — one list, two gates.
///
/// It exists so neither gate can quietly stop covering a screen: the golden
/// pass and the accessibility sweep both walk *this*, and a screen that is not
/// here is in neither.
///
/// Each entry is a *builder*, not a widget: the golden pass now runs one test
/// per screen and each of those boots its own fake API, so a widget captured
/// outside that test would hold the repository of whichever test happened to
/// build the list. `_mainScreens(repo)` still works — the builder simply
/// ignores the argument it is handed when the caller already has a repo.
List<(String, Widget Function(Repository))> _mainScreens(Repository repo) => [
      ('00_landing', (_) => const LandingScreen()),
      ('01_signin', (_) => const AuthScreen(mode: AuthMode.signIn)),
      ('04_customer_home', (_) => const CustomerHomeScreen()),
      ('08_worker_home', (_) => const WorkerHomeScreen()),
      ('10_browse', (_) => const BrowseScreen()),
      // The signed-out dashboard *is* the dashboard: a visitor gets the same
      // worker home as a signed-in contractor, so the shot is the same screen.
      ('16_guest_worker', (_) => const WorkerHomeScreen()),
      (
        '12_chat',
        (r) => ChatScreen(
            conversationId: 5,
            otherUserId: 31,
            otherName: 'مقاول تجربة',
            repo: r),
      ),
      ('15_notifications', (_) => NotificationsScreen(clock: () => _pinnedClock)),
      (
        '07_project_detail',
        (r) => ProjectDetailScreen(
            projectId: _project['id'] as String, repo: r),
      ),
    ];

/// The clock every capture that shows a relative time is measured against.
///
/// Notification rows render «قبل ساعة» from the distance to *now*, so a shot
/// taken against the real clock is only correct for the hour it was taken in.
/// `15_notifications` was baselined that way and the gate went red 50 minutes
/// later on a 171 px diff — the hour, not the layout, had changed. Pinning the
/// clock makes both the PNG and the baseline time-independent.
///
/// UTC, not local: `parseServerTime` hands back an absolute instant, so only
/// the instant of `now` matters — a local `DateTime(2026, 9, 13, 3, 0)` would
/// label the rows 48 minutes old under CET and an hour and 48 under UTC, i.e.
/// the baseline would depend on the machine's timezone as well as its clock.
final DateTime _pinnedClock = DateTime.utc(2026, 9, 13, 3, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  Future<({ApiClient api, AuthState auth})> boot() async {
    SharedPreferences.setMockInitialValues({});
    final api = _fakeApi();
    final auth = AuthState(api);
    await auth.restore();
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
    return (api: api, auth: auth);
  }

  testWidgets('shots: landing + auth', (tester) async {
    final s = await boot();
    await _shoot(tester, '00_landing', const LandingScreen(), s.api, s.auth);
    await _shoot(tester, '01_signin', const AuthScreen(mode: AuthMode.signIn),
        s.api, s.auth);
    await _shoot(tester, '02_signup_client',
        const AuthScreen(mode: AuthMode.signUp), s.api, s.auth);
    await _shoot(
        tester,
        '03_signup_worker',
        const AuthScreen(mode: AuthMode.signUp, role: UserRole.worker),
        s.api,
        s.auth);
  });

  testWidgets('shots: customer', (tester) async {
    final s = await boot();
    await _shoot(
        tester, '04_customer_home', const CustomerHomeScreen(), s.api, s.auth);
    await _shoot(
        tester, '05_project_new', const ProjectNewScreen(), s.api, s.auth);
    await _shoot(tester, '06_projects', ProjectsScreen(repo: Repository(s.api)),
        s.api, s.auth);
    await _shoot(
        tester,
        '07_project_detail',
        ProjectDetailScreen(
            projectId: _project['id'] as String, repo: Repository(s.api)),
        s.api,
        s.auth);
  });

  testWidgets('shots: worker', (tester) async {
    final s = await boot();
    await _shoot(
        tester, '08_worker_home', const WorkerHomeScreen(), s.api, s.auth);
    await _shoot(tester, '09_worker_profile',
        const WorkerProfileScreen(workerId: 16), s.api, s.auth);
  });

  testWidgets('shots: browse + chat + misc', (tester) async {
    final s = await boot();
    await _shoot(tester, '10_browse', const BrowseScreen(), s.api, s.auth);
    await _shoot(tester, '11_chat_list',
        ChatListScreen(repo: Repository(s.api)), s.api, s.auth);
    await _shoot(
        tester,
        '12_chat',
        ChatScreen(
            conversationId: 5,
            otherUserId: 31,
            otherName: 'مقاول تجربة',
            repo: Repository(s.api)),
        s.api,
        s.auth);
    await _shoot(tester, '13_profile', const ProfileScreen(), s.api, s.auth);
    await _shoot(
        tester, '14_verification', const VerificationScreen(), s.api, s.auth);
    // The half-accepted dossier — identity approved, contractor card refused.
    // This is the state the all-or-nothing status flag cannot describe, and it
    // is the one that used to render as the same blank form a man who had sent
    // nothing sees. The shot is the evidence that the accepted half is named.
    await _shoot(
        tester,
        '18_verification_partial',
        const VerificationScreen(),
        _fakeApi(profile: {
          ..._worker,
          'verification_status': 'pending',
          'is_identity_verified': 1,
          'is_certificate_verified': 0,
          'verification_pending_docs': 0,
        }),
        s.auth);
    // The rating input: the unselected stars are the track the user picks
    // from, and they used to be drawn in `line` (1.22:1). This shot is the
    // evidence that `AppTheme.starEmpty` reached the widget tree.
    await _shoot(
        tester,
        '17_review',
        ReviewScreen(
            projectId: 'demo-project', workerId: 16, repo: Repository(s.api)),
        s.api,
        s.auth);
    // …and the same screen after the user picks 2 of 5: the three stars still
    // on the table have to be visible, because that is the scale they choose
    // from. Tap the second star (index 1) in the RTL row.
    await _shoot(
        tester,
        '18_review_2of5',
        ReviewScreen(
            projectId: 'demo-project', workerId: 16, repo: Repository(s.api)),
        s.api,
        s.auth,
        act: (t) => t.tap(find.byIcon(Icons.star_outline_rounded).at(1)));
  });

  // The owner's own project: the two actions he did not have before, and the
  // form the edit one opens. A client could publish a project from the app and
  // never touch it again — no fix for a typo, no way out of a project he no
  // longer wants. Both states are captured here because both are new.
  testWidgets('shots: owner edit + cancel', (tester) async {
    final s = await boot();
    // The action row sits under the quote list, so the capture scrolls to it.
    // A shot of the top of the page would prove nothing about a row 900 px
    // further down.
    await _shoot(
      tester,
      '19_project_owner_actions',
      ProjectDetailScreen(
          projectId: _project['id'] as String, repo: Repository(s.api)),
      s.api,
      s.auth,
      act: (t) async {
        for (var i = 0; i < 3; i++) {
          await t.drag(find.byType(ListView).first, const Offset(0, -320));
          await t.pump(const Duration(milliseconds: 60));
        }
      },
    );
    // The publish form in edit mode, prefilled from the project, with the
    // photos it already has shown as removable tiles above the picker.
    await _shoot(
      tester,
      '20_project_edit',
      ProjectNewScreen(
          initial: Project.fromJson({
        ..._project,
        'images': <String>['https://cdn.test/kept.jpg'],
      })),
      s.api,
      s.auth,
    );
  });

  testWidgets('shots: notifications', (tester) async {
    final s = await boot();
    await _shoot(
        tester, '15_notifications', NotificationsScreen(clock: () => _pinnedClock), s.api, s.auth);

    // The same screen with nothing in it: a brand-new account sees exactly
    // this, so the empty state has to stand on its own without any rows.
    final emptyApi = _fakeApi(emptyNotifications: true);
    final emptyAuth = AuthState(emptyApi);
    await emptyAuth.restore();
    await emptyAuth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
    await _shoot(tester, '16_notifications_empty',
        NotificationsScreen(clock: () => _pinnedClock), emptyApi, emptyAuth);
  });

  // ── The design gate ───────────────────────────────────────────────────────
  // One baseline per main screen. The /tmp shots above exist for a human to
  // look at; these exist for the suite to fail on, so a design regression is
  // caught by the gate instead of by the founder.
  //
  // One test per screen, generated from the one list.
  //
  // This used to be a single test that looped. A loop is what hid the gate:
  // `matchesGoldenFile` reports a pixel difference by throwing *asynchronously*
  // out of the running test, so the first stale baseline ended the test and
  // every screen listed after it was never compared. 12_chat has sat at 0.01%
  // for days and it is followed by 15_notifications and 07_project_detail, so
  // a green "goldens: the main screens" line was evidence of nothing at all —
  // and 07 is the screen four cycles of Arabic copy fixes have been editing.
  //
  // Splitting the loop is the fix that matches the failure mode: each golden is
  // its own test case, so a throw is scoped to its own screen, the runner
  // executes all of them, and the report names every screen that differs at
  // once. A `try`/`catch` around `expectLater` does *not* work here — the
  // failure is not delivered through the awaited future, so it lands in the
  // test zone and is still reported as an unhandled async error.
  //
  // The list is still the single source of truth: adding a screen to
  // [_mainScreens] adds its golden test here and its a11y check below.
  for (final (name, build) in _mainScreens(Repository(_fakeApi()))) {
    testWidgets('golden: $name', (tester) async {
      final s = await boot();
      await _golden(tester, name, build(Repository(s.api)), s.api, s.auth);
    });
  }

  // ── The sweep, so "every control is named" is not a hand-written list ─────
  // `a11y_semantics_test.dart` proves the nine controls the 13 Sep audit found
  // are named. This proves the rest are: it walks the semantics tree a reader
  // actually walks, over all eight main screens, and fails on any node that
  // carries a tap action yet has no name — something a reader can reach and
  // cannot describe. It reads the *tree*, not the source, so a control built
  // any way at all has to answer for itself.
  //
  // It earned its keep before it existed: reading the SDK while writing it
  // found the remember-me `Checkbox` on the sign-in screen tappable and nameless
  // (checkboxes take a `semanticLabel` and that call site passed none), which is
  // the kind of thing a nine-item hand audit misses.
  testWidgets('no main screen has a tappable node with no name',
      (tester) async {
    final handle = tester.ensureSemantics();
    final s = await boot();
    final repo = Repository(s.api);

    final silent = <String, List<String>>{};
    final silentFields = <String>[];
    for (final (name, build) in _mainScreens(repo)) {
      await _pumpScreen(tester, name, build(repo), s.api, s.auth);
      final unnamed = <String>[];
      for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
        final d = node.getSemanticsData();
        if (!d.hasAction(SemanticsAction.tap)) continue;
        // A reader takes the name from whichever channel the control used:
        // `label` (Semantics, or the visible text), `hint` (a field's
        // placeholder) or `tooltip` (an icon-only button). Empty in all three
        // is silence. Note this reads the node's *data*, not `node.label`: a
        // merged node keeps its own label empty and carries the child's in its
        // data, and the data is what the platform is handed.
        final spoken = <String>[d.label, d.hint, d.tooltip]
            .where((t) => t.trim().isNotEmpty);
        if (spoken.isNotEmpty) continue;
        final found = '$name node ${node.id} @ ${node.rect}';
        // Text fields are counted apart: see the pinned note below.
        if (d.flagsCollection.isTextField) {
          silentFields.add(found);
        } else {
          unnamed.add(found);
        }
      }
      if (unnamed.isNotEmpty) silent[name] = unnamed;
    }

    expect(silent, isEmpty,
        reason: 'a reader can reach these but cannot say what they are');

    // One box on the sign-in form has no accessible name, and no Dart API can
    // give it one: a Material text field is named only by its own decoration's
    // hint Text (`_RenderDecoration` merges the hint up; a `Semantics` wrapper
    // on the field or on its prefix icon adds a second node instead — checked
    // in this screen's own tree). Its visible label therefore has to sit above
    // the box, which is how UI-UX drew this form, or the form has to show a
    // placeholder inside it. That is a design call, filed in the backlog, so
    // the count is pinned here: a *new* nameless box fails this test.
    // The phone box on the sign-in form: still the only nameless box, and its
    // node id moved 26 -> 24 -> 20 as copy came off the forms around it. Same
    // debt, same rectangle — the entry is re-pinned, not waved through.
    expect(silentFields, <String>[
      '01_signin node 20 @ Rect.fromLTRB(0.0, 0.0, 322.0, 62.0)',
    ], reason: 'the nameless-field debt changed — fix it or re-file it');
    handle.dispose();
  });

  // The rule above catches what a rule can catch. This pins the one control it
  // found by hand, so the fix cannot rot: the remember-me `Checkbox` on the
  // sign-in screen. `Checkbox` reads `semanticLabel` into the node it makes and
  // the call site passed none, leaving the row a tappable node with nothing to
  // say — on a golden screen, so every user met it.
  testWidgets('the remember-me box on 01_signin is named and announces its state',
      (tester) async {
    final handle = tester.ensureSemantics();
    final s = await boot();
    await _pumpScreen(tester, '01_signin', const AuthScreen(mode: AuthMode.signIn),
        s.api, s.auth);

    final row = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((n) => n.getSemanticsData().label.contains('تذكرني'))
        .toList();
    expect(row, hasLength(1), reason: 'the box must be named exactly once');
    final d = row.single.getSemanticsData();
    expect(d.hasAction(SemanticsAction.tap), isTrue,
        reason: 'a reader that hears the name has to be able to change it');
    expect(d.flagsCollection.isChecked, isNotNull,
        reason: 'a tick box must announce whether it is ticked');
    handle.dispose();
  });

  // ── The flake that took the gate red ──────────────────────────────────────
  // Two tests, because one is not enough. The first proves the screen really
  // obeys an injected clock (the labels below are what the baseline pixels
  // contain, and a real clock would print «قبل 11 ساعة» instead). The second
  // proves every capture in this file still hands one in: dropping the argument
  // would not fail today, it would fail tomorrow at the top of some hour, which
  // is how a flaky gate wastes a night.
  testWidgets('the notifications labels come from the injected clock, not the hour',
      (tester) async {
    final s = await boot();
    await _shoot(tester, '15_notifications_pinned',
        NotificationsScreen(clock: () => _pinnedClock), s.api, s.auth);
    expect(find.text('قبل ساعة'), findsOneWidget,
        reason: 'row 41 is 01:12Z against the pinned 03:00Z — 1h48 ago');
    expect(find.text('أمس'), findsOneWidget,
        reason: 'row 38 is a day and a half old at the pinned clock');
    expect(find.text('قبل ساعة'), findsOneWidget);
  });

  test('every relative-time capture in this file pins the clock', () {
    // Split so this test does not find its own needle in the file it reads.
    const needle = 'Notifications' 'Screen(';
    final source = File('test/design_shots_test.dart').readAsStringSync();
    final callSites = source.split(needle).skip(1).toList();
    expect(callSites, isNotEmpty,
        reason: 'the harness stopped capturing the notifications screen');
    for (final site in callSites) {
      expect(site.substring(0, 40), contains('clock:'),
          reason: 'a capture here would drift on the hour boundary and take '
              'the whole gate red — hand the screen a fixed `clock:`');
    }
  });
}
