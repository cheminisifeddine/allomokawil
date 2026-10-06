// The directory's empty state told a customer who pasted a phone number to
// «جرّب كلمة أقصر» — *try a shorter word* — and echoed his number back between
// «» where a name belongs.
//
// Found 5 Oct 2026 on production. The search box has accepted a number since
// `data/worker_phone_search.dart` shipped (the server ignores `q`: `q=خالد` and
// `q=zzzzznotarealname` both return all 97 live rows), so `narrowWorkers` is
// the only thing that filters, and it has two arms — text and phone. The
// sentence below it was written for the text arm and never learned about the
// other one.
//
// The rule tests live in `empty_phone_search_copy_test.dart`. These are the
// screen tests: they prove the copy is actually *rendered*, because a rule that
// is correct and never called ships nothing — and the word case is pinned in the
// same file so the two cannot be collapsed back into one state.

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
import 'package:allomokawil/src/widgets/ui.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

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
      'is_identity_verified': 1,
      'subscription_plan': 'free_trial',
      'avg_rating': 4.6,
      'total_reviews': 12,
      'total_completed_jobs': 40,
      'response_time_hours': 3,
      'commune': 'باب الزوار',
      'wilaya': '16',
      'cover_image_url': null,
      'avatar_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
    };

/// Boots a real `ApiClient` over a `MockClient` that answers the search with
/// whatever [search] is told to, and records every read.
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
      log.add('${req.method} $p${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
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
    log.where((l) => l.contains('/api/mobile/workers/search')).length;

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  String? initialCategory,
}) async {
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
      home: BrowseScreen(initialCategory: initialCategory),
    ),
  ));
  await _settle(tester);
}

