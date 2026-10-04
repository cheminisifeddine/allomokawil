// A pull-to-refresh that landed *after* the contractor was already looking at
// a newer header puts the previous profile back over it — and on the way there
// it throws the header away twice.
//
// Found on 4 Oct 2026, 52nd tick, by the audit the 51st tick's "Next" named:
// `worker_home_screen._readProfileForRefresh`, the last of the 38 `await` +
// `setState` methods in the app that carry no token guard. The four ticks
// before it closed the same family in [`my_portfolio_screen._load`] and
// `notifications_screen`, and the shape is the same here with the arms the
// other way round: this method *replaces* the read's future on the way out and
// *restores* the captured pair on the way back, and neither write checks
// whether it is still the read that owns the header.
//
// The doc comment on the method says the restore is the point — "a failed
// profile read must not cost him the header". The restore is right, and it is
// still the defect:
//
//   * **A pull blanks the header while it is in the air.** `setState` installs
//     `next` over a *working* `_me`, so `FutureBuilder` resubscribes, resets to
//     `ConnectionState.none` and paints `_skeletonRows()` (async.dart:612-622).
//     His name, his stats, his three tool tiles and his plan row are replaced by
//     grey bars every single time he refreshes, on a healthy connection, for as
//     long as the request takes — which on a phone connection in Algiers is
//     seconds, not milliseconds. The gesture he pulled to *see* something new
//     is the thing that hides what he already had.
//   * **A late failure restores a header that is no longer the one on
//     screen.** `previous` was captured at issue, and nothing between the issue
//     and the `catch` re-checks it. So read A fails late, after read B landed:
//     the header snaps from B back to A, and B's freshness stamp is replaced by
//     A's — the exact lie `stats_freshness_test.dart` was written to prevent,
//     reached from a different direction.
//
//   read A  09:00  pull — installs read A over a working header
//   read B  09:00  retry tapped (or a second pull) — installs read B
//   read B  09:01  lands: server says 9 jobs, header shows 9
//   read A  09:02  the connection finally answers: 500
//                  → catch puts A's captured pair back → header shows A, and
//                    the stats line dates numbers the server has superseded
//
// Two reads are not a corner case here: `_retryProfile` and the pull both call
// the same install, and `RefreshIndicator._shouldStart` only refuses a *drag*
// while one is in the air — it does not refuse a second `onRefresh`, and it
// never sees the retry button, which is reachable the whole time a read is
// open (that is the point of it).
//
// The fix is one counter, `_profileEpoch`, shared by every arm that installs
// and every arm that restores: a per-read token is not enough here for the same
// reason it was not enough in the portfolio — the restore is a *write*, and
// writes are what supersede.
import 'dart:async';
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape.
http.Response _boom() => http.Response('<html>boom</html>', 500,
    headers: {'content-type': 'text/html'});

