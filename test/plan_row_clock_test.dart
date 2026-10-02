// The account tab's subscription line, dated against the clock it was handed.
//
// The last reader of the wall-clock getters. `52b3640` closed the fuse on
// `subscription_screen.dart` (its card asked `isExpiredAt(now)`), and its note
// named this row as what was left — "has **no `clock` seam at all**, so there is
// nothing to inject". This file is that seam, plus the part that turned out to
// be worse than a missing seam: the row has **no timer either**.
//
// Why it matters more here than there. The account tab is a child of the
// shell's `IndexedStack` (`worker_home_screen.dart:214`), so it is built once
// and stays mounted for the whole session — tab switches do not rebuild it.
// `_PlanAccountRowState` issues its read exactly once, in
// `didChangeDependencies`, and never again. So `_planSummary` had been printing
// the answer that was true when the read landed, for as long as the app stayed
// open. A plan that ends *during* a session keeps reading «نشط حتى 2026-10-01»,
// on the one row whose entire job is to send the contractor to the renewal
// screen.
//
// The mutation gate matters more than the assertions. A test that only checks
// for «انتهت» passes just as happily against the old code, because the old code
// had a *different* sentence rather than no sentence. What is pinned below is
// the behaviour: one fixture, two clocks, and a timer that must actually move
// the line without a rebuild.
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
import 'package:allomokawil/src/screens/profile_screen.dart';

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

/// A paid plan that ends at **21:00 on 30 Sep 2026 Algiers**, so the two clocks
/// below straddle the end instant with no boundary of its own to argue about.
Map<String, Object?> _catalogue() => <String, Object?>{
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
        'status': 'active',
        'price_month': 4500,
        'price_year': 45000,
        'quote_limit': 10,
        'quotes_used_this_month': 2,
        'expires_at': '2026-09-30 21:00:00',
      },
      'pending_request': null,
      'payment': <String, Object?>{'methods': <Object?>[]},
    };

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Boots a logged-in worker against a catalogue whose only variable is time.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/mobile/subscription')) return _json(_catalogue());
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, log: log);
}

/// Every line the account screen drew, so a claim about which sentence is on
/// screen is a claim about the tree and not about one `find.text` guess.
List<String> _lines(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

void main() {
  group('the account row dates the plan line with the clock it was handed', () {
    testWidgets('a clock before the end instant still reads as running',
        (tester) async {
      final b = await _boot();
      tester.view.physicalSize = const Size(1080, 2475);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AppScope(
        api: b.api,
        auth: b.auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ProfileScreen(clock: () => DateTime(2026, 9, 29, 10)),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('نشط حتى')),
        isTrue,
        reason: 'a plan with cover still running was not described as '
            'running:\n$lines',
      );
      expect(
        lines.any((t) => t.contains('انتهت في')),
        isFalse,
        reason: 'the row called a live plan finished:\n$lines',
      );
    });

    testWidgets('the SAME row reads as finished once the clock passes the end',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // server payload is byte-identical to the case above; only the injected
      // clock moved past 30 Sep 21:00. Before the fix both cases printed the
      // wall clock's answer, so the difference this file exists to prove was
      // not observable at all — which is the definition of the fuse.
      final b = await _boot();
      tester.view.physicalSize = const Size(1080, 2475);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AppScope(
        api: b.api,
        auth: b.auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ProfileScreen(clock: () => DateTime(2026, 10, 2, 10)),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('انتهت في 2026-09-30')),
        isTrue,
        reason: 'a plan past its expiry still rendered as live:\n$lines',
      );
      expect(
        lines.any((t) => t.contains('نشط حتى')),
        isFalse,
        reason: 'the row called a finished plan running:\n$lines',
      );
    });

    testWidgets('the minute tick ages the line without anything rebuilding it',
        (tester) async {
      // The half that no screenshot can show. The two cases above both pump a
      // fresh tree; a contractor does not do that. He leaves the tab mounted in
      // the shell's `IndexedStack` and the only thing that can move the line is
      // the tick — so this case moves **only** the clock, never the widget.
      //
      // Before the fix there was no timer at all, so this pump was a no-op and
      // the row kept the sentence from the first frame for the rest of the
      // session.
      var now = DateTime(2026, 9, 29, 10);
      final b = await _boot();
      tester.view.physicalSize = const Size(1080, 2475);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AppScope(
        api: b.api,
        auth: b.auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ProfileScreen(clock: () => now),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(_lines(tester).any((t) => t.contains('نشط حتى')), isTrue,
          reason: 'setup did not reach the running sentence:\n${_lines(tester)}');

      // No `pumpWidget`, no key change, no `setState` — only the clock moves,
      // the way a real midnight moves while the app sits in a pocket.
      now = DateTime(2026, 10, 2, 10);
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));

      final lines = _lines(tester);
      expect(
        lines.any((t) => t.contains('انتهت في 2026-09-30')),
        isTrue,
        reason: 'the line did not age with the clock it was handed; the row '
            'lives in an IndexedStack and nothing rebuilds it:\n$lines',
      );
    });

    testWidgets('the ageing timer is cancelled when the row leaves the tree',
        (tester) async {
      // A `Timer.periodic` left armed after `dispose` keeps a live isolate
      // handle and fails the very next test with "A Timer is still pending",
      // which is how one author's widget test becomes everybody's. Cancelling
      // it is part of the feature, so it is pinned.
      final b = await _boot();
      tester.view.physicalSize = const Size(1080, 2475);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(AppScope(
        api: b.api,
        auth: b.auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ProfileScreen(clock: () => DateTime(2026, 9, 29, 10)),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      // Reaching here without "A Timer is still pending even after the widget
      // tree was disposed" *is* the assertion.
    });
  });
}
