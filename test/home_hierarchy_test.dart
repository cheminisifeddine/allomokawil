// What the two home screens lead with, measured rather than asserted in prose.
//
// The founder's review item was "home screen hierarchy": the client home must
// open with one action he can take, and the contractor home must open with the
// work that earns him money instead of his own scoreboard. Both are layout
// claims, so both are pinned here by real geometry from a real widget tree —
// the position of the blocks on the page, not the presence of a string.
import 'dart:convert';
import 'dart:math' as math;

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
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

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

/// A contractor with a real history: 12 finished jobs, 12 reviews, 4.8.
const _worker = <String, Object?>{
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
  'avg_rating': 4.8,
  'total_reviews': 12,
  'total_completed_jobs': 12,
  'response_time_hours': 2,
  'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45',
  'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة',
  'phone': '077442495',
  'user_wilaya': '16',
  'avatar_url': null,
};

const _conversation = <String, Object?>{
  'id': 5,
  'customer_id': 30,
  'worker_user_id': 31,
  'project_id': 'p1',
  'other_user_name': 'مقاول تجربة',
  'other_user_avatar': null,
  'last_message_content': 'مرحبا',
  'unread_count': 0,
  'last_message_at': '2026-09-11 21:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api({required String role}) => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': _user(role)});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.endsWith('/api/mobile/my/profile')) return _json(_worker);
        // A contractor who has really uploaded: the count must reach the tile.
        if (p.endsWith('/api/mobile/workers/16/portfolio')) {
          return _json(<String>['a.jpg', 'b.jpg', 'c.jpg']);
        }
        if (p.contains('/workers/top')) return _json([_worker]);
        if (p.endsWith('/api/mobile/my/projects') ||
            p.endsWith('/api/mobile/projects')) {
          return _json([_project]);
        }
        if (p.endsWith('/api/mobile/conversations')) {
          return _json([_conversation]);
        }
        return _json(<Object>[]);
      }),
    );

Future<({ApiClient api, AuthState auth})> _boot(String role) async {
  SharedPreferences.setMockInitialValues({});
  final api = _api(role: role);
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, role, reason: 'the fixture must land on $role');
  return (api: api, auth: auth);
}

/// Pumps a home screen at a real phone size and returns the logical viewport
/// height, so "on the first screen" is arithmetic and not an opinion.
Future<double> _pump(WidgetTester tester, Widget screen, ApiClient api,
    AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2400);
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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return tester.view.physicalSize.height / tester.view.devicePixelRatio;
}

