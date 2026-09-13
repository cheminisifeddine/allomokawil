// The review POST answers with `{ok: true}` — not with a Review row.
//
// The screen is the last step of the marketplace's whole promise ("the rating
// tells you who to trust"), and it is the one place where the API contract and
// the client model disagree. `Repository.createReview` handed the response to
// `Review.fromJson`, which reads `json['id'] as int`; the real body has no `id`,
// so the cast throws a `_TypeError`. That is an `Error`, not an `Exception`, so
// the screen's `on Exception` catch never saw it: the review *was* written by
// the server, but the app showed no confirmation and never left the screen.
//
// These tests hold the client to the contract the live Worker actually
// implements (mobile.ts -> `return json({ ok: true })`), with the same widget
// and the same Repository the app uses.
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
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';

/// Answers exactly like the live API: 200 and `{"ok":true}`.
class _OkRecorder {
  final reviews = <Map<String, dynamic>>[];

  ApiClient client() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/review')) {
            reviews.add(jsonDecode(req.body) as Map<String, dynamic>);
            return http.Response('{"ok":true}', 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('{"error":"unexpected"}', 404,
              headers: {'content-type': 'application/json'});
        }),
      );
}

Finder _pickerStars(IconData icon) => find.descendant(
    of: find.byType(InkWell), matching: find.byIcon(icon));


// ---------------------------------------------------------------------------
// The door into the rating form after the job is already closed
// ---------------------------------------------------------------------------

/// A project owned by the signed-in customer, with the lifecycle state under
/// test. `selected_worker_id` is the contractor who won it.
Map<String, dynamic> _project(String status, {int? workerId = 16}) => {
      'id': 'p-1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': null,
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
      'updated_at': '2026-09-13 08:00:00',
    };

/// Serves one project in the requested state and lets the whole review POST
/// through, so a tap on the CTA can be followed to the end of the flow.
ApiClient _detailApi(String status, {int? workerId = 16, List<Map<String, dynamic>>? posted}) =>
    ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/review')) {
          posted?.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('{"ok":true}', 200,
              headers: {'content-type': 'application/json'});
        }
        if (p.endsWith('/api/login')) {
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
              headers: {'content-type': 'application/json'});
        }
        if (p.endsWith('/unread')) {
          return http.Response('{"unread":0}', 200,
              headers: {'content-type': 'application/json'});
        }
        if (p.contains('/quotes')) {
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }
        if (p.contains('/projects/')) {
          return http.Response(
              jsonEncode(_project(status, workerId: workerId)), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }),
    );

Future<({ApiClient api, AuthState auth})> _detailBoot(String status,
    {int? workerId = 16}) async {
  SharedPreferences.setMockInitialValues({});
  final api = _detailApi(status, workerId: workerId);
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pumpDetail(
    WidgetTester tester, String status, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
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

void main() {
  test('a review accepted as {ok:true} does not throw', () async {
    final rec = _OkRecorder();
    final repo = Repository(rec.client());

    await repo.createReview(
      projectId: 'demo-project',
      workerId: 16,
      rating: 4,
      comment: 'عمل جيد',
    );

    expect(rec.reviews, hasLength(1));
    expect(rec.reviews.single['rating'], 4);
    expect(rec.reviews.single['worker_id'], 16);
    expect(rec.reviews.single['comment'], 'عمل جيد');
  });

  testWidgets('the screen confirms the review and leaves the form',
      (tester) async {
    final rec = _OkRecorder();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ReviewScreen(
        projectId: 'demo-project',
        workerId: 16,
        repo: Repository(rec.client()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(_pickerStars(Icons.star_outline_rounded).at(3)); // 4 stars
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('إرسال التقييم'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(rec.reviews, hasLength(1));
    expect(rec.reviews.single['rating'], 4);
    expect(find.text('شكراً لك، تم إرسال التقييم'), findsOneWidget,
        reason: 'the user has to be told the rating was published');
    expect(tester.takeException(), isNull,
        reason: 'a published review must not surface as an unhandled error');
  });

  testWidgets('a closed job still offers the rating form', (tester) async {
    // The only door into the review used to be the tap that closed the job:
    // back out of that screen once and a completed project had no primary
    // action left, so the rating could never be written.
    final s = await _detailBoot('completed');
    await _pumpDetail(tester, 'completed', s.api, s.auth);

    expect(find.text('قيّم المقاول'), findsOneWidget);
    await tester.tap(find.text('قيّم المقاول'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('كيف كانت تجربتك مع المقاول؟'), findsOneWidget);
  });

  testWidgets('a job that is still running asks for the close, not the rating',
      (tester) async {
    final s = await _detailBoot('in_progress');
    await _pumpDetail(tester, 'in_progress', s.api, s.auth);

    expect(find.text('أكمل المشروع وتقييم'), findsOneWidget);
    expect(find.text('قيّم المقاول'), findsNothing);
    expect(find.byType(ReviewScreen), findsNothing);
  });

  testWidgets('a closed job with no chosen contractor offers no rating',
      (tester) async {
    // selected_worker_id is null: there is nobody to rate, and a button that
    // opened a form for worker 0 would post a rating at nobody.
    final s = await _detailBoot('completed', workerId: null);
    await _pumpDetail(tester, 'completed', s.api, s.auth);

    expect(find.text('قيّم المقاول'), findsNothing);
  });
}
