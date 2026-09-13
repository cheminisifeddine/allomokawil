// The touch-target contract: 56 dp, measured on the rendered tree — not summed
// in a comment.
//
// Why this file exists: `tool/tap_target_audit.py` can prove a *floor*. A box
// that declares 56, or a theme that raises every `IconButton`, is provable from
// source; a control whose size only layout decides is not, and a hand sum is an
// arithmetic claim rather than a measurement. A phone taps pixels. So this file
// builds the real screens against the mock API, reads the rendered rect of each
// control, and — where the effect is observable — taps the *edge* of that rect:
// a hit at the top 1 dp and the bottom 1 dp proves the whole 56 dp band takes
// the tap, which is the part a user with a thumb and bright sun actually needs.
//
// The number is the app's own `AppTheme.tapMin` (56, against Material's 48):
// the two controls this item fixed were 26 dp (the ✕ on an attached photo) and
// 30.9 dp (the «عرض الكل» action on every home strip) — the first cost the user
// a re-picked photo, the second was invisible as a target on every card band.
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
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';
import 'package:allomokawil/src/screens/landing/landing_screen.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const double _min = AppTheme.tapMin;

// ── Fixtures the screens parse (same shapes the live API returns) ──────────
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

const _notification = {
  'id': 41,
  'type': 'new_quote',
  'title': 'عرض جديد على مشروعك',
  'body': '75000 دج',
  'link': null,
  'is_read': 0,
  'created_at': '2026-09-13 01:12:00',
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

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Every non-GET the app makes, so a tap can be proved by its effect on the
/// API and not only by a rectangle change.
final List<String> writes = <String>[];

ApiClient _fakeApi({bool noNotifications = false}) => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (req.method != 'GET') {
          writes.add('${req.method} $p');
        }
        if (p.endsWith('/login') || p.endsWith('/register')) {
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
        if (p.contains('/unread')) return _json({'unread': 1});
        if (p.contains('/notifications/read')) return _json({'unread': 0});
        if (p.contains('/notifications')) {
          return _json(noNotifications ? <Object>[] : [_notification]);
        }
        if (p.contains('/messages')) return _json([_message]);
        if (p.contains('/portfolio')) return _json(<Object>[]);
        if (p.contains('/conversations')) return _json([_conversation]);
        // Order matters: '/workers/search' and '/workers/top' also contain
        // '/workers/', and the browse screen casts the body to a List — the
        // single-worker Map made the cast throw, so the screen rendered its error
        // state and the card under test was never built.
        if (p.contains('/workers/search') || p.contains('/workers/top')) {
          return _json([_worker]);
        }
        if (p.contains('/workers/')) return _json(_worker);
        if (p.contains('/workers')) return _json([_worker]);
        if (p.contains('/my/profile')) return _json(_worker);
        return _json(<Object>[]);
      }),
    );

late ApiClient api;
late AuthState auth;

Future<void> _boot({bool noNotifications = false}) async {
  SharedPreferences.setMockInitialValues({});
  writes.clear();
  api = _fakeApi(noNotifications: noNotifications);
  auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
}

