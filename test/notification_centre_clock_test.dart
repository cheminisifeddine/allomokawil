// The notification centre's timestamps, dated against the clock it was handed.
//
// **[NotificationsScreen.clock] was already here** — it was added so the
// `15_notifications` golden would stop drifting on an hour boundary and taking
// the whole `flutter test` gate red with it. So this screen was the one screen
// in the app that *looked* like it had solved wall-clock rendering, and it had
// solved only the test's half of the problem.
//
// What it left was worse than a missing seam. With `clock` null in production,
// `_tile` called `relativeTimeAr` against the real wall clock **at build time**,
// and this screen rebuilds on exactly three things: the first `_load`, a
// pull-to-refresh, and a row being marked read. None of them is "a minute
// passed". So a contractor who opened the centre and sat reading it for twenty
// minutes watched «قبل 12 دقيقة» stay «قبل 12 دقيقة» for all twenty — while
// messages landing *during* those twenty minutes pushed the newest row's
// stamp forward. Two rows on one screen, disagreeing about when they arrived,
// both frozen from the same build.
//
// Same fuse as `profile_screen.dart`'s plan row (`80a0e65`) and
// `subscription_screen.dart`'s card (`52b3640`): a computed answer whose screen
// never asks the question again. The seam was already present here. What was
// missing was the timer that makes it live.
//
// The mutation gate matters more than the assertions. A test that only looks
// for «الآن» passes just as happily against the old code, because the old code
// had a *different* sentence rather than no sentence. What is pinned below is
// the behaviour: one fixture, two clocks, and a timer that must move the label
// with no rebuild of anything.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

/// One row, stamped exactly **12 minutes** before the clock this file injects.
///
/// 12 is chosen so the two cases land on different sentences that a glance can
/// tell apart — «قبل 12 دقيقة» inside the minute band, «قبل ساعتين» past the
/// hour — and so neither is «الآن», which would make the fixture pass against
/// any build that rendered no time at all.
Map<String, Object?> _row() => <String, Object?>{
      'id': 91,
      'type': 'new_quote',
      'title': 'عرض جديد على مشروعك',
      'body': 'أرسل المقاول عرضاً',
      'link': null,
      'is_read': 0,
      'created_at': '2026-10-02 09:48:00',
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: const {'content-type': 'application/json'});

/// Boots a signed-in user against a centre holding exactly one row.
Future<ApiClient> _boot() async {
  final api = ApiClient(
    baseUrls: const ['https://api.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/notifications')) return _json(<Object?>[_row()]);
      return _json(<Object?>[]);
    }),
  );
  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(const {
      'id': 7,
      'phone': '0550000000',
      'email': null,
      'full_name': 'زبون تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-01-01 00:00:00',
    }),
  });
  return api;
}

/// Every line the centre drew, so a claim about which sentence is on screen is
/// a claim about the tree and not about one `find.text` guess.
List<String> _lines(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// A phone-shaped viewport tall enough that the row's time column is built.
Future<void> _pump(WidgetTester tester, DateTime Function() now) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = await _boot();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: await _authOf(api),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: NotificationsScreen(clock: now),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<AuthState> _authOf(ApiClient api) async {
  final auth = AuthState(api);
  await auth.restore();
  return auth;
}

void main() {
  group('the notification centre dates its rows with the clock it was handed',
      () {
    testWidgets('a row 12 minutes old is labelled 12 minutes', (tester) async {
      await _pump(tester, () => DateTime(2026, 10, 2, 10));

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('12 دقيقة')),
        isTrue,
        reason: 'a row stamped 12 minutes before the clock did not say so:\n'
            '$lines',
      );
      expect(
        lines.any((t) => t.contains('ساعتين')),
        isFalse,
        reason: 'a 12-minute-old row was labelled two hours old:\n$lines',
      );
    });

    testWidgets('the SAME row reads as two hours old once the clock moves',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // server payload is byte-identical to the case above; only the injected
      // clock moved from 10:00 to 12:05. Before the fix both cases printed the
      // wall clock's answer, so the difference this file exists to prove was
      // not observable at all — which is the definition of the fuse.
      await _pump(tester, () => DateTime(2026, 10, 2, 12, 5));

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('ساعتين')),
        isTrue,
        reason: 'a row over two hours old was not labelled as such:\n$lines',
      );
      expect(
        lines.any((t) => t.contains('12 دقيقة')),
        isFalse,
        reason: 'the centre called a 2-hour-old row 12 minutes old:\n$lines',
      );
    });

    testWidgets('the minute tick re-labels the row without anything rebuilding it',
        (tester) async {
      // The half no screenshot can show, and the half the other two cases
      // cannot reach. Both of those pump a fresh tree. A contractor does not do
      // that: he opens the centre once and reads it while messages arrive. So
      // this case moves **only** the clock — no `pumpWidget`, no key change, no
      // `setState` — because that is the actual defect.
      //
      // Before the fix there was no timer at all, so this pump was a no-op and
      // the row kept the first frame's sentence for as long as the centre sat
      // open.
      var now = DateTime(2026, 10, 2, 10);
      await _pump(tester, () => now);
      expect(_lines(tester).any((t) => t.contains('12 دقيقة')), isTrue,
          reason: 'setup did not reach the minute sentence:\n${_lines(tester)}');

      // Only the clock moves, the way a real minute moves while the app sits in
      // a pocket and the user is halfway down the list.
      now = DateTime(2026, 10, 2, 12, 5);
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('ساعتين')),
        isTrue,
        reason: 'the timestamp did not age with the clock it was handed; this '
            'screen rebuilds only on load, refresh and mark-read, so nothing '
            'else can move the label:\n$lines',
      );
    });

    testWidgets('the ageing timer is cancelled when the centre leaves the tree',
        (tester) async {
      // A `Timer.periodic` left armed after `dispose` keeps a live handle and
      // fails the very next test with "A Timer is still pending", which is how
      // one author's widget test becomes everybody's. Cancelling it is part of
      // the feature, so it is pinned.
      await _pump(tester, () => DateTime(2026, 10, 2, 10));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      // Reaching here without "A Timer is still pending even after the widget
      // tree was disposed" *is* the assertion.
    });
  });
}
