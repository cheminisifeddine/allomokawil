// The plan card on the contractor's home: the second read on that screen, and
// the only one of the three that lied about all three of age, failure and
// volume.
//
// Found on 27 Sep 2026, immediately after the stats line got its age. The
// backlog entry that shipped that line named this row as the next thing, for
// one reason: **`_PlanEntry` runs a second read**. So the header carries two
// numbers — a completed-jobs count and a remaining-quota count — read at two
// different moments, and until now neither said which was which.
//
// Three defects, all inside the same nine lines:
//
//   * **`future: repo.subscription()` was evaluated in `build`.** Every
//     rebuild of the header issued a fresh `GET /api/mobile/subscription`. The
//     once-a-minute freshness tick shipped the previous cycle turned that from
//     "once per visit" into "once a minute for the whole session", because the
//     shell is an `IndexedStack` and the tab never unmounts. A phone left on
//     the home screen overnight asks the server about the man's money sixty
//     times an hour, forever, and the only visible symptom is a plan that
//     occasionally flickers through «جارٍ التحميل...».
//   * **A failed read printed «خطتك وحدود العروض وتفعيل الاشتراك»** — the
//     invitation to buy — on the one card whose whole job is to get him to the
//     renewal screen. The account tab said the same thing about the same money
//     and was fixed; this one was missed because it is a different widget in a
//     different file. A contractor whose *paid* plan failed to load is told, in
//     the app's own voice, that he has no plan.
//   * **No age.** The stats line four centimetres above it dates itself; this
//     did not, so a quarter-old "2 quotes left" read exactly like a fresh one.
//
// The mutation gate matters more than the assertions here. A test that only
// checks the new copy passes just as happily against the old code, because the
// old code had *different* copy rather than no copy. What is pinned below is
// the *behaviour*: the request count, which is the only one of the three that a
// screenshot cannot show and the only one that costs the user something.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:allomokawil/src/data/repository.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

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
      'subscription_plan': 'basic',
      'avg_rating': 4.6,
      'total_reviews': 5,
      'total_completed_jobs': 4,
      'response_time_hours': 2,
      'cover_image_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'full_name': 'مقاول تجريبي',
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': null,
    };

/// A paid plan with **two** quotes left, so the quota sentence and the age
/// clause are two separate things on the card and a test can tell them apart.
///
/// `quote_limit` 3 with 1 used is 2 left, which is the «عرضان» dual form — so
/// the count grammar is exercised too, and a card that printed the wrong noun
/// could not pass by accident.
Map<String, Object?> _catalogue({int left = 2}) => <String, Object?>{
      'currency': 'DZD',
      'note_ar': 'الدفع مسبق',
      'renew_note_ar': 'ادفع مسبقاً',
      'auto_renew': 0,
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'basic',
        'name_ar': 'أساسي',
        'price_month': 4500,
        'price_year': 45000,
        'quote_limit': 3,
        'quotes_used_this_month': 3 - left,
        'expires_at': '2027-01-01 00:00:00',
      },
      'pending_request': null,
      'payment': <String, Object?>{'methods': <Object?>[]},
    };

/// The contractor's home, with the plan read counted and individually
/// failable, and a clock the test drives itself.
class _Platform {
  int planReads = 0;
  bool planFails = false;

  /// Held open by a retry so the latched state is observable — an instant 500
  /// puts the busy state over inside one pump, and the test would be asserting
  /// on a moment that no longer exists. Set by the test, awaited by the mock.
  Completer<void>? retryGate;

  /// True once the gate has been opened, so the retry's *second* attempt is
  /// allowed to fail fast. Without this, a gate that gates every read would
  /// hang the first read too.
  bool gateOpen = false;

