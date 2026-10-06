// The four left edges of «انشر مشروعك», measured.
//
// Why this file exists. The R4 sweep in `card_recipe_test.dart` counts *text*:
// it can tell you the screen stopped typing `18`, and it cannot tell you the
// screen still lines up. The 6 Oct slice proved that the gap is real — 24
// literals in this one file were not one list inset but FOUR edge systems, and
// the two modal picker sheets disagreed with themselves:
//
//  - the wilaya search field sat at 18 over a list at 12 (6 dp apart, and the
//    box framing rows that start 6 dp inside it),
//  - the commune count line sat at 6 while the commune names it counts sat at
//    12 — the line counting the list was 6 dp outside the list.
//
// R4 would have gone green on both, because in both cases the fix was to
// replace a literal with an identifier. So these read RenderBoxes and pin the
// geometry. R4 counts; this measures.
//
// Read as rects, not pixels: two runs of the design shots on identical code
// differ by ~1442 raster rows on this host.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

const _user = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'عميل تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': null,
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

Future<({ApiClient api, AuthState auth})> _boot() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/login')) {
        return http.Response(
          jsonEncode(<String, Object?>{'token': 'tok', 'user': _user}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode(<Object?>[]), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Rect rectOf(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero) &
    tester.renderObject<RenderBox>(f).size;

/// Puts the form on screen at the app's own logical size.
Future<({ApiClient api, AuthState auth})> _pumpForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final s = await _boot();
  await tester.pumpWidget(AppScope(
    api: s.api,
    auth: s.auth,
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
      home: const ProjectNewScreen(),
    ),
  ));
  await _settle(tester);
  return s;
}

/// Opens the real wilaya sheet through the real tap.
Future<void> _openWilayaSheet(WidgetTester tester) async {
  final row = find.text('اختر الولاية');
  if (row.evaluate().isEmpty) {
    await tester.scrollUntilVisible(row, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(row);
  await tester.tap(row, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('the edges of «انشر مشروعك»', () {
    testWidgets('the step headings line up with the fields they head',
        (tester) async {
      await _pumpForm(tester);

      // A heading band and the field under it are two children of one Column,
      // so they share a left edge by construction *only if both are flush*.
      // This screen had the heading at 2 and every field at 0 — the accent bar
      // on «عنوان المشروع» was 2 dp right of the box below it, on all seven
      // headings, forever.
      // The *band*, not the text in it: the heading Row carries a 4 dp accent
      // bar and an 8 dp gap before the words, so the text sits well inside the
      // band it defines. Measuring the text is measuring an icon offset and
      // calling it alignment — which is exactly the mistake the first cut of
      // this file made, and why the number below came back 146.5 and not 18.
      final heading = rectOf(tester, find.ancestor(
        of: find.text('عنوان المشروع'),
        matching: find.byType(Padding),
      ).first);
      final field = rectOf(tester, find.byType(TextField).first);

      expect(heading.left, field.left,
          reason: 'the step heading and the field under it must share one '
              'left edge; the heading band was inset 2 dp past the form');

      // On the page gutter, and *not* on the 4 dp grid — deliberately. The
      // screen margin is `AppTheme.gutter` (18), a named house exception: at 16
      // the form would carry 2 dp more breathing room than every list in the
      // app, and the sweep is about component gaps, not about moving a page
      // margin. The first run of this test asserted `% 4 == 0` here and failed
      // on 18 — asserting the grid against a value the codebase documents as
      // off-grid. The 2 dp that WAS a defect is the one asserted above.
      expect(heading.left, AppTheme.gutter,
          reason: 'the page edge is AppTheme.gutter, named — a bare 18 here '
              'is the literal this slice removed');
    });

    testWidgets('the wilaya sheet\'s search field is flush with its own list',
        (tester) async {
      await _pumpForm(tester);
      await _openWilayaSheet(tester);

      // Guard the guard: no tile means every rect read below is void.
      final tiles = find.byType(ListTile);
      expect(tiles, findsWidgets,
          reason: 'the wilaya sheet rendered no rows — the 58-name taxonomy '
              'did not load, so this test is measuring an empty sheet');

      final search = rectOf(tester, find.ancestor(
        of: find.text('ابحث عن ولاية...'),
        matching: find.byType(TextField),
      ));
      final list = rectOf(tester, tiles.first);

      expect(search.left, list.left,
          reason: 'the search box and the rows below it must share one left '
              'edge — they were 18 against 12, 6 dp apart, with the box '
              'framing rows that started inside it');
      expect(search.left, AppTheme.s12,
          reason: 'and that edge is the grid: 12 on it, 18 was not');
      expect(search.left % 4, 0);
    });

    testWidgets('the commune count line lines up with the names it counts',
        (tester) async {
      await _pumpForm(tester);
      await _openWilayaSheet(tester);

      // The commune sheet is two levels down: a commune only means something
      // inside a wilaya. The first run of the sibling sheet tests took the
      // wilaya row, photographed the *wilaya* sheet, and asserted on a screen
      // that has no count line at all.
      await tester.tap(find.byType(ListTile).first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final communeRow = find.text('اختر البلدية (اختياري)');
      await tester.scrollUntilVisible(communeRow, 260,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(communeRow);
      await tester.tap(communeRow, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await _settle(tester);

      final names = find.byType(ListTile);
      expect(names, findsWidgets,
          reason: 'the commune sheet rendered no rows');

      // The count line is the first child of the list, so its own padding is
      // the difference between it and every row below. It read 6 against the
      // rows' 12 — the line counting the list sat outside the list.
      // Scoped INSIDE the list. A bare `contains('بلدية')` also matches the
      // search hint «ابحث عن بلدية...», which sits 47 dp further right behind
      // its own prefix icon — the first run of this test asserted the count
      // line was at 59 dp and read that as a misalignment.
      final countLine = find.descendant(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate((w) {
          if (w is! Text) return false;
          final d = w.data;
          return d != null && d.contains('بلدية');
        }),
      );
      expect(countLine, findsWidgets,
          reason: 'no count line in the commune sheet — the commune index '
              'answered nothing, so there is nothing to align');

      // The count line is a `Padding` inside the list, and the `Text` inside
      // it starts another 0 dp in but the TextStyle's own left bearing is
      // what the second run measured. The band is the thing that has the edge.
      final count = rectOf(tester, find.ancestor(
        of: countLine.first,
        matching: find.byType(Padding),
      ).first);
      final firstName = rectOf(tester, names.first);

      expect(count.left, firstName.left,
          reason: 'the count line and the commune names it counts must share '
              'one left edge');
      expect(count.left % 4, 0,
          reason: 'measured left edge ${count.left} dp is off the 4 dp grid');
    });
  });
}
