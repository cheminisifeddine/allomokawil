// The notification centre queued its own answer behind the line it was
// replacing.
//
// This is the class the last four ticks opened: `ScaffoldMessenger` **queues**.
// A second `showSnackBar` while one is visible does not replace it — it waits
// for the first to time out. On the mark-read recheck path the first is
// «نتحقّق من الإشعارات…» (`S.notifReadUnconfirmedRecheck`), a progress note
// with its own four-second duration, and the second is the only sentence that
// answers «is this notification still counted as new?».
//
// So a user whose tap reached the Worker and lost its answer read, for four
// full seconds, a note about a check that had already finished, and only then
// the answer — on a screen whose entire job is the unread pip.
//
// `_settleRead` hand-rolled both calls and never hid. The project screen
// reached the same conclusion for `_accept`/`_complete` and for the bid sheet
// and grew `_showRechecking` / `_showCommitResult`; those were not applied
// here. The third `showSnackBar` on this screen — the «no action» line in
// `_open` — is deliberately left alone: nothing is above it, so it has no line
// to replace and hiding there would only blank a message nobody is covering.
//
// The rule pinned here: **a line that is about to be replaced must be removed
// first**, so the answer to «did my read land?» is the only thing on screen.
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
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

/// One stored notification, shaped exactly like the D1 row the API returns.
Map<String, Object?> _row({required int id, int isRead = 0}) => <String, Object?>{
      'id': id,
      'type': 'new_quote',
      'title': 'عرض جديد على مشروعك',
      'body': 'مقاول أرسل عرضاً',
      'link': 'projects/7',
      'is_read': isRead,
      'created_at': '2026-09-29 10:00:00',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

/// The signed-in user the screen assumes.
const _sessionUser = <String, Object?>{
  'id': 7,
  'phone': '0550000000',
  'email': null,
  'full_name': 'عميل تجريبي',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

/// Boots the real screen on a Worker that **stores the mark-read and then
/// never answers it**.
///
/// The failure is produced by the **real transport**, not hand-thrown: the POST
/// outruns `ApiClient`'s timeout, so `isWriteUnconfirmed` matches on the
/// exception the network layer really throws and `_settleRead` is reached the
/// way a user reaches it. A stubbed exception would have proved the screen
/// handles an object, not that the failure arrives.
///
/// The re-read is answered with **real rows marked read**, because
/// `notificationsProvenRead` is what turns a fresh list into «landed» — a
/// fixture that returned the wrong shape here would classify every verdict as
/// `unknown` and the test would be measuring a different sentence. (That is
/// precisely the fixture bug that made the bid test read as «no bug».)
Future<({ApiClient api, AuthState auth})> _boot({
  Duration timeout = const Duration(milliseconds: 40),
  int answerDelayMs = 400,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_sessionUser),
  });
  var writes = 0;
  final api = ApiClient(
    baseUrls: const ['https://api.test'],
    timeout: timeout,
    httpClient: MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/notifications/read') {
        writes++;
        // The rows are cleared. The answer is not on its way.
        await Future<void>.delayed(Duration(milliseconds: answerDelayMs));
        return _json(<String, Object?>{'unread': 0});
      }
      if (path == '/api/notifications') {
        // Before the write the centre holds two unread rows; after it, the
        // server holds none — which is the proof the verdict reads as «landed».
        if (writes == 0) {
          return _json([_row(id: 11), _row(id: 12)]);
        }
        return _json([_row(id: 11, isRead: 1), _row(id: 12, isRead: 1)]);
      }
      if (path == '/api/unread') return _json(<String, Object?>{'unread': 0});
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  expect(auth.user?.id, 7, reason: 'the screen is driven as a signed-in user');
  return (api: api, auth: auth);
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
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
        home: NotificationsScreen(repo: Repository(api)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget,
      reason: 'two unread rows must be on screen, or the button is not drawn');
}

/// Presses «تعليم الكل كمقروء» — the action that reaches the unconfirmed
/// branch, with no navigation on top of it to complicate the pump.
Future<void> _markAll(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('notifications-mark-all')));
  await tester.pumpAndSettle();

  // `pumpAndSettle` returns as soon as no frame is scheduled, and a pending
  // timer schedules none — so it returns while the POST is still waiting for an
  // answer that never comes. The recheck only starts once the transport gives
  // up, so the budget below has to outlast the timeout (40 ms) *and* the answer
  // that never lands (400 ms) before any verdict can exist. An earlier version
  // of the bid test asserted on an empty queue here and looked like the bug
  // was absent; this pump is what makes the branch reachable.
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
/// behind it. Counting SnackBars in the tree cannot see a queue at all.
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
      'the verdict on a mark-read whose answer never came is drawn without '
      'waiting out the line it replaces', (tester) async {
    final boot = await _boot();

    await _pump(tester, boot.api, boot.auth);
    await _markAll(tester);

    // Proof the screen reached the branch under test at all: the POST outran
    // its timeout, so either the recheck line is up or — once the fix is in —
    // it has already been replaced by the verdict. Anything else means the
    // recheck never ran and the timing below would be measuring a screen that
    // never got there. Asserted *before* the timing, so the test cannot pass by
    // measuring nothing.
    expect(
        _visibleLine(tester),
        anyOf(S.notifReadUnconfirmedRecheck, S.notifReadUnconfirmedLanded),
        reason: 'the mark-read must outrun its timeout and enter the recheck '
            'path');

    // The whole payload of this path is the verdict, and the moment the re-read
    // resolves the app knows it. `ScaffoldMessenger` queues, so without
    // `hideCurrentSnackBar()` the verdict waits out the recheck line's default
    // four seconds. The user is told he is being checked for four seconds
    // *after* the check finished, and the only sentence that answers «is this
    // still counted as new?» arrives last and alone.
    final took = await _millisUntilVisible(tester, S.notifReadUnconfirmedLanded);

    expect(took, isNot(-1),
        reason: 'the Worker cleared the rows, so the app must eventually say so');
    expect(
        took,
        lessThan(2000),
        reason: 'the verdict waited $took ms to reach the screen. It is the '
            'answer to «did my read land?» and it must not sit behind the '
            'recheck line for its full default four-second duration.');
  });

  testWidgets('the recheck line is removed, so one verdict is ever on screen',
      (tester) async {
    final boot = await _boot();

    await _pump(tester, boot.api, boot.auth);
    await _markAll(tester);

    final took = await _millisUntilVisible(tester, S.notifReadUnconfirmedLanded);
    expect(took, isNot(-1), reason: 'the verdict must exist to judge this');

    // One failure, one line: once the verdict arrives the progress note about
    // a check that has already finished must not be on screen, and nothing may
    // be queued behind the answer either.
    expect(_visibleLine(tester), S.notifReadUnconfirmedLanded,
        reason: 'the answer replaces the recheck line; it does not join it');
    expect(_visibleLine(tester), isNot(S.notifReadUnconfirmedRecheck));
  });

  testWidgets(
      'the mark-all form is answered with the same single line, since it is the '
      'same recheck', (tester) async {
    final boot = await _boot();

    await _pump(tester, boot.api, boot.auth);
    await _markAll(tester);

    // The no-ids form clears everything, so the proof is that **no** row is
    // unread in the fresh list — which is exactly what the fixture returns.
    // If this ever classified as `unknown` the copy would send the user to the
    // list instead of telling them the tap worked, and the timing below would
    // be measuring a different sentence.
    final took =
        await _millisUntilVisible(tester, S.notifReadUnconfirmedLanded);
    expect(took, isNot(-1),
        reason: 'the mark-all form must classify as landed on this fixture');
  });
}
