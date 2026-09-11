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
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/profile_screen.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

// Real payloads captured from the live API on 2026-09-11.
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

const _review = {
  'id': 5, 'project_id': null, 'customer_id': 30, 'worker_id': 16, 'rating': 5,
  'comment': 'عمل ممتاز', 'images': '[]', 'is_visible': 1,
  'created_at': '2026-09-11 20:23:50', 'customer_full_name': 'زبون تجربة',
  'customer_avatar_url': null,
};

const _quote = {
  'id': 13, 'project_id': null, 'worker_id': 16, 'amount': 75000,
  'message': 'جاهز للبدء فوراً', 'estimated_days': 5, 'status': 'pending',
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'worker_full_name': 'مقاول تجربة', 'worker_avatar_url': null,
  'worker_avg_rating': 4.5, 'worker_total_reviews': 3,
  'worker_verification_status': 'verified',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

ApiClient _fakeApi() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': {
            'id': 30, 'phone': '0773000000', 'email': null,
            'full_name': 'زبون تجربة', 'type': 'customer', 'avatar_url': null,
            'wilaya': '16', 'commune': null,
            'created_at': '2026-09-11 20:00:00',
          }});
        }
        if (p.contains('/unread')) return _json({'unread': 1});
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
        if (p.contains('/my/profile')) return _json(_worker);
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
  // Typical Android phone (1080x2280 physical @2.75 -> ~392x829 logical) so
  // overflow findings reflect a real device rather than the 800x600 default.
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: AppScope(api: api, auth: auth, child: screen),
  ));
  // Let the screen's futures resolve without waiting on shimmers forever.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('customer dashboard renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const CustomerHomeScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
    expect(find.text('استكشف'), findsWidgets);
  });

  testWidgets('worker dashboard renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const WorkerHomeScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
    expect(find.text('المنصة'), findsWidgets);
  });

  testWidgets('browse screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const BrowseScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new project screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const ProjectNewScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects list screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(
        tester, ProjectsScreen(repo: Repository(s.api)), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat list screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(
        tester, ChatListScreen(repo: Repository(s.api)), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project detail screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(
      tester,
      ProjectDetailScreen(projectId: _project['id'] as String,
          repo: Repository(s.api)),
      s.api,
      s.auth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker profile screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const WorkerProfileScreen(workerId: 16),
        s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const ProfileScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification screen renders', (tester) async {
    final s = await _boot();
    await _pumpScreen(tester, const VerificationScreen(), s.api, s.auth);
    expect(tester.takeException(), isNull);
  });
}