/// Pump a screen at real phone dimensions (392 dp is the founder's phone,
/// 320 dp the narrowest Android this app still supports).
Future<void> _pump(WidgetTester tester, Widget screen,
    {Size size = const Size(392, 850)}) async {
  tester.view.physicalSize = size * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
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
    home: AppScope(api: api, auth: auth, child: screen),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Measure the rendered rect and print it — the number belongs in the log,
/// not only in the pass/fail.
Size _measure(WidgetTester tester, Finder f, String label) {
  final s = tester.getSize(f);
  stdout.writeln('TAP  $label: ${s.width.toStringAsFixed(1)} x '
      '${s.height.toStringAsFixed(1)} dp');
  return s;
}

void _atLeast(WidgetTester tester, Finder f, String label) {
  final s = _measure(tester, f, label);
  expect(s.height, greaterThanOrEqualTo(_min),
      reason: '$label is ${s.height.toStringAsFixed(1)} dp tall, under $_min');
  expect(s.width, greaterThanOrEqualTo(_min),
      reason: '$label is ${s.width.toStringAsFixed(1)} dp wide, under $_min');
}

/// Tap 1 dp inside the top edge of the control's own rect. A control whose
/// visible box is bigger than its hit area fails this, which is exactly the
/// bug class a source audit cannot see.
Future<void> _tapTopEdge(WidgetTester tester, Finder f) async {
  final r = tester.getRect(f);
  await tester.tapAt(Offset(r.center.dx, r.top + 1));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Rasterise the screen to /tmp/shots and return the path. A widget test that
/// only compares doubles can still be looking at a yellow-and-black overflow
/// stripe where the user sees a rating control, so the picker gets a picture.
Future<String> _shoot(WidgetTester tester, String name, Widget screen,
    {Size size = const Size(392, 850)}) async {
  tester.view.physicalSize = size * 2.75;
  tester.view.devicePixelRatio = 2.75;
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
    home: AppScope(
        api: api, auth: auth, child: RepaintBoundary(key: key, child: screen)),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
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
  group('framework controls the theme raises to 56', () {
    testWidgets('auth: back and reveal are 56 dp, not the Material 48',
        (tester) async {
      await _boot();
      await _pump(tester, const AuthScreen(mode: AuthMode.signIn));

      _atLeast(tester, find.byKey(const Key('auth-back')), 'auth back');
      _atLeast(tester, find.widgetWithIcon(IconButton, Icons.visibility_rounded),
          'reveal password');
      _atLeast(
          tester,
          find.widgetWithText(TextButton, 'إنشاء الحساب'),
          'auth switch link');
    });

    testWidgets('landing: the contractor link is 56 dp tall', (tester) async {
      await _boot();
      await _pump(tester, const LandingScreen());

      _atLeast(tester, find.byKey(const Key('landing-contractor-link')),
          'landing contractor link');
    });

    testWidgets('notifications: the empty-state action is 56 dp tall',
        (tester) async {
      await _boot(noNotifications: true);
      await _pump(tester, const NotificationsScreen());

      _atLeast(tester, find.byType(OutlinedButton), 'empty-state action');
    });
  });

  group('hand-rolled taps, measured on the rendered tree', () {
    testWidgets('the section action («عرض الكل») is 56 dp and taps at both edges',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SectionTitle('مقاولون موثوقون',
              actionText: 'عرض الكل', onAction: () => fired++),
        ),
      ));
      await tester.pump();

      final action = find
          .ancestor(
              of: find.text('عرض الكل'),
              matching: find.byType(GestureDetector))
          .first;
      _atLeast(tester, action, 'section action (عرض الكل)');

      final r = tester.getRect(action);
      await tester.tapAt(Offset(r.center.dx, r.top + 1));
      await tester.pump();
      await tester.tapAt(Offset(r.center.dx, r.bottom - 1));
      await tester.pump();
      expect(fired, 2,
          reason: 'the action is 56 dp tall but a tap 1 dp inside its top or '
              'bottom edge did not reach it — the hit area is smaller than the box');
    });

    testWidgets('the account-type switch is 56 dp and the top edge takes the tap',
        (tester) async {
      await _boot();
      await _pump(tester, const AuthScreen(mode: AuthMode.signIn));
      expect(find.text('الاسم الكامل'), findsNothing,
          reason: 'sanity: the sign-up-only field is absent before the tap');

      final tab = find.byKey(const Key('auth-tab-signup'));
      _atLeast(tester, tab, 'account-type switch (حساب جديد)');

      await _tapTopEdge(tester, tab);
      expect(find.text('الاسم الكامل'), findsOneWidget,
          reason: 'a tap 1 dp below the switch\'s top edge did not switch the '
              'form to sign-up');
    });

    testWidgets('the urgency pill is 56 dp and its top edge selects it',
        (tester) async {
      await _boot();
      await _pump(tester, const ProjectNewScreen());

      final label = find.text('عاجل جداً');
      final pill = find.ancestor(of: label, matching: find.byType(InkWell)).first;
      await tester.ensureVisible(label);
      await tester.pump();
      _atLeast(tester, pill, 'urgency pill (عاجل جداً)');

      await _tapTopEdge(tester, pill);
      final box = tester.widget<AnimatedContainer>(find
          .ancestor(of: label, matching: find.byType(AnimatedContainer))
          .first);
      expect((box.decoration as BoxDecoration).color, AppTheme.dangerWash,
          reason: 'the pill did not select from a tap on its top edge');
    });

    testWidgets('a notification row is 56 dp and its top edge marks it read',
        (tester) async {
      await _boot();
      await _pump(tester, const NotificationsScreen());

      final tile = find.byKey(const Key('notification-41'));
      _atLeast(tester, tile, 'notification row');
      await _tapTopEdge(tester, tile);

      expect(writes.any((w) => w.contains('/notifications/read')), isTrue,
          reason: 'the row did not mark itself read from an edge tap: $writes');
    });

    testWidgets('the chat send button is 56 dp and sends from its top edge',
        (tester) async {
      await _boot();
      await _pump(
          tester,
          ChatScreen(
              conversationId: 5,
              otherUserId: 31,
              otherName: 'مقاول تجربة',
              repo: Repository(api)));

      // The composer's send is the 56 dp round `_CircleAction`, not a TextButton:
      // the only 'إرسال' TextButton on this screen is the offline retry banner,
      // which is not in the tree while there is nothing pending.
      final send = find
          .ancestor(
              of: find.byIcon(Icons.send_rounded),
              matching: find.byType(InkWell))
          .first;
      _atLeast(tester, send, 'chat send');

      await tester.enterText(find.byType(TextField), 'مرحبا');
      await tester.pump();
      await _tapTopEdge(tester, send);

      expect(writes.any((w) => w.contains('/api/messages/5')), isTrue,
          reason: 'the send button did not fire from an edge tap: $writes');
    });

    testWidgets('a contractor card is 56 dp tall', (tester) async {
      await _boot();
      await _pump(tester, const BrowseScreen());

      final card = find
          .ancestor(
              of: find.text('مقاول تجربة'), matching: find.byType(InkWell))
          .first;
      _atLeast(tester, card, 'browse contractor card');
    });

    testWidgets('the portfolio add tile is 56 dp square', (tester) async {
      await _boot();
      await _pump(tester, const MyPortfolioScreen());

      final tile = find
          .ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(InkWell))
          .first;
      _atLeast(tester, tile, 'portfolio add tile');
    });
  });

  group('the star picker, at both phone widths', () {
    for (final width in const [392.0, 320.0]) {
      testWidgets('five stars of at least 56 dp at ${width.toInt()} dp wide',
          (tester) async {
        await _boot();
        await _pump(
            tester,
            ReviewScreen(
                projectId: 'demo-project', workerId: 16, repo: Repository(api)),
            size: Size(width, 850));

        // The stars *inside the picker* — the trust line at the bottom of the
        // screen carries a single star glyph and is not part of the control.
        final stars = find.descendant(
            of: find.byType(InkWell), matching: find.byIcon(Icons.star_outline_rounded));
        expect(stars, findsNWidgets(5));

        for (var i = 0; i < 5; i++) {
          final star =
              find.ancestor(of: stars.at(i), matching: find.byType(InkWell)).first;
          _atLeast(tester, star, 'star ${i + 1} @ ${width.toInt()} dp');
        }

        // The third star, tapped 1 dp inside its own top edge, has to register:
        // the picker is the one control where a miss silently changes a rating.
        await _tapTopEdge(tester, stars.at(2));
        expect(
            find.descendant(
                of: find.byType(InkWell), matching: find.byIcon(Icons.star_rounded)),
            findsNWidgets(3),
            reason: 'an edge tap on the third star did not set a 3-star rating');
      });
    }

    testWidgets('the 320 dp picker rasterises without an overflow stripe',
        (tester) async {
      await _boot();
      final path = await _shoot(
          tester,
          'tap_review_320',
          ReviewScreen(
              projectId: 'demo-project', workerId: 16, repo: Repository(api)),
          size: const Size(320, 850));
      stdout.writeln('SHOT $path');
      expect(tester.takeException(), isNull,
          reason: 'the star row still overflows at 320 dp');
    });
  });
}
