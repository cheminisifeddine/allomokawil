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
        {Size size = const Size(1176, 2550)}) async {
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
              body: MarketplaceView(repo: Repository(api))),
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
  });
}
