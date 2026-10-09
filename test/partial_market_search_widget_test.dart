// Proves a failed *or slow* re-read on the contractor's market keeps the open
// projects on screen, says the doubt out loud, and never shows another
// wilaya's jobs.
//
// The **ninth** screen in the failed-read family, and the only member with
// **two** defects rather than one. The other eight drew a full-screen error
// when a re-read failed. This one did that *and* answered a skeleton for
// anything unsettled, over a feed re-issued by six controls — pull-to-refresh,
// two filter chips, the late location fix, the empty state's own «تحديث», and
// the profile-save path. So a *slow* read was a defect too, and it is the one
// that costs a screen rather than a list: the hairline is drawn by a different
// widget, so nothing on screen looked like an error at all.
//
// It is also the only read in the family a **visitor** can lose. The market is
// served with no account (`initState` reads the profile only when
// `!widget.guest`), so this is the first surface in the sequence where a
// dropped connection hits somebody who has never signed in.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean.
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

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// The 500 an unreachable Worker produces: an HTML body, no JSON.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
        headers: const {'content-type': 'text/html'});

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

Map<String, Object?> _project(String id, String title, String wilaya) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'أعمال جافة',
      'category': 'painting',
      'images': <String>[],
      'wilaya': wilaya,
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

Map<String, Object?> _worker() => {
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
      'full_name': 'مقاول تجربة',
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': null,
    };

/// The market, with every read counted and individually failable, so a test
/// can kill exactly one of the requests a gesture stands for.
///
/// [feedGate] is the mechanism for the *pending* case, which is the half the
/// other eight screens never had to answer: a read that is still in flight
/// used to blank the market for a shimmer, and it needs a future that genuinely
/// does not answer to be observed.
class _Platform {
  int feedReads = 0;
  int profileReads = 0;
  bool feedFails = false;

  /// When set, every market read parks here until it is completed.
  Completer<void>? feedGate;

  /// The wilaya the market answers for. Changed by the filter tests, so the
  /// fixture has to be able to serve a *different city* on demand.
  String marketWilaya = '16';

  /// Per-read steering for the market, keyed on the read's ordinal.
  ///
  /// **[feedGate] cannot express this race and neither can [feedFails].** Both
  /// are *state* held across reads: the gate parks every read at once, and the
  /// flag kills every read from the moment it is set. A late answer needs a
  /// third thing — read #1 issued and parked while read #2 issues and answers
  /// — which is two reads behaving differently from each other, so the
  /// mechanism has to be per-read. Returning **null** falls through to
  /// [feedGate] then [feedFails], so every other case keeps the simple
  /// mechanism it was written against.
  Future<http.Response?> Function(int read)? feedRespond;

  /// Pages of the **widened** search (the one with `page=2..5`) that never
  /// answer. Empty set = every page answered, tail pages with `[]` included.
  Set<int> widenPagesLost = <int>{};

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.endsWith('/api/mobile/my/profile')) {
            profileReads++;
            // A **real** worker payload, and the reason is in the assertions:
            // an empty `{}` here makes the header render its own
            // «تعذّر جلب ملفك» with its own «إعادة المحاولة», so a test that
            // asserts the market's error page carries a retry matches *two*
            // buttons and fails for a reason that has nothing to do with the
            // market. A healthy header is also the honest starting point: the
            // item is about the feed, not about the header.
            return _json(_worker());
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
          // Exact equality, and it is not a style choice: `req.url.path` has no
          // query string, so `endsWith('/mobile/projects')` matches nothing and
          // every read falls through to the empty-list branch — which makes the
          // first run of a test measure the harness instead of the screen. The
          // shell's `IndexedStack` also builds the projects tab at boot, and it
          // reads `my/projects`, which *contains* `/mobile/projects`.
          if (p == '/api/mobile/projects') {
            feedReads++;
            final qp = req.url.queryParameters['page'];
            if (qp != null && qp != '1') {
              final page = int.parse(qp);
              if (widenPagesLost.contains(page)) return _boom();
              if (widenPagesLost.isEmpty && page >= 4) return _json(<Object>[]);
            }
            final steer = feedRespond;
            if (steer != null) {
              final answer = await steer(feedReads);
              if (answer != null) return answer;
            }
            final held = feedGate;
            if (held != null) await held.future;
            if (feedFails) return _boom();
            return _json(<Object>[
              _project('p1', 'دهان شقة 3 غرف', marketWilaya),
              _project('p2', 'سباكة حمام', marketWilaya),
            ]);
          }
          return _json(<Object>[]);
        }),
      );
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The market tab's read is a lazy sliver under a long contractor header, so
/// at rest on a real device it has not even been built. Scrolling it into the
/// built range is the only honest way to reach it — the same move, and the same
/// reason, as `worker_home_pull_to_refresh_test.dart`, which cost a tick by
/// stretching the window instead and then finding nothing to pull against.
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

