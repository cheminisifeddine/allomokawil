// The wilaya sheet can outlive the screen that opened it — and on two of the
// three screens that open it, nothing was guarding the draw that follows.
//
// Found on 28 Sep 2026. `test/picker_unmount_test.dart` fixed six
// `setState`-after-dispose sites on the **image picker** seam, and
// `test/chat_unmount_test.dart` fixed the chat screen. Neither ever covered the
// **wilaya bottom sheet**, which is the other surface in this app that hands
// control to something outside the current frame and then draws with whatever
// comes back. A three-site audit turned up exactly this:
//
//   | screen                    | its `_pickWilaya` | guarded? |
//   |---------------------------|-------------------|----------|
//   | project_new_screen.dart   | yes               | **yes**  |
//   | browse_screen.dart        | yes               | **NO**   |
//   | worker_home_screen.dart   | yes               | **NO**   |
//
// The same function, copied three times, and the copy is the defect: the guard
// exists in the app already and a later audit never looked for the two that
// lacked it. Both unguarded sites then call `_reload()`, which is a `setState`
// — so the shape is exactly the one the picker audit was written for.
//
// The reachability is the picker sheet's, not the OS picker's. A bottom sheet
// is the app's **own** surface, so this is strictly *more* reachable than the
// image-picker case the app already treats as a live bug: the OS rotates the
// phone mid-selection, the app is killed and restored from recents, or the
// system takes the activity back while the sheet is still up. The route for the
// sheet is gone, its answer is delivered anyway, and the screen underneath is
// no longer there to receive it.
//
// On `worker_home_screen.dart` the consequence is larger than a red frame. Its
// `_pickWilaya` sets `_wilayaChosen = true` and `_wilaya = picked` **before**
// calling `_reload()`. `_wilayaChosen` is what stops line 426 from silently
// re-detecting the GPS wilaya over the man's own choice — so a lost guard is not
// only a throw, it is a man who picked a wilaya and gets his location back
// instead. That is a wrong answer, not just a missing frame, and it is why this
// case gets its own assertion rather than only the shared "does not throw".
//
// On `browse_screen.dart` the draw is a `setState` that replaces the search
// future, so a lost guard throws *and* would have issued a network read nobody
// is waiting for.
//
// The harness is `picker_unmount_test.dart`'s, unchanged, because the disposal
// order it works out is the whole difficulty and re-deriving it is how the
// earlier versions of that file measured nothing while looking like coverage:
//
//   * **the screen's route goes first**, while the sheet is still above it —
//     an entry below a present route is kept, not disposed, so removing the
//     sheet first leaves the `State` alive and the post-`await` draw lands on a
//     live widget;
//   * **then one pump**, because a route entry's `dispose` is deferred to a
//     post-frame callback, so with no frame in between the answer is delivered
//     while the screen is still alive — the case goes green with the guards
//     removed, which is the vacuous pass;
//   * **then the sheet is removed with its answer**, so the flush that delivers
//     it finds an already-disposed `State`.
//
// No `await` sits between the two removals: a pump lets the continuation run in
// between and puts the draw back on a live widget.
//
// The disposers are not claimed to be reachable from inside the app — there is
// no `pushAndRemoveUntil`, no `popUntil` above these routes and no
// `navigatorKey` in `lib/`. `Navigator.removeRoute` is used because it is the
// only API that disposes a route imperatively, in one frame, with no exit
// animation. The claim is that the screens are not safe when the system does
// this, which is a smaller claim than a crash and the one the evidence carries.
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
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

Map<String, Object?> _user(String type) => <String, Object?>{
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// A contractor row for the market feed both screens draw from it.
Map<String, Object?> _worker() => <String, Object?>{
      'id': 5,
      'user_id': 31,
      'full_name': 'مقاول أول',
      'bio': 'دهان وتشطيب',
      'specialties': '["painting"]',
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

Map<String, Object?> _me() => <String, Object?>{
      'id': 5,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'bio': 'دهان',
      'specialties': '["painting"]',
      'experience_years': 6,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'user_wilaya': '16',
      'commune': 'حسين داي',
    };

Map<String, Object?> _subscription() => <String, Object?>{
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
    };

Future<({ApiClient api, AuthState auth, List<String> log})> _boot(
    {required String type}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': _user(type),
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/api/mobile/my/profile')) return _json(_me());
      if (p.contains('/subscription')) return _json(_subscription());
      if (p.endsWith('/api/mobile/workers/search')) {
        return _json(<Object?>[_worker()]);
      }
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123');
  return (api: api, auth: auth, log: log);
}

Widget _app(ApiClient api, AuthState auth, Widget screen) => AppScope(
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
        // Behind a launcher route, so the screen sits on a route the test can
        // actually remove. As `home:` it is the navigator's only route, `pop()`
        // does nothing and `removeRoute` empties the history.
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => screen),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('افتح'));
  await tester.pump();
}

