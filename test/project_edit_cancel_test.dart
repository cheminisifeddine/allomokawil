// The owner's two management actions: edit and cancel.
//
// The publish screen and its validation are only half of a project's life: a
// client who mistyped his phone number in the description, or who found his
// own contractor, had no way out — the app could post a project and never
// touch it again, while the web app could do both. These tests pin the three
// things that make the new path trustworthy:
//   * the wire calls (PATCH /api/mobile/projects/:id, POST .../cancel) with
//     the same snake_case urgency the create path had to be repaired to send;
//   * that the edit form is the create form (prefilled, same save validation);
//   * that a button the API would refuse is never rendered, per lifecycle
//     state — no button may lie about what it will do.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

Map<String, dynamic> _project(String status, {int? workerId = 16}) => {
      'id': 'p-1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'الوصف القديم',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': workerId,
      'created_at': '2026-09-13 08:00:00',
    };

/// Records every request and answers like the live Worker: the PATCH returns
/// the updated project, the cancel returns `{ok:true,status:'cancelled'}`.
class _Recorder {
  final List<http.Request> calls = [];
  _Recorder(this.status);
  final String status;

  /// Every request that changes something on the server. The login POST is
  /// excluded: it belongs to booting the session, not to this screen.
  Iterable<http.Request> get writeCalls => calls.where(
      (r) => r.method != 'GET' && !r.url.path.endsWith('/login'));

  ApiClient client() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          calls.add(req);
          final p = req.url.path;
          final json = {'content-type': 'application/json'};
          if (p.endsWith('/cancel')) {
            return http.Response('{"ok":true,"status":"cancelled"}', 200,
                headers: json);
          }
          if (p.endsWith('/projects/p-1') && req.method == 'PATCH') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
                jsonEncode({..._project(status), ...body, 'id': 'p-1'}), 200,
                headers: json);
          }
          if (p.endsWith('/login')) {
            return http.Response(
                jsonEncode({
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
                    'created_at': '2026-09-13 08:00:00',
                  },
                }),
                200,
                headers: json);
          }
          if (p.endsWith('/unread')) {
            return http.Response('{"unread":0}', 200, headers: json);
          }
          if (p.contains('/quotes')) {
            return http.Response('[]', 200, headers: json);
          }
          if (p.contains('/projects/')) {
            return http.Response(jsonEncode(_project(status)), 200,
                headers: json);
          }
          return http.Response('[]', 200, headers: json);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Recorder rec})> _boot(
    String status) async {
  SharedPreferences.setMockInitialValues({});
  final rec = _Recorder(status);
  final api = rec.client();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, rec: rec);
}