Map<String, Object?> _user() => {
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// Real history, so the stats line renders at all: the header gates it on
/// `hasHistory`, and a fixture with zero jobs measures the *gate* instead of
/// the defect.
Map<String, Object?> _worker({int jobs = 4}) => {
      'id': 16,
      'user_id': 31,
      'bio': 'دهان وديكور',
      'specialties': <String>['painting'],
      'experience_years': 5,
      'price_range_min': 20000,
      'price_range_max': 60000,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'verification_status': 'verified',
      'subscription_plan': 'free_trial',
      'avg_rating': 4.6,
      'total_reviews': 12,
      'total_completed_jobs': jobs,
      'response_time_hours': 2,
      'cover_image_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'full_name': 'مقاول تجربة',
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': 'https://x.test/a.png',
    };

Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'أعمال جافة',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'باب الوادي',
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

/// The platform under the contractor, with each profile read individually
/// holdable and individually failable — the only way to put two reads in the
/// air on purpose and release them in the order that breaks the screen.
class _Platform {
  int profileReads = 0;

  /// The job count the editor's PATCH lands with, null until one is written.
  int? patched;

  /// The completed-job count each read *answers* with. A read that is going to
  /// be made late is given a number the contractor's header is not showing yet,
  /// so "the older read won" is visible in the pixels and not only in a flag.
  List<int> answers = <int>[4];

  /// Reads held open until their completer completes, in issue order. Null
  /// entries answer immediately.
  final List<Completer<void>?> gates = <Completer<void>?>[];

  /// Reads that will answer with a 500 instead of a profile.
  final Set<int> failing = <int>{};

  int planReads = 0;

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (req.method == 'PATCH' && p.endsWith('/api/mobile/my/profile')) {
            // The editor's own write. It answers with the row the server kept,
            // which is what `_editProfile` installs on this screen — no header
            // read involved, which is the whole point of the case that drives
            // it.
            return _json(_worker(jobs: patched ?? 4));
          }
          if (p.endsWith('/api/mobile/my/profile')) {
            final read = profileReads++;
            final gate = read < gates.length ? gates[read] : null;
            if (gate != null) await gate.future;
            if (failing.contains(read)) return _boom();
            // **A read issued after the PATCH answers with what the PATCH
            // landed**, not with the fixture's own list — the editor verifies
            // its save with a second `myProfile` and a mismatch there reports
            // «لم يصل» for a save that did land. My first version indexed
            // `answers` and got `4` back, so the form stayed open and the test
            // was measuring the editor's verifier.
            final landed = patched;
            if (landed != null) return _json(_worker(jobs: landed));
            return _json(_worker(jobs: answers[read < answers.length ? read : 0]));
          }
          if (p.endsWith('/api/mobile/my/subscription')) {
            planReads++;
            return _json(<String, Object?>{
              'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
              'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
              'payment': <String, Object?>{'methods': <Object?>[]},
            });
          }
          // Exact equality, for the reason the sibling files record:
          // `req.url.path` excludes the query string, so a `contains` here
          // would serve the shell's own projects tab the market's fixture.
          if (p == '/api/mobile/projects') {
            return _json([_project('p1', 'مشروع'), _project('p2', 'سباكة')]);
          }
          if (p == '/api/mobile/my/projects') return _json(<Object>[]);
          if (p.endsWith('/portfolio')) return _json(<Object>[]);
          if (p.endsWith('/documents')) return _json(<Object>[]);
          return _json(<Object>[]);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Platform platform})> _boot(
  _Platform platform,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = platform.build();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'worker');
  return (api: api, auth: auth, platform: platform);
}

/// Bounded pumps: the loading skeleton and the shimmer animate forever, so
/// `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The header tab body, with a clock the test owns.
///
/// `MarketplaceView` is a tab *body*, not a page: `WorkerHomeScreen` supplies
/// the Scaffold it sits in, so the test does the same. The clock is the app's
/// own injection point, and it is what lets the freshness claim be read rather
/// than guessed at.
Future<void> _pumpHeader(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  required DateTime Function() clock,
}) async {
  tester.view.physicalSize = const Size(1176, 2550);
  tester.view.devicePixelRatio = 3.0;
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
      home: Scaffold(
        body: MarketplaceView(repo: Repository(api), clock: clock),
      ),
    ),
  ));
  await _settle(tester);
}

/// The clause the header's own copy claims for finished projects.
///
/// Read off the **widget**, not off a regex over the screen: the count and the
/// claim are one sentence («4 مشاريع منجزة»), and the projects list below the
/// header carries rows whose titles contain «مشروع» too — so a scan of every
/// string on screen would measure the market, not the header. Stripping the
/// digits out was the first version of this helper and it read `45`, because
/// the tail is «4 مشاريع منجزة · 5 سنوات خبرة» and the years ride in the very
/// same string. So the phrase is matched, and only the text in front of it is
/// read.
String? _claimedJobs(WidgetTester tester) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final data = t.data;
    if (data == null || !data.contains('مشاريع منجزة')) continue;
    final before = data.substring(0, data.indexOf('مشاريع منجزة')).trim();
    final space = before.lastIndexOf(' ');
    return space < 0 ? before : before.substring(space + 1);
  }
  return null;
}

