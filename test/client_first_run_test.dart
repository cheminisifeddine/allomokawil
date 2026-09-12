import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/first_run.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

// Real payload shapes captured from the live API on 2026-09-11.
const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.5, 'total_reviews': 3,
  'total_completed_jobs': 7, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

const _project = {
  'id': 'b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551',
  'customer_id': 30, 'title': 'دهان شقة 3 غرف', 'description': 'دهان كامل',
  'category': 'painting', 'images': <String>[], 'wilaya': '16',
  'commune': 'حسين داي', 'latitude': null, 'longitude': null,
  'budget_min': 60000, 'budget_max': 90000, 'urgency': 'within_week',
  'status': 'open', 'selected_worker_id': null,
  'created_at': '2026-09-11 20:23:44', 'updated_at': '2026-09-11 20:23:44',
};

const _conversation = {
  'id': 5, 'customer_id': 30, 'worker_user_id': 31, 'project_id': null,
  'last_message_at': '2026-09-11 20:23:47', 'created_at': '2026-09-11 20:23:47',
  'other_user_name': 'مقاول تجربة', 'other_user_avatar': null,
  'last_message_content': 'مرحبا، متى يمكنك البدء؟', 'unread_count': 0,
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// A mutable fake platform: the test can make a project appear between two
/// pumps, which is exactly what happens when the user posts one.
class _Platform {
  bool hasProject;
  bool hasConversation;
  int conversationCalls = 0;

  _Platform({this.hasProject = false, this.hasConversation = false});

  ApiClient client() => ApiClient(
        baseUrls: ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login')) {
            return _json({
              'token': 'tok',
              'user': {
                'id': 30, 'phone': '0773000000', 'email': null,
                'full_name': 'زبون تجربة', 'type': 'customer',
                'avatar_url': null, 'wilaya': '16', 'commune': null,
                'created_at': '2026-09-11 20:00:00',
              },
            });
          }
          if (p.contains('/conversations')) {
            conversationCalls++;
            return _json(hasConversation ? [_conversation] : <Object>[]);
          }
          if (p.contains('/my/projects')) {
            return _json(hasProject ? [_project] : <Object>[]);
          }
          if (p.contains('/unread')) return _json({'unread': 0});
          if (p.contains('/reviews')) return _json(<Object>[]);
          if (p.contains('/portfolio')) return _json(<Object>[]);
          if (p.contains('/my/profile')) return _json(_worker);
          if (p.contains('/workers')) return _json([_worker]);
          if (p.contains('/notifications')) return _json(<Object>[]);
          return _json(<Object>[]);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Platform platform})> _boot(
    _Platform platform) async {
  SharedPreferences.setMockInitialValues({});
  final api = platform.client();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, platform: platform);
}

