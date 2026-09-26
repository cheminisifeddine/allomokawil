// The search box as a contractor actually meets it.
//
// The unit tests beside this one prove `projectMatchesQuery` reads every trade
// a job covers. That is not the claim a user would make, and it is not the one
// that can rot silently: a correct filter wired to nothing is a feature that
// does not exist, and the defect this fixes lived in the real marketplace feed.
//
// So this drives the real screen, types into the real search field, and reads
// the real cards — with the payload the server actually sends, not a
// single-trade row that would pass either way.
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
import 'package:allomokawil/src/screens/project/projects_screen.dart';

Map<String, Object?> _session() => <String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 336,
        'phone': '0773000000',
        'email': null,
        'full_name': 'زبون',
        'type': 'customer',
        'avatar_url': null,
        'wilaya': '04',
        'commune': null,
        'created_at': '2026-09-19 20:00:00',
      },
    };

/// Two real rows, straight off `GET /api/mobile/my/projects`.
///
/// The first is the six-trade finishing job. Its `title` and `description` are
/// the literal string `test` — they were never filled in by whoever posted it —
/// so the *only* place its trades are written down is `categories`. That is
/// what makes it the right row for this test and a single-trade row useless.
Map<String, Object?> _job({
  required String id,
  required String primary,
  required List<String> trades,
  String title = 'test',
  String description = 'test',
}) =>
    <String, Object?>{
      'id': id,
      'customer_id': 336,
      'title': title,
      'description': description,
      'category': primary,
      'categories': trades,
      'images': <Object?>[],
      'wilaya': '04',
      'commune': 'أولاد قاسم',
      'budget_min': 6000,
      'budget_max': 7000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-19 20:39:41',
      'updated_at': '2026-09-19 20:39:41',
    };

final List<Map<String, Object?>> _projects = <Map<String, Object?>>[
  _job(
    id: '8cee95af91ebda3846132f183fe6141ead3a89fdf79d9c9cb26b59a8096ce601',
    primary: 'general_finishing',
    trades: const [
      'general_finishing',
      'painting',
      'renovation',
      'construction',
      'plumbing',
      'carpentry_aluminum',
    ],
  ),
  // A painting-only job, so "the search is broken and returns everything" is
  // a failure mode this test can actually detect.
  _job(
    id: '90dc904525441d7b687bb58460cbcb3e92caa66afd8e052da9c0b90b8e9a1e49',
    primary: 'painting',
    trades: const ['painting', 'electrical'],
    title: 'دهان فيلا',
    description: 'دهان كامل',
  ),
];

String _body(String path) {
  if (path.endsWith('/api/login')) return jsonEncode(_session());
  if (path.contains('/my/projects')) return jsonEncode(_projects);
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 336,
      'user_id': 336,
      'full_name': 'زبون',
      'specialties': <Object?>[],
      'experience_years': 0,
    });
  }
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'note_ar': '',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'starts_at': '2026-09-01 00:00:00',
        'expires_at': null,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

void main() {
  Future<List<String>> search(WidgetTester tester, String query) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});

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
        home: ProjectsScreen(repo: Repository(api)),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final untyped = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    // Guard the guard: an empty list would make every "the card is gone"
    // assertion below true for the wrong reason.
    expect(untyped, isNotEmpty, reason: 'the list rendered no text at all');

    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
  }

  group('the search box on the real screen', () {
    testWidgets('finds a job by a trade that is not its primary one',
        (tester) async {
      final before = await search(tester, 'dzay');
      // A query nothing matches: the list empties, which is the control. If
      // this is empty the screen is not filtering at all and the rest proves
      // nothing.
      expect(before.where((t) => t == 'test'), isEmpty,
          reason: 'the screen is not narrowing, so every other case is void');

      final after = await search(tester, 'نجارة');
      expect(after, contains('test'),
          reason: 'the job the card badges with 6 trades must be findable by '
              'the carpenter\'s own word');
    });

    testWidgets('finds it by every secondary trade it declares',
        (tester) async {
      for (final word in const ['دهان', 'ترميم', 'سباكة', 'بناء', 'نجارة']) {
        final texts = await search(tester, word);
        expect(texts, contains('test'),
            reason: '«$word» is a trade this job covers and must match');
      }
    });

    testWidgets('the primary trade still matches', (tester) async {
      final texts = await search(tester, 'تشطيب');
      expect(texts, contains('test'));
    });

    testWidgets('a trade no job covers still returns nothing', (tester) async {
      final texts = await search(tester, 'حدادة');
      expect(texts.where((t) => t == 'test' || t == 'دهان فيلا'), isEmpty);
    });

    testWidgets('two jobs, one search, and it returns the right one',
        (tester) async {
      // Both jobs are multi-trade, so this is the case the old code got wrong
      // in the *opposite* direction as well: `كهرباء` is the second trade of
      // both, and only the carpenter should match `نجارة`.
      final texts = await search(tester, 'نجارة');
      expect(texts, contains('test'));
      expect(texts, isNot(contains('دهان فيلا')));
    });

    testWidgets('a cleared box restores the whole list', (tester) async {
      final texts = await search(tester, '');
      expect(texts, contains('test'));
      expect(texts, contains('دهان فيلا'));
    });
  });
}
