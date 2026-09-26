// The real project screen, with a real bid on it, and the two trust signals
// the API sends beside the contractor's name.
//
// The unit tests in `quote_trust_signals_test.dart` prove the badge and the
// photo behave. That is not the claim a customer would make, and it is not the
// one that can rot: a correct widget wired to nothing is a feature that does
// not exist, and the defect this fixes lived on the screen where a man decides
// who gets his keys.
//
// So this drives `ProjectDetailScreen`, hands it the payload the server
// actually sends, and reads the icons and the image off the rendered tree.
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
import 'package:allomokawil/src/widgets/net_image.dart';
import 'package:allomokawil/src/widgets/quote_worker_trust.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _projectId = 'b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551';

/// Straight off `GET /api/mobile/projects/{id}`.
const _project = '''
{"id":"b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551","customer_id":30,"title":"دهان شقة 3 غرف",
 "description":"دهان كامل مع تحضير الجدران","category":"painting","images":[],
 "wilaya":"16","commune":"حسين داي","latitude":null,"longitude":null,
 "budget_min":60000,"budget_max":90000,"urgency":"within_week","status":"open",
 "selected_worker_id":null,"created_at":"2026-09-11 20:23:44",
 "updated_at":"2026-09-11 20:23:44"}''';

Map<String, Object?> _quoteRow({
  required int id,
  required String name,
  required String status,
  String? avatar,
  double? avgRating = 0,
  int? totalReviews = 0,
}) =>
    <String, Object?>{
      'id': id,
      'project_id': _projectId,
      'worker_id': 16 + id,
      'amount': 75000 + id,
      'message': 'جاهز للبدء فوراً',
      'estimated_days': 5,
      'status': 'pending',
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'worker_full_name': name,
      'worker_avatar_url': avatar,
      'worker_avg_rating': avgRating,
      'worker_total_reviews': totalReviews,
      'worker_verification_status': status,
    };

String _body(String path) {
  if (path.contains('/quotes')) {
    return jsonEncode(_rows);
  }
  if (path.endsWith('/api/login')) {
    return jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 30,
        'phone': '0773000000',
        'email': null,
        'full_name': 'زبون',
        'type': 'customer',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-09-11 20:20:00',
      },
    });
  }
  if (path.contains('/api/mobile/projects/')) return _project;
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 30,
      'user_id': 30,
      'full_name': 'زبون',
      'specialties': <Object?>[],
      'experience_years': 0,
    });
  }
  return jsonEncode(<Object>[]);
}

late List<Map<String, Object?>> _rows;

