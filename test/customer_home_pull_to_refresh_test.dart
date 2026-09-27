// Pull-to-refresh on the client home — the screen the founder opens first, and
// the last big read in the app with no way to refresh a page that has gone
// stale.
//
// Found on 27 Sep 2026, immediately after the contractor search got the same
// treatment. `browse_screen`, `chat_list_screen`, `notifications_screen`,
// `projects_screen` and `subscription_screen` all wrapped their read in a
// `RefreshIndicator`; the client home did not. A client coming back after an
// hour — a contractor who signed up across town, a quote that landed on his
// project, his own project moved to «قيد التنفيذ» — got the same screen, and
// the only way to move it was to kill the app. The explore tab is the page with
// the most that can change while it is open, so it is the worst one to have
// this on.
//
// This one is the hard case the other five were not, and the reason it gets
// its own file. One gesture here stands for **three** independent reads — the
// top contractors, the client's own projects, and the conversations that
// decide the first-run guide — and each can fail on its own. So the file is
// written around the two questions a single-future screen never has to answer:
//
//   * what does the indicator wait on?  (all three, and nothing shorter)
//   * what does it say when one of the three is dead?  (its own message, in
//     place — never a generic failure that throws away the two that worked)
//
// A third rule is asserted here that no sibling screen has to think about: a
// **visitor** has no account, so his pull must not request the two
// session-only strips. The founder saw the «تعذّر جلب المشاريع» this used to
// produce for a man who had never signed in.
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
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
        headers: {'content-type': 'text/html'});

Map<String, Object?> _user({String type = 'customer'}) => {
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// A contractor row as D1 files it.
Map<String, Object?> _worker(int id, String name) => {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': 'دهان وتشطيب',
      'specialties': <String>['painting'],
      'experience_years': 9,
      'price_range_min': 20000,
      'price_range_max': 90000,
      'service_radius_km': 15,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_rib_exported': 0,
      'rating_avg': 4.6,
      'rating_count': 12,
      'response_time_hours': 3,
      'commune': 'باب الزوار',
      'wilaya': '16',
      'completed_jobs': 40,
      'avatar_url': null,
    };

/// A project row as D1 files it.
Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'دهان كامل',
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

/// A conversation row as D1 files it.
Map<String, Object?> _conversation(int id) => {
      'id': id,
      'customer_id': 30,
      'worker_user_id': 31,
      'project_id': null,
      'last_message_at': '2026-09-11 20:23:47',
      'created_at': '2026-09-11 20:23:47',
      'other_user_name': 'مقاول تجربة',
      'other_user_avatar': null,
      'last_message_content': 'مرحبا',
      'unread_count': 0,
    };

/// The three reads the explore tab owns, plus the traffic they cause on the
/// way. Every endpoint is recorded so a test can count *requests* rather than
/// frames — the only number that distinguishes "the pull re-read the strips"
/// from "the pull happened but re-read nothing".
class _Platform {
  _Platform({
    this.guest = false,
    this.workers = _okWorkers,
    this.projects = _okProjects,
  });

  /// A signed-out visitor: the screen must not request the session-only reads.
  final bool guest;

  /// Answer for each read, told which attempt it is serving.
  final Future<http.Response> Function(int attempt) workers;
  final Future<http.Response> Function(int attempt) projects;

  final List<String> log = <String>[];
  int _workerAttempts = 0;
  int _projectAttempts = 0;
  int _conversationAttempts = 0;

  int get workerReads => _workerAttempts;
  int get projectReads => _projectAttempts;
  int get conversationReads => _conversationAttempts;

  static Future<http.Response> _okWorkers(int _) async =>
      _json(<Object?>[_worker(1, 'مقاول قديم')]);

  static Future<http.Response> _okProjects(int _) async =>
      _json(<Object?>[_project('p1', 'مشروع قديم')]);

  static Future<http.Response> _okConversations(int _) async =>
      _json(<Object?>[_conversation(1)]);

  ApiClient client() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          log.add('${req.method} $p');
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.contains('/api/unread')) return _json({'unread': 0});
          if (p.contains('/workers/top')) {
            return workers(_workerAttempts++);
          }
          if (p.contains('/my/projects')) return projects(_projectAttempts++);
          if (p.contains('/conversations')) {
            return _okConversations(_conversationAttempts++);
          }
          if (p.contains('/notifications')) return _json(<Object?>[]);
          if (p.contains('/reviews')) return _json(<Object?>[]);
          if (p.contains('/portfolio')) return _json(<Object?>[]);
          if (p.contains('/my/profile')) return _json(_user());
          if (p.contains('/workers')) {
            return _json(<Object?>[_worker(1, 'مقاول قديم')]);
          }
          return _json(<Object?>[]);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Platform platform})> _boot(
  _Platform platform,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = platform.client();
  final auth = AuthState(api);
  await auth.restore();
  if (!platform.guest) {
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
  }
  return (api: api, auth: auth, platform: platform);
}