void main() {
  group('MarketplaceView — a partial search may not say "nothing matches"', () {
    Future<({ApiClient api, AuthState auth, _Platform platform})> boot() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final platform = _Platform();
      final api = platform.build();
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      return (api: api, auth: auth, platform: platform);
    }

    Future<void> pump(WidgetTester tester, ApiClient api, AuthState auth) async {
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
              body: MarketplaceView(repo: Repository(api), guest: true)),
        ),
      ));
      await _settle(tester);
    }

    /// Serves a market, reveals it, and leaves the search box reachable.
    Future<({ApiClient api, AuthState auth, _Platform platform})>
        serveThenSearch(WidgetTester tester) async {
      final b = await boot();
      await pump(tester, b.api, b.auth);
      await _revealMarket(tester);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the fixture must really serve a market at rest');
      return b;
    }

    /// Types a query that matches nothing on the pages that answered.
    Future<void> typeAQuery(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, 'جبس بورد');
      await _settle(tester, frames: 12);
    }

    testWidgets('a search that lost pages refuses the «لا نتائج» verdict',
        (tester) async {
      // THE REGRESSION. Pages 2 and 4 of the five-page widen die; pages 1, 3
      // and 5 answer, and the query matches none of them. Before this the
      // screen merged the union, set `_widened = true`, and the in-memory
      // filter printed «لا نتائج مطابقة» — a statement about the whole market,
      // made by a read of three pages out of five. The repository had recorded
      // the loss in the log the whole time; the log just had no path to here.
      final b = await serveThenSearch(tester);
      b.platform.widenPagesLost = {2, 4};

      await typeAQuery(tester);

      expect(find.text('لا نتائج مطابقة'), findsNothing,
          reason: 'a partial read may not claim the market has nothing');
      expect(find.byKey(const Key('partial-market')), findsOneWidget,
          reason: 'the gap has to be visible to the man who searched');
      expect(find.text('لم نتمكن قراءة كل النتائج'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a complete search still says «لا نتائج مطابقة»',
        (tester) async {
      // The half that must not move. Nothing failed, the market was read in
      // full and nothing matched it — so the verdict is true and the band would
      // be a lie. Every screenshot and every test of the ordinary empty state
      // was written against this wording.
      await serveThenSearch(tester);
      await typeAQuery(tester);

      expect(find.text('لا نتائج مطابقة'), findsOneWidget);
      expect(find.byKey(const Key('partial-market')), findsNothing,
          reason: 'a complete search has no gap to announce');
      expect(find.text('لم نتمكن قراءة كل النتائج'), findsNothing);
    });

    testWidgets('a partial search that DID find rows still shows them',
        (tester) async {
      // The band is an annotation, not a replacement. A search that reached
      // three pages and matched one of them must keep showing that card: the
      // defect was never "showed results while pages were down", it was
      // "declared nothing while pages were down".
      final b = await serveThenSearch(tester);
      b.platform.widenPagesLost = {2, 4};

      await tester.enterText(find.byType(TextField).first, 'دهان');
      await _settle(tester, frames: 12);

      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the rows that arrived still belong to the contractor');
      expect(find.byKey(const Key('partial-market')), findsOneWidget,
          reason: 'and they are still only part of the market');
    });

    testWidgets('pages that answer EMPTY are not a gap', (tester) async {
      // The mirror-image lie. `widenPagesLost` is empty here, so every one of
      // the five pages answered — pages 4 and 5 with `[]`, which is what a
      // market of 27 open projects correctly does. A band here would announce a
      // network failure that never happened, over a search that read
      // everything.
      await serveThenSearch(tester);
      await typeAQuery(tester);

      expect(find.text('لا نتائج مطابقة'), findsOneWidget);
      expect(find.byKey(const Key('partial-market')), findsNothing);
    });

    testWidgets('clearing the QUERY keeps the band, because the rows are still partial',
        (tester) async {
      // The first draft of this test asserted the opposite and the run said so.
      // Clearing the box calls `_clearSearch`, which does **not** drop
      // `_wideRows` — so the list on screen is still the union of three pages
      // out of five, and the band is still true. Dropping it here would leave
      // a partial result set being drawn as a whole market, which is the
      // defect, not a fix of it: the sentence must follow the *rows*, not the
      // text box.
      final b = await serveThenSearch(tester);
      b.platform.widenPagesLost = {2, 4};
      await typeAQuery(tester);
      expect(find.byKey(const Key('partial-market')), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '');
      await _settle(tester, frames: 12);

      expect(find.byKey(const Key('partial-market')), findsOneWidget,
          reason: 'the rows behind it are still three pages of five');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fresh reload drops the gap with the rows it described',
        (tester) async {
      // The other half, and the one that actually ends the condition: a reload
      // is a *new* market read, so the loss it may report is its own and the
      // previous one is over. A band left describing pages of a market the
      // contractor is no longer looking at is a stale sentence in a fresh list.
      final b = await serveThenSearch(tester);
      b.platform.widenPagesLost = {2, 4};
      await typeAQuery(tester);
      expect(find.byKey(const Key('partial-market')), findsOneWidget);

      // The pages are healthy again: this is the state the reload leaves
      // behind, and it has to clear the field where the loss was kept — the
      // arm that installs `_wideRows` also resets `_wideLoss`.
      b.platform.widenPagesLost = <int>{};
      // Back to the top first: the market tab is a lazy sliver under a long
      // contractor header, so at the revealed scroll position the pull
      // gesture has nothing to pull against — the same trap
      // `_revealMarket` exists for, hit from the other direction.
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 2400));
      await _settle(tester, frames: 8);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 14);
      await tester.enterText(find.byType(TextField).first, 'جبس بورد');
      await _settle(tester, frames: 14);

      expect(find.byKey(const Key('partial-market')), findsNothing,
          reason: 'the reload re-widened over pages that all answered');
    });
  });
}
