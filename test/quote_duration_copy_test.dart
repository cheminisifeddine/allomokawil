// The completion-time line on a contractor's quote card, as the client reads it.
//
// Found on 26 Sep 2026 while auditing what the gallery badge left. Same vein,
// fifth cycle down: a count is either delegated to `arabicCounted` or spelled
// out by hand, and every hand-written one so far has been wrong.
//
// The line was built out of interpolation with one fixed noun:
//
//     Text('مدة الإنجاز: ${quote.estimatedDays} يوم')
//
// which is the worst instance of the bug in the app so far, because the
// gallery tile was wrong on two ranges out of four and **this one was wrong at
// every value except two**:
//
//   * 1  -> «1 يوم»    the singular is not counted: one is what «يوم» means
//   * 2  -> «2 يوم»    the dual is «يومين», and takes no number with it
//   * 3  -> «3 يوم»    3-10 need the broken plural «أيام»
//   * 7  -> «7 يوم»    same, and this is the commonest real answer
//   * 11 -> «11 يوم»   counted singular, so the word is right
//   * 30 -> «30 يوم»   the word is right, 3-10's is not
//
// «يوم» is the correct *word* for 1 and for 11+, and it hides the rest: a
// reviewer looking at «مدة الإنجاز: 7 يوم» sees a real Arabic noun and moves
// on. The quote card is the row a client compares contractors on, so this is
// the worst place in the app to hand him a sentence no Algerian would write.
//
// **This file corrected its own author.** The first draft of the header, and
// the first draft of the test named "3-10 is the only range the old line got
// right", both claimed 3-10 was correct and 1 and 11+ were not. Restoring the
// old line on purpose made the 3-10 and 7-DAY widget tests fail, which is what
// proved the claim backwards: 3-10 is exactly the range the hard-coded word
// got wrong. A test that documents the defect incorrectly is worse than none,
// because the next tick reads it as a map of what is already handled.
//
// The days are read off the real `ProjectDetailScreen` and the quote is driven
// from the JSON the Worker actually sends, because "a client read «2 يوم»" is
// a claim about a rendered screen, not about a function's return value.
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
import 'package:allomokawil/src/data/quote_duration_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

/// The project the client is looking at. `customer_id: 30` matches the signed
/// in session below, so the screen builds the owner half and the quote card
/// with its own actions.
Map<String, dynamic> _project() => <String, dynamic>{
      'id': 'p-1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': null,
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-26 08:00:00',
      'updated_at': '2026-09-26 08:00:00',
    };

/// One quote, exactly as `Quote.fromJson` reads it.
///
/// `estimated_days` is what this whole file is about, so it is the one field
/// that varies; `null` is the ordinary case, since the contractor may leave the
/// field empty.
Map<String, dynamic> _quote(int? days) => <String, dynamic>{
      'id': 5,
      'project_id': 'p-1',
      'worker_id': 16,
      'amount': 75000,
      'message': 'أقدر نتكفل بها في الوقت المحدد',
      'estimated_days': days,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 4.5,
      'worker_total_reviews': 3,
      'worker_verification_status': 'verified',
    };

