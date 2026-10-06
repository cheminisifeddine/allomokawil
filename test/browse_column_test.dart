// The browse screen's column, and the strip that filters it.
//
// `browse_screen.dart` held 7 off-grid literals and `trade_filter_bar.dart`
// three more, and **R4 could not see the defect in either file**. R4 counts
// literals; it cannot compare two numbers in two files. Both sites went green
// the moment each literal became an identifier, because `_literals()` skips
// identifiers by design — so a ratchet that police�� the spelling of a number
// is blind to the case where two spellings disagree, which is the only case a
// user can see.
//
// Measured on the committed golden `test/goldens/10_browse.png` (392x850,
// DPR 1.0, so 1 px = 1 dp) with `tool/png_read.py`:
//
//     cards / search field   x18 .. x373
//     the trade strip       x0  .. x377   <- 4 dp outside on the start edge
//
// `TradeFilterBar` is the control that filters the list sitting directly under
// it, and it did not share that list's start edge — nor the search box above
// it. So the one screen a client uses to *find* a contractor had its cards,
// its search box and its filter strip on three left edges, and only two of
// them were the same number. The strip also bled off the canvas: ink starts at
// x=0 while the cards start at x=18.
//
// The three measurement traps, all inherited from `account_column_test.dart`,
// and every one of them fires on this screen:
//
//   * a `ListView` hands its `padding` to an internal `SliverPadding`, so
//     `ListView.padding` is null and the naive read answers 0.0 — which passes
//     for ANY inset, including the broken one. The loaded list is a list.
//   * a `Padding` lays out at its parent's full width, so its own rect is the
//     **outer** edge; the inset is `rect + padding`, never `rect`.
//   * every inset here is measured from the start edge, which in this RTL app
//     is the **right** edge. Measuring `left` puts the arithmetic 60 dp out on
//     a 392 dp canvas and fails for a reason that has nothing to do with the
//     seam under test.
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

/// One live-shaped contractor, so the list takes its **loaded** branch and the
/// card gutter is the one under test. A screen sitting on its empty state has
/// no cards to measure, and this file would pass for the wrong reason.
Map<String, Object?> _worker(int id, String name) => {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': 'دهان وتشطيب',
      'specialties': ['painting'],
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
      'phone': '055000000${id % 10}',
      'cover_image_url': null,
      'avatar_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
    };

Future<({ApiClient api, AuthState auth})> _boot(
    List<Map<String, Object?>> rows) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user()});
      }
      if (p.endsWith('/api/mobile/workers/search')) return _json(rows);
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

/// The x of a box's **start** edge, which in this app's RTL is its RIGHT edge.
double _startEdge(WidgetTester tester, Finder f) {
  final b = tester.renderObject<RenderBox>(f);
  return b.localToGlobal(Offset.zero).dx + b.size.width;
}

