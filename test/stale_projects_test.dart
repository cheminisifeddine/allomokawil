// Proves a failed *re-read* on «مشاريعي» keeps the user's own projects and
// states the doubt.
//
// The sixth screen in the family the subscription bug opened, and the mildest
// of them — which is worth saying, because the family is only useful if its
// members are ranked honestly. The directory is worse: it holds the supply, so
// a blink mid-pull told a client there were no contractors. This one holds the
// user's own history, and he can still get to the marketplace. But the rows
// are the *only* record he has of jobs he posted or worked, so
// «تعذّر جلب المشاريع» is not a temporary inconvenience here — the list
// ceases to exist, and he cannot reach the detail screen of an offer he is
// choosing between. The tab strip makes it worse than a single screen: five
// pills, each a full re-read, on one bar of signal in the shop.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stale_projects_copy.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _me() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

Map<String, Object?> _job(String id, String title) => <String, Object?>{
      'id': id,
      'customer_id': 391,
      'title': title,
      'description': 'دهان غرفة',
      'category': 'painting',
      'categories': const <String>['painting'],
      'images': const <Object?>[],
      'wilaya': '16',
      'commune': 'باب الزوار',
      'budget_min': 20000,
      'budget_max': 40000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-19 20:39:41',
      'updated_at': '2026-09-19 20:39:41',
    };

/// Builds the screen against a `/my/projects` that succeeds once and then
/// fails: the exact shape of a pull-to-refresh on a dropped connection.
Future<ApiClient> _pumpProjects(
  WidgetTester tester, {
  required int succeedingReads,
  required Future<void> Function(WidgetTester) afterLoad,

  /// Reads (1-based) that answer successfully *after* the first [succeedingReads]
  /// have been spent. Exists for the one case that needs a read to fail and
  /// then recover, which a plain threshold cannot express — without it the
  /// "the doubt clears" test would fail its own second pull and prove nothing.
  Set<int> recoveringReads = const <int>{},
}) async {
  tester.view.physicalSize = const Size(1080, 2532);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  var reads = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
        return http.Response(
            jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (path.contains('/api/mobile/my/projects')) {
        reads++;
        if (reads <= succeedingReads || recoveringReads.contains(reads)) {
          return http.Response(
              jsonEncode(<dynamic>[
                _job('p1', 'دهان فيلا'),
                _job('p2', 'سباكة حمام'),
              ]),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('', 503,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<String, Object?>{}), 200,
          headers: {'content-type': 'application/json'});
    }),
    timeout: const Duration(milliseconds: 200),
  );

  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
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

  // The first read worked: the projects are on screen and there is no band,
  // because there is nothing to doubt yet.
  expect(reads, 1);
  expect(find.byKey(const Key('stale-projects')), findsNothing,
      reason: 'a successful first read must not warn about anything');
  expect(find.text('دهان فيلا'), findsOneWidget);

  await afterLoad(tester);
  return api;
}

