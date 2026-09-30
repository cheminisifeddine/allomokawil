// The bid sheet queued its own answer behind the line it was replacing.
//
// This is the class the previous three ticks opened: `ScaffoldMessenger`
// **queues**. A second `showSnackBar` while one is visible does not replace
// it — it waits for the first to time out. On the bid path the first is
// «نتحقّق الآن من القائمة…» (`S.writeUnconfirmedRecheck`), a recheck line with
// its own four-second duration, and the second is the only sentence that
// answers «did my bid arrive?».
//
// So a contractor whose bid reached the Worker and lost its answer read, in
// order, for four full seconds:
//
//   نتحقّق الآن من القائمة…          (the app is checking — harmless)
//   وجدناه في القائمة — الطلب وصل بنجاح   (it arrived; leave the screen)
//
// then, if the sheet re-opened, a *second* copy of the first line. The verdict
// is the entire payload of this path and it is the one message that arrives
// late, behind a progress note about a check that has already finished.
//
// `_accept` and `_complete` on the same screen already do this correctly —
// they go through `_showCommitResult`, which calls `hideCurrentSnackBar()`
// first. The bid path, twenty lines below them, hand-rolls both calls and
// never hides. Same file, same screen, two disciplines: the one the loop
// hand-fixed in the review screen on 30 Sep, un-applied here.
//
// The rule pinned here: **a line that is about to be replaced must be removed
// first**, so the answer to «did my bid land?» is the only thing on screen.
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
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

Map<String, Object?> _project() => <String, Object?>{
      'id': 'p-1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
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

Map<String, Object?> _myProfile() => <String, Object?>{
      'id': 16,
      'user_id': 16,
      'full_name': 'مقاول تجربة',
      'bio': null,
      'specialties': <String>['painting'],
      'experience_years': 4,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': null,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': null,
      'cover_image_url': null,
      'avatar_url': null,
      'user_wilaya': '16',
      'commune': null,
    };

/// The row the Worker actually stored for the bid whose answer never came.
Map<String, Object?> _storedQuote({int amount = 70000}) => <String, Object?>{
      'id': 501,
      'project_id': 'p-1',
      'worker_id': 16,
      'amount': amount,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Boots a signed-in **contractor** on someone else's open project — the only
/// session the bid button is offered to — against a Worker that stores the bid
/// and then never answers.
///
/// The failure is produced by the **real transport**, not hand-thrown: the POST
/// outruns `ApiClient`'s timeout, so `isWriteUnconfirmed` matches on the
/// exception the network layer really throws. A stubbed exception would have
/// proved the screen handles an object, not that the failure reaches it.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required List<int> quotesAfterRecheck,
  Duration timeout = const Duration(milliseconds: 40),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  var bids = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    timeout: timeout,
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 16,
            'phone': '0550000000',
            'email': null,
            'full_name': 'مقاول تجربة',
            'type': 'worker',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-01-01 00:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p == '/api/mobile/my/profile') return _json(_myProfile());
      if (p == '/api/mobile/projects/p-1/quotes' && req.method == 'POST') {
        bids++;
        // The row lands. The answer does not. This is the only failure shape
        // that makes the recheck path exist at all.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return _json(_storedQuote(amount: 70000));
      }
      if (p == '/api/mobile/projects/p-1/quotes') {
        if (bids == 0) return _json(<Object>[]);
        // The list the recheck reads: the stored rows themselves. An earlier
        // version mapped the amounts through the *response* builder and encoded
        // a list of `http.Response`, so the recheck could never recognise the
        // row and every verdict came back as `unknown` — a fixture that made
        // the app look broken in a different way than the one under test.
        return _json([
          for (final amount in quotesAfterRecheck) _storedQuote(amount: amount),
        ]);
      }
      if (p == '/api/mobile/projects/p-1') return _json(_project());
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0550000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'worker',
      reason: 'the fixture must land on a contractor, or no bid button is drawn');
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppScope(
        api: api,
        auth: auth,
        child: ProjectDetailScreen(projectId: 'p-1', repo: Repository(api)),
      ),
    ),
  );
  // Bounded pumps: the loading skeleton animates forever, so `pumpAndSettle`
  // would never return.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Fills the sheet and sends the bid, which is the path that reaches the