Future<void> _pumpDetail(
    WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    home: AppScope(
      api: api,
      auth: auth,
      child: ProjectDetailScreen(projectId: 'p-1', repo: Repository(api)),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Drags the project page to its end, so an assertion about something *not*
/// being there cannot pass merely because the list never built that far.
Future<void> _toBottom(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 4; i++) {
    await tester.drag(list, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  test('an edit is a PATCH that carries the same wire values as create',
      () async {
    final rec = _Recorder('open');
    final repo = Repository(rec.client());

    await repo.updateProject(
      'p-1',
      title: 'دهان شقة 4 غرف',
      description: 'بعد التعديل',
      category: 'painting',
      wilaya: '31',
      commune: 'بئر الجير',
      budgetMin: 70000,
      budgetMax: 95000,
      urgency: UrgencyLevel.withinWeek,
      images: const ['https://cdn.test/a.jpg'],
    );

    final call = rec.writeCalls.single;
    expect(call.method, 'PATCH');
    expect(call.url.path, endsWith('/api/mobile/projects/p-1'));
    final body = jsonDecode(call.body) as Map<String, dynamic>;
    expect(body['title'], 'دهان شقة 4 غرف');
    expect(body['wilaya'], '31');
    expect(body['budget_max'], 95000);
    // `.name` here was the publish bug; the edit path must not reintroduce it.
    expect(body['urgency'], 'within_week');
    expect(body['images'], ['https://cdn.test/a.jpg']);
  });

  test('cancelling posts to the cancel route and sends nothing else', () async {
    final rec = _Recorder('open');
    await Repository(rec.client()).cancelProject('p-1');

    final call = rec.writeCalls.single;
    expect(call.method, 'POST');
    expect(call.url.path, endsWith('/api/mobile/projects/p-1/cancel'));
  });

  testWidgets('an open project offers edit and cancel', (tester) async {
    final boot = await _boot('open');
    await _pumpDetail(tester, boot.api, boot.auth);

    await _reveal(tester, find.text('إلغاء المشروع'));
    expect(find.text('عدّل المشروع'), findsOneWidget);
    expect(find.text('إلغاء المشروع'), findsOneWidget);
  });

  testWidgets('a running job can be cancelled, never re-scoped', (tester) async {
    final boot = await _boot('in_progress');
    await _pumpDetail(tester, boot.api, boot.auth);

    await _toBottom(tester);
    expect(find.text('إلغاء المشروع'), findsOneWidget);
    // The contractor bid on this scope; the API refuses the edit, so no button.
    expect(find.text('عدّل المشروع'), findsNothing);
  });

  testWidgets('a finished job offers neither action', (tester) async {
    final boot = await _boot('completed');
    await _pumpDetail(tester, boot.api, boot.auth);

    await _toBottom(tester);
    expect(find.text('عدّل المشروع'), findsNothing);
    expect(find.text('إلغاء المشروع'), findsNothing);
  });

  testWidgets('cancel asks first, then posts and reports it', (tester) async {
    final boot = await _boot('open');
    await _pumpDetail(tester, boot.api, boot.auth);

    await _reveal(tester, find.text('إلغاء المشروع'));
    await tester.tap(find.text('إلغاء المشروع'));
    await tester.pumpAndSettle();

    expect(find.text('إلغاء المشروع؟'), findsOneWidget);
    expect(boot.rec.writeCalls, isEmpty, reason: 'no write before confirming');

    await tester.tap(find.text('نعم، ألغِ المشروع'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final call = boot.rec.writeCalls.single;
    expect(call.url.path, endsWith('/api/mobile/projects/p-1/cancel'));
    expect(find.text('تم إلغاء المشروع'), findsOneWidget);
  });

  testWidgets('backing out of the confirmation writes nothing', (tester) async {
    final boot = await _boot('open');
    await _pumpDetail(tester, boot.api, boot.auth);

    await _reveal(tester, find.text('إلغاء المشروع'));
    await tester.tap(find.text('إلغاء المشروع'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();

    expect(boot.rec.writeCalls, isEmpty);
  });

  testWidgets('the edit form is the publish form, prefilled', (tester) async {
    final boot = await _boot('open');
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: AppScope(
        api: boot.api,
        auth: boot.auth,
        child: ProjectNewScreen(initial: Project.fromJson(_project('open'))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('عدّل مشروعك'), findsOneWidget);
    expect(find.text('دهان شقة 3 غرف'), findsOneWidget);
    expect(find.text('الوصف القديم'), findsOneWidget);
    expect(find.text('احفظ التعديل'), findsOneWidget);
    // The create path is untouched: the same screen still announces itself
    // as a publish form when it was opened without a project.
    expect(find.text('نشر المشروع'), findsNothing);

    await tester.tap(find.text('احفظ التعديل'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    final call = boot.rec.writeCalls.single;
    expect(call.method, 'PATCH');
    final body = jsonDecode(call.body) as Map<String, dynamic>;
    expect(body['title'], 'دهان شقة 3 غرف');
    expect(body['description'], 'الوصف القديم');
    expect(body['category'], 'painting');
    expect(body['wilaya'], '16');
    expect(body['budget_min'], 60000);
    expect(body['urgency'], 'within_week');
  });
}