/// Signs in as the customer who owns the project, and serves one quote.
Future<({ApiClient api, AuthState auth})> _boot(int? days) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login')) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'token': 'tok',
            'user': <String, Object?>{
              'id': 30,
              'phone': '0773000000',
              'email': null,
              'full_name': 'زبون تجربة',
              'type': 'customer',
              'avatar_url': null,
              'wilaya': '16',
              'commune': null,
              'created_at': '2026-09-26 08:00:00',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // `/quotes` also contains `/projects/`, so this arm has to sit above
      // the project arm or the quotes request would be answered with a
      // Project and the card would never build.
      if (p.contains('/quotes')) {
        return http.Response(jsonEncode(<Object>[_quote(days)]), 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.contains('/projects/')) {
        return http.Response(jsonEncode(_project()), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');
  return (api: api, auth: auth);
}

/// Renders the real screen and returns every string it printed.
Future<List<String>> card(WidgetTester tester, int? days) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final boot = await _boot(days);

  // The key is load-bearing, not decoration. `ProjectDetailScreen` is a
  // StatefulWidget whose `initState` fetches the project and its quotes, and
  // pumping the same widget type into the same tree slot **reuses that State**
  // — so the second call in a loop kept the first call's quote and asserted
  // against stale data, which is a test that passes for the wrong reason and
  // cost one run of this file to find. A key that changes with the count
  // forces a fresh element, and a fresh fetch.
  await tester.pumpWidget(AppScope(
    api: boot.api,
    auth: boot.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ProjectDetailScreen(
        key: ValueKey<int?>(days),
        projectId: 'p-1',
        repo: Repository(boot.api),
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
  return texts;
}

void main() {
  group('the count takes the form the number calls for', () {
    // The four arms the old one-word interpolation could not express.
    test('1 / 2 / 3-10 / 11+ each take their own noun', () {
      expect(durationDaysAr(1), 'يوم');
      expect(durationDaysAr(2), 'يومين');
      expect(durationDaysAr(3), '3 أيام');
      expect(durationDaysAr(10), '10 أيام');
      expect(durationDaysAr(11), '11 يوم');
      expect(durationDaysAr(30), '30 يوم');
    });

    test('the singular is never counted with a 1', () {
      // The old line at n == 1 was «1 يوم». «يوم» alone is one; the number is
      // what makes «11 يوم» singular, and it is never written before a lone
      // «يوم».
      expect(durationDaysAr(1), isNot(contains('1 ')));
    });

    test('the dual is never counted with a 2 — it already says two', () {
      // The old line at n == 2 was «2 يوم».
      expect(durationDaysAr(2), isNot(contains('2 ')));
      expect(durationDaysAr(2), 'يومين');
    });

    test('3-10 is the range the old line got wrong at every value', () {
      // The old line printed '$n يوم' for all of these. «أيام» is the broken
      // plural and the only correct noun for 3-10, so every value in this
      // range changed. This is the commonest real answer on the screen, which
      // is why it is asserted as a range rather than at one value: a single
      // spot check at 3 would have passed on the old code for a 1, 2 or 11.
      for (var n = 3; n <= 10; n++) {
        expect(durationDaysAr(n), '$n أيام', reason: '$n');
      }
    });

    test('11+ keeps the counted singular, the one range the old line had', () {
      // Asserted in both directions, because a one-sided check would let this
      // regress into the broken plural and the sentence would still read like
      // Arabic to anyone not checking.
      for (final n in [11, 30, 101]) {
        expect(durationDaysAr(n), '$n يوم', reason: '$n');
        expect(durationDaysAr(n), isNot(contains('أيام')), reason: '$n');
      }
    });

    test('the dual is the word the rest of the app already ships', () {
      // «يومان» is the nominative dual and «يومين» the other one. The
      // notification clock («قبل يومين») and the subscription card
      // («بعد يومين») both take the latter, and this line follows a colon
      // like both of them do. A third variant invented here would be a third
      // thing to keep in agreement.
      expect(durationDaysAr(2), 'يومين');
      expect(durationDaysAr(2), isNot('يومان'));
    });

    test('a count the client could never see is silence, not a wrong noun', () {
      // `arabicCount` asserts on n <= 0. A zero or negative `estimated_days`
      // from a hand-edited or stale row would otherwise trip that assert
      // inside a widget build, in production, on a screen nobody tested.
      expect(durationDaysAr(0), '');
      expect(durationDaysAr(-3), '');
      expect(quoteDurationLineAr(0), '');
      expect(quoteDurationLineAr(null), '');
    });
  });

  group('the line the screen builds', () {
    test('keeps the label the client is used to, and delegates the count', () {
      expect(quoteDurationLineAr(3), 'مدة الإنجاز: 3 أيام');
      expect(quoteDurationLineAr(1), 'مدة الإنجاز: يوم');
      expect(quoteDurationLineAr(2), 'مدة الإنجاز: يومين');
      expect(quoteDurationLineAr(11), 'مدة الإنجاز: 11 يوم');
      // No Arabic-Indic digits: this is a number field, and the count is
      // rendered the way the rest of the app writes Latin digits in copy.
      expect(quoteDurationLineAr(7), contains('7 أيام'));
    });
  });

  group('what the quote card actually renders', () {
    testWidgets('a 2-day quote reads «يومين», never «2 يوم»', (tester) async {
      final texts = await card(tester, 2);
      // Guard the guard: a screen still loading, or an error state, prints
      // none of this, and a test that passes because every assertion below is
      // false is worse than no test at all.
      expect(texts, isNotEmpty, reason: 'the screen rendered no text');
      expect(texts, contains('مدة الإنجاز: يومين'), reason: '$texts');
      expect(texts.any((t) => t.contains('2 يوم')), isFalse, reason: '$texts');
    });

    testWidgets('a 1-day quote reads «يوم», never «1 يوم»', (tester) async {
      final texts = await card(tester, 1);
      expect(texts, contains('مدة الإنجاز: يوم'), reason: '$texts');
      expect(
        texts.any((t) => t.contains('1 يوم')),
        isFalse,
        reason: '$texts',
      );
    });

    testWidgets('a 7-day quote reads «7 أيام»', (tester) async {
      final texts = await card(tester, 7);
      expect(texts, contains('مدة الإنجاز: 7 أيام'), reason: '$texts');
    });

    testWidgets('an 11-day quote reads «11 يوم», never «11 أيام»',
        (tester) async {
      final texts = await card(tester, 11);
      expect(texts, contains('مدة الإنجاز: 11 يوم'), reason: '$texts');
      // Word-wise, not a bare substring: '11 يوم' contains the letters of
      // 'أيام'? No — but 'يوم' is a substring of both, so the plural has to be
      // matched as a whole word with its boundary.
      expect(
        texts.any((t) => t.trim() == '11 أيام' || t.contains('11 أيام ')),
        isFalse,
        reason: '$texts',
      );
    });

    testWidgets('the whole 1 / 2 / 3-10 / 11+ range is right on the card',
        (tester) async {
      for (final n in [1, 2, 3, 5, 10, 11, 30]) {
        final texts = await card(tester, n);
        expect(texts, contains(quoteDurationLineAr(n)), reason: '$n days: $texts');
      }
    });

    testWidgets('a contractor who left the field empty prints no line',
        (tester) async {
      final texts = await card(tester, null);
      // The row is hidden for a null, and the card still shows the amount —
      // which is what proves the card itself was on the page and this is an
      // absence rather than a screen that never rendered.
      expect(texts, isNotEmpty, reason: 'the screen rendered no text');
      expect(texts.any((t) => t.contains('المبلغ')), isTrue,
          reason: 'the quote card never rendered: $texts');
      expect(texts.any((t) => t.contains('مدة الإنجاز')), isFalse,
          reason: '$texts');
    });
  });
}