/// Scrolls the explore page far enough down for the projects strip to be built.
///
/// This is not tidiness, it is a measurement rule. The explore tab is a
/// `CustomScrollView` of slivers, and the projects strip sits roughly 1100
/// logical px below the fold on a 392x829 phone — so a lazy sliver never builds
/// it and its `FutureBuilder` never runs. An assertion on a project title
/// passes or fails on whether the *viewport* happened to reach it, not on
/// whether the refresh worked. Every test that cares about the projects strip
/// scrolls it in first.
///
/// Found by instrumenting the boot log on 27 Sep: the first `my/projects` read
/// visible at rest belongs to the **projects tab** (an `IndexedStack` builds
/// all four children), not to the explore strip, which is why the count looked
/// like it started at 2.
Future<void> _revealProjects(WidgetTester tester) async {
  await tester.drag(
      find.byType(CustomScrollView).first, const Offset(0, -1600));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
) async {
  tester.view.physicalSize = const Size(1080, 2280);
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
      home: const CustomerHomeScreen(),
    ),
  ));
  await _settle(tester);
}

/// Drags the explore tab downward — the pull-to-refresh gesture — and pumps the
/// frames the indicator needs to accept it.
///
/// Anchored on the scroll view *under the indicator*, never on
/// `find.byType(Scrollable).last`: the shell is an `IndexedStack`, so the page
/// carries the contractor strip's horizontal list, the projects tab and the
/// messages tab as well, and a positional finder silently starts aiming at
/// whichever one is built last. The same trap cost a tick on 27 Sep, on
/// `offline_taxonomy_test`.
Future<void> _pull(WidgetTester tester) async {
  final page = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(Scrollable),
  );
  expect(page, findsWidgets, reason: 'the explore tab must be pullable');
  await tester.fling(
      find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // ── The gesture reaches the screen at all ──────────────────────────────
  testWidgets('a settled home that is pulled re-reads all three strips',
      (tester) async {
    final b = await _boot(_Platform());
    await _pump(tester, b.api, b.auth);
    // Captured before the gesture, not assumed: the projects tab's own boot
    // read means the absolute number is not this loop's to predict.
    final projectsAtRest = b.platform.projectReads;
    expect(find.text('مقاول قديم'), findsOneWidget);
    expect(b.platform.workerReads, 1);
    expect(b.platform.conversationReads, 1,
        reason: 'the first-run guide reads conversations, so a signed-in '
            'client has issued that one by the time the home settles');
    // `projectReads` is deliberately NOT asserted as 1 here: the shell is an
    // `IndexedStack`, so the projects tab fires its own `my/projects` at boot
    // and the explore strip's is a second, indistinguishable request. The
    // count is asserted *relative* to a captured baseline further down, which
    // is the only form of this assertion that is honest.

    await _pull(tester);

    expect(b.platform.workerReads, 2,
        reason: 'the pull must re-read the contractor strip');
    expect(b.platform.projectReads, projectsAtRest + 1,
        reason: 'the pull must re-read the client\'s own projects on top of '
            'the reads the other tabs already made');
    expect(b.platform.conversationReads, 2,
        reason: 'the pull must re-read the conversations the guide is '
            'derived from — skipping it would leave a client who just posted '
            'staring at a first-run card that should have retired');
  });

  testWidgets('a pull publishes the new answers, not the page it replaced',
      (tester) async {
    final b = await _boot(_Platform(
      workers: (i) async => _json(<Object?>[
        _worker(1, i == 0 ? 'مقاول قديم' : 'مقاول جديد'),
      ]),
      projects: (i) async => _json(
          <Object?>[_project('p1', i == 0 ? 'مشروع قديم' : 'مشروع جديد')]),
    ));
    await _pump(tester, b.api, b.auth);
    await _revealProjects(tester);
    expect(find.text('مقاول قديم'), findsOneWidget);
    expect(find.text('مشروع قديم'), findsOneWidget);

    // Back to the top, or the fling has nothing to pull against: the gesture
    // only fires when the page is at scroll offset zero.
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    await _pull(tester);
    await _revealProjects(tester);

    expect(find.text('مقاول جديد'), findsOneWidget,
        reason: 'the pull must publish the new contractor');
    expect(find.text('مقاول قديم'), findsNothing,
        reason: 'the replaced contractor must be gone');
    // `findsWidgets`, not `findsOneWidget`: a `ProjectCard` renders its title
    // twice — once as the heading and once inside the category chip, because
    // the title was chosen to be a trade name and the chip is built from the
    // row's category. Insisting on exactly one here would be asserting a fact
    // about the card, not about the refresh.
    expect(find.text('مشروع جديد'), findsWidgets,
        reason: 'the pull must publish the new project');
    expect(find.text('مشروع قديم'), findsNothing,
        reason: 'the replaced project must be gone');
  });

  // ── The contract: what the indicator waits on ─────────────────────────
  testWidgets('the indicator is held until every read behind it has answered',
      (tester) async {
    // The mutation this kills: `await Future.wait([...])` shortened to the
    // first future, or to a bare fire-and-forget. On this page that is not a
    // cosmetic difference — two of the three strips would still be loading
    // behind a spinner that had already gone, so the home would announce
    // itself as fresh while showing the answer the user was trying to
    // replace.
    //
    // Keyed on a flag, not on an attempt number. Attempt indices are shared
    // with the projects tab, which reads for itself inside the `IndexedStack`,
    // so the strip's first request is not attempt 0 and its post-pull request
    // is not attempt 1 — an index-keyed delay silently never fires and the
    // test measures nothing. It did exactly that on the first run of this file,
    // which is why the fast/slow ordering kept coming out wrong.
    var slowProjects = false;
    final b = await _boot(_Platform(
      workers: (i) async => _json(<Object?>[
        _worker(i == 0 ? 1 : 2, i == 0 ? 'مقاول قديم' : 'مقاول جديد')
      ]),
      projects: (i) async {
        if (!slowProjects) {
          return _json(<Object?>[_project('p1', 'مشروع قديم')]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return _json(<Object?>[_project('p2', 'مشروع جديد')]);
      },
    ));
    await _pump(tester, b.api, b.auth);
    final projectsAtRest = b.platform.projectReads;
    expect(b.platform.workerReads, 1);
    // From here on the projects read answers at ~1500 ms and the contractors
    // read answers immediately.
    slowProjects = true;

    await tester.fling(
        find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
    // Step 1 — wait until the pull has actually reached the read. Measured, not
    // guessed: on this page the indicator accepts the gesture and the callback
    // fires at ~300 ms, so a single `pump(400ms)` races the *fling*, not the
    // contract, and the whole test ends up measuring the gesture animation.
    for (var i = 0; i < 20 && b.platform.workerReads < 2; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(b.platform.workerReads, 2,
        reason: 'the pull must have reached the read by now');

    // Step 2 — the assertion below has to be taken in a window where the fast
    // read is **published** and the slow one is **provably still in flight**.
    // This is the second version of this test; the first two asserted at the
    // instant the fast read landed, where the indicator is on screen in the
    // fixed build *and* in a build that awaits only `reads.first`, so the
    // mutant survived both. Two conditions, in order:
    //   * the new contractor row is visible — the fast read has not just
    //     resolved, it has been rendered, so a `reads.first` build is already
    //     running its ~200 ms exit animation;
    //   * then 600 ms more. The projects read answers at ~1500 ms, so it is
    //     demonstrably unfinished, and any exit animation has long since
    //     finished and removed the spinner.
    for (var i = 0; i < 20 && find.text('مقاول جديد').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('مقاول جديد'), findsOneWidget,
        reason: 'the fast read must have answered and been published');
    await tester.pump(const Duration(milliseconds: 600));
    // The projects read is issued by the **state**, not by the sliver: the
    // future is created in `didChangeDependencies` and re-created by
    // `_reloadProjects`, so a request goes out even though the strip is still
    // unbuilt below the fold. That is the point — the indicator waits on the
    // futures the state holds, so a pull that skipped a strip nobody can see
    // yet would still be waiting when he scrolls down to it.
    //
    // I first wrote this assertion backwards, assuming an unbuilt sliver had
    // issued nothing. Instrumenting the boot log on 27 Sep is what corrected
    // it: a signed-in client shows *two* `my/projects` at rest — the projects
    // tab's and the explore strip's — before any pull.
    expect(b.platform.projectReads, projectsAtRest + 1,
        reason: 'the pull must re-read the projects strip even while it is '
            'still below the fold, and must wait for it');
    expect(find.byType(RefreshProgressIndicator), findsOneWidget,
        reason: 'the indicator must outlive an unanswered read on *any* of '
            'the three strips, not just the one that happened to be slow');

    // Past the 1500 ms projects read, then long enough for the indicator to
    // finish its own exit animation.
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('مقاول جديد'), findsOneWidget);
    expect(find.text('مشروع جديد'), findsWidgets);
  });

  // ── The contract: what it says when one of the three is dead ──────────
  testWidgets('a failed strip is named in place and the other two still land',
      (tester) async {
    // The mutation this kills: letting the gesture itself throw when one read
    // fails. `Future.wait` without an error handler rejects on the first
    // error, which would take the indicator down early *and* — in the shape a
    // careless fix takes — leave the two healthy strips showing nothing at
    // all. One dead request must not cost the user the two that answered.
    final b = await _boot(_Platform(
      workers: (i) async =>
          i == 0 ? _boom() : _json(<Object?>[_worker(1, 'مقاول أول')]),
    ));
    await _pump(tester, b.api, b.auth);
    expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);

    await _pull(tester);
    await _settle(tester);
    await _revealProjects(tester);

    expect(b.platform.workerReads, 2, reason: 'the pull must have been issued');
    expect(find.text('مقاول أول'), findsOneWidget,
        reason: 'the strip that answered must be published');
    expect(find.text('مشروع قديم'), findsWidgets,
        reason: 'a dead contractor read must not cost the client his own '
            'projects — the whole point of the per-strip contract');
    expect(find.byType(RefreshProgressIndicator), findsNothing,
        reason: 'a failed pull must still take the indicator down');
  });

  testWidgets(
      'a failed projects read is named too, and the contractor strip '
      'survives it', (tester) async {
    final b = await _boot(_Platform(
      projects: (i) async =>
          i == 0 ? _boom() : _json(<Object?>[_project('p1', 'مشروع أول')]),
    ));
    await _pump(tester, b.api, b.auth);
    await _revealProjects(tester);
    expect(find.text('تعذّر جلب المشاريع'), findsOneWidget,
        reason: 'the projects strip\'s own error state, in place');

    // Back to the top for the gesture.
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    await _pull(tester);
    await _settle(tester);
    await _revealProjects(tester);

    expect(find.text('مشروع أول'), findsWidgets,
        reason: 'a pull that recovers one strip must publish its answer');
    expect(find.text('مقاول قديم'), findsOneWidget,
        reason: 'the other strip must be unaffected by this one\'s failure');
  });

  // ── The guest rule: no account, no session-only reads ─────────────────
  testWidgets('a visitor\'s pull asks for the contractor strip only',
      (tester) async {
    // The founder saw «تعذّر جلب المشاريع» on the home of a man who had
    // never signed in, and the screen was already fixed not to request it at
    // boot. A pull that re-issued those reads would walk straight back into
    // the same fault, one gesture later.
    final b = await _boot(_Platform(guest: true));
    await _pump(tester, b.api, b.auth);
    await _revealProjects(tester);
    expect(find.text('مشاريعك تظهر هنا'), findsOneWidget,
        reason: 'the strip shows the way in instead of a fault');
    expect(find.text('تعذّر جلب المشاريع'), findsNothing,
        reason: 'the exact failure the founder reported must never appear');

    // Baseline the shell's own traffic, and say why the absolute numbers are
    // not this test's to assert. `CustomerHomeScreen` holds an `IndexedStack`,
    // so `ProjectsScreen` and `ChatListScreen` are built and read for
    // themselves whether or not anyone is signed in — instrumented and
    // measured on 27 Sep: a signed-out visitor still produces one
    // `my/projects` and one `conversations` at boot, from those two tabs.
    // They own that traffic and it is not a leak; what this file owns is the
    // **explore strip**, and the contract there is that a pull adds nothing on
    // top of what the shell already does.
    final projectsAtRest = b.platform.projectReads;
    final conversationsAtRest = b.platform.conversationReads;
    expect(projectsAtRest, greaterThanOrEqualTo(0));
    expect(conversationsAtRest, greaterThanOrEqualTo(0));
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, 1600));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));

    await _pull(tester);
    await _revealProjects(tester);

    expect(b.platform.workerReads, 2,
        reason: 'the one strip a visitor has must still refresh');
    expect(b.platform.projectReads, projectsAtRest,
        reason: 'a signed-out pull must not add an account-only read of its '
            'own — the only `my/projects` on this screen is the projects '
            'tab\'s, and the gesture must not trigger another');
    expect(b.platform.conversationReads, conversationsAtRest,
        reason: 'and must not re-read his messages either');
    expect(find.text('مشاريعك تظهر هنا'), findsOneWidget,
        reason: 'the invite must survive the gesture');
    expect(find.text('تعذّر جلب المشاريع'), findsNothing,
        reason: 'the exact failure the founder reported must never appear');
  });

  // ── The widget contract, pinned on the widget ─────────────────────────
  testWidgets(
      'the explore page stays scrollable under the indicator, so the '
      'gesture survives a home shorter than the phone', (tester) async {
    // `AlwaysScrollableScrollPhysics` is what lets a page that does not
    // overflow accept the pull. Asserted on the widget rather than through a
    // fling because the explore tab is *always* taller than the viewport, so
    // no behavioural test can distinguish the two physics here — and a
    // contract that cannot be tested is a contract that quietly disappears.
    final b = await _boot(_Platform());
    await _pump(tester, b.api, b.auth);

    // Scoped by axis, not by position. The indicator is over the explore page,
    // but the contractor strip inside it is a *horizontal* `ListView`, and it
    // is built as its own scrollable under the same indicator — so
    // `findsOneWidget` is wrong here and `findsNWidgets(n)` would be right only
    // by accident. The vertical one is the page; the horizontal ones are the
    // strip, which must keep its own default physics (a horizontal rail that
    // could not be flicked sideways would be a different bug).
    // One predicate, not two composed finders: a `Scrollable` is not a
    // descendant of another `Scrollable`, so `descendant(of: page, …)` finds
    // nothing. The mistake is quiet — it reads like a scoping refinement and
    // reports a missing widget rather than a broken finder.
    final vertical = find.descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down),
    );
    expect(vertical, findsOneWidget,
        reason: 'exactly one vertical scroll view owns the explore page');
    expect(tester.widget<Scrollable>(vertical).physics,
        isA<AlwaysScrollableScrollPhysics>(),
        reason: 'a client whose whole home fits on one screen must still be '
            'able to pull it');
    //
    // This assertion does NOT kill the deletion of the explicit line: measured
    // on 27 Sep, deleting `physics:` leaves all eight tests green at +8,
    // because `ScrollView` already defaults a vertical, controllerless scroll
    // view to exactly this physics (scroll_view.dart:141-148). It is an
    // equivalent mutant, the same one the contractor-search test recorded a
    // tick earlier.
    //
    // So this is a contract pin, not a proof. It is kept because the
    // alternative is a line whose necessity nobody can state, and the cost of
    // stating the intent is one assertion. What it buys is a *change* — a
    // future edit that gives this page a controller, or switches it to
    // `physics: null` explicitly, fails here with a message that says why,
    // instead of silently changing whether a short home can be pulled.
  });

  testWidgets('the indicator is themed like every other pull in the app',
      (tester) async {
    final b = await _boot(_Platform());
    await _pump(tester, b.api, b.auth);

    final indicator =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator).first);
    expect(indicator.color, AppTheme.navy,
        reason:
            'the spinner is the brand\'s own navy, as on every other screen');
    expect(indicator.backgroundColor, AppTheme.surface);
  });
}
