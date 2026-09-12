// Proves the two project feeds can actually be narrowed by a typed word:
// the client's "مشاريعي" list and the contractor's open-project marketplace.
// Real widget tree + the real Repository against a fake HTTP client serving
// three projects, one per trade, so a filter that does nothing is visible.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

Map<String, Object?> _project({
  required String id,
  required String title,
  required String description,
  required String category,
  required String wilaya,
  required String commune,
}) =>
    {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': description,
      'category': category,
      'images': <String>[],
      'wilaya': wilaya,
      'commune': commune,
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

/// Three open projects: painting in Algiers, drywall in Blida, plumbing in
/// Algiers. Each one is reachable only through a different match rule
/// (title, category name, commune).
final _projects = <Map<String, Object?>>[
  _project(
    id: 'p1',
    title: 'دهان شقة 3 غرف',
    description: 'دهان كامل مع تصليح',
    category: 'painting',
    wilaya: '16',
    commune: 'حسين داي',
  ),
  _project(
    id: 'p2',
    title: 'تركيب جبس بورد',
    description: 'سقف معلق للصالة',
    category: 'plaster_drywall',
    wilaya: '09',
    commune: 'بوفاريك',
  ),
  _project(
    id: 'p3',
    title: 'سباكة حمام كامل',
    description: 'تبديل الأنابيب القديمة',
    category: 'plumbing',
    wilaya: '16',
    commune: 'باب الوادي',
  ),
];

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

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

ApiClient _fakeApi() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({
            'token': 'tok',
            'user': {
              'id': 30, 'phone': '0773000000', 'email': null,
              'full_name': 'زبون تجربة', 'type': 'customer', 'avatar_url': null,
              'wilaya': '16', 'commune': null,
              'created_at': '2026-09-11 20:00:00',
            }
          });
        }
        if (p.contains('/my/profile')) return _json(_worker);
        if (p.contains('/my/projects')) return _json(_projects);
        if (p.endsWith('/mobile/projects')) return _json(_projects);
        if (p.contains('/workers')) return _json([_worker]);
        if (p.contains('/conversations')) return _json(<Object>[]);
        return _json(<Object>[]);
      }),
    );

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues({});
  final api = _fakeApi();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth,
) async {
  // Tall Android phone so three project cards are all built and countable.
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppScope(api: api, auth: auth, child: screen),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeletons and the widen progress bar animate
/// forever, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('مشاريعي (client feed) narrows as the owner types', (tester) async {
    final s = await _boot();
    await _pumpScreen(
        tester, ProjectsScreen(repo: Repository(s.api)), s.api, s.auth);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProjectCard), findsNWidgets(3));
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget);

    // 1. A trade word: matches the drywall project by title AND by the Arabic
    //    name of its English category slug.
    await tester.enterText(find.byType(TextField), 'جبس');
    await _settle(tester, frames: 3);
    expect(find.byType(ProjectCard), findsOneWidget);
    expect(find.text('تركيب جبس بورد'), findsOneWidget);
    expect(find.text('دهان شقة 3 غرف'), findsNothing);

    // 2. A wilaya typed without the hamza and with a ya: the stored value is
    //    the numeric code '16', so this only works through folding + taxonomy.
    await tester.enterText(find.byType(TextField), 'الجزاير');
    await _settle(tester, frames: 3);
    expect(find.byType(ProjectCard), findsNWidgets(2));
    expect(find.text('تركيب جبس بورد'), findsNothing);

    // 3. A commune inside a description-free field search.
    await tester.enterText(find.byType(TextField), 'باب الوادي');
    await _settle(tester, frames: 3);
    expect(find.byType(ProjectCard), findsOneWidget);
    expect(find.text('سباكة حمام كامل'), findsOneWidget);

    // 4. Nothing matches: an Arabic empty state that names the term, with the
    //    action that undoes it — not a blank list.
    await tester.enterText(find.byType(TextField), 'مسبح');
    await _settle(tester, frames: 3);
    expect(find.byType(ProjectCard), findsNothing);
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(
      find.textContaining('لا يوجد مشروع في هذه الحالة يطابق «مسبح»'),
      findsOneWidget,
    );

    // 5. Clearing restores the full feed and empties the box.
    await tester.tap(find.text('مسح البحث'));
    await _settle(tester, frames: 3);
    expect(find.byType(ProjectCard), findsNWidgets(3));
    expect(_field(tester).controller!.text, isEmpty);
  });

  testWidgets('marketplace (contractor feed) narrows as the contractor types',
      (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const WorkerHomeScreen(), s.api, s.auth);

    expect(tester.takeException(), isNull);
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget);
    expect(find.text('تركيب جبس بورد'), findsOneWidget);

    // Ta marbuta typed as ha — the spelling a phone keyboard produces.
    await tester.enterText(find.byType(TextField), 'سباكه');
    await _settle(tester, frames: 4);
    expect(find.text('سباكة حمام كامل'), findsOneWidget);
    expect(find.text('دهان شقة 3 غرف'), findsNothing);
    expect(find.text('تركيب جبس بورد'), findsNothing);

    // A category name stored as an English slug.
    await tester.enterText(find.byType(TextField), 'جبس');
    await _settle(tester, frames: 4);
    expect(find.text('تركيب جبس بورد'), findsOneWidget);
    expect(find.text('سباكة حمام كامل'), findsNothing);

    // No match anywhere.
    await tester.enterText(find.byType(TextField), 'زززز');
    await _settle(tester, frames: 4);
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);

    // The box's own clear button restores the feed.
    await tester.tap(find.byTooltip('مسح البحث'));
    await _settle(tester, frames: 4);
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget);
    expect(_field(tester).controller!.text, isEmpty);
  });
}
