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
import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stale_market_copy.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// The 500 an unreachable Worker produces: an HTML body, no JSON.
///
/// **The failure the band is actually shown, in the shape the network layer
/// actually throws it.** The baseline is built by feeding [_boom] through the
/// same `ApiClient` the screen uses and catching what comes out, so the test
/// compares the band against *the sentence the screen really composed*.
///
/// That is not ceremony. Two earlier baselines were wrong, both in the same
/// direction — each guessed at the error instead of raising the one the fixture
/// produces:
///
///   * `S.errOffline` — the offline arm. The fixture breaks the feed with a
///     500, which is not an offline arm at all.
///   * `errorCopy(const _StatusFailure(500))` — a stand-in implementing only
///     `StatusCopyError`. The real 500 arrives as an [ApiException], which is
///     **also** an `ArabicCopyError`, so `errorCopy` returns its curated
///     sentence `S.errServer` directly and never consults the status. The
///     stand-in skipped the interface that decides the answer, so the baseline
///     read «حدث خطأ غير متوقع» while the band on screen read «خلل مؤقّت في
///     الخادم».
///
/// Both failures had the same cause: a baseline written from a failure the test
/// never produced is a test that measures the wrong thing and then fails for a
/// reason that has nothing to do with the band.
Future<String> _theBandLineForA500(Repository repo) async {
  try {
    await repo.browseProjects(category: null, wilaya: null);
  } catch (e) {
    return staleMarketLineAr(errorCopy(e));
  }
  throw StateError('the fixture was supposed to fail the feed with a 500');
}

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