/// Pumps the real client home on a typical Android phone (1080x2280 @2.75 ->
/// ~392x829 logical, RTL) and lets its futures resolve.
Future<void> _pumpHome(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  // AppScope sits above MaterialApp exactly like main.dart does, so a pushed
  // route can still read the API client; the theme, the Arabic locale and the
  // localisation delegates mirror app.dart so this renders the real RTL tree.
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
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
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  // ── The rule ─────────────────────────────────────────────────────────
  group('clientNeedsFirstRunGuide', () {
    test('a fresh account that loaded nothing gets the guide', () {
      expect(
        clientNeedsFirstRunGuide(
          projectsLoaded: true,
          conversationsLoaded: true,
          projectCount: 0,
          conversationCount: 0,
        ),
        isTrue,
      );
    });

    test('one posted project is enough to retire the guide', () {
      expect(
        clientNeedsFirstRunGuide(
          projectsLoaded: true,
          conversationsLoaded: true,
          projectCount: 1,
          conversationCount: 0,
        ),
        isFalse,
      );
    });

    test('contacting one contractor is enough to retire the guide', () {
      expect(
        clientNeedsFirstRunGuide(
          projectsLoaded: true,
          conversationsLoaded: true,
          projectCount: 0,
          conversationCount: 1,
        ),
        isFalse,
      );
    });

    test('a failed load never produces a guide', () {
      expect(
        clientNeedsFirstRunGuide(
          projectsLoaded: false,
          conversationsLoaded: true,
          projectCount: 0,
          conversationCount: 0,
        ),
        isFalse,
      );
      expect(
        clientNeedsFirstRunGuide(
          projectsLoaded: true,
          conversationsLoaded: false,
          projectCount: 0,
          conversationCount: 0,
        ),
        isFalse,
      );
    });

    test('null lists mean "not loaded", empty lists mean "nothing yet"', () {
      expect(clientNeedsFirstRunGuideFor(projects: null, conversations: null),
          isFalse);
      expect(
        clientNeedsFirstRunGuideFor(projects: const [], conversations: const []),
        isTrue,
      );
    });
  });

  // ── The screen ───────────────────────────────────────────────────────
  testWidgets('a fresh client sees a named first step and a working CTA',
      (tester) async {
    final s = await _boot(_Platform());
    await _pumpHome(tester, s.api, s.auth);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('client-start-card')), findsOneWidget);
    expect(find.text('ابدأ من هنا'), findsOneWidget);
    // The first step is named, and so are the two that follow it.
    expect(find.text('انشر مشروعك'), findsOneWidget);
    expect(find.text('قارن عروض المقاولين'), findsOneWidget);
    expect(find.text('تواصل واختر الأنسب'), findsOneWidget);
    expect(find.byKey(const Key('client-start-cta')), findsOneWidget);
    expect(find.byKey(const Key('client-start-browse')), findsOneWidget);
    // Rendered right-to-left, like the shipped app.
    expect(
      Directionality.of(tester.element(find.byKey(const Key('client-start-card')))),
      TextDirection.rtl,
    );
    // The banner that carries the same action lower down steps aside.
    expect(find.text('انشر مشروعك مجاناً'), findsNothing);

    // The CTA is a real navigation, not a decoration.
    await tester.tap(find.byKey(const Key('client-start-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProjectNewScreen), findsOneWidget);
  });

  testWidgets('the guide offers the browse path too', (tester) async {
    final s = await _boot(_Platform());
    await _pumpHome(tester, s.api, s.auth);

    await tester.tap(find.byKey(const Key('client-start-browse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(find.byType(ProjectNewScreen), findsNothing);
  });

  testWidgets('posting the first project retires the guide on return',
      (tester) async {
    final platform = _Platform();
    final s = await _boot(platform);
    await _pumpHome(tester, s.api, s.auth);

    expect(find.byKey(const Key('client-start-card')), findsOneWidget);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);

    await tester.tap(find.byKey(const Key('client-start-cta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProjectNewScreen), findsOneWidget);

    // The user published while he was on that screen.
    platform.hasProject = true;
    nav.pop();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byKey(const Key('client-start-card')), findsNothing);
    expect(find.text('ابدأ من هنا'), findsNothing);
    // ...and the banner that carries the publish action for the rest of us is
    // back where it belongs.
    expect(find.text('انشر مشروعك مجاناً'), findsOneWidget);
  });

  testWidgets('a client with one project never sees the guide', (tester) async {
    final s = await _boot(_Platform(hasProject: true));
    await _pumpHome(tester, s.api, s.auth);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('client-start-card')), findsNothing);
    expect(find.text('ابدأ من هنا'), findsNothing);
    expect(find.text('انشر مشروعك مجاناً'), findsOneWidget);
  });

  testWidgets('a client who has only messaged a contractor never sees it',
      (tester) async {
    final s = await _boot(_Platform(hasConversation: true));
    await _pumpHome(tester, s.api, s.auth);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('client-start-card')), findsNothing);
  });

  testWidgets('the home reads the conversations endpoint exactly once',
      (tester) async {
    final platform = _Platform();
    final s = await _boot(platform);
    await _pumpHome(tester, s.api, s.auth);

    // The messages tab is built inside the same IndexedStack, so the guide's
    // question and the chat list must share one request.
    expect(platform.conversationCalls, 1);
  });
}