Future<void> _open(WidgetTester tester) async {
  // Required, and its absence is why the first revision of this file hung
  // with `flutter_tester` at 0.4% CPU. `AuthState` reads SharedPreferences on
  // boot; with no mock registered the platform channel never answers, the
  // first `pump` waits forever, and the suite dies on a wall clock rather
  // than on a failure. `screen_smoke_test.dart` and `design_shots_test.dart`
  // both do this for the same screens.
  SharedPreferences.setMockInitialValues({});

  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => http.Response(
          _body(req.url.path),
          200,
          headers: {'content-type': 'application/json'},
        )),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ProjectDetailScreen(projectId: _projectId, repo: Repository(api)),
    ),
  ));
  // NOT `pumpAndSettle`. The project screen keeps a shimmer/repaint running
  // while the mock client answers, so settle never returns: the previous
  // revision of this file hung here and the whole suite was killed at 9
  // minutes with `flutter_tester` at 0.1% CPU. Bounded pumps are what
  // `screen_smoke_test.dart` uses against this same screen, and they let the
  // futures resolve without waiting on a spinner forever.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() => _rows = <Map<String, Object?>>[]);

  group('the bid card a customer actually reads', () {
    testWidgets('shows the contractor\'s photo when the API sent one',
        (tester) async {
      const url = 'https://cdn.test/avatar.png';
      _rows = <Map<String, Object?>>[
        _quoteRow(
            id: 1, name: 'مقاول موثّق', status: 'verified', avatar: url),
      ];
      await _open(tester);

      expect(find.byType(QuoteWorkerTrust), findsOneWidget,
          reason: 'the trust widget is on the card at all');
      expect(
        find.descendant(
          of: find.byType(QuoteWorkerTrust),
          matching: find.byType(NetImage),
        ),
        findsOneWidget,
        reason: 'a verified contractor with a photo must not be a monogram',
      );
      expect(
        tester
            .widget<NetImage>(
              find.descendant(
                of: find.byType(QuoteWorkerTrust),
                matching: find.byType(NetImage),
              ),
            )
            .url,
        url,
      );
    });

    testWidgets('shows the tick when the API says verified', (tester) async {
      _rows = <Map<String, Object?>>[
        _quoteRow(id: 2, name: 'مقاول موثّق', status: 'verified'),
      ];
      await _open(tester);

      // Scoped to the trust widget on purpose. The screen's own chrome draws
      // `Icons.verified_rounded` too, so a bare global finder passes on the
      // page's furniture and proves nothing about the bid card — which is how
      // the earlier revision of this test was green for the wrong reason.
      final tick = find.descendant(
        of: find.byType(QuoteWorkerTrust),
        matching: find.byIcon(Icons.verified_rounded),
      );
      expect(tick, findsOneWidget);
      final icon = tester.widget<Icon>(tick);
      expect(icon.color, AppTheme.success,
          reason: 'the tick is the success token, not a default icon colour');
    });

    testWidgets('does not claim verified when the API says pending',
        (tester) async {
      _rows = <Map<String, Object?>>[
        _quoteRow(id: 3, name: 'مقاول بانتظار التحقق', status: 'pending'),
      ];
      await _open(tester);

      final trust = find.byType(QuoteWorkerTrust);
      expect(
        find.descendant(of: trust, matching: find.byIcon(Icons.verified_rounded)),
        findsNothing,
        reason: 'this is the exact defect: pending looked identical to '
            'verified, so the badge meant nothing',
      );
      expect(
        find.descendant(of: trust, matching: find.byIcon(Icons.schedule_rounded)),
        findsOneWidget,
        reason: 'the server\'s own word is "asked, not answered", which the '
            'customer is entitled to see',
      );
    });

    testWidgets('a verified bid and a pending bid look different',
        (tester) async {
      // The control. If both render identically the badge proves nothing.
      _rows = <Map<String, Object?>>[
        _quoteRow(id: 4, name: 'أ', status: 'verified'),
      ];
      await _open(tester);
      expect(
        find.descendant(
          of: find.byType(QuoteWorkerTrust),
          matching: find.byIcon(Icons.verified_rounded),
        ),
        findsOneWidget,
      );

      // Tear the screen down before the second render. `pumpWidget` reuses an
      // element when the new tree has the same types at the same position, so
      // without this the second `_open` re-pumped the *first* fetch's quotes
      // and the badge under test was never re-read from the payload at all.
      await tester.pumpWidget(const SizedBox.shrink());

      _rows = <Map<String, Object?>>[
        _quoteRow(id: 4, name: 'أ', status: 'pending'),
      ];
      await _open(tester);
      expect(
        find.descendant(
          of: find.byType(QuoteWorkerTrust),
          matching: find.byIcon(Icons.verified_rounded),
        ),
        findsNothing,
        reason: 'the same bid, re-rendered with `pending` in the payload',
      );
    });

    testWidgets('no photo means the monogram, and the tick still shows',
        (tester) async {
      _rows = <Map<String, Object?>>[
        _quoteRow(id: 5, name: 'مقاول بلا صورة', status: 'verified'),
      ];
      await _open(tester);
      expect(find.byType(InitialAvatar), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget,
          reason: 'the photo and the tick are independent facts');
    });

    testWidgets('every bid on the screen gets its own trust signals',
        (tester) async {
      _rows = <Map<String, Object?>>[
        _quoteRow(id: 6, name: 'مقاول أول', status: 'verified'),
        _quoteRow(id: 7, name: 'مقاول ثان', status: 'pending'),
        _quoteRow(id: 8, name: 'مقاول ثالث', status: 'rejected'),
      ];
      await _open(tester);
      expect(find.byType(QuoteWorkerTrust), findsNWidgets(3));
      final trust = find.byType(QuoteWorkerTrust);
      expect(
        find.descendant(of: trust, matching: find.byIcon(Icons.verified_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: trust, matching: find.byIcon(Icons.schedule_rounded)),
        findsOneWidget,
        reason: 'only `rejected` is silent; `pending` is an unanswered check',
      );
    });
  });

  group('the score the card prints, or the fact that there is none', () {
    // The unit cases in `quote_zero_score_test.dart` are about the model. These
    // are about the card, because a correct model wired to a screen that still
    // prints the sentinel is how this whole class of bug rots silently: when
    // the card guard was reverted to `workerTotalReviews > 0`, every unit test
    // in the suite still passed.
    Future<void> openOne(Map<String, Object?> row) async {
      _rows = <Map<String, Object?>>[row];
    }

    testWidgets('a bid with no score says so, and prints no «0.0»',
        (tester) async {
      await openOne(_quoteRow(
          id: 20, name: 'مقاول جديد', status: 'pending'));
      await _open(tester);

      expect(find.text('لا تقييمات بعد'), findsOneWidget,
          reason: 'the card states the truth about the scoreboard');
      // Scoped to the star row's own text, because a bare global search for
      // "0.0" would also match any price or budget printed on the page.
      expect(
        find.descendant(
          of: find.byType(RatingStars),
          matching: find.text('0.0'),
        ),
        findsNothing,
      );
      expect(find.byType(RatingStars), findsNothing,
          reason: 'no stars at all for a score nobody gave');
    });

    testWidgets('reviews-without-a-score is not drawn as «0.0»', (tester) async {
      // The payload the old guard got wrong: the count says he has reviews, so
      // `workerTotalReviews > 0` passed, and the card printed five empty stars
      // and «0.0» for a tradesman somebody did rate.
      await openOne(_quoteRow(id: 21, name: 'مقاول مُقيَّم', status: 'pending',
          avgRating: 0, totalReviews: 7));
      await _open(tester);

      expect(find.byType(RatingStars), findsNothing);
      expect(find.text('لا تقييمات بعد'), findsOneWidget);
    });

    testWidgets('a real score still draws its stars and its count',
        (tester) async {
      await openOne(_quoteRow(id: 22, name: 'مقاول موثّق', status: 'verified',
          avgRating: 4.7, totalReviews: 30));
      await _open(tester);

      expect(find.byType(RatingStars), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RatingStars),
          matching: find.text('4.7'),
        ),
        findsOneWidget,
      );
      expect(find.text('لا تقييمات بعد'), findsNothing,
          reason: 'the fix must not silence a real score');
    });

    testWidgets('a score with no review count still draws its stars',
        (tester) async {
      // The mirror case, so the guard cannot be quietly swapped back for a
      // count check in the other direction.
      await openOne(_quoteRow(id: 23, name: 'مقاول مصدَّر', status: 'verified',
          avgRating: 5, totalReviews: 0));
      await _open(tester);

      expect(find.byType(RatingStars), findsOneWidget);
      expect(find.text('لا تقييمات بعد'), findsNothing);
    });
  });
}
