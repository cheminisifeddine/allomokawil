// Tapping a wilaya with nobody in it used to blame the reader's search.
//
// Found 5 Oct 2026 by asking the live API 58 times. `GET
// /api/mobile/workers/search?wilaya=<id>` returns **0 rows for 51 of the 58**
// wilayas the sheet offers, and the cause is in the same payload: 88 of the 97
// live rows carry no `user_wilaya`, no `wilaya_name` and no `commune` at all.
//
// The seven that answer are 16 الجزائر 3 · 09 البليدة 1 · 15 تيزي وزو 1 ·
// 19 سطيف 1 · 25 قسنطينة 1 · 31 وهران 1 · 35 بومرداس 1 — that is the nine
// located contractors, minus two.
//
// So the sheet asks the customer a question the platform cannot answer, and the
// answer it gave him was:
//
//   لا نتائج مطابقة
//   جرّب تغيير التخصص أو الولاية
//   [ مسح البحث والفلاتر ]
//
// Every word true, together actively harmful: it says *your search matched
// nothing* — blaming him and a trade chip he may never have set — for a wilaya
// that simply has no contractors, and the button offered undoes the filter he
// did not know was the problem. See `data/empty_wilaya_copy.dart`.
//
// These tests pin the unit rule and both screen outcomes, and they pin the
// boundary: a category or a word set still gets the old sentence.
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
import 'package:allomokawil/src/data/empty_wilaya_copy.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

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

/// A located contractor, so the control case has something real to draw.
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

Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required Future<http.Response> Function(String wilaya) search,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/mobile/workers/search')) {
        return search(req.url.queryParameters['wilaya'] ?? '');
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

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Taps the trade chip named [name] in the horizontal filter strip.
///
/// The strip is a single `Row` in a horizontal `SingleChildScrollView` and the
/// page is RTL, so a chip past the first few sits far off-screen at a negative
/// x — `tap()` on it resolves to `Offset(-900, 164)`, misses every hit test
/// and silently changes nothing. That is the same 58-of-16 stretch problem the
/// sheet has, on the other axis.
Future<void> _tapTrade(WidgetTester tester, String name) async {
  final target = find.text(name);
  expect(target, findsOneWidget,
      reason: 'the trade strip must build «$name» at all');
  // The strip is a single `Row` — non-lazy, so every chip is in the tree even
  // when it is 900 px off-screen — which is why the sheet above needed
  // `scrollUntilVisible` and this needs `ensureVisible` instead. Dragging was
  // tried first and did nothing: the RTL scroll position starts at the far end.
  await Scrollable.ensureVisible(tester.element(target));
  await _settle(tester, frames: 4);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth) async {
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

/// Opens the wilaya sheet and picks [name], the way a customer does it — the
/// seam is the sheet, not a test-only constructor argument.
///
/// The sheet is a **lazy** `ListView` over 58 rows, so a wilaya past the fold
/// is not in the tree at all and `find.text(name)` throws `Bad state: No
/// element`. That laziness is the customer's own problem too — «تيزي وزو» is
/// 15th of 58 and a phone 850 dp tall shows about ten — so the test scrolls
/// for him rather than pretending the row was there.
Future<void> _pickWilaya(WidgetTester tester, String name) async {
  await tester.tap(find.text('كل الولايات'));
  await _settle(tester);
  final target = find.text(name);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 120,
        scrollable: find.byType(Scrollable).last);
    await _settle(tester, frames: 6);
  }
  expect(target, findsOneWidget,
      reason: 'the sheet must be able to reach «$name» at all');
  await tester.tap(target);
  await _settle(tester);
}

void main() {
  group('the rule', () {
    test('names the wilaya when it is the only filter', () {
      final s = emptyWilayaAr(
          wilayaName: 'تيزي وزو', categorySet: false, querySet: false);
      expect(s, isNotNull);
      expect(s, contains('تيزي وزو'),
          reason: 'the customer picked this name in the sheet and the state '
              'must name the same place he picked');
      expect(s, contains('ليس هناك مقاول'),
          reason: 'the heading is «لا يوجد مقاول في هذه الولاية»; the body has '
              'to say the same thing about the place rather than about his '
              'search');
    });

    test('stays silent when a category or a word is also set', () {
      // Those are the ordinary «لا نتائج مطابقة» case and the screen already
      // draws it. Claiming the wilaya is empty there would be a claim about a
      // place the category may simply not overlap.
      expect(
          emptyWilayaAr(
              wilayaName: 'تيزي وزو', categorySet: true, querySet: false),
          isNull);
      expect(
          emptyWilayaAr(
              wilayaName: 'تيزي وزو', categorySet: false, querySet: true),
          isNull);
    });

    test('stays silent with no wilaya at all', () {
      expect(emptyWilayaAr(
          wilayaName: null, categorySet: false, querySet: false), isNull);
      expect(emptyWilayaAr(
          wilayaName: '', categorySet: false, querySet: false), isNull);
    });
  });

  testWidgets('an empty wilaya names itself instead of blaming the search',
      (tester) async {
    // 15 (تيزي وزو) is one of the 51 measured to answer with zero rows.
    final b = await _boot(
        search: (w) async => _json(<Object?>[if (w.isEmpty) _worker(1, 'رشيد')]));
    await _pump(tester, b.api, b.auth);
    expect(find.text('رشيد'), findsOneWidget, reason: 'the control: unfiltered '
        'the directory has a contractor');

    await _pickWilaya(tester, 'تيزي وزو');

    expect(find.text(emptyWilayaTitle), findsOneWidget);
    expect(find.textContaining('ليس هناك مقاول مسجّل في تيزي وزو'),
        findsOneWidget);
    expect(find.text('لا نتائج مطابقة'), findsNothing,
        reason: 'nothing was matched because nothing was searched for this '
            'wilaya — the search ran and the place is empty');
    expect(find.textContaining('جرّب تغيير التخصص'), findsNothing,
        reason: 'this names a filter the reader may never have set, and it is '
            'sent on 51 of 58 taps');
    // The action that actually helps stays, and it still undoes the filter.
    expect(find.text('مسح البحث والفلاتر'), findsOneWidget);
    expect(b.log.last, contains('wilaya=15'),
        reason: 'the empty state must be the answer to a real filtered read');
  });

  testWidgets('a category-filtered empty directory keeps the old sentence',
      (tester) async {
    // The boundary. With a trade chip set the emptiness may be the trade, not
    // the place, and this file does not get to claim the wilaya is empty.
    final b = await _boot(search: (w) async => _json(<Object?>[]));
    await _pump(tester, b.api, b.auth);
    await _pickWilaya(tester, 'تيزي وزو');
    await _tapTrade(tester, 'دهان وطلاء ديكوري');

    expect(find.text(emptyWilayaTitle), findsNothing);
    expect(find.text('لا نتائج مطابقة'), findsOneWidget);
  });

  testWidgets('«مسح البحث والفلاتر» on this state really re-reads', (tester) async {
    final b = await _boot(search: (w) async => _json(<Object?>[]));
    await _pump(tester, b.api, b.auth);
    await _pickWilaya(tester, 'تيزي وزو');
    expect(find.text(emptyWilayaTitle), findsOneWidget);

    await tester.tap(find.text('مسح البحث والفلاتر'));
    await _settle(tester);

    expect(find.text(emptyWilayaTitle), findsNothing);
    expect(b.log.last, isNot(contains('wilaya=')),
        reason: 'the button promises to drop the filters, so the read it '
            'issues must not still be filtered by the wilaya');
  });
}