double _luminance(Color c) {
  double chan(double v) {
    v /= 255.0;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * chan(c.r * 255) +
      0.7152 * chan(c.g * 255) +
      0.0722 * chan(c.b * 255);
}

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('the client home leads with the one action', () {
    testWidgets('publish is the first block, above the categories',
        (tester) async {
      final s = await _boot('customer');
      final viewH = await _pump(tester, const CustomerHomeScreen(), s.api, s.auth);

      final cta = find.byKey(const Key('client-post-cta'));
      expect(cta, findsOneWidget, reason: 'the publish action must exist');

      final ctaTop = tester.getTopLeft(cta).dy;
      final ctaBottom = tester.getBottomLeft(cta).dy;
      final categories = tester.getTopLeft(find.text('التخصصات')).dy;

      expect(ctaTop, lessThan(categories),
          reason: 'the one action leads: publish at $ctaTop, categories at '
              '$categories');
      expect(ctaBottom, lessThan(viewH),
          reason: 'the action is on the first screen without scrolling '
              '($ctaBottom of $viewH)');
      // …and it is above the first thing a client might otherwise browse.
      expect(ctaTop,
          lessThan(tester.getTopLeft(find.text('أفضل المقاولين')).dy));
    });

    testWidgets('the action is the accent tile, lettered in navy',
        (tester) async {
      final s = await _boot('customer');
      await _pump(tester, const CustomerHomeScreen(), s.api, s.auth);

      final material = tester
          .widget<Material>(find.byKey(const Key('client-post-cta')));
      expect(material.color, AppTheme.accent,
          reason: 'the primary action is the accent, as PrimaryButton is');

      final title = tester.widget<Text>(find.text('انشر مشروعك مجاناً'));
      expect(title.style?.color, AppTheme.navy);
      expect(_contrast(AppTheme.navy, AppTheme.accent),
          greaterThanOrEqualTo(4.5),
          reason: 'navy on accent is the PrimaryButton pair and must stay '
              'readable');

      final sub =
          tester.widget<Text>(find.text('استقبل عروض مقاولين موثوقين خلال أيام'));
      expect(sub.style?.color, AppTheme.navy,
          reason: 'the subtitle is on the accent fill too — a muted grey would '
              'drop under 4.5:1');
    });

    testWidgets('a first-run client still sees the guide instead, once',
        (tester) async {
      // Same screen, but with nothing owned: the guide carries the action, so
      // the banner must stand down rather than repeat it twice.
      final api = ApiClient(
        baseUrls: ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user('customer')});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          return _json(<Object>[]);
        }),
      );
      final auth = AuthState(api);
      SharedPreferences.setMockInitialValues({});
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);

      await _pump(tester, const CustomerHomeScreen(), api, auth);

      expect(find.text('ابدأ من هنا'), findsOneWidget);
      expect(find.byKey(const Key('client-post-cta')), findsNothing);
    });
  });

  group('the contractor home leads with the work, not with a stats row', () {
    testWidgets('an open project is on the first screen', (tester) async {
      final s = await _boot('worker');
      final viewH = await _pump(tester, const WorkerHomeScreen(), s.api, s.auth);

      final marketTop =
          tester.getTopLeft(find.text('مشاريع مفتوحة للعروض')).dy;
      expect(marketTop, lessThan(viewH),
          reason: 'the market heading must be visible without scrolling '
              '($marketTop of $viewH)');

      final firstCard = tester.getTopLeft(find.byType(ProjectCard).first).dy;
      expect(firstCard, lessThan(viewH),
          reason: 'a real open project — the thing that earns a contractor '
              'money — has to be on the first screen ($firstCard of $viewH)');
    });

    testWidgets('his numbers are one line in the header card', (tester) async {
      final s = await _boot('worker');
      await _pump(tester, const WorkerHomeScreen(), s.api, s.auth);

      // The three 112 dp stat cards are gone: their labels went with them.
      expect(find.text('التقييم'), findsNothing,
          reason: 'a scoreboard row is not what this screen opens with');
      expect(find.text('سنوات خبرة'), findsNothing);

      // The numbers themselves are still said, in the identity card.
      final rating = find.text('4.8');
      expect(rating, findsOneWidget);
      expect(find.textContaining('12 مشروع منجز'), findsOneWidget);
      expect(find.textContaining('5 سنوات خبرة'), findsOneWidget);

      final headerCardTop = tester.getTopLeft(find.text('مقاول تجربة')).dy;
      expect(tester.getTopLeft(rating).dy, greaterThan(headerCardTop),
          reason: 'the numbers live under the contractor name');
      expect(tester.getTopLeft(rating).dy,
          lessThan(tester.getTopLeft(find.text('مشاريع مفتوحة للعروض')).dy));
    });

    testWidgets('the three doors are one row, and it is a compact one',
        (tester) async {
      final s = await _boot('worker');
      await _pump(tester, const WorkerHomeScreen(), s.api, s.auth);

      final portfolio = find.byKey(const Key('worker-tools-portfolio'));
      final documents = find.byKey(const Key('worker-tools-documents'));
      final edit = find.byKey(const Key('worker-tools-edit'));
      for (final f in [portfolio, documents, edit]) {
        expect(f, findsOneWidget, reason: 'every door survives the reshape');
      }

      final tops = [portfolio, documents, edit]
          .map((f) => tester.getTopLeft(f).dy)
          .toSet();
      expect(tops.length, 1, reason: 'one row, not three stacked tiles');

      final h = tester.getSize(portfolio).height;
      expect(h, lessThan(170),
          reason: 'the strip is compact — it was ~250 dp of stacked tiles; '
              'this tile is $h');
      expect(tester.getSize(portfolio).width, lessThan(200),
          reason: 'three to a row on a 392 dp phone');

      // The strip still fits above the market without pushing it off-screen.
      expect(tester.getBottomLeft(portfolio).dy, lessThan(872.0));
    });

    testWidgets('the portfolio tile counts his photos, in digits',
        (tester) async {
      final s = await _boot('worker');
      await _pump(tester, const WorkerHomeScreen(), s.api, s.auth);

      // This label was `'\$n صور'` — an escaped dollar, so every contractor who
      // had uploaded anything read the literal "\$n صور" under his own gallery.
      expect(find.text('\$n صور'), findsNothing);
      expect(find.text('3 صور'), findsOneWidget);
    });
  });
}