  final log = <String>[];

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          log.add('${req.method} $p');
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.endsWith('/api/mobile/my/profile')) return _json(_worker());
          if (p.endsWith('/api/mobile/subscription')) {
            planReads++;
            // A gate that has not been opened holds this read open, which is
            // what makes «latched» a state the test can look at.
            if (retryGate != null && !gateOpen) await retryGate!.future;
            if (planFails) return _boom();
            return _json(_catalogue());
          }
          if (p == '/api/mobile/my/projects') return _json(<Object>[]);
          if (p == '/api/mobile/projects') return _json(<Object>[]);
          return _json(<Object>[]);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Platform platform})> _boot(
  _Platform platform, {
  bool signedOut = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = platform.build();
  final auth = AuthState(api);
  await auth.restore();
  // A guest is `auth.user == null` — `AuthGate.isGuest` reads the session, not
  // the scope (auth_gate.dart:38), so the honest way to render one is to never
  // sign in. My first version passed a `guest:` flag to `AppScope`, which has
  // no such parameter.
  if (!signedOut) {
    await auth.login(
        phone: '0773000000', password: 'secret123', rememberMe: true);
    expect(auth.role.name, 'worker');
  }
  return (api: api, auth: auth, platform: platform);
}

/// A clock the test owns. The plan row's age is the thing under test, so the
/// "now" cannot be the wall clock: a test that renders «قبل 3 ساعات» only on the
/// one run where real time happened to pass is green whenever it is green and
/// worth nothing the day it is not.
class _Clock {
  DateTime at = DateTime(2026, 9, 27, 10, 0);
  DateTime call() => at;
  void advance(Duration d) => at = at.add(d);
}

/// Renders the market tab with the test's clock wired in.
///
/// **The widget under test is `MarketplaceView`, not `WorkerHomeScreen`.** My
/// first version pumped the shell, and it failed for a reason that turned out to
/// be the most useful thing I learned this cycle: the shell mounts
/// `ProfileScreen` inside an `IndexedStack` (worker_home_screen.dart:108), so
/// the account tab's own `_PlanAccountRow` reads `/api/mobile/subscription`
/// *at the same time* and the screen legitimately answered two requests. The
/// shell also has no `clock` parameter — the injectable clock is on
/// `MarketplaceView` (`:168`) — so every age assertion against a pumped shell
/// was measuring `DateTime.now`, not the clock the test advanced, and passed or
/// failed for reasons that had nothing to do with the code.
///
/// Both mistakes had the same shape: a test pointed at a bigger widget than the
/// one carrying the behaviour, asserting on things the bigger widget also
/// does.
Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth,
  _Clock clock,
) async {
  tester.view.physicalSize = const Size(1176, 2550);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_scopedApp(api: api, auth: auth, clock: clock));
  await _settle(tester);
}

/// The market tab, wrapped in a scope.
///
/// [_scopedApp] deliberately builds a **new** [AppScope] on every call, so a
/// test can swap the dependency the way signing out and back in does. See the
/// note in the aged-read test for why that event is the one worth producing.
Widget _scopedApp({
  required ApiClient api,
  required AuthState auth,
  required _Clock clock,
  bool guest = false,
}) {
  return AppScope(
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
        body: MarketplaceView(
            repo: Repository(api), guest: guest, clock: clock.call),
      ),
    ),
  );
}

/// Bounded pumps: the skeleton and the shimmer animate forever, so
/// `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Rebuilds the screen without re-issuing a single read.
///
/// `pumpWidget` with the same tree is the wrong tool: Flutter short-circuits
/// on an identical widget, so the first version of this helper rebuilt
/// nothing and the test passed for the wrong reason. A one-pixel viewport nudge
/// is a real layout pass, and the plan read must survive it.
Future<void> _rebuild(WidgetTester tester) async {
  // **Driving a rebuild by nudging the viewport does not reach this row.**
  // The plan card is nested several `SliverToBoxAdapter`s deep inside
  // `MarketplaceView`, and a one-pixel physical-size change only relayouts what
  // the viewport can see — the card is below the fold, so the card's own
  // `build` never ran again and `plan-read-at` could not appear no matter how
  // old the clock got. The first version of this helper "passed" the fresh
  // case and could not pass the aged one, and the reason was invisible in the
  // output: the count of builds never moved.
  //
  // The real trigger is the one the app itself uses: `MarketplaceView` runs a
  // `Timer.periodic(const Duration(minutes: 1))` whose body is a bare
  // `setState(() {})` (worker_home_screen.dart:560). Pumping past a minute
  // fires that timer for real, which rebuilds the whole market view including
  // the header and the card. So the tick is pumped directly.
  //
  // This is not a test convenience, it is the path that makes this card's age
  // grow in production, and a test that faked the rebuild some other way would
  // not be testing it. It is also the reason the fix has to be real: a card
  // whose age cannot grow is a card whose age clause is decoration.
  await tester.pump(const Duration(minutes: 1, milliseconds: 100));
  await _settle(tester);
}