Finder get _freshness => find.byKey(const Key('stats-read-at'));

void main() {
  testWidgets(
      'a pull must not blank a header that was already on screen',
      (tester) async {
    // The defect nobody would have gone looking for, because the *failure*
    // path of this method is already guarded and already tested. This is the
    // **success** path, on a connection that answers everything.
    //
    // `setState` installs the new read over a working `_me`, so
    // `FutureBuilder.didUpdateWidget` resets the snapshot to
    // `ConnectionState.none` and the builder paints `_skeletonRows()`. The
    // contractor drags to refresh, and his name, his job count, his three tool
    // tiles and his plan row are replaced by grey bars until the request comes
    // back — the gesture that was added to make this screen answerable takes
    // away everything he was already reading.
    final p = _Platform();
    // Read 0 answers at rest; read 1 (the pull) is held open so the state
    // *during* the refresh is the thing on screen.
    p.gates.add(null);
    final held = Completer<void>();
    p.gates.add(held);
    final start = DateTime(2026, 10, 4, 9);
    final b = await _boot(p);
    await _pumpHeader(tester, b.api, b.auth, clock: () => start);

    expect(_claimedJobs(tester), '4',
        reason: 'the fixture must really draw the header before the pull');

    // A pull, through the screen's own gesture.
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 340));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _settle(tester, frames: 3);

    expect(p.profileReads, 2, reason: 'the pull must have issued its read');

    // **The contract.** A header that is on screen and working must stay on
    // screen while its refresh is in the air. The app already owns the rule for
    // this — the market band (`stale-market`) keeps the rows and says they are
    // the last ones read — and this screen has no version of it for the header.
    expect(find.text('مقاول تجربة'), findsWidgets,
        reason: 'a refresh in the air must not erase the name he is looking '
            'at; he pulled to see something NEW, not to lose what he had');
    expect(find.textContaining('مشاريع منجزة'), findsWidgets,
        reason: 'his own job count must survive the refresh he asked for');
    expect(find.byKey(const Key('worker-tools-portfolio')), findsOneWidget,
        reason: 'the gallery he uploads work to must stay reachable');
    expect(find.text('تعذّر جلب ملفك'), findsNothing,
        reason: 'nothing has failed yet — this is a wait, not a failure');

    // And the read is not cancelled by refusing to blank: releasing it must
    // still deliver the new numbers.
    p.answers = <int>[4, 9];
    held.complete();
    await _settle(tester, frames: 6);
    expect(_claimedJobs(tester), '9',
        reason: 'the refresh still has to land — keeping the header must not '
            'become a way to refuse the answer');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a read that fails after the editor saved cannot roll the header back',
      (tester) async {
    // **The overlap that is actually reachable, found by the one that was not.**
    //
    // My first version drove the retry button, on the reasoning that it is live
    // the whole time a read is open and `RefreshIndicator` refuses a second
    // pull. The second claim is right — `_shouldStart` will not arm while
    // `_status != null` (refresh_indicator.dart:417), which is how this file
    // caught a harness asserting `profileReads == 3` when two had been issued.
    // The first is not: the retry lives in the failure state, and this
    // method's **restore removes that state** — the header goes back to the
    // profile it had and the button is never on screen. The finder came up
    // empty, and the code was right. Over-correcting would have meant deleting
    // the restore to make a test reachable, which is the exact mistake this
    // file's third case is written to catch.
    //
    // The path that really is reachable needs no indicator at all: he pulls, the
    // read hangs on a bad connection, he opens the profile editor anyway and
    // saves. `_editProfile` then installs the editor's own answer with **no
    // request behind it** — nothing in `_readProfileForRefresh` can tell a
    // newer profile had landed. Then the pull's read finally answers, and
    // fails.
    final p = _Platform();
    p.gates.add(null); // read 0 — at rest
    final doomed = Completer<void>(); // read 1 — the pull, held open
    p.gates.add(doomed);
    p.failing.add(1);
    p.answers = <int>[4, 4];
    var now = DateTime(2026, 10, 4, 9);
    final boot = await _boot(p);
    await _pumpHeader(tester, boot.api, boot.auth, clock: () => now);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 1));
    expect(_claimedJobs(tester), '4');

    // Pull. Its read is held open, so the header is waiting.
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 340));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _settle(tester, frames: 3);
    expect(p.profileReads, 2, reason: 'the pull must have issued its read');

    // He opens the editor and saves. The mock's PATCH is the editor's own
    // request — a different endpoint from the header's read — and the editor
    // pops with the profile the server kept.
    await tester.tap(find.byKey(const Key('worker-tools-edit')));
    await _settle(tester, frames: 6);
    expect(find.text('حفظ الملف'), findsOneWidget,
        reason: 'the editor must really be open, or nothing below is tested');

    p.answers = <int>[4, 4];
    p.patched = 3; // the PATCH lands with three jobs on file
    await tester.tap(find.text('حفظ الملف'));
    await _settle(tester, frames: 8);
    expect(find.text('حفظ الملف'), findsNothing,
        reason: 'a verified save closes the form; if it did not, the header '
            'was never re-installed by the editor at all');

    expect(_claimedJobs(tester), '3',
        reason: 'the header must show what he just saved');

    // Now the read that was still in the air finally answers — with a 500. Its
    // restore holds the pair captured *before* he opened the editor, and
    // nothing in the old code re-checked whether that pair still belonged to
    // the screen.
    doomed.complete();
    await _settle(tester, frames: 8);

    // **The contract.** The values he just saved stay on screen. Before the fix
    // this printed 4 again — the app silently undoing a save he had been told
    // had landed, with no error anywhere to explain it.
    expect(_claimedJobs(tester), '3',
        reason: 'a read that failed late must not roll the header back over '
            'the profile the editor just installed');
    expect(find.text('تعذّر جلب ملفك'), findsNothing,
        reason: 'the profile on screen is the one he saved; an older read '
            'failing is not a fact about it');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a failed pull whose own read is the newest still restores the header',
      (tester) async {
    // The guard against over-correcting. If the fix simply dropped the
    // restore, a lone failed pull would leave the header empty and the method's
    // entire documented reason for existing would be gone. This is the case
    // that restore was written for and it must keep working.
    final p = _Platform();
    p.gates.add(null); // read 0 — at rest
    final a = Completer<void>(); // read 1 — the pull, held and doomed
    p.gates.add(a);
    p.failing.add(1);
    p.answers = <int>[4, 4];
    // Moved past a minute so the age clause is on screen to compare — see test 2.
    var now = DateTime(2026, 10, 4, 9);
    final boot = await _boot(p);
    await _pumpHeader(tester, boot.api, boot.auth, clock: () => now);
    // **The clock's value has to move too, not just the timer.** The clause is
    // computed from `now.difference(readAt)`, so stepping `pump` a minute fires
    // the freshness tick — which rebuilds — but with the *same* `now` the age is
    // still zero and `readAgeAr` returns '' by design. The first version did
    // only the `pump` and the finder came up empty («Bad state: No element»):
    // a correct finder, an unmeasurable value.
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 1));
    expect(_claimedJobs(tester), '4');
    final before = tester.widget<Text>(_freshness).data;

    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 340));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _settle(tester, frames: 3);

    a.complete();
    await _settle(tester, frames: 8);

    expect(find.text('تعذّر جلب ملفك'), findsNothing,
        reason: 'a pull that failed must still cost him nothing — this is the '
            'contract `worker_home_pull_to_refresh_test.dart` asserts');
    expect(_claimedJobs(tester), '4',
        reason: 'and the profile that was on screen must be the one still on '
            'screen');
    // Its age goes back with it — `stats_freshness_test.dart` already asserts
    // this, and it is asserted here too because the fix adds a third writer to
    // this pair and a guard on the wrong half would pass that test.
    expect(tester.widget<Text>(_freshness).data, before,
        reason: 'restored numbers keep the age they already had');
    expect(tester.takeException(), isNull);
  });
}
