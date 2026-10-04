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

  /// The clock the band is dated against, when a test needs to move time.
  /// Defaults to the real one, so every existing case is unchanged.
  DateTime Function()? clock,

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
      home: ProjectsScreen(repo: Repository(api), clock: clock),
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

  group('staleProjectsAgeAr — the band says HOW old, not just that it is old',
      () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('a read inside the minute is not a number worth printing', () {
      // A pull that failed on a slow connection while the list is twenty
      // seconds old is a hiccup. «قبل 20 ثانية» under it is a reassurance
      // dressed as a measurement, and the band already said everything there
      // is to say.
      expect(staleProjectsAgeAr(base.subtract(const Duration(seconds: 20)),
          now: base), isEmpty);
    });

    test('a minute and older is counted in the app\'s own words', () {
      // Same grammar the market band prints, asserted on this surface so the
      // two cannot drift into dating one read two ways.
      expect(staleProjectsAgeAr(base.subtract(const Duration(minutes: 12)),
          now: base), 'قبل 12 دقيقة');
      expect(staleProjectsAgeAr(base.subtract(const Duration(minutes: 2)),
          now: base), 'قبل دقيقتين');
      expect(staleProjectsAgeAr(base.subtract(const Duration(hours: 3)),
          now: base), 'قبل 3 ساعات');
      expect(staleProjectsAgeAr(base.subtract(const Duration(hours: 2)),
          now: base), 'قبل ساعتين');
    });

    test('a read that crossed midnight is yesterday, not N hours', () {
      // 28 Sep 10:00 read, 29 Sep 14:00 now: **28 hours**, but it crossed one
      // midnight, so the calendar day count is 1. Asserted here because
      // `relativeTimeAr` counts **calendar** days and a future "simplification"
      // of this file into a 24-hour period count is the exact defect that made
      // one message read two ways in the chat list.
      expect(staleProjectsAgeAr(DateTime(2026, 9, 28, 10), now: base), 'أمس');
    });

    test('a read older than a year is dated, not counted in months', () {
      expect(staleProjectsAgeAr(DateTime(2024, 3, 9), now: base), contains('/'));
    });

    test('clock skew is not the future', () {
      // A stamp ahead of the phone is a broken clock between the server and
      // the handset. Ageing it would print «قبل -3 دقيقة» and blame the
      // reader\'s phone for somebody else\'s clock.
      expect(staleProjectsAgeAr(base.add(const Duration(minutes: 3)), now: base),
          isEmpty);
    });

    test('a read that never happened has no age', () {
      expect(staleProjectsAgeAr(null, now: base), isEmpty);
    });
  });

  group('staleProjectsLineWithAgeAr — the age is added, the reason is kept', () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('an undatable read produces the OLD line, byte for byte', () {
      // The contract that protects the existing screenshots of this screen. A
      // shorter "variant" here would re-open a defect on a screen that is
      // already correct, so the fallback is equality, not resemblance.
      expect(staleProjectsLineWithAgeAr(S.errOffline, null, now: base),
          staleProjectsLineAr(S.errOffline));
      expect(
          staleProjectsLineWithAgeAr(
              S.errOffline, base.subtract(const Duration(seconds: 5)),
              now: base),
          staleProjectsLineAr(S.errOffline));
    });

    test('an old read gains a second sentence, and keeps the reason', () {
      // Both halves are load-bearing: the reason says *why* the list is not
      // newer, the age says how wrong it can be.
      final line = staleProjectsLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(minutes: 12)),
          now: base);
      expect(line, contains(S.errOffline));
      expect(line, contains('لم نتمكن من تحديث مشاريعك'));
      expect(line, contains('قبل 12 دقيقة'));
      expect(line, matches(RegExp(_arabic)));
    });

    test('the age is its own sentence, so the band stays two lines tall', () {
      final line = staleProjectsLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(hours: 3)),
          now: base);
      expect(line, contains('\n'));
      expect(line.split('\n'), hasLength(2));
      expect(line.split('\n').last, 'قرأناها قبل 3 ساعات.');
    });

    test('the failure with no sentence still ages', () {
      final line = staleProjectsLineWithAgeAr(
          '   ', base.subtract(const Duration(minutes: 5)), now: base);
      expect(line, startsWith(staleProjectsLineAr('   ')));
      expect(line, contains('قبل 5 دقائق'));
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

    testWidgets('a failed tab switch does not answer with the OTHER tab',
        (tester) async {
      // The tab strip is this screen's *primary* interaction, so this is the
      // path a real customer takes, not the pull.
      //
      // **This case used to assert the defect.** It required
      // `find.text('تعذّر جلب المشاريع')` to be **absent** after a failed tab
      // switch — i.e. it passed precisely because the «مفتوح» rows were being
      // drawn under the «الكل» pill. A test written to prove "don't erase the
      // list" was welded to "don't ever say you could not read it", and the
      // second is the false half: those are four *other* projects, not a stale
      // copy of these. A customer tapping «قيد التنفيذ» to see whether his
      // renovation has started was shown four open projects as though they
      // were the running one, and the band above them said the rows were
      // *old* — which is true, and useless, because they are not his question.
      //
      // Cross-tab rows are not a fallback at all. A failed switch has nothing
      // of its own to draw, and the screen says so, because the retry is
      // already wired to *this* tab.
      await _pumpProjects(tester, succeedingReads: 1, afterLoad: (t) async {
        // «الكل» is the first pill and therefore in bounds; «قيد التنفيذ»
        // needs a horizontal drag on the strip first, since the strip is a
        // scrolling ListView and tap() would warn it is off-screen.
        await t.tap(find.text('الكل'));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      expect(find.text('دهان فيلا'), findsNothing,
          reason: 'another tab\'s rows must not be drawn under this tab');
      expect(find.byKey(const Key('stale-projects')), findsNothing,
          reason: 'the band dates the rows below it, and there are none here');
      expect(find.text('تعذّر جلب المشاريع'), findsOneWidget,
          reason: 'a failed switch must say it could not read THIS tab');
    });

    testWidgets('a pull inside one tab still keeps the rows (unchanged tab)',
        (tester) async {
      // The half of the rule that must not move: the same question asked twice
      // still falls back, because there the rows genuinely are a stale copy of
      // what is on screen. The cross-tab fix is scoped to the tab, not to "any
      // failed read", and this is what stops a future tick from widening it.
      await _pumpProjects(tester, succeedingReads: 1, afterLoad: (t) async {
        await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      expect(find.text('دهان فيلا'), findsOneWidget);
      expect(find.byKey(const Key('stale-projects')), findsOneWidget);
    });

    testWidgets('two taps in a row: neither read is filed under the wrong tab',
        (tester) async {
      // The race the parameterised [_arm] exists for. Both reads are issued
      // before either answers, so the callback that settles second is running
      // while `_status` already names the third thing the user tapped. Reading
      // `_status` inside the callback — the one-line version of this fix — tags
      // the *first* read's rows with the *second* tab, which is the identical
      // mislabelling one level down.
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      // Opened up front so the handler can park on it; closed by the test.
      final gates = <int, Completer<void>>{1: Completer<void>()};
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
            // **Read 1 is parked and then SUCCEEDS; read 2 fails.**
            //
            // Both halves matter, and the first version of this case got the
            // second one wrong in a way that made the whole test vacuous: it
            // failed *both* reads, so no cache was ever written, the screen had
            // nothing to mislabel, and the test passed against the unfixed
            // source. A case that cannot fail is not evidence.
            //
            // Read 1 succeeds, so the «مفتوح» rows reach the cache — and they
            // reach it *after* the tap has moved `_status` to «الكل». Read 2
            // (issued by that tap, answering immediately) fails. So the cache
            // holds one tab's rows while the other tab is on screen, which is
            // the only state in which the mislabelling can happen at all.
            if (reads == 1) {
              await gates[1]!.future;
              return http.Response(
                  jsonEncode(<dynamic>[_job('p1', 'دهان فيلا')]),
                  200,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        // **Long, deliberately.** The other cases here use 200 ms so a 503
        // settles inside a `pumpAndSettle`, but this one parks a read on
        // purpose, and at 200 ms the client's own `.timeout` fired while the
        // test was still arranging the race — the read became a *failure*, no
        // cache was ever written, and the case passed against the unfixed
        // screen. A test that passes on the bug it was written to catch is
        // worse than no test, because the next tick reads it as coverage.
        timeout: const Duration(seconds: 20),
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
      // Bounded pumps, not `pumpAndSettle`: the waiting read draws a Shimmer,
      // which animates forever, so settling never returns.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      // Tap «الكل» while the first read is still open, then release read 1 so
      // it lands *after* the tab has already moved.
      await tester.tap(find.text('الكل'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(reads, 2, reason: 'the tap must issue its own read');
      gates[1]!.complete();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Read 1 succeeded for «مفتوح» and landed under the «الكل» tab; read 2
      // failed for «الكل». Those rows belong to another tab, so nothing of them
      // may answer this one.
      expect(find.text('دهان فيلا'), findsNothing,
          reason: 'the «مفتوح» rows must not answer the «الكل» tab');
      expect(find.text('تعذّر جلب المشاريع'), findsOneWidget);
    });

    testWidgets('a late SUCCESS cannot replace newer rows with older ones, nor '
        're-date them as if they were just read', (tester) async {
      // **The generation token [_arm] does not have, and every other arming
      // screen in this app does.** `chat_list_screen` (`_armToken`),
      // `worker_home_screen` (`_feedToken`, `_conversationToken`) and
      // `customer_home_screen` (`_workersToken`, `_projectsToken`) all ignore
      // a read that settles after a newer one was issued. This file is the one
      // arming screen left that writes unconditionally, and the tab-keyed
      // `_cache` cannot catch the case below — because both reads asked the
      // **same** tab.
      //
      // The sequence is three taps on a phone, all ordinary: open «مشاريعي»
      // (read 1, «مفتوح»), tap «الكل» (read 2), tap «مفتوح» again (read 3).
      // Three reads, two of them in flight at once on one bar of signal. Read
      // 3 answers with the newest rows and `_cache.readAt` is dated when it
      // lands. Then read 1 — issued **forty minutes earlier** and parked on a
      // slow connection the whole time — lands last, and its `then` writes
      // `_cache` over the record: its older rows, stamped `_now()`.
      //
      // The damage is invisible for one frame and then permanent. The rows
      // drawn come from the FutureBuilder, so read 1 does not change what is
      // on screen *yet*. The next refresh fails, and then two things are wrong
      // at once, both from that one late write:
      //
      //   1. the fallback draws **read 1's rows**, so a project the newest
      //      read for this very tab listed has vanished from the customer's
      //      own project list — over a read he abandoned before it answered;
      //   2. the band dates them **read 1's landing time**, not the time the
      //      rows were true, so «ما ن-displayه» is reported 40 minutes fresher
      //      than it is. On this screen the age is the half that decides
      //      whether he restarts a job from nothing.
      //
      // Both halves are asserted, and the numbers are an hour apart on purpose
      // so a predicate that took the wrong stamp cannot be mistaken for the
      // right one.
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var now = DateTime(2026, 9, 29, 9, 0);
      final gates = <int, Completer<void>>{1: Completer<void>()};
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
            if (reads == 1) {
              // Read 1 (initState, «مفتوح») is issued at 09:00 and parked.
              // Its answer is the OLD state of the tab: one project only.
              await gates[1]!.future;
              return http.Response(
                  jsonEncode(<dynamic>[_job('p1', 'دهان فيلا')]),
                  200,
                  headers: {'content-type': 'application/json'});
            }
            // Read 3 (the second «مفتوح» tap, landing at 09:40) and read 2
            // both see a job that read 1's answer cannot contain — it was
            // posted while read 1 was in the air. That difference is the
            // evidence, and it has to be in the data: two identical answers
            // would make the case vacuous.
            if (reads >= 4) {
              return http.Response('', 503,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response(
                jsonEncode(<dynamic>[
                  _job('p1', 'دهان فيلا'),
                  _job('p2', 'سباكة حمام'),
                ]),
                200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        // Long, deliberately: read 1 is MEANT to hang, and a 200 ms timeout
        // fires while it is parked and turns this into a failed-read case it
        // is not. The same trap the race case above documents, hit a second
        // time.
        timeout: const Duration(seconds: 20),
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
          home: ProjectsScreen(repo: Repository(api), clock: () => now),
        ),
      ));
      // Bounded pumps, not `pumpAndSettle`: the parked read draws a Shimmer,
      // which animates forever, so settling never returns while it is open.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(reads, 1, reason: 'the first read must be issued and parked');

      // Tap «الكل» (read 2, answers at once) then «مفتوح» again (read 3).
      //
      // The tap target is the **pill**, not the word. `find.text('مفتوح')`
      // finds three widgets once the rows are on screen — the tab label and
      // the status pill on each card — and `tap()` refuses an ambiguous
      // finder, so the first run of this case failed on its own setup with a
      // finder error and proved nothing about the defect. Scoped to the
      // horizontal strip, which is the only one in the tree: the project list
      // itself scrolls vertically.
      final strip = find.byWidgetPredicate((w) =>
          w is ListView && w.scrollDirection == Axis.horizontal);
      await tester.tap(find.descendant(
          of: strip, matching: find.text('الكل')));
      await tester.pump(const Duration(milliseconds: 50));
      now = DateTime(2026, 9, 29, 9, 40);
      await tester.tap(find.descendant(
          of: strip, matching: find.text('مفتوح')));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(reads, 3, reason: 'both taps must issue their own read');
      expect(find.text('سباكة حمام'), findsOneWidget,
          reason: 'the newest read for this tab listed two jobs');

      // Read 1 lands last, at 09:40, carrying the 09:00 answer.
      gates[1]!.complete();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // The next refresh fails at 11:00, so the band is drawn and the fallback
      // rows are drawn. Read 1's late write is only visible here, which is
      // exactly why this case cannot assert anything before the failure.
      //
      // **The hour, not the twenty minutes this first used.** The rows on
      // screen were true at 09:40 and a stamp of `_now()` at read 1's landing
      // would be 09:40 as well — the two candidates were the same number, so
      // the discriminator could not discriminate and the case passed on the
      // bug it was written to catch. An hour out makes them an hour and eighty
      // minutes, which no rounded wording can collapse into one string.
      now = DateTime(2026, 9, 29, 11, 0);
      await tester.drag(find.text('سباكة حمام'), const Offset(0, 340));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // **Half 1 — the rows.** The two-project answer for this very tab is
      // still the newest one, and an answer the user replaced is not allowed to
      // replace it.
      expect(find.text('سباكة حمام'), findsOneWidget,
          reason: 'a read issued at 09:00 and answered at 09:40 must not '
              'delete a job the 09:40 read listed for this tab');

      // **Half 2 — the stamp.** The rows on screen were true at 09:40, so the
      // band must say an hour and a half, not eighty minutes.
      final band =
          tester.widget<Text>(find.byKey(const Key('stale-projects-line')))
              .data!;
      expect(band, contains('قبل ساعة'),
          reason: 'the rows were read at 09:40, so at 11:00 they are an hour '
              'and a half old; got: ${band.replaceAll('\n', ' / ')}');
      expect(band, isNot(contains('قبل 80 دقيقة')),
          reason: 'eighty minutes is the landing time of a read issued at '
              '09:00: an abandoned answer cannot be the stamp on the rows it '
              'did not replace — got: ${band.replaceAll('\n', ' / ')}');
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

  group('ProjectsScreen — the band dates the read it is qualifying', () {
    testWidgets('a failed refresh says how old the surviving rows are',
        (tester) async {
      // The band already said «هذه آخر نتيجة قرأناها». What it could not say is
      // how long ago that was, and for *this* screen it is not a nicety: these
      // rows are the only record the customer has of the jobs he posted, so a
      // list that failed at 09:00 and one that failed an hour ago printing the
      // same confident sentence is how he restarts a job from nothing.
      var now = DateTime(2026, 9, 29, 9, 0);
      await _pumpProjects(
        tester,
        succeedingReads: 1,
        clock: () => now,
        afterLoad: (t) async {
          await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
          await t.pumpAndSettle(const Duration(seconds: 3));
        },
      );


      // Twelve minutes later the list fails to re-read.
      now = DateTime(2026, 9, 29, 9, 12);
      await tester.drag(find.text('دهان فيلا'), const Offset(0, 340));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final band = tester.widget<Text>(find.byKey(
          const Key('stale-projects-line')));
      final text = band.data!;
      // Both halves: the reason says why the list is not newer, the age says
      // how wrong it can be. A band that traded one for the other is worse
      // than the band it replaces.
      expect(text, contains(S.errServer));
      expect(text, contains('لم نتمكن من تحديث مشاريعك'));
      expect(text, contains('قبل 12 دقيقة'));
    });

    testWidgets('a fresh read is not dated, and the old wording is untouched',
        (tester) async {
      // The contract that protects this screen\'s existing screenshots: a read
      // inside the minute produces the OLD line, byte for byte. A shorter
      // "variant" would silently re-open a defect on a screen already correct.
      var now = DateTime(2026, 9, 29, 9, 0);
      await _pumpProjects(
        tester,
        succeedingReads: 1,
        clock: () => now,
        afterLoad: (t) async {
          // Before the pull, a good read has nothing to qualify.
          expect(find.byKey(const Key('stale-projects-line')), findsNothing,
              reason: 'a successful first read must not print an age');
          now = DateTime(2026, 9, 29, 9, 0, 20); // 20 seconds later
          await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
          await t.pumpAndSettle(const Duration(seconds: 3));
        },
      );

      final text =
          tester.widget<Text>(find.byKey(const Key('stale-projects-line')))
              .data!;
      expect(text, staleProjectsLineAr(S.errServer),
          reason: 'a read still inside the minute must read exactly as it did '
              'before the age existed — «قبل 20 ثانية» would be a reassurance '
              'dressed as a measurement');
    });

    testWidgets('the age advances on its own, without a re-read',
        (tester) async {
      // The tick is the half a stamp alone does not give. Without it the age is
      // frozen at whatever it said when the failure landed: a customer who
      // leaves the tab open over a coffee break keeps reading «قبل 12 دقيقة»
      // on a list that is now an hour old — the same lie in a slower costume.
      var now = DateTime(2026, 9, 29, 9, 0);
      await _pumpProjects(
        tester,
        succeedingReads: 1,
        clock: () => now,
        afterLoad: (t) async {
          now = DateTime(2026, 9, 29, 9, 12);
          await t.drag(find.text('دهان فيلا'), const Offset(0, 340));
          await t.pumpAndSettle(const Duration(seconds: 3));
        },
      );
      expect(find.textContaining('قبل 12 دقيقة'), findsOneWidget);

      // Fifty minutes pass with no request issued at all. Nothing is pulled,
      // nothing is refetched — the only thing that moves is the clock. Still
      // inside the hour arm, so the answer is a minute count; the boundary is
      // deliberately left to the pure cases above rather than guessed here.
      now = DateTime(2026, 9, 29, 9, 50);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('قبل 12 دقيقة'), findsNothing,
          reason: 'a frozen age is the same confidently-wrong claim this file '
              'was opened for, in slower motion');
      // Counted from the **successful read at 09:00**, not from the failure at
      // 09:12 — the age describes when the rows were true, which is the whole
      // point of it. (My first guess here was 38, measured from the failure,
      // and the screen correctly refused it.)
      expect(find.textContaining('قبل 50 دقيقة'), findsOneWidget,
          reason: 'the tick must age the band without a re-read');
    });
  });
}
