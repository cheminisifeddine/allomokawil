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
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/home/renia/tools/flutter';
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
        tester, '15_notifications', const NotificationsScreen(), s.api, s.auth);

    // The same screen with nothing in it: a brand-new account sees exactly
    // this, so the empty state has to stand on its own without any rows.
    final emptyApi = _fakeApi(emptyNotifications: true);
    final emptyAuth = AuthState(emptyApi);
    await emptyAuth.restore();
    await emptyAuth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
    await _shoot(tester, '16_notifications_empty', const NotificationsScreen(),
        emptyApi, emptyAuth);
  });
}