/// unconfirmed branch.
Future<void> _sendBid(WidgetTester tester) async {
  await tester.tap(find.text('قدّم عرضك'));
  await tester.pumpAndSettle();
  expect(find.text('إرسال العرض'), findsOneWidget,
      reason: 'the sheet must be on screen for this to measure anything');
  await tester.enterText(find.byType(TextField).at(0), '70000');
  await tester.enterText(find.byType(TextField).at(1), '5');
  await tester.tap(find.text('إرسال العرض'));
  await tester.pumpAndSettle();

  // `pumpAndSettle` returns as soon as no frame is scheduled, and a pending
  // timer schedules none — so it returns while the POST is still waiting for
  // an answer that will never come. The recheck only starts once the
  // transport gives up, so the budget below has to outlast the timeout (40 ms)
  // *and* the answer that never lands (400 ms) before any verdict can exist.
  // Two earlier versions of this test asserted on an empty queue here and
  // looked like the bug was absent; this pump is what makes the branch
  // reachable.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

/// The sentence the user is actually looking at right now.
///
/// Exactly one [SnackBar] is ever *built*, whether it is the only one or the
/// head of a queue — `ScaffoldMessenger` holds the rest as pending requests and
/// builds them only when their turn arrives. So this returns the line on
/// screen, and the timing below is what says whether another one is waiting
/// behind it. Counting SnackBars in the tree cannot see a queue at all, which
/// is why an earlier version of this test asserted on a tree that had nothing
/// to say and read as "no bug".
String? _visibleLine(WidgetTester tester) {
  final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
  if (bars.isEmpty) return null;
  final c = bars.first.content;
  return c is Text ? (c.data ?? '') : null;
}

/// Fake-clock milliseconds from now until [line] is the one on screen.
///
/// Pumped in steps rather than in one jump, so the returned value is the first
/// instant the line appears and not an artefact of an over-long pump.
Future<int> _millisUntilVisible(
  WidgetTester tester,
  String line, {
  Duration step = const Duration(milliseconds: 100),
  int cap = 200,
}) async {
  var elapsed = 0;
  for (var i = 0; i < cap; i++) {
    if (_visibleLine(tester) == line) return elapsed;
    await tester.pump(step);
    elapsed += step.inMilliseconds;
  }
  return _visibleLine(tester) == line ? elapsed : -1;
}

void main() {
  testWidgets(
      'the verdict on a bid whose answer never came is drawn without waiting '
      'out the line it replaces', (tester) async {
    final boot = await _boot(quotesAfterRecheck: [70000]);

    await _pump(tester, boot.api, boot.auth);
    await _sendBid(tester);

    // Proof the screen reached the branch under test at all: the POST outran
    // its timeout, so either the recheck line is up or — once the fix is in —
    // it has already been replaced by the verdict. Anything else means the
    // recheck never ran and the timing below would be measuring a screen that
    // never got there. This is asserted *before* the timing, so the test cannot
    // pass by measuring nothing.
    expect(
        _visibleLine(tester),
        anyOf(S.writeUnconfirmedRecheck, S.writeUnconfirmedLanded),
        reason: 'the bid must outrun its timeout and enter the recheck path');

    // The whole payload of this path is the verdict, and the moment the
    // recheck resolves the app knows it. `ScaffoldMessenger` queues, so without
    // `hideCurrentSnackBar()` the verdict waits for the recheck line to time
    // out — the default four seconds. The contractor is told he is being
    // checked for four seconds *after* the check finished, and the only
    // sentence that answers «did my bid arrive?» arrives last and alone.
    final took = await _millisUntilVisible(tester, S.writeUnconfirmedLanded);

    expect(took, isNot(-1),
        reason: 'the Worker stored the bid, so the app must eventually say so');
    expect(
        took,
        lessThan(2000),
        reason: 'the verdict waited $took ms to reach the screen. It is the '
            'answer to «did my bid land?» and it must not sit behind the '
            'recheck line for its full default four-second duration.');
  });

  testWidgets('the recheck line is removed, so one verdict is ever on screen',
      (tester) async {
    final boot = await _boot(quotesAfterRecheck: [70000]);

    await _pump(tester, boot.api, boot.auth);
    await _sendBid(tester);

    final took = await _millisUntilVisible(tester, S.writeUnconfirmedLanded);
    expect(took, isNot(-1), reason: 'the verdict must exist to judge this');

    // One failure, one line: once the verdict arrives the progress note about
    // a check that has already finished must not be on screen, and nothing may
    // be queued behind the answer either.
    expect(_visibleLine(tester), S.writeUnconfirmedLanded,
        reason: 'the answer replaces the recheck line; it does not join it');
    expect(_visibleLine(tester), isNot(S.writeUnconfirmedRecheck));
  });
}
