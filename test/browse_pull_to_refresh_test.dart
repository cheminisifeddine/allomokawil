// Pull-to-refresh on the contractor search — the screen a client opens to
// find a pro, and the only read in the app with no way to refresh a feed that
// has gone stale or come back from the background.
//
// Found on 27 Sep 2026. Four sibling screens wrap their read in a
// `RefreshIndicator` — `chat_list_screen`, `notifications_screen`,
// `projects_screen` and `subscription_screen` — and `browse_screen` did not.
// Its `FutureBuilder` had all three settled states: shimmer, error, and a
// populated `ListView.separated`. The error state carried a retry button, so a
// man whose first load failed could press his way back. A man whose *first* load
// succeeded and whose feed then went stale — a contractor who registered
// yesterday, an hour spent in the fields, a new job posted across town — had
// nothing at all. Not a slow path, not a hidden one: the list simply did not
// move when pulled, which is the app silently ignoring a gesture every Android
// user has been trained since 2013 to try first on a dead-looking feed.
//
// The pull also has to work on the *failed* and *empty* states, which is the
// half that is easy to get wrong: `EmptyView` is a `Center` around a
// `Column(mainAxisSize: min)`, so it is not scrollable and a `RefreshIndicator`
// over it never fires a single notification. The indicator has to be given a
// list that can always be scrolled, or the gesture is accepted by the framework
// and dropped by the child.
//
// The refresh future is awaited rather than fired. `RefreshIndicator` holds the
// spinner until the future resolves, so a pull that returns before the request
// has answered snaps the indicator away and leaves a list that looks freshly
// loaded while still holding the data the user was trying to replace.
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
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// A 500 with an HTML body — the captive-portal / Worker-crash shape.
http.Response _boom() =>
    http.Response('<html>Internal Server Error</html>', 500,
        headers: {'content-type': 'text/html'});

Map<String, Object?> _user() => {
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'عميل تجربة',
      'type': 'customer',
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

/// Boots a real `ApiClient` over a `MockClient` that answers the search with
/// whatever [search] is told to, and records every read so the test can count
/// the *requests*, not the frames.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required Future<http.Response> Function(int attempt) search,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  var attempts = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/mobile/workers/search')) {
        return search(attempts++);
      }
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, log: log);
}

int _searchReads(List<String> log) =>
    log.where((l) => l.endsWith('/api/mobile/workers/search')).length;

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
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
      home: const BrowseScreen(),
    ),
  ));
  await _settle(tester);
}