/// The list's own inset off its start edge — `SliverPadding`, not
/// `ListView.padding` (which is null and answers 0.0, passing for ANY inset,
/// including the broken one).
///
/// This returns the **inset**, not the x it produces. A first draft returned
/// the absolute x (374 on a 392 dp canvas) and then compared it against the
/// strip's inset (18) — two different kinds of quantity, so the assertion
/// failed at 374 vs 18 on a build that was already correct. Every comparison
/// in this file is inset-against-inset for that reason.
double _rowsInset(WidgetTester tester, Finder list) {
  final pads = tester
      .widgetList<SliverPadding>(find.descendant(
          of: list, matching: find.byType(SliverPadding)))
      .map((e) => e.padding.resolve(TextDirection.rtl))
      .where((p) => p.left > 0);
  if (pads.isEmpty) {
    throw StateError('no SliverPadding under the list: this screen is not '
        'painting its inset and the assertions below would pass vacuously');
  }
  return pads.first.left;
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
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('the strip filters the list it sits on, on one edge', () {
    testWidgets('the trade strip and the card list share a start edge',
        (tester) async {
      final b = await _boot([_worker(5, 'رشيد خليفي'), _worker(6, 'كريم حداد')]);
      await _pump(tester, b.api, b.auth);

      final list = find.byType(ListView).first;
      final strip = find.byKey(const Key('trade-filter-scroll'));
      expect(strip, findsOneWidget, reason: 'the filter strip is not on screen');
      expect(find.byType(ListView), findsWidgets);

      // NOT the strip's rect: it is a horizontal scroll viewport and so spans
      // the full 392 dp by construction — measuring it answers 392.0 for the
      // broken build and for the fixed one alike. The gutter is the viewport's
      // **padding**, which is what puts the first pill in from the edge.
      final stripGutter = tester
          .widget<SingleChildScrollView>(strip)
          .padding!
          .resolve(TextDirection.rtl)
          .left;
      final rowsInset = _rowsInset(tester, list);
      expect(stripGutter, moreOrLessEquals(rowsInset, epsilon: 0.01),
          reason: 'the strip that filters this list insets its first pill '
              '${stripGutter.toStringAsFixed(1)} from the start edge while the '
              'rows it filters sit ${rowsInset.toStringAsFixed(1)} in — a '
              'control the user taps to narrow the list must sit on the '
              'list\'s own start edge');
    });

    testWidgets('the search field and the card list share a start edge too',
        (tester) async {
      final b = await _boot([_worker(5, 'رشيد خليفي'), _worker(6, 'كريم حداد')]);
      await _pump(tester, b.api, b.auth);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      // A `Padding` lays out at its parent's full width, so the field's own
      // rect is the OUTER edge; the inset is `rect - fieldStart` read back off
      // the viewport, never the rect itself.
      final fieldStart = _startEdge(tester, field);
      final viewport = _startEdge(tester, find.byType(Scaffold).first);
      final fieldInset = viewport - fieldStart;
      final rowsInset = _rowsInset(tester, find.byType(ListView).first);
      expect(fieldInset, moreOrLessEquals(rowsInset, epsilon: 0.01),
          reason: 'the box the query is typed into sits '
              '${fieldInset.toStringAsFixed(1)} from the start edge while the '
              'results it returns sit ${rowsInset.toStringAsFixed(1)} in');
    });

    testWidgets('the strip\'s gutter is the house gutter, not a 14 of its own',
        (tester) async {
      final b = await _boot([_worker(5, 'رشيد خليفي'), _worker(6, 'كريم حداد')]);
      await _pump(tester, b.api, b.auth);

      final pad = tester
          .widget<SingleChildScrollView>(
              find.byKey(const Key('trade-filter-scroll')))
          .padding!
          .resolve(TextDirection.rtl);
      expect(pad.left, AppTheme.gutter,
          reason: 'the strip used to spell 14 where the app spells 18, which '
              'is why it was 4 dp outside the list it filters and outside the '
              'search box above it, and why its first pill bled off the canvas');
      expect(pad.right, pad.left,
          reason: 'a strip whose two ends disagree reads as a misalignment');
      expect(pad.top, AppTheme.s4, reason: 'the cross-axis pad is unchanged');
      expect(pad.bottom, AppTheme.s4);
    });

    testWidgets('the loaded list and the empty state share one gutter',
        (tester) async {
      // The two empty branches were on `s16` while the rows that replace them
      // sit on `pagePad`, so the whole column shifted 2 dp the moment the
      // directory had data in it — the client saw the empty state, then the
      // list jump sideways under the same search box.
      final b = await _boot([_worker(5, 'رشيد خليفي'), _worker(6, 'كريم حداد')]);
      await _pump(tester, b.api, b.auth);
      final rowsInset = _rowsInset(tester, find.byType(ListView).first);
      expect(rowsInset, AppTheme.pagePad.resolve(TextDirection.rtl).left,
          reason: 'the loaded list is on pagePad');
      expect(rowsInset, AppTheme.gutter,
          reason: 'the empty states now carry the same token as the rows that '
              'replace them, so the gutter cannot change by 2 dp the moment '
              'the directory has data in it');
    });
  });
}
