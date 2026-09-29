// Pull-to-refresh on the contractor's home — the busiest surface in the product,
// and the last `CustomScrollView` in the app that ignored the gesture every
// user tries first on a screen that has gone stale.
//
// Found on 27 Sep 2026, immediately after the client home got the same
// treatment. `browse_screen`, `chat_list_screen`, `notifications_screen`,
// `projects_screen` and `subscription_screen` all wrapped their read in a
// `RefreshIndicator`; the contractor's market tab did not. It was not a
// low-value screen. A project posted across town, a quote that landed, a
// competitor who registered an hour ago, his own completed-jobs count and his
// remaining monthly quotes — every one of those changes while the tab is open,
// and none of them moved when he pulled. The shell also carries the header read
// (`GET /api/mobile/my/profile`) and the feed read behind the same gesture, so
// one drag stands for two independent requests, either of which can fail on its
// own.
//
// That second half is the part no sibling screen had to answer, and it is why
// this file is its own. The header gates **everything** on `worker != null`
// (see `worker_header_failure_test.dart`): his name, his stats line, his three
// tool tiles — the gallery, the documents, the professional file — and his
// subscription row. Re-reading the profile on a pull and letting that read fail
// would, on a flaky connection, *destroy a header that was working* in
// exchange for a sentence the contractor did not ask for. So the contract here
// is threefold and every clause is asserted below:
//
//   * the indicator waits on both reads, and on nothing shorter;
//   * a failed profile read leaves the header exactly where it was;
//   * a failed market read says nothing from the gesture, because the feed's
//     own `FutureBuilder` already states it in place with its own retry button.
//
// A fourth clause came out of the audit and is the more serious of the two
// defects this loop found: a **reload during an in-flight widen left the feed
// shimmering forever**. It is in the same code path, it is the reason a pull
// needed a contract at all, and it has its own test at the bottom of this file.
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
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
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

Map<String, Object?> _worker(int id, String name) => {
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
      'avg_rating': 0.0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': 2,
      'cover_image_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'full_name': name,
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': id == 0 ? null : 'https://x.test/a$id.png',
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

/// The platform under the contractor, with every read counted and each one
/// individually failable, so a test can kill exactly one of the two requests a
/// pull stands for.
class _Platform {
  /// Answers `my/profile` with a *different* name each call, so a re-read is
  /// visible on screen and not only in the counter.
  int profileReads = 0;
  int feedReads = 0;

  bool profileFails = false;
  bool feedFails = false;

  /// When set, the profile read stays in flight until this completes — the
  /// only way to observe the indicator's own waiting behaviour.
  Completer<void>? gate;

  /// When set, the **widened** feed read (pages 2..5 — the multi-page request
  /// a typed search issues) stays in flight until this completes.
  ///
  /// It has to be a separate gate. The widened read is a fan-out of five
  /// requests and the first run of this file got that wrong: with nothing held
  /// open, the mock answers inside a couple of frames, the widen completes on
  /// its own, `_widening` is already `false`, and the `LinearProgressIndicator`
  /// this test then measures is some *other* bar in the tree — an assertion on
  /// the wrong widget, green for the wrong reason.
  Completer<void>? widenGate;

  List<String> get names =>
      List.generate(profileReads, (i) => 'مقاول ${profileReads - i}');

  /// A closure, not a value: the mock calls it after the gate opens, so the
  /// name it returns is the one from *this* call and not a stale capture.
  http.Response Function() profile() {
    final read = profileReads++;
    if (profileFails) return _boom;
    return () => _json(_worker(0, 'مقاول $read'));
  }

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.endsWith('/api/mobile/my/profile')) {
            final answer = profile();
            final held = gate;
            if (held != null) await held.future;
            return answer();
          }
          if (p.endsWith('/api/mobile/my/subscription')) {
            return _json(<String, Object?>{
              'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
              'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
              'payment': <String, Object?>{'methods': <Object?>[]},
            });
          }
          if (p == '/api/mobile/my/projects') return _json(<Object>[]);
          if (p.endsWith('/portfolio')) return _json(<Object>[]);
          if (p.endsWith('/documents')) return _json(<Object>[]);
          // **Exact** path equality, and this is not a style choice. `req.url
          // .path` excludes the query string, so `endsWith('/mobile/projects')`
          // matches nothing at all — the repository always sends
          // `?status=open&page=1` — and every read fell through to the
          // empty-list branch, which made the first run of this file measure
          // the harness instead of the screen. And `contains` is no better: the
          // shell's `IndexedStack` builds the projects tab at boot and it reads
          // `my/projects`, which *contains* `/mobile/projects`, so the client's
          // own list was being served the market's fixture.
          if (p == '/api/mobile/projects') {
            feedReads++;
            // Only the extra pages of a widened fetch are held open.
            final page =
                int.tryParse(req.url.queryParameters['page'] ?? '1') ?? 1;
            if (page > 1 && widenGate != null) await widenGate!.future;
            if (feedFails) return _boom();
            return _json([
              _project('p1', 'مشروع ${feedReads - 1}'),
              _project('p2', 'سباكة حمام'),
            ]);
          }
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

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
) async {
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
      home: const WorkerHomeScreen(),
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeleton and the shimmer animate forever, so
/// `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Drags the market tab downward and pumps the frames the indicator needs to
/// accept the drag.
///
/// Anchored on the scroll view *under the indicator*, never on
/// `find.byType(Scrollable).last`: the shell is an `IndexedStack`, so the market
/// tab, the projects tab and the messages tab are all built at once, and a
/// positional finder silently starts aiming at whichever one is built last. The
/// same trap cost a tick on 27 Sep, on `offline_taxonomy_test.dart`.
/// Scrolls the market strip into the built range.
///
/// The contractor header is a first-run guide, a tool strip and a subscription
/// row, so on a real device the market's `FutureBuilder` is a lazy sliver below
/// the fold and has not even run at rest. A window tall enough to build it all
/// (4600 px) is *worse*: nothing overflows, the shell is not a scroll view at
/// rest, and the pull gesture has nothing to pull against. So the strip is
/// scrolled into view instead of the window being stretched — the same move,
/// and the same reason, as `customer_home_pull_to_refresh_test.dart`.
Future<void> _revealMarket(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// Returns to the top so the pull has something to pull against.
Future<void> _backToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 2400));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