/// Scrolls the market sliver until the filter bar is on screen.
///
/// The contractor's home is a `CustomScrollView` whose header — avatar, name,
/// stats, three tool tiles — fills the first screen, so the filter bar starts
/// below the fold and a bare `find.text` sees nothing. The client browse screen
/// is a `Column` and needs none of this, so it is harmless there.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 6; i++) {
    if (f.evaluate().isNotEmpty) return;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Bounded pumps: both feeds run a shimmer that never settles, so
/// `pumpAndSettle` would time out.
Future<void> _frames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The wilaya filter's own label, on both screens. Before a wilaya is chosen
/// both read «كل الولايات».
const String allWilayas = 'كل الولايات';

/// A wilaya the sheet lists and neither screen starts on, so a selection is
/// visible as a change of label. Algiers is id `16`, which is what the logged-in
/// user and the mock profile carry, so `وهران` (31) is the one to pick.
const String oran = 'وهران';
const String oranId = '31';

/// Takes the screen off the stack and disposes its `State`, then lets the sheet
/// above it answer. The order is `picker_unmount_test.dart`'s and is not the
/// obvious one; see this file's header.
Future<void> _disposeRoute(WidgetTester tester, Type screen,
    {Object? answer}) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).last);

  final screenEl = find.byType(screen);
  expect(screenEl.evaluate().isNotEmpty, isTrue,
      reason: 'the screen must be on the tree to be disposed');
  final screenRoute = ModalRoute.of(tester.element(screenEl.first));
  expect(screenRoute, isNotNull, reason: 'the screen must be on a real route');

  // The sheet on top, captured before the screen's element unmounts.
  //
  // `BottomSheet`, not `DraggableScrollableSheet`: these two callers are the
  // app's only `showModalBottomSheet` without `isScrollControlled`, so the
  // route is a plain `ModalBottomSheetRoute<String>`. The project form's sheet
  // (the one `picker_unmount_test.dart` drives) *is* scroll-controlled, which
  // is why the type differs between the two files and why the first run of
  // this one found nothing.
  final sheet = find.byType(BottomSheet);
  final sheetRoute = sheet.evaluate().isEmpty
      ? null
      : ModalRoute.of(tester.element(sheet.first));

  nav.removeRoute(screenRoute!);
  await tester.pump(const Duration(milliseconds: 50));
  if (sheetRoute != null) {
    nav.removeRoute(sheetRoute, answer);
  } else if (nav.canPop()) {
    nav.pop();
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 50));

  // The proof the `State` is really gone. Without this every assertion after it
  // is a false green.
  expect(find.byType(screen), findsNothing,
      reason: 'the screen must actually be disposed, not just popped');
}

void main() {
  testWidgets('client browse: a wilaya picked after the screen is gone is not '
      'applied and does not throw', (tester) async {
    final b = await _boot(type: 'customer');
    tester.view.physicalSize = const Size(392, 860) * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _app(b.api, b.auth, const BrowseScreen(customerSide: true)));
    await _frames(tester);
    await _open(tester);
    await _frames(tester, n: 12);

    // The filter bar is a horizontal list, RTL, so the wilaya pill is the
    // first child and is on screen without scrolling.
    final pill = find.text(allWilayas);
    expect(pill, findsOneWidget, reason: 'the wilaya filter must be visible');

    await tester.tap(pill);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester, n: 6);

    expect(find.byType(BottomSheet), findsWidgets,
        reason: 'the wilaya sheet must be open before the route is removed');

    final readsBefore = b.log
        .where((l) => l.endsWith('/api/mobile/workers/search'))
        .length;

    await _disposeRoute(tester, BrowseScreen, answer: oranId);
    await _frames(tester, n: 4);

    expect(tester.takeException(), isNull,
        reason: 'a wilaya picked after the browse screen is gone must not throw');

    final readsAfter = b.log
        .where((l) => l.endsWith('/api/mobile/workers/search'))
        .length;
    expect(readsAfter, readsBefore,
        reason: 'a dead screen must not issue a search nobody is waiting for');
  });

  testWidgets('contractor home: a wilaya picked after the screen is gone is '
      'not applied and does not throw', (tester) async {
    final b = await _boot(type: 'worker');
    tester.view.physicalSize = const Size(1176, 2550);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _app(b.api, b.auth, const WorkerHomeScreen()));
    await _frames(tester, n: 12);
    await _open(tester);
    await _frames(tester, n: 16);

    // Below the fold on this screen — see `_reveal`.
    await _reveal(tester, find.text(allWilayas));
    final pill = find.text(allWilayas);
    expect(pill, findsOneWidget, reason: 'the wilaya filter must be visible');

    await tester.tap(pill);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester, n: 6);

    expect(find.byType(BottomSheet), findsWidgets,
        reason: 'the wilaya sheet must be open before the route is removed');

    await _disposeRoute(tester, WorkerHomeScreen, answer: oranId);
    await _frames(tester, n: 4);

    expect(tester.takeException(), isNull,
        reason: 'a wilaya picked after the contractor home is gone must not throw');
  });
}