void main() {
  group('staleProjectsLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      final line = staleProjectsLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is the state the
      // screen was already in; what was missing is the second clause, the only
      // thing that says the projects in front of the reader are real.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('a failure with no sentence still says the list may be old', () {
      expect(staleProjectsLineAr('   '), 'هذه المشاريع قد لا تكون محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleProjectsLineAr('  ${S.errOffline}  ');
      expect(line, contains('لم نتمكن من تحديث مشاريعك — هذه آخر نتيجة قرأناها. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });

    test('the wording is about the reader\'s own projects, not a market', () {
      // The directory's sentence says «القائمة» and «نتيجة قرأناها». Copying it
      // verbatim would be a lazy re-use: this list is *his* work, and the
      // sentence has to read like it.
      expect(staleProjectsLineAr(S.errOffline), contains('مشاريعك'));
    });
  });

  group('ProjectsScreen — a failed refresh is not a blank project list', () {
    testWidgets('a failed pull-to-refresh keeps the rows and says so',
        (tester) async {
      await _pumpProjects(tester, succeedingReads: 1, afterLoad: (t) async {
        // The gesture the screen itself offers.
        await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      // The defect: the projects were replaced by «تعذّر جلب المشاريع», so the
      // only record the user had of jobs he posted ceased to exist over a
      // network that blinked.
      expect(find.text('تعذّر جلب المشاريع'), findsNothing,
          reason: 'a failed refresh must not claim the projects are gone');
      expect(find.text('دهان فيلا'), findsOneWidget,
          reason: 'the rows that survived the last good read must stay');
      expect(find.byKey(const Key('stale-projects')), findsOneWidget,
          reason: 'a failed refresh must state the doubt');
      expect(find.byKey(const Key('stale-projects-line')), findsOneWidget);
    });

    testWidgets('a failed tab switch keeps the rows too', (tester) async {
      // The tab strip is this screen's *primary* interaction, so this is the
      // path a real customer takes, not the pull.
      await _pumpProjects(tester, succeedingReads: 1, afterLoad: (t) async {
        // «الكل» is the first pill and therefore in bounds; «قيد التنفيذ»
        // needs a horizontal drag on the strip first, since the strip is a
        // scrolling ListView and tap() would warn it is off-screen.
        await t.tap(find.text('الكل'));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      expect(find.text('تعذّر جلب المشاريع'), findsNothing,
          reason: 'a failed tab read must not erase the other tab\'s rows');
      expect(find.byKey(const Key('stale-projects')), findsOneWidget);
    });

    testWidgets('the band is a header, not a replacement for the list',
        (tester) async {
      await _pumpProjects(tester, succeedingReads: 1, afterLoad: (t) async {
        await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });
      // The doubt is an annotation *on* the data, so the band is a child of
      // the scrolling list itself. Asserted as a descendant rather than as an
      // item count, because a count would still pass if the band were swapped
      // in for a project: the thing that must not happen is the list being
      // replaced, and only the tree shape rules that out.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byKey(const Key('stale-projects')),
        ),
        findsOneWidget,
        reason: 'the band must be a header inside the list, not the list',
      );
      // And a project is still a child of that same list.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('دهان فيلا'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a read that succeeds again clears the doubt', (tester) async {
      // A band that outlives the failure is its own lie: the doubt must not
      // outlast the read that answered it. Only the first read succeeds and
      // only the third recovers, so the first pull fails and the second
      // answers — the screen has to come back from a band.
      await _pumpProjects(tester,
          succeedingReads: 1,
          recoveringReads: const <int>{3},
          afterLoad: (t) async {
        await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
        expect(find.byKey(const Key('stale-projects')), findsOneWidget,
            reason: 'the second read failed, so the doubt must be on screen');
          // Pull again: the same gesture, and this time the server answers.
          await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
          await t.pumpAndSettle(const Duration(seconds: 3));
        });

      expect(find.byKey(const Key('stale-projects')), findsNothing,
          reason: 'a successful read must clear the doubt');
      expect(find.text('دهان فيلا'), findsOneWidget);
    });

    testWidgets('a read still in flight shows the skeleton, never the empty state',
        (tester) async {
      // The regression this fix introduced and the loop caught: writing
      // `shown` as "(waiting or failed) and cache, else null-or-data" makes
      // "no cache" and "no rows" the same empty list, so a *waiting* first read
      // falls out of the skeleton into `_emptyList` and tells a customer on a
      // slow connection that he has no projects — before the request has
      // answered. It passed `stale_projects_test.dart` in isolation and only
      // surfaced in the full suite, which is why it is pinned here.
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Never answers — a Completer that is never completed, which is what
      // "still in flight" actually means. A 503 would resolve in a microtask
      // and test the *failed* branch instead, which is the case next door.
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((_) => Completer<http.Response>().future),
      );

      // Session from prefs only, and no `login()`: the dead client would answer
      // neither, so calling it would hang the test instead of testing anything.
      // This is the harness `skeleton_loading_test.dart` uses for the same
      // reason.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_me()),
      });
      final auth = AuthState(api);
      await auth.restore();
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
      // Bounded pumps, not `pumpAndSettle`: the skeleton animates forever, so
      // settling never returns on a screen that is still loading.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.byType(Shimmer), findsOneWidget,
          reason: 'a waiting read must show the skeleton, not the empty state');
      expect(find.text('لا مشاريع في هذه الحالة'), findsNothing,
          reason: 'an unanswered request is not an empty account');

      // Drain the client's own 20 s timeout so the test does not end with a
      // pending timer. Same teardown `skeleton_loading_test.dart` uses, and
      // the reason its dead-connection case is a *failed* read rather than a
      // hanging one.
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('a first read that fails still gets the full-screen error',
        (tester) async {
      // The fix must not weaken the branch it moves. With no cache there is
      // genuinely nothing to draw, and the retry button is the whole answer —
      // the same split `browse_screen` and `subscription_screen` use.
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
            return http.Response(
                jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
                200,
                headers: {'content-type': 'application/json'});
          }
          if (path.contains('/api/mobile/my/projects')) {
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
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

      expect(find.text('تعذّر جلب المشاريع'), findsOneWidget);
      expect(find.byKey(const Key('stale-projects')), findsNothing,
          reason: 'there is nothing to qualify — the error is the truth here');
    });
  });
}