/// The widen bar **only** — never `find.byType(LinearProgressIndicator)`.
///
/// The contractor header carries a first-run checklist whose completion meter
/// is also a `LinearProgressIndicator` (the «4 من 4» row), and it has a
/// `value`. The widen hairline is the indeterminate one: `value == null`, which
/// is the only thing that tells the two apart. A type-wide finder measured the
/// checklist's meter and stayed green after the widen had gone — the same class
/// of mistake as a positional `Scrollable` finder, and the reason this helper
/// exists. Found by the assertion matching **two** widgets and neither of them
/// being the one under test.
Finder get _widenBar => find.byWidgetPredicate(
      (w) =>
          w is LinearProgressIndicator && w.minHeight == 3 && w.value == null,
      description: 'the widened-search progress hairline',
    );

Future<void> _pull(WidgetTester tester) async {
  final page = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(Scrollable),
  );
  expect(page, findsWidgets, reason: 'the market tab must be pullable');
  await tester.fling(
      find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // ── The gesture reaches the screen, and the header is never sacrificed ──
  testWidgets('a pulled market re-reads the feed and the header together',
      (tester) async {
    final p = _Platform();
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);

    // Captured before the gesture, not assumed.
    expect(p.feedReads, greaterThan(0));
    final feedAtRest = p.feedReads;
    final profileAtRest = p.profileReads;
    expect(profileAtRest, 1);
    expect(find.textContaining('مقاول'), findsWidgets);

    // The market is a lazy sliver under a long header, so it is scrolled into
    // the built range rather than assumed: at rest on a real device its
    // `FutureBuilder` has not even run. Dragging it into view is also what
    // leaves the scroll view in a state where a pull has something to answer.
    await _revealMarket(tester);
    expect(find.textContaining('مشروع'), findsWidgets,
        reason: 'the fixture must really serve a market at rest');

    await _backToTop(tester);
    await _pull(tester);

    expect(p.feedReads, feedAtRest + 1,
        reason: 'the pull must re-read the market exactly once');
    expect(p.profileReads, profileAtRest + 1,
        reason: 'the pull must re-read the header, or the tab shows a '
            'contractor\'s own completed-jobs count that is an hour old');
    // And the answer is on screen, not merely requested.
    await _revealMarket(tester);
    expect(find.textContaining('مشروع'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the indicator stays up until the slower read has answered',
      (tester) async {
    final p = _Platform();
    // The feed is answered; the header is not. A gesture that returned early
    // would take the spinner down over a market that is still loading, which is
    // the one thing a spinner is for.
    final held = Completer<void>();
    p.gate = held;
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);
    await _revealMarket(tester);
    expect(find.textContaining('مشروع'), findsWidgets,
        reason: 'the fixture must really serve a market at rest');

    await _backToTop(tester);
    await _pull(tester);

    // Measured through the indicator's own widget: `RefreshIndicator` paints a
    // `RefreshProgressIndicator` for exactly as long as `onRefresh` has not
    // returned, so its presence is the contract, not a proxy for it.
    expect(find.byType(RefreshProgressIndicator), findsOneWidget,
        reason: 'the market read answered but the header has not — the '
            'indicator must still be up, and it is the indicator that is the '
            'promise, not a timer that happens to line up with one');

    // Letting the held read land takes the spinner down. If the gesture had
    // returned early this bar would already be gone, and the assertion above
    // would have failed — the release is what proves the wait was real.
    held.complete();
    await _settle(tester, frames: 6);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed profile read does not cost a working header',
      (tester) async {
    final p = _Platform();
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);
    expect(find.textContaining('مقاول 0'), findsWidgets,
        reason: 'the fixture must render the name it returned');

    // The header is working. The network dies. He pulls.
    p.profileFails = true;
    final feedAtRest = p.feedReads;
    await _revealMarket(tester);
    await _backToTop(tester);
    await _pull(tester);

    expect(p.feedReads, feedAtRest + 1,
        reason: 'one dead read must not swallow the refresh he asked for');
    // The contract: a profile read that *he* triggered indirectly cannot remove
    // his name, his stats, his tool tiles and his plan row.
    expect(find.text('تعذّر جلب ملفك'), findsNothing,
        reason: 'a pull is not a request to lose the header');
    expect(find.textContaining('مقاول 0'), findsWidgets,
        reason: 'the previous profile must be put back, not dropped');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed market RE-READ keeps the rows and states the doubt',
      (tester) async {
    final p = _Platform();
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);
    await _revealMarket(tester);
    expect(find.textContaining('مشروع'), findsWidgets,
        reason: 'the first read must really serve a market to lose');

    p.feedFails = true;
    final profileAtRest = p.profileReads;
    await _backToTop(tester);
    await _pull(tester);
    await _revealMarket(tester);

    expect(p.profileReads, profileAtRest + 1,
        reason: 'the header read is independent of the feed read');
    // **This assertion is the item.** It used to read `findsOneWidget`, which
    // *is* the defect: a re-read that failed replaced twenty open projects with
    // «تعذّر جلب المشاريع» over the whole screen, on a feed that pull,
    // two filter chips, the location fix, the empty state's own button and the
    // profile-save path all re-issue. A contractor who was reading the market
    // lost the market.
    expect(find.text('تعذّر جلب المشاريع'), findsNothing,
        reason: 'a re-read that failed must not cost him the rows he had');
    expect(find.byKey(const Key('stale-market')), findsOneWidget,
        reason: 'and it must say out loud that these rows are the last ones read');
    // The gesture still says nothing *itself* — the band, not the snackbar, is
    // how the failure reaches him, and it is the one that scrolls with the rows.
    expect(find.textContaining('مشروع'), findsWidgets,
        reason: 'the rows that survived the last good read must stay');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed market FIRST read still keeps the full-screen error',
      (tester) async {
    // The mirror of the case above, and the reason the split exists. With no
    // rows yet, «تعذّر جلب المشاريع» is the **truth** — there is nothing to
    // qualify, and a band saying «these are the last results we read» over an
    // empty screen would be a lie with no rows under it.
    final p = _Platform()..feedFails = true;
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);
    await _revealMarket(tester);

    expect(find.text('تعذّر جلب المشاريع'), findsOneWidget,
        reason: 'with nothing on screen the error page is the honest state');
    expect(find.text('إعادة المحاولة'), findsOneWidget,
        reason: 'and it must carry the one action that can fix it');
    expect(find.byKey(const Key('stale-market')), findsNothing,
        reason: 'a band over an empty screen claims rows that do not exist');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a visitor is never asked to read a profile he does not have',
      (tester) async {
    final p = _Platform();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = p.build();
    final auth = AuthState(api);
    await auth.restore();
    // No login: the feed is public, the header is not.
    await _pump(tester, api, auth);
    expect(p.profileReads, 0, reason: 'the fixture must be a signed-out read');

    final feedAtRest = p.feedReads;
    await _revealMarket(tester);
    await _backToTop(tester);
    await _pull(tester);

    expect(p.feedReads, feedAtRest + 1);
    expect(p.profileReads, 0,
        reason: 'a visitor must not be sent the contractor endpoints');
    expect(tester.takeException(), isNull);
  });

  // ── The wider defect, in the same code path ────────────────────────────
  testWidgets('a reload during an in-flight widen stops the shimmer',
      (tester) async {
    final p = _Platform();
    p.feedFails = true;
    // The widened fetch — the one the first keystroke issues, and the one that
    // has to still be in flight when the reload lands — is held open here. With
    // nothing held it answers within a frame or two, `_widening` clears itself,
    // and this test goes on to measure a different progress bar in the tree:
    // green for the wrong reason.
    final held = Completer<void>();
    p.widenGate = held;
    final b = await _boot(p);
    await _pump(tester, b.api, b.auth);
    await _revealMarket(tester);

    // The market is empty and the feed's own retry button is on screen. This is
    // the control the app itself uses to call `_reload`, and it is a plain
    // settled widget — unlike the category strip, which is a horizontal lazy
    // list, so a category is not even built until it is scrolled into view and
    // tapping one is not a stable way to drive this path.
    // A **first** read that failed, so the full-screen error is the correct
    // state here and the retry below is the control the app itself offers.
    // (The pull above it re-read a market that had rows; that path now keeps
    // them and draws the band instead, and it is asserted in its own test.)
    expect(find.text('تعذّر جلب المشاريع'), findsOneWidget,
        reason: 'nothing was ever read, so there is nothing to fall back on');
    final retry = find.text('إعادة المحاولة');
    expect(retry, findsOneWidget);

    // Type a word: the first character issues the widened read, and the hairline
    // progress bar goes into the air.
    await tester.enterText(find.byType(TextField).first, 'سباكة');
    await _settle(tester, frames: 2);
    expect(_widenBar, findsOneWidget,
        reason: 'the widen progress bar should be in the air now');

    // The connection comes back and he presses the button the UI gave him,
    // while the widened read is still in the air.
    p.feedFails = false;
    await tester.tap(retry);
    await _settle(tester, frames: 4);

    // The contract: a reload stands the widen down. Before the fix the flag
    // stayed `true` with nothing in the air to clear it, so the empty branch
    // answered with an eternal skeleton — «لا مشاريع مفتوحة حالياً» and the
    // button under it could never be shown, and a user looking at a shimmering
    // screen with no results coming had no way out of it.
    //
    // The stranded widen is still running — it was never cancelled, only made
    // irrelevant — so it is released here too: it must not resurrect the bar,
    // and its stale rows must not overwrite the newer market.
    held.complete();
    await _settle(tester, frames: 6);
    expect(_widenBar, findsNothing,
        reason: 'a reload must stand the widen down, or the hairline progress '
            'bar never leaves the screen');
    // The search box still holds «سباكة», so the market is filtered to what
    // matches it — asserting on the query word itself would only be reading the
    // text field back.
    await _revealMarket(tester);
    expect(find.text('سباكة حمام'), findsOneWidget,
        reason: 'and the market itself must actually arrive, not just a bar '
            'that stopped spinning');
    expect(tester.takeException(), isNull);
  });
}