/// The screen's search box — the only `TextField` on the page.
TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('a directory with nobody in it offers a refresh, not advice '
      'about filters the reader never set', (tester) async {
    // Before the fix this rendered the title «لا نتائج مطابقة», the body
    // «جرّب تغيير التخصص أو الولاية» and NO button at all, because
    // `actionLabel` and `onAction` were both null when nothing was filtered.
    final b = await _boot(search: (i) async => _json(<Object?>[]));
    await _pump(tester, b.api, b.auth);

    // The heading has to stop claiming a search happened. Nothing was typed
    // and nothing was filtered: there is no query to have failed to match.
    expect(find.text('لا نتائج مطابقة'), findsNothing);
    expect(find.text('لا يوجد مقاول حالياً'), findsOneWidget);
    expect(find.textContaining('لم يسجّل أي مقاول في الدليل'), findsOneWidget);
    expect(find.textContaining('جرّب تغيير التخصص'), findsNothing,
        reason: 'that advice names two filters that are both off, and the '
            'state offered nothing to press');

    // And the state must never be a dead end — a button, not a sentence.
    expect(find.text('تحديث'), findsOneWidget,
        reason: 'the honest action here is a re-fetch, the same one the '
            'sibling market offers in the identical situation');
  });

  testWidgets('تحديث on the unfiltered state really re-issues the search',
      (tester) async {
    // A label that renders but does nothing is the exact bug this covers.
    final b = await _boot(search: (i) async {
      if (i == 0) return _json(<Object?>[]);
      return _json(<Object?>[_worker(1, 'مقاول جديد')]);
    });
    await _pump(tester, b.api, b.auth);
    expect(find.text('لا يوجد مقاول حالياً'), findsOneWidget);
    expect(_searchReads(b.log), 1, reason: 'the first load read once');

    await tester.tap(find.text('تحديث'));
    await _settle(tester);

    expect(_searchReads(b.log), 2,
        reason: 'تحديث must issue a real request, not just redraw');
    expect(find.text('لا يوجد مقاول حالياً'), findsNothing);
    expect(find.text('مقاول جديد'), findsOneWidget,
        reason: 'a contractor who signed up since must now be on screen');
  });

  testWidgets('a filtered state keeps its clear action and its own heading',
      (tester) async {
    // The other half of the split, and the reason the fix could not simply
    // bolt a button onto the old state: with a filter set the old copy and
    // the old heading are both correct, and the action is still «undo».
    //
    // Opened with a category already set — the same entry point
    // `customer_home_screen` uses when a client taps a trade. «كهرباء» is one
    // of the categories the server answers with **zero** contractors, measured
    // on production, so this is the ordinary tap, not a contrived one.
    final b = await _boot(search: (i) async => _json(<Object?>[]));
    await _pump(tester, b.api, b.auth, initialCategory: 'electrical');

    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
    expect(find.text('تحديث'), findsNothing,
        reason: 'with a filter set the action is undo, not re-fetch');
    expect(
      find.descendant(
        of: find.byType(PrimaryButton),
        matching: find.byIcon(Icons.close_rounded),
      ),
      findsOneWidget,
      reason: 'the clear action must not carry the refresh icon, or it '
          'promises to re-fetch what it is throwing away',
    );

    // And pressing it really drops the filter and re-reads.
    final before = _searchReads(b.log);
    await tester.tap(find.text('مسح البحث والفلاتر'));
    await _settle(tester);
    expect(_searchReads(b.log), greaterThan(before));
    expect(find.text('لا نتائج مطابقة'), findsNothing,
        reason: 'the filter is gone, so the filtered heading must go with it');
  });

  testWidgets('a typed word that matches nothing still offers to clear it',
      (tester) async {
    // The case that was already working, pinned so the split cannot be
    // collapsed back into one state. The server ignores `q`, so this
    // narrowing is entirely the screen's own `_matchesQuery`.
    final b = await _boot(search: (i) async => _json(<Object?>[
          _worker(1, 'مقاول دهان'),
        ]));
    await _pump(tester, b.api, b.auth);
    expect(find.text('مقاول دهان'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'سسسس');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(find.textContaining('لا يوجد مقاول يطابق «سسسس»'), findsOneWidget);
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
    expect(_field(tester).controller!.text, 'سسسس');
  });

  testWidgets('a pasted number that matches nobody is not told to shorten a '
      'word', (tester) async {
    // The defect. The directory has a phone arm since 5 Oct; the empty state
    // was still the word sentence, so a man holding a number from the street
    // was told to «جرّب كلمة أقصر» about a number.
    final b = await _boot(search: (i) async => _json(<Object?>[
          _worker(1, 'مقاول دهان'),
        ]));
    await _pump(tester, b.api, b.auth);
    expect(find.text('مقاول دهان'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0770123456');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    // He typed a number: the state must say so.
    expect(find.textContaining('لم يُعثر على رقم مطابق'), findsOneWidget);

    // And must not talk about a word he never used.
    expect(
        find.descendant(
            of: find.byType(EmptyView),
            matching: find.textContaining('كلمة'),
        ),
        findsNothing,
        reason: 'there is no word in "0770123456" to shorten; this sentence is '
            'the defect');

    // Nor quote his own number back at him where a name is expected. Scoped to
    // the empty state: the search box itself still holds what he typed, and
    // that is correct — the field is his, and the message is the app's.
    expect(
        find.descendant(
            of: find.byType(EmptyView),
            matching: find.textContaining('0770123456'),
        ),
        findsNothing,
        reason: 'what the customer pasted is his business; an empty state is '
            'the wrong place to re-print a phone number');

    // The safe action is still offered — unchanged by this fix.
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
  });

  testWidgets('the digits are folded before they are matched, so an '
      'Arabic-Indic paste reaches the same state', (tester) async {
    // ٠٧٧٠١٢٣٤٥٦ is what an Algerian keypad produces. The matcher folds it
    // (that is the arm that exists), so the copy must claim the same thing.
    final b = await _boot(search: (i) async => _json(<Object?>[
          _worker(1, 'مقاول دهان'),
        ]));
    await _pump(tester, b.api, b.auth);

    await tester.enterText(find.byType(TextField), '٠٧٧٠١٢٣٤٥٦');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(find.textContaining('لم يُعثر على رقم مطابق'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(EmptyView), matching: find.textContaining('كلمة')),
      findsNothing,
    );
  });

  testWidgets('a word that matches nothing keeps the sentence it always had',
      (tester) async {
    // The case that was already correct, pinned in the same file so the split
    // cannot be collapsed back. If this ever fails with the number copy on it,
    // the two states have been merged.
    final b = await _boot(search: (i) async => _json(<Object?>[
          _worker(1, 'مقاول دهان'),
        ]));
    await _pump(tester, b.api, b.auth);

    await tester.enterText(find.byType(TextField), 'سسسس');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
    expect(find.textContaining('لا يوجد مقاول يطابق «سسسس»'), findsOneWidget);
    expect(find.textContaining('لم يُعثر على رقم مطابق'), findsNothing,
        reason: 'a word is not a number, and this state must keep saying so');
  });

  testWidgets('a number that DOES match shows a contractor, not an empty '
      'state', (tester) async {
    // The other direction: the number arm must not steal a real hit. A worker
    // whose stored phone is the fragment the customer typed.
    final b = await _boot(search: (i) async => _json(<Object?>[
          {..._worker(1, 'مقول دهان'), 'phone': '0770123456'},
        ]));
    await _pump(tester, b.api, b.auth);

    await tester.enterText(find.byType(TextField), '0770123456');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);

    expect(find.text('مقول دهان'), findsOneWidget);
    expect(find.textContaining('لم يُعثر على رقم مطابق'), findsNothing);
  });
}