int _planReads(_Platform p) => p.log
    .where((l) => l.endsWith('/api/mobile/subscription'))
    .length;

/// Renders the plan card to a PNG so the aged state is looked at rather than
/// asserted about, and so the founder can see the clause the tests describe.
///
/// The capture wraps the whole screen in a [RepaintBoundary] *before* it is
/// pumped, which is the only arrangement that works: a key attached after the
/// first frame is a key with no render object, and my first version of this
/// helper did exactly that.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  ApiClient api,
  AuthState auth,
  _Clock clock, {
  Size logical = const Size(392, 900),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: RepaintBoundary(
      key: key,
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
        home: Scaffold(body: MarketplaceView(repo: Repository(api), clock: clock.call)),
      ),
    ),
  ));
  await _settle(tester);

  // The row is deep in a `CustomScrollView`; without this the capture is
  // whatever the viewport happened to be showing.
  final target = find.text('اشتراكي');
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
  }

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  return path;
}

void main() {
  testWidgets('the plan card reads once, not once per rebuild', (tester) async {
    final platform = _Platform();
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);

    expect(_planReads(platform), 1, reason: 'the first read happened');

    // The defect, stated as a count. The old code issued a new
    // `GET /api/mobile/subscription` from inside `build`, so *any* rebuild of
    // the header cost the user a request. Twelve pumps is twelve extra
    // requests against the old code and none against the new.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(_planReads(platform), 1,
        reason: 'the plan read is cached in state; a rebuild must not re-issue '
            'it, or the once-a-minute tick turns this into a request a minute '
            'for the whole session');

    // And the real trigger, not just pumps: the app's own once-a-minute
    // freshness tick, which is the thing that made the old code issue sixty
    // requests an hour.
    clock.advance(const Duration(hours: 2));
    await tester.pump(const Duration(minutes: 1, milliseconds: 100));
    await _settle(tester);
    expect(_planReads(platform), 1,
        reason: 'the freshness tick rebuilds this row; it must not also move '
            'this read');
  });

  testWidgets('the plan card is not rebuilt into a new read by a filter change',
      (tester) async {
    // The second caller that re-ran `build` on this row: any `setState` in the
    // market view. A category chip re-issues the feed, the header rebuilds, and
    // the old code asked about the plan again.
    final platform = _Platform();
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);
    final before = _planReads(platform);

    // Tapping a category chip, not dragging. My first version dragged the list
    // down by 400px from offset 0, which is the *pull-to-refresh* gesture: it
    // fires `_refresh`, re-reads the profile and the feed, and costs a plan read
    // for a reason that has nothing to do with the header rebuilding. The test
    // was named for a filter change and was measuring a refresh — two
    // different defects, one of them real and already fixed two cycles ago.
    //
    // The chip is the honest trigger: `onCategory` calls `_reload()`, which is
    // the same `setState` path a real tap takes, with no refresh in it.
    await tester.tap(find.text('الكل'));
    await _settle(tester);

    expect(_planReads(platform), before,
        reason: 'a filter change rebuilds the header; the plan read is cached '
            'in state and must not move');
  });

  testWidgets('a failed plan read never reads as the invitation to buy',
      (tester) async {
    final platform = _Platform()..planFails = true;
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);

    expect(find.text('خطتك وحدود العروض وتفعيل الاشتراك'), findsNothing,
        reason: 'a 500 is not a free trial; this card told a paying man he '
            'had no plan');
    expect(find.text('تعذّر جلب خطتك'), findsOneWidget,
        reason: 'the failure has to be visible, not substituted');
  });

  testWidgets('the failed card offers a retry that re-issues the read',
      (tester) async {
    // Fails from the very first read, so the card is in its failure state
    // without a second pump — and the mock is now waiting on a gate the test
    // owns, so the retry's in-flight state is a moment that still exists when
    // the assertions run. An instant 500 puts the busy state over inside one
    // pump, and the latched icon would be asserted on a frame that has already
    // been replaced.
    final platform = _Platform()..planFails = true;
    final gate = Completer<void>();
    final b = await _boot(platform);
    // First read fails fast so the failure state is reached inside the pump
    // budget; the gate is armed *after*, so only the retry is the slow one.
    await _pump(tester, b.api, b.auth, _Clock());
    platform
      ..retryGate = gate
      ..gateOpen = false;
    expect(find.byKey(const Key('worker-plan-retry')), findsOneWidget,
        reason: 'a failed read must offer a way back, not just a sentence');
    final beforeRetry = _planReads(platform);

    final key = find.byKey(const Key('worker-plan-retry')).first;
    await tester.tap(key);
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget,
        reason: 'the control must show it latched');
    final afterTap = _planReads(platform);
    expect(afterTap, beforeRetry + 1,
        reason: 'the retry must actually re-issue the read');

    // A second tap on a slow connection must not queue a second request. This
    // is the whole reason the control latches: without it, a man on a bad
    // network tapping twice sends two reads and sees nothing for it.
    await tester.tap(key, warnIfMissed: false);
    await tester.pump();
    expect(_planReads(platform), afterTap,
        reason: 'two taps issued two requests against one retry');

    gate.complete();
    await _settle(tester);
  });

  testWidgets('a real paid plan is never overwritten by the error state',
      (tester) async {
    final platform = _Platform();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, _Clock());

    expect(find.textContaining('بقي'), findsOneWidget,
        reason: 'a good read publishes the quota');
    expect(find.text('تعذّر جلب خطتك'), findsNothing);
    expect(find.text('خطتك وحدود العروض وتفعيل الاشتراك'), findsNothing);
  });

  testWidgets('the card is dressed as a failure, not as a settled plan',
      (tester) async {
    final platform = _Platform()..planFails = true;
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, _Clock());

    final card = find.byKey(const Key('worker-plan-entry'));
    expect(card, findsOneWidget);
    // The chevron is counted inside the card: it is the "open your plan"
    // affordance, and on a card that has no plan to read it is the old lie
    // wearing a different font.
    expect(
        find.descendant(
            of: card, matching: find.byIcon(Icons.chevron_left_rounded)),
        findsNothing);
    expect(find.descendant(of: card,
            matching: find.byIcon(Icons.refresh_rounded)), findsOneWidget);
  });

  testWidgets('the retry control keeps a real >= 48dp tap target', (tester) async {
    final platform = _Platform()..planFails = true;
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, _Clock());

    final target =
        tester.getSize(find.byKey(const Key('worker-plan-retry')).first);
    // AppTheme.tapMin is 56 dp. The control is a transparent 56 dp box around a
    // 20 dp glyph, so a pixel scan of the shot can only ever measure the glyph
    // — the target is asserted here instead.
    expect(target.width, greaterThanOrEqualTo(48.0),
        reason: 'a retry the user cannot hit is not a retry');
    expect(target.height, greaterThanOrEqualTo(48.0));
  });

  testWidgets('a fresh read prints no age clause at all', (tester) async {
    // The contract the header established, applied here: under a minute the
    // clause is *absent*, not «الآن». A clause that is never missing is a
    // clause a reader learns to skip, and then misses it on the read where it
    // is the only thing that matters.
    final platform = _Platform();
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);

    expect(find.byKey(const Key('plan-read-at')), findsNothing,
        reason: 'a read thirty seconds old is not an event');
  });

  testWidgets('an hour-old quota is dated, and dated loudly', (tester) async {
    final platform = _Platform();
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);

    // Move the wall clock rather than waiting: the row's age is the thing under
    // test and it cannot be observed by patience.
    clock.advance(const Duration(hours: 3));
    // A rebuild is needed for the row to re-read its own clock, and that
    // rebuild must NOT issue a request — which is the first test's contract.
    await _rebuild(tester);

    // **And the age has to survive a *second* rebuild.**
    //
    // This is the assertion that makes the mutant die, and getting it wrong is
    // how the bug I found today would have shipped green. `_stamp()` used to run
    // on *every* `didChangeDependencies`, so the age on screen was the age of
    // the last rebuild rather than the age of the read. One rebuild after the
    // clock moved still shows «قبل 3 ساعات» — the clause appears the instant
    // anything rebuilds — so a test that checked the age exactly once passed
    // against the broken code. The defect only shows up when a rebuild happens
    // *after* the age is already on screen: the re-stamp then resets it to zero
    // and the clause vanishes.
    //
    // Which is the actual user-visible bug: an hour-old quota that flickers back
    // to undated every time the freshness tick fires, forever.
    await _rebuild(tester);
    expect(find.byKey(const Key('plan-read-at')), findsOneWidget,
        reason: 'a rebuild must not re-date the read; the age belongs to the '
            'read, not to the last frame that drew it');

    // **The surviving case, and the one that actually matters in production.**
    //
    // The two rebuilds above only fire `setState`, and `AppScope` is an
    // `InheritedWidget` whose `updateShouldNotify` compares the api, auth and
    // place *instances* (app_scope.dart:53). A `setState` swaps none of them, so
    // `didChangeDependencies` does not re-run, and a re-stamping
    // `didChangeDependencies` is unreachable that way. My first mutation survived
    // the whole file because the test never produced the event that triggers it.
    //
    // So the event is produced directly: a **new scope**. Signing out and back in
    // builds a fresh `ApiClient`, the tab shell re-mounts with it, and every
    // `didChangeDependencies` down the tree fires. That is a real user path —
    // the man whose session expired and who signs in again — and on it the
    // un-guarded stamp reset the plan row's age to zero, so a quarter-old quota
    // went back to reading as fresh the instant he came back to the app.
    await tester.pumpWidget(_scopedApp(api: b.api, auth: b.auth, clock: clock));
    await _settle(tester);
    expect(
        find.descendant(
            of: find.byKey(const Key('worker-plan-entry')),
            matching: find.byKey(const Key('plan-read-at'))),
        findsOneWidget,
        reason: 'a new AppScope re-runs didChangeDependencies; the read is '
            'still the same read, so its age must survive being re-observed');

    final clause = find.byKey(const Key('plan-read-at'));
    expect(clause, findsOneWidget,
        reason: 'three hours is an age, and an age this old is worth saying');
    // Scoped to the card on purpose. The stats line eight centimetres above
    // prints «قبل 3 ساعات» too — both were read at 10:00 against a clock that
    // has since moved, so two widgets saying the same words is the *correct*
    // result and a bare `find.text` would call it a duplicate. What has to be
    // checked is that this one, the card's, is the one that changed.
    expect(
        find.descendant(of: find.byKey(const Key('worker-plan-entry')),
            matching: find.text('قبل 3 ساعات')),
        findsOneWidget,
        reason: 'the same clock the header uses, so one read is dated one way');
    // …and the weight, because the words are not the whole signal at this size.
    final text = tester.widget<Text>(clause);
    expect(text.style?.fontWeight, FontWeight.w800,
        reason: 'a quarter-old quota is a different kind of statement');
  });

  testWidgets('the aged card is shot, so the claim is looked at', (tester) async {
    final platform = _Platform();
    final clock = _Clock();
    final b = await _boot(platform);
    await _pump(tester, b.api, b.auth, clock);
    clock.advance(const Duration(hours: 3));

    // No `pumpWidget(find.byType(MaterialApp))` here, unlike the version I
    // inherited. That line re-pumped the **bare** `MaterialApp`, which is the
    // widget's own subtree — and `AppScope` sits *above* it, so the re-pump
    // dropped the scope and the very next frame threw
    // `AppScope not found in widget tree` out of `_PortfolioBadgeState`. The
    // failure named the portfolio badge and pointed nowhere near the line that
    // caused it.
    //
    // `_shoot` re-pumps the complete tree, scope included, so the aged state is
    // captured by advancing the clock and letting the capture do the pumping.
    final path = await _shoot(tester, 'plan_row_aged', b.api, b.auth, clock);
    expect(File(path).lengthSync(), greaterThan(20000),
        reason: 'a shot this small means nothing rendered');
  });

  testWidgets('a guest is never asked for a plan he has no account for',
      (tester) async {
    final platform = _Platform();
    final b = await _boot(platform, signedOut: true);
    // `guest: true` is what the shell passes when `AuthGate.isGuest` is set
    // (worker_home_screen.dart:100). Without it the market view still asks for
    // a profile, because it does not know there is no session.
    await tester.pumpWidget(
        _scopedApp(api: b.api, auth: b.auth, clock: _Clock(), guest: true));
    await _settle(tester);

    expect(_planReads(platform), 0,
        reason: 'the plan is the one read a signed-out visitor has no '
            'account to make');
    expect(find.byKey(const Key('worker-plan-entry')), findsNothing);
  });
}