Future<void> _backToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 2400));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('staleMarketLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      final line = staleMarketLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is a state the screen
      // could already be in; what was missing is the second clause — the only
      // thing that says the projects in front of the reader are real.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('it is about the LIST, not about the user\'s own projects', () {
      // The trap this file exists to close. The «مشاريعي» screen composes
      // «تحديث مشاريعك» because those are *his* jobs; this feed is the open
      // market every other contractor is bidding on, and calling it «مشاريعك»
      // would tell a contractor that somebody else's job posting is his.
      final line = staleMarketLineAr(S.errOffline);
      expect(line, contains('القائمة'));
      expect(line, isNot(contains('مشاريعك')));
    });

    test('a failure with no sentence still says the rows may be old', () {
      expect(staleMarketLineAr('   '), 'هذه المشاريع قد لا تكون محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleMarketLineAr('  ${S.errOffline}  ');
      expect(line, contains('لم نتمكن من تحديث القائمة — هذه آخر نتيجة قرأناها. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });
  });

  group('MarketplaceView — a failed or slow re-read is not a dead one', () {
    Future<({ApiClient api, AuthState auth, _Platform platform})> boot(
      _Platform platform,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = platform.build();
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      return (api: api, auth: auth, platform: platform);
    }

    Future<void> pump(WidgetTester tester, ApiClient api, AuthState auth,
        {Size size = const Size(1176, 2550),
        DateTime Function()? clock,
        bool guest = false}) async {
      tester.view.physicalSize = size;
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
          // `MarketplaceView`, not `WorkerHomeScreen`: the widget that carries
          // the behaviour, which the sibling tests also use — the shell's
          // `IndexedStack` builds three tabs at once, so a type-wide
          // `find.text('مشروع')` would be aiming at whichever tab was built
          // last.
          // `MarketplaceView` is a tab *body*, not a page: `WorkerHomeScreen`
          // supplies the Scaffold it sits in, and so does the test. Without it
          // the search field throws «No Material widget found» and the whole
          // file measures an exception instead of a screen — which is what the
          // first run of this file did, for exactly that reason.
          home: Scaffold(
              body: MarketplaceView(
                  repo: Repository(api), clock: clock, guest: guest)),
        ),
      ));
      await _settle(tester);
    }

    /// Serves a market, reveals it, then kills the next read.
    Future<({ApiClient api, AuthState auth, _Platform platform})>
        serveThenBreak(WidgetTester tester) async {
      final p = _Platform();
      final b = await boot(p);
      await pump(tester, b.api, b.auth);
      await _revealMarket(tester);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the fixture must really serve a market at rest');
      return b;
    }

    testWidgets('a failed pull keeps the projects and states the doubt',
        (tester) async {
      final b = await serveThenBreak(tester);
      b.platform.feedFails = true;

      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      // The defect, in its original form: the market was replaced by an error
      // page, and the error page is the *first read's* honest state, not this
      // one's.
      expect(find.text('تعذّر جلب المشاريع'), findsNothing);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'a re-read that failed must not cost him the rows he had');
      expect(find.text('سباكة حمام'), findsOneWidget);
      expect(find.byKey(const Key('stale-market')), findsOneWidget);
      expect(find.byKey(const Key('stale-market-line')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a SLOW re-read keeps the projects — the half nobody had',
        (tester) async {
      // The defect the other eight screens could not have: the builder's first
      // line returned a skeleton for anything unsettled, so a filter tap or a
      // pull on one bar of signal replaced twenty open projects with a shimmer
      // for as long as the request took. Nothing on that screen said "error" —
      // it simply stopped being a market.
      final held = Completer<void>();
      final b = await serveThenBreak(tester);
      b.platform.feedGate = held;

      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      // The read has been issued and has not answered, which is asserted
      // through the fixture: a test that never proved the read was in flight
      // would pass on a screen that simply ignored the gesture.
      expect(b.platform.feedReads, greaterThan(1),
          reason: 'the pull must really have issued a second read');
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'a pending re-read must not blank the market either');
      expect(find.text('تعذّر جلب المشاريع'), findsNothing);
      // No band yet: nothing has failed, and a band that appeared on a pending
      // read would be crying wolf on every pull the user makes.
      expect(find.byKey(const Key('stale-market')), findsNothing);

      // And the read really was pending — releasing it settles the screen and
      // the doubt never appears, because nothing failed.
      held.complete();
      await _settle(tester, frames: 10);
      expect(find.byKey(const Key('stale-market')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a successful re-read clears the doubt', (tester) async {
      final b = await serveThenBreak(tester);
      b.platform.feedFails = true;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);
      expect(find.byKey(const Key('stale-market')), findsOneWidget);

      // The network comes back and he pulls again. The doubt must not outlive
      // the read that answered it, or the band becomes a permanent scar the
      // reader learns to ignore — which is worse than never having drawn it.
      b.platform.feedFails = false;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      expect(find.byKey(const Key('stale-market')), findsNothing);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the band is a sliver ABOVE the rows, not a page over them',
        (tester) async {
      final b = await serveThenBreak(tester);
      b.platform.feedFails = true;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      // Asserted as a descendant of the same scroll view, because an item
      // count cannot separate "a header on the list" from "a banner that
      // replaced the list" — the thing that must not happen is the rows being
      // gone, and only the tree shape rules that out.
      final scroller = find.byType(Scrollable).first;
      expect(
        find.descendant(
          of: scroller,
          matching: find.byKey(const Key('stale-market')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: scroller,
          matching: find.text('دهان شقة 3 غرف'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed FIRST read keeps the error page and draws no band',
        (tester) async {
      // The mirror, and the reason the split exists: with nothing on screen,
      // «تعذّر جلب المشاريع» is the truth, and a band claiming «these are the
      // last results we read» over an empty sliver would be a lie with no rows
      // underneath it to qualify.
      final p = _Platform()..feedFails = true;
      final b = await boot(p);
      await pump(tester, b.api, b.auth);
      await _revealMarket(tester);

      expect(find.text('تعذّر جلب المشاريع'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.byKey(const Key('stale-market')), findsNothing,
          reason: 'a band over an empty screen claims rows that do not exist');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed read after a WILAYA change never shows the old city',
        (tester) async {
      // The half a bare `_cache` gets wrong, and the reason [_cacheKey]
      // exists. On this screen the changed query is usually a *wilaya*, and the
      // same feed re-read for Boumerdès and then for Blida does not have a
      // subset relationship: showing the first answer under the second filter is
      // not a stale list, it is a set of jobs in the **wrong city** under a
      // filter chip that says otherwise. A contractor bids from that row.
      final p = _Platform();
      final b = await boot(p);
      await pump(tester, b.api, b.auth);
      await _revealMarket(tester);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the fixture must serve a market to move away from');

      // The market moves to another wilaya and the read of it dies.
      p.marketWilaya = '09';
      p.feedFails = true;
      // Driven through the screen's own two controls rather than by reaching
      // into the state, so the test is about what a user can actually do: the
      // «كل الولايات» chip opens the picker, and the picker is where the
      // filter changes. Tapping the «الكل» *category* chip would have re-read
      // the same market with the same filter and proved nothing — it was the
      // first attempt at this test, and it stayed green for that reason.
      await tester.tap(find.text('كل الولايات'));
      await _settle(tester, frames: 8);
      // The picker is a `ListTile` list, so it is **lazy**: البليدة is the
      // 9th wilaya and is simply not built at the top of the sheet. The first
      // attempt at this test asserted the tap without scrolling and failed on a
      // finder that had nothing to match — a harness fault that looks exactly
      // like a screen fault, which is the worst kind to read at 3am. The
      // `findsWidgets` below is the honest check that the sheet opened.
      expect(find.byType(ListTile), findsWidgets,
          reason: 'the wilaya picker must be open before it can be driven');
      await tester.scrollUntilVisible(find.text('البليدة'), 120,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('البليدة'));
      await _settle(tester, frames: 8);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(p.feedReads, greaterThan(1),
          reason: 'picking a wilaya must really re-read the market');

      // Whatever the read did, a Blida filter must never be showing Boumerdès
      // jobs. The honest states are the error page or an empty market, and the
      // band is not one of them — the band says «these are the last results we
      // read», which is precisely the claim that would be false.
      expect(find.text('دهان شقة 3 غرف'), findsNothing,
          reason: 'rows read for another wilaya are jobs in another city');
      expect(find.byKey(const Key('stale-market')), findsNothing,
          reason: 'the band would be claiming rows the filter excludes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a read that answers LATE leaves the market unable to keep '
        'its own rows on the next failure', (tester) async {
      // The half of [_cacheKey] nothing tested, and the half that is the real
      // defect. The sibling case above proves a read of the *new* wilaya that
      // fails does not show the old city's jobs — it only ever kills a read.
      // It says nothing about the read that was **already in flight** when the
      // filter moved, which is the one that answers, and answering is what
      // costs.
      //
      // The shape, driven through on-screen controls: the market is read for
      // one wilaya, the contractor picks another while that read is parked on
      // a slow connection, the new read answers and is what he sees, and then
      // the first one lands.
      //
      // `_arm` takes no generation token, so the late answer installs itself
      // over the good one — and installs **its own** `_cacheKey`, the filter
      // pair captured when it was *issued*, which is now a wilaya the user has
      // moved off. `_fallback` compares that against the live pair, refuses,
      // and returns null. So the cache did not merely go stale, it went
      // **dead**, and the deadness costs him the screen on the next blip: a
      // pull that fails finds no fallback and draws «تعذّر جلب المشاريع»,
      // losing Blida's own rows and the band that is supposed to qualify them.
      // Every guarantee this screen's family is built on — a failed re-read
      // keeps the projects — is undone by one read that answered too late.
      final p = _Platform();
      final release = Completer<void>();
      var moved = false;
      // Counts **deliveries**, not issues: [feedReads] is incremented when a
      // request *starts*, so a parked read has already been counted and
      // asserting on it after the release measures the wrong moment. The first
      // attempt asserted `feedReads > 2` here and failed on a precondition,
      // which proved nothing about the screen.
      var lateDelivered = 0;
      // Installed **before** the screen is pumped, so it can hold the very
      // first read. The first attempt installed it after the market was
      // already at rest, by which point the read it meant to park was long
      // settled and the case passed green — a harness that measured itself.
      p.feedRespond = (read) async {
        if (moved) return null; // the read of the wilaya he chose
        await release.future; // every pre-move read, parked
        lateDelivered++;
        return _json(<Object>[
          _project('p1', 'مشروع بومرداس المتأخر', '16'),
        ]);
      };
      final b = await boot(p);
      await pump(tester, b.api, b.auth);
      await _revealMarket(tester);

      // The filter moves: the picker is the control that changes it, since a
      // category chip re-reads the same market and would prove nothing.
      await tester.tap(find.text('كل الولايات'));
      await _settle(tester, frames: 8);
      expect(find.byType(ListTile), findsWidgets,
          reason: 'the wilaya picker must be open before it can be driven');
      await tester.scrollUntilVisible(find.text('البليدة'), 120,
          scrollable: find.byType(Scrollable).last);
      moved = true;
      await tester.tap(find.text('البليدة'));
      await _settle(tester, frames: 8);
      await tester.pump(const Duration(seconds: 1));
      expect(p.feedReads, greaterThan(1),
          reason: 'picking a wilaya must really re-read the market');
      expect(find.text('سباكة حمام'), findsOneWidget,
          reason: 'the new wilaya must be served before the old read lands');

      // The parked read lands, and it lands **after** the answer that replaced
      // it — the ordering that is the whole defect.
      release.complete();
      await _settle(tester, frames: 10);
      await _revealMarket(tester);
      expect(lateDelivered, greaterThan(0),
          reason: 'the parked read must really have answered after the move');

      // Now the network blinks, which is ordinary on a phone.
      p.feedRespond = null;
      p.feedFails = true;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      // The sibling case's contract, in the one state it never reached: a Blida
      // filter must never be showing Boumerdès jobs, and must never *claim*
      // them as «the last results we read».
      expect(find.text('مشروع بومرداس المتأخر'), findsNothing,
          reason: 'a read that settled after the filter moved is another city');
      // And the guarantee the whole family is built on, which the late read
      // silently disarmed: the rows still on screen survive the next failure,
      // with the doubt stated rather than an error page drawn.
      expect(find.text('تعذّر جلب المشاريع'), findsNothing,
          reason: 'the late answer must not have left the cache dead');
      expect(find.text('سباكة حمام'), findsOneWidget,
          reason: 'a failed pull must not cost him the rows he was reading');
      expect(find.byKey(const Key('stale-market')), findsOneWidget,
          reason: 'the doubt must still be stated out loud');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the band says HOW OLD the projects are, not just that they '
        'are old', (tester) async {
      // **The half this item adds, on the real screen.** The band already said
      // «هذه آخر نتيجة قرأناها» — these are the last results we read — which is
      // true and useless alone. A contractor about to bid is asking *how wrong
      // can this be?*, and a list that failed to refresh four seconds ago and
      // one that failed forty minutes ago printed the same sentence. Only the
      // second is one where an open project somebody else has already taken is
      // a bid he loses.
      //
      // The clock is injected rather than slept through, for the reason
      // `stats_freshness_copy.dart` was written the way it was: waiting forty
      // real minutes is not a thing a test can do, and a `Future.delayed` that
      // long is a hung suite, not a slow one.
      var now = DateTime(2026, 9, 29, 14, 0);
      final p = _Platform();
      final b = await boot(p);
      await pump(tester, b.api, b.auth, clock: () => now);
      await _revealMarket(tester);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget);

      p.feedFails = true;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      // The read landed at 14:00 and the clock has not moved, so there is no
      // age to print yet: a hiccup is not a number.
      //
      // Read off the band widget rather than with `find.textContaining`, and
      // the reason is a trap this file set for itself: the base line already
      // ends «هذه آخر نتيجة **قرأناها**», so any matcher on that word matches
      // the band whether or not it has an age, and the "no age yet" assertion
      // passed for the wrong reason until the second sentence was added.
      expect(find.byKey(const Key('stale-market')), findsOneWidget);
      const bandKey = Key('stale-market-line');
      expect(
        tester.widget<Text>(find.byKey(bandKey)).data,
        isNot(contains('قبل')),
        reason: 'a read that is still current must not be dated',
      );
      // The fixture breaks the feed with a 500, which `errorCopy` renders as
      // the transient-server arm — so the baseline is composed from *that* arm
      // rather than from a failure the test never produced. Comparing against
      // a hard-coded string is how a test comes to be asserting a wording the
      // screen does not actually use.
      expect(tester.widget<Text>(find.byKey(bandKey)).data,
          await _theBandLineForA500(Repository(b.api)),
          reason: 'no age means the old line, byte for byte');

      // Now the clock runs and the same band, unchanged in every other way,
      // starts reporting an age.
      now = now.add(const Duration(minutes: 40));
      // A full minute, not a second: the age is not recomputed on demand, the
      // screen's one-minute tick is what redraws it — that is the same
      // mechanism `stats_freshness_test.dart` drives, and pumping 1 s here only
      // worked because the clock had already been advanced. Pumping a minute
      // also proves the timer is the thing firing, which is the actual claim:
      // a band that read the clock on every build would pass either way.
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      await _settle(tester, frames: 4);
      await _revealMarket(tester);

      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the rows are still the market — dating them costs nothing');
      final text = tester.widget<Text>(find.byKey(bandKey)).data!;
      expect(text, contains('قبل 40 دقيقة'),
          reason: 'the band must now say how old these rows are');
      // The reason is still there. The age says *how wrong*, the failure says
      // *why*, and a band that traded one for the other would be worse than
      // the one this replaced.
      expect(text, contains('لم نتمكن من تحديث'));
      expect(text, endsWith('.'), reason: 'the age is its own sentence: "$text"');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a VISITOR with no profile read still gets a band that keeps counting',
        (tester) async {
      // **The case the one-minute tick gate was actually changed for, and the
      // reason it is worth its own test.** The market is served with no account
      // at all, and `initState` reads the profile only when `!widget.guest`, so
      // for a visitor [_meReadAt] is null *forever* — there is no header to
      // stamp. The tick used to be gated on that stamp alone, so for this whole
      // audience the band rendered once, at the moment the pull failed, and
      // then froze: «قبل 40 دقيقة» would have stayed «قبل 12 دقيقة» for as
      // long as the tab stayed open, which is the same confidently-wrong claim
      // in slower motion than the one this item exists to fix.
      //
      // It is a **separate** case rather than an extra assertion on the one
      // above because the two differ only in a flag, and a shared helper would
      // let the one that carries the fix be silently dropped while the copy
      // tests stayed green — which is exactly what happened on the first
      // verification pass: with the gate reverted to `_meReadAt` only, this
      // file still reported 20/20, because no test here was a guest.
      var now = DateTime(2026, 9, 29, 14, 0);
      final p = _Platform();
      final b = await boot(p);
      await pump(tester, b.api, b.auth, clock: () => now, guest: true);
      await _revealMarket(tester);
      expect(find.text('دهان شقة 3 غرف'), findsOneWidget,
          reason: 'the market is served to a signed-out visitor too');

      p.feedFails = true;
      await _backToTop(tester);
      await tester.fling(
          find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
      await _settle(tester, frames: 12);
      await _revealMarket(tester);

      now = now.add(const Duration(minutes: 12));
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      await _settle(tester, frames: 4);
      await _revealMarket(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('stale-market-line'))).data,
        contains('قبل 12 دقيقة'),
        reason: 'a visitor has no profile read, so only the market age can '
            'keep this line moving',
      );
    });
  });

  group('staleMarketAgeAr — the band says HOW old, not just that it is old', () {
    final base = DateTime(2026, 9, 29, 14, 0);
    DateTime ago(int m) => base.subtract(Duration(minutes: m));

    test('a read inside the minute is not a number worth printing', () {
      // A pull that failed on a slow connection while the list is thirty
      // seconds old is a hiccup. «قبل 30 ثانية» under it is a reassurance
      // dressed as a measurement, and the band already said everything there is
      // to say.
      expect(staleMarketAgeAr(base.subtract(const Duration(seconds: 20)),
          now: base), isEmpty);
    });

    test('a minute and older is counted in the app\'s own words', () {
      expect(staleMarketAgeAr(ago(12), now: base), 'قبل 12 دقيقة');
      expect(staleMarketAgeAr(ago(1), now: base), 'قبل دقيقة');
      expect(staleMarketAgeAr(ago(2), now: base), 'قبل دقيقتين');
      expect(staleMarketAgeAr(ago(190), now: base), 'قبل 3 ساعات');
      // Doubles and the calendar boundary, because a re-derived grammar is
      // exactly how the subscription card ended up wrong.
      expect(staleMarketAgeAr(ago(120), now: base), 'قبل ساعتين');
      // 28 Sep 10:00 read, 29 Sep 14:00 now: **28 hours**, but it crossed
      // midnight once, so the calendar day count is 1 and the answer is «أمس»,
      // not «قبل 28 ساعة». This is the boundary `relativeTimeAr` documents —
      // a 27-hour-old message is two calendar days old — and asserting it here
      // is what stops this file from later being "simplified" into a 24-hour
      // period count, which is the exact defect that made one message read two
      // ways in the chat list and the chat divider.
      expect(staleMarketAgeAr(DateTime(2026, 9, 28, 10), now: base), 'أمس');
      // Checked against the implementation rather than assumed, because the
      // guess was wrong once already on this tick: 27 hours also reads «أمس»
      // here. `relativeTimeAr` counts **calendar** days, and a read that
      // crossed one midnight is yesterday however long it has been. That is the
      // documented rule and it is the one this surface inherits — what this
      // file must not do is quietly become a 24-hour period count, which is
      // how the chat list and the chat divider ended up dating one message two
      // different ways on the same thread.
    });

    test('a read older than a year is dated, not counted in months', () {
      // Same bound `relativeTimeAr` applies to a message from 2015. A market
      // unrefreshed for a year is not a latency problem and must not be
      // described in the vocabulary of one.
      expect(staleMarketAgeAr(DateTime(2024, 3, 9), now: base), contains('/'));
    });

    test('clock skew is not the future', () {
      // A stamp ahead of the phone is a broken clock somewhere between the
      // server and the handset. Ageing it would print «قبل -3 دقيقة» and blame
      // the reader's phone for somebody else\'s clock.
      expect(staleMarketAgeAr(base.add(const Duration(minutes: 3)),
              now: base),
          isEmpty);
    });

    test('a read that never happened has no age', () {
      expect(staleMarketAgeAr(null, now: base), isEmpty);
    });
  });

  group('staleMarketLineWithAgeAr — the age is added, the reason is kept', () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('an undatable read produces the OLD line, byte for byte', () {
      // **The contract that protects the other eight screens.** Every one of
      // them was screenshotted and tested against this exact wording. A
      // shorter "variant" here would re-open a defect on seven screens that
      // are already correct, so the fallback is not approximate: it is
      // equality with what `staleMarketLineAr` alone returns.
      expect(staleMarketLineWithAgeAr(S.errOffline, null, now: base),
          staleMarketLineAr(S.errOffline));
      expect(
          staleMarketLineWithAgeAr(S.errOffline,
              base.subtract(const Duration(seconds: 5)), now: base),
          staleMarketLineAr(S.errOffline));
    });

    test('an old read gains a second sentence, and keeps the reason', () {
      final line = staleMarketLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(minutes: 12)),
          now: base);
      // Both halves are load-bearing. The reason says *why* the list is not
      // newer, which is the half the contractor can act on; the age says how
      // wrong it can be. A band that traded one for the other would be a worse
      // band than the one this item replaces.
      expect(line, contains(S.errOffline));
      expect(line, contains('لم نتمكن من تحديث'));
      expect(line, contains('قبل 12 دقيقة'));
      expect(line, matches(RegExp(_arabic)));
    });

    test('the age is its own sentence, so the band stays two lines tall', () {
      // Both wrap on a 360 px handset and a band that grows to three is a
      // notice a contractor scrolls past.
      final line = staleMarketLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(hours: 3)),
          now: base);
      expect(line, contains('\n'));
      expect(line.split('\n'), hasLength(2));
      expect(line.split('\n').last, 'قرأناها قبل 3 ساعات.');
    });

    test('the failure with no sentence still ages', () {
      final line = staleMarketLineWithAgeAr(
          '   ', base.subtract(const Duration(minutes: 5)), now: base);
      expect(line, startsWith(staleMarketLineAr('   ')));
      expect(line, isNot(startsWith(staleMarketLineAr(S.errOffline))),
          reason: 'a reasonless failure must not borrow the named-failure '
              'wording');
      expect(line, contains('قبل 5 دقائق'));
    });
  });
}