/// Drags from near the top of the list downward — the pull-to-refresh gesture
/// — and pumps the frames the indicator needs to accept it.
Future<void> _pull(WidgetTester tester) async {
  await tester.fling(
    find.byType(ListView).last,
    const Offset(0, 340),
    1200,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}


void main() {
  testWidgets('a settled feed that is pulled issues a new search read',
      (tester) async {
    final b = await _boot(
        search: (i) async => _json(<Object?>[_worker(1, 'مقاول أول')]));
    await _pump(tester, b.api, b.auth);
    expect(_searchReads(b.log), 1, reason: 'the first load read once');
    expect(find.text('مقاول أول'), findsOneWidget);

    await _pull(tester);

    expect(_searchReads(b.log), 2,
        reason: 'pulling a settled feed must re-run the search');
  });

  testWidgets('a pull shows the refreshed data, not the list it replaced',
      (tester) async {
    final b = await _boot(search: (i) async {
      // First read answers with a contractor; the pull answers with a
      // different one, so a refresh that did not actually replace the list
      // cannot pass.
      return i == 0
          ? _json(<Object?>[_worker(1, 'مقاول قديم')])
          : _json(<Object?>[_worker(2, 'مقاول جديد')]);
    });
    await _pump(tester, b.api, b.auth);
    expect(find.text('مقاول قديم'), findsOneWidget);

    await _pull(tester);

    expect(find.text('مقاول جديد'), findsOneWidget,
        reason: 'the pull must publish the new answer');
    expect(find.text('مقاول قديم'), findsNothing,
        reason: 'the replaced row must be gone');
  });

  testWidgets('the failed state is pullable — the gesture that recovers it '
      'when the retry button is not found', (tester) async {
    final b = await _boot(
        search: (i) async => i == 0 ? _boom() : _json(<Object?>[_worker(1, 'مقاول أول')]));
    await _pump(tester, b.api, b.auth);
    expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);
    expect(_searchReads(b.log), 1);

    await _pull(tester);

    expect(_searchReads(b.log), 2,
        reason: 'the error state must accept the pull, not swallow it');
    expect(find.text('تعذّر جلب المقاولين'), findsNothing);
    expect(find.text('مقاول أول'), findsOneWidget);
  });

  testWidgets('the empty state is pullable too — a filter that matched nothing '
      'when more contractors have since signed up', (tester) async {
    final b = await _boot(search: (i) async {
      if (i == 0) return _json(<Object?>[]);
      return _json(<Object?>[_worker(1, 'مقاول أول')]);
    });
    await _pump(tester, b.api, b.auth);
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(_searchReads(b.log), 1);

    await _pull(tester);

    expect(_searchReads(b.log), 2,
        reason: 'EmptyView is not scrollable; the pull must still be heard');
    expect(find.text('مقاول أول'), findsOneWidget);
  });

  testWidgets('a short feed — three contractors, a screen that fits them all — '
      'is still pullable', (tester) async {
    // The mutation this kills: dropping `AlwaysScrollableScrollPhysics` from
    // the populated list. Every other test here uses a one-row feed that the
    // default `ClampingScrollPhysics` will still scroll a few pixels, so the
    // pull fires and the mutation survives. A young Algerian marketplace
    // usually has *fewer* contractors than fit on a phone screen, and that is
    // precisely the list that refuses to move when pulled: the content is not
    // scrollable, so the indicator never gets a scroll notification.
    final b = await _boot(search: (i) async => _json(<Object?>[
          _worker(1, 'مقاول أول'),
          _worker(2, 'مقاول ثان'),
          _worker(3, 'مقاول ثالث'),
        ]));
    await _pump(tester, b.api, b.auth);
    expect(find.text('مقاول ثالث'), findsOneWidget);
    expect(_searchReads(b.log), 1);

    await _pull(tester);

    expect(_searchReads(b.log), 2,
        reason: 'a feed shorter than the viewport must still accept the pull');
  });

  testWidgets('the populated list is scrollable even when it fits the screen',
      (tester) async {
    // Pins the contract the mutation above could not catch behaviourally.
    //
    // `AlwaysScrollableScrollPhysics` is what makes a list that is *shorter
    // than the viewport* accept the pull at all: without it the scroll view
    // has nothing to scroll, so the indicator never receives a scroll
    // notification and the gesture is silently dropped. That is the state of
    // every new marketplace — two contractors on the whole platform — and it
    // is the one case that matters.
    //
    // Asserted on the widget, not through a fling. Recorded here because the
    // reason is not obvious and cost an hour: `ScrollView` already defaults a
    // vertical, controllerless list to `AlwaysScrollableScrollPhysics`
    // (flutter/lib/src/widgets/scroll_view.dart:141-148), so on *this* screen
    // the explicit line is belt-and-braces — deleting it is an equivalent
    // mutant and no behavioural test can tell the two apart. The assertion
    // pins the contract rather than pretending a gesture proved it.
    final b = await _boot(
        search: (i) async => _json(<Object?>[_worker(1, 'مقاول أول')]));
    await _pump(tester, b.api, b.auth);

    // Scoped to the scrollable that belongs to the pull indicator, not to
    // "any scrollable on the page": the page also carries a horizontal filter
    // bar and the search box, and an axis filter is not enough to be honest
    // about which one is the feed.
    final underIndicator = find.descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byType(Scrollable),
    );
    expect(underIndicator, findsOneWidget,
        reason: 'the settled feed is the one scrollable under the indicator');
    expect(tester.widget<Scrollable>(underIndicator).physics,
        isA<AlwaysScrollableScrollPhysics>(),
        reason: 'the result list must stay scrollable when it is short — a '
            'feed with two contractors on it is the normal state of a new '
            'marketplace, and a list that cannot scroll swallows the pull');
  });

  testWidgets('the pull indicator is held until the read it is waiting on has '
      'actually answered', (tester) async {
    final b = await _boot(search: (i) async {
      if (i != 1) return _json(<Object?>[_worker(1, 'مقاول أول')]);
      // A slow read: the indicator must still be on screen 600ms in.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return _json(<Object?>[_worker(2, 'مقاول جديد')]);
    });
    await _pump(tester, b.api, b.auth);
    expect(_searchReads(b.log), 1);

    await tester.fling(
        find.byType(ListView).last, const Offset(0, 340), 1200);
    await tester.pump(const Duration(milliseconds: 400));
    // The request is in flight and unanswered: a refresh that returned early
    // would already have taken the indicator down here.
    expect(find.byType(RefreshProgressIndicator), findsOneWidget,
        reason: 'the indicator must outlive an unanswered read');

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('مقاول جديد'), findsOneWidget);
  });

  testWidgets('a failed pull comes back to the list and takes the indicator '
      'down instead of hanging on a spinner forever', (tester) async {
    final b = await _boot(search: (i) async {
      if (i == 0) return _json(<Object?>[_worker(1, 'مقاول قديم')]);
      return _boom();
    });
    await _pump(tester, b.api, b.auth);
    expect(find.text('مقاول قديم'), findsOneWidget);

    await _pull(tester);
    await _settle(tester);

    // Without this count assertion the whole test is vacuous: on the unfixed
    // screen no pull is ever issued, so "the indicator is gone" is true there
    // too, for the wrong reason.
    expect(_searchReads(b.log), 2, reason: 'the pull must have been issued');
    expect(find.byType(RefreshProgressIndicator), findsNothing,
        reason: 'a failed pull must still take the indicator down');
  });
}
