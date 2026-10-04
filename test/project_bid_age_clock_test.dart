// The bid cards on the project detail page, and the one thing that makes them
// lie while an owner compares four bids.
//
// **[ProjectDetailScreen.clock] was already here**, added because "a screen
// that reads the real clock is a screen whose pixels depend on when the test
// ran" — the seam exists so a test can pin the answer. That is all it was ever
// wired to. Production leaves it null, `_QuoteCard` calls
// `relativeTimeAr(quote.createdAt, now: clock?.call())` **at build time**, and
// this screen rebuilds on exactly two things: the first pair of reads, and
// `_reload()`. Neither of those is "a minute passed".
//
// So an owner who opened a project with four bids on it and sat comparing them
// — which is what this page is for, and the whole reason the ages are printed —
// watched «قبل 12 دقيقة» stay «قبل 12 دقيقة» on all four cards for as long as
// he sat there, while the bid that arrived during his reading pushed the
// newest card's stamp forward. Four cards, one screen, disagreeing about when
// they arrived, on the screen that decides who gets the job.
//
// Fourth screen in this family (`profile_screen` 80a0e65, `subscription_screen`
// 52b3640, `notifications_screen` a87647e) and the first reached from four
// different callers, so it is a pushed route and the `dispose` cancel is part of
// the feature rather than hygiene.
//
// The mutation gate matters more than the assertions. A test that only looks for
// «ساعتين» passes just as happily against the old code, because the old code
// printed a *different* sentence rather than no sentence. What is pinned below
// is the behaviour: one fixture, two clocks, and a timer that must move the
// label with no rebuild of anything.
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
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

// **The injected clocks below are `DateTime.utc`, and that is not cosmetic.**
//
// Both fixtures here are read the way D1 writes them: `'2026-10-02 09:48:00'`
// has no zone, and `parseServerTime` reads it as UTC — correctly, because that
// is what the server sends. The clock these tests inject used to be a **local**
// `DateTime(2026, 10, 2, 10)`, so the two ends of the subtraction disagreed by
// whatever offset the machine running them was in. On this box the shell
// exports `TZ=Africa/Algiers` while `/etc/localtime` points at `Etc/UTC`, and
// that one-hour disagreement is the whole failure:
//
//     Expected: <2>   Actual: <0>       // two cards that must say «12 دقيقة»
//
// A 12-minute-old bid read as **two hours** old, because 09:48 UTC against a
// clock claiming 10:00 local is 10:00-09:48 **plus** the offset. The suite went
// red on six cases the moment the host timezone and the shell's `TZ` drifted
// apart — with **no change to `lib/` at all** (`git stash` + rerun reproduces
// it on clean HEAD). The alarm was on a test fixture, not on the product, which
// is why the fix is here and not in `relativeTimeAr`: the product's arithmetic
// is `today.difference(at)` over two absolute instants, and it is correct for
// every zone. Pinning the clock to UTC makes both ends of that subtraction
// absolute and the assertions zone-independent, so the file says what it means
// on a laptop in Algiers and on a CI box in UTC alike.

/// A bid stamped exactly **12 minutes** before the clock this file injects.
///
/// 12 so the two cases land on sentences a glance can tell apart —
/// «قبل 12 دقيقة» inside the minute band, «قبل ساعتين» past the hour — and so
/// neither is «الآن», which would let the fixture pass against any build that
/// rendered no time at all.
Map<String, dynamic> _row(int id) => <String, dynamic>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 100 + id,
      'amount': 5000 + id,
      'message': 'عرض تجريبي',
      'estimated_days': 5,
      'status': 'pending',
      'created_at': '2026-10-02 09:48:00',
      'worker_full_name': 'مقاول رقم $id',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

Map<String, dynamic> _user() => <String, dynamic>{
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'زبون تجربة',
      'type': 'customer',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// The owner's own project, so `_isOwner` is true and the cards under test are
/// the ones drawn on the page he is judging bids on.
final Map<String, dynamic> _project = <String, dynamic>{
  'id': 'p1',
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

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Boots a signed-in project owner whose project carries two bids, both from
/// the same fixture row.
Future<ApiClient> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, dynamic>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.startsWith('/api/mobile/projects/p1/quotes')) {
        return _json(<Map<String, dynamic>>[_row(48), _row(49)]);
      }
      if (p == '/api/mobile/projects/p1') return _json(_project);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer',
      reason: 'the fixture must land on the owner, or the action row is not '
          'drawn and the cards are not the ones under test');
  return api;
}

/// Every line the page drew, so a claim about which sentence is on screen is a
/// claim about the tree and not about one `find.text` guess.
List<String> _lines(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// A phone-shaped viewport tall enough that the bid cards' date lines are
/// built — the quote list sits well below the fold on a real screen.
Future<void> _pump(WidgetTester tester, DateTime Function() now) async {
  tester.view.physicalSize = const Size(392, 2400) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final api = await _boot();
  final auth = AuthState(api);
  await auth.restore();
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
      home: ProjectDetailScreen(
        projectId: 'p1',
        repo: Repository(api),
        clock: now,
      ),
    ),
  ));
  // Bounded pumps, not pumpAndSettle: the loading skeleton animates forever,
  // so settling would never return.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('the bid cards age their stamps while the page sits open', () {
    testWidgets('a bid 12 minutes old is labelled 12 minutes', (tester) async {
      await _pump(tester, () => DateTime.utc(2026, 10, 2, 10));

      final lines = _lines(tester);
      expect(
        lines.where((t) => t.contains('12 دقيقة')).length,
        2,
        reason: 'both cards are the same fixture row 12 minutes old and must '
            'both say so; what the page drew:\n$lines',
      );
      expect(
        lines.any((t) => t.contains('ساعتين')),
        isFalse,
        reason: 'a 12-minute-old bid was labelled two hours old:\n$lines',
      );
    });

    testWidgets('the SAME bids read as two hours old once the clock moves',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // server payload is byte-identical to the case above; only the injected
      // clock moved from 10:00 to 12:05. Before the fix both cases printed the
      // wall clock's answer, so the difference this file exists to prove was
      // not observable at all — which is the definition of the fuse.
      await _pump(tester, () => DateTime.utc(2026, 10, 2, 12, 5));

      final lines = _lines(tester);
      expect(
        lines.where((t) => t.contains('ساعتين')).length,
        2,
        reason: 'both bids are over two hours old and must both say so:\n$lines',
      );
      expect(
        lines.any((t) => t.contains('12 دقيقة')),
        isFalse,
        reason: 'the page called a 2-hour-old bid 12 minutes old:\n$lines',
      );
    });

    testWidgets('the minute tick re-labels the cards without anything rebuilding them',
        (tester) async {
      // The half no screenshot can show, and the half the two cases above
      // cannot reach. Both of those pump a fresh tree. An owner does not do
      // that: he opens the project once and reads it while bids arrive. So this
      // case moves **only** the clock — no `pumpWidget`, no key change, no
      // `setState` — because that is the actual defect.
      //
      // Before the fix there was no timer at all, so this pump was a no-op and
      // both cards kept the first frame's sentence for as long as the page sat
      // open.
      var now = DateTime.utc(2026, 10, 2, 10);
      await _pump(tester, () => now);
      expect(_lines(tester).where((t) => t.contains('12 دقيقة')).length, 2,
          reason: 'setup did not reach the minute sentence:\n${_lines(tester)}');

      // Only the clock moves, the way a real minute moves while the phone sits
      // in a pocket and the owner is halfway down the list.
      now = DateTime.utc(2026, 10, 2, 12, 5);
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));

      final lines = _lines(tester);
      expect(
        lines.where((t) => t.contains('ساعتين')).length,
        2,
        reason: 'the stamps did not age with the clock they were handed; this '
            'page rebuilds only on its first read and on `_reload()`, so nothing '
            'else can move the label:\n$lines',
      );
    });

    testWidgets('the ageing timer is cancelled when the page leaves the tree',
        (tester) async {
      // A `Timer.periodic` left armed after `dispose` keeps a live handle and
      // fails the very next test with "A Timer is still pending", which is how
      // one author's widget test becomes everybody's. Cancelling it is part of
      // the feature, so it is pinned.
      await _pump(tester, () => DateTime.utc(2026, 10, 2, 10));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));
      // Reaching here without "A Timer is still pending even after the widget
      // tree was disposed" *is* the assertion.
    });
  });
}
