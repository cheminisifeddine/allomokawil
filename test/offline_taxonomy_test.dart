import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/communes.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

/// The taxonomy half of the backlog item "Offline behaviour": on a dead
/// connection the app must still open with the lists a user needs in order to
/// act — the 58 wilayas and the 16 trades — instead of a blank spinner or an
/// error where the picker should be.
///
/// Those lists are *bundled*, not cached: `Taxonomy.wilayas` and
/// `Taxonomy.categories` are compile-time `const`, and the commune dataset is
/// an asset loaded through `rootBundle`. That is a stronger guarantee than a
/// cache, but it is also invisible — a later refactor could move the lists
/// behind `/api/mobile/...` and nothing would fail until a contractor with no
/// signal opened the publish form. So the guarantee is pinned here instead.
///
/// "Dead connection" is the strict sense: every request throws
/// [SocketException] ("network is unreachable"), which is what `dart:io` raises
/// with no route to the network at all. The client converts that to
/// [S.errOffline], and the assertion on `_attempts` proves the fetch really was
/// tried and really did fail — otherwise the screen could be rendering its
/// static lists for the trivial reason that it never called the API.
///
/// The chat half of the same item (a refused message is written to the device
/// before the first attempt and retried) shipped in `4a3f1cd` and is covered by
/// `test/chat_outbox_test.dart`.
int _attempts = 0;

/// A client whose every request fails the way an offline phone fails.
ApiClient _deadApi() => ApiClient(
      baseUrls: const ['https://offline.test'],
      httpClient: MockClient((_) async {
        _attempts++;
        throw const SocketException('network is unreachable');
      }),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth,
) async {
  // A real phone viewport, like the rest of the suite, so the layout this test
  // walks through is the one users get.
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  // The real app's shell: Arabic locale with the RTL it implies, and the app
  // theme, so the layout this test walks is the one shipped (a bare
  // `MaterialApp` is LTR and would hide a mirrored-layout bug).
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AppScope(api: api, auth: auth, child: screen),
  ));
  // Let the screen's futures fail and the error states settle.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// How many rows a `ListView` was given — its own count, not how many happened
/// to fit on a 392 px screen. Both sheet styles are in play, so both delegates
/// are read.
int _rowCount(WidgetTester tester) {
  final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
  expect(lists, isNotEmpty, reason: 'no list rendered');
  final delegate = lists.last.childrenDelegate;
  if (delegate is SliverChildListDelegate) return delegate.children.length;
  if (delegate is SliverChildBuilderDelegate) return delegate.childCount ?? -1;
  fail('unexpected delegate ${delegate.runtimeType}');
}

void main() {
  setUp(() {
    _attempts = 0;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('offline: the market still offers all 58 wilayas as a filter',
      (tester) async {
    final api = _deadApi();
    await _pump(tester, const BrowseScreen(), api, AuthState(api));

    // The fetch happened and failed — this is a dead connection, not a screen
    // that never asked.
    expect(_attempts, greaterThan(0));
    expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);
    expect(find.text(S.errOffline), findsNothing,
        reason: 'the screen has its own, more specific copy for a failed list');

    // The filter bar is the static half and must survive the failure.
    await tester.tap(find.text('كل الولايات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(Taxonomy.wilayas.length, 58);
    expect(_rowCount(tester), Taxonomy.wilayas.length);
    expect(find.text(Taxonomy.wilayas.first.name), findsOneWidget);
  });

  testWidgets('offline: the trade filters are still on the market',
      (tester) async {
    final api = _deadApi();
    await _pump(tester, const BrowseScreen(), api, AuthState(api));

    // The chip row is a horizontal list, so only the chips that fit are
    // inflated. The claim is that the row still reaches the eighth trade with
    // no connection — the names come from the bundled taxonomy, not from the
    // response that just failed.
    expect(find.text('كل الولايات'), findsOneWidget);
    // Two scrollables exist here: the search field, then the trade row. The row
    // is addressed by position because once it scrolls, the pill finder inside
    // it goes empty and an ancestor lookup throws.
    expect(find.byType(Scrollable), findsNWidgets(2));
    final row = find.byType(Scrollable).last;
    final last = Taxonomy.categories.take(8).last;
    await tester.scrollUntilVisible(find.text(last.name), 200, scrollable: row);
    expect(find.text(last.name), findsOneWidget, reason: 'chip ${last.slug}');
  });

  testWidgets('offline: the publish form still lists all 16 trades',
      (tester) async {
    final api = _deadApi();
    await _pump(tester, const ProjectNewScreen(), api, AuthState(api));

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
    expect(Taxonomy.categories.length, 16);
    expect(delegate.childCount, Taxonomy.categories.length);
    // And the names are rendered, not just counted.
    expect(find.text(Taxonomy.categories.first.name), findsOneWidget);
  });

  testWidgets('offline: the form wilaya picker opens, searches and selects',
      (tester) async {
    final api = _deadApi();
    await _pump(tester, const ProjectNewScreen(), api, AuthState(api));

    // The form is a non-lazy `SingleChildScrollView`, so the field is already
    // in the tree and only needs scrolling into view.
    final field = find.text('اختر الولاية');
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_rowCount(tester), Taxonomy.wilayas.length);

    // Searching the 58 by Arabic name has to work with no connection: the
    // sheet filters the const list with the same folder the rest of the app
    // uses, so وهران is reachable by typing it or by its code.
    await tester.enterText(find.byType(TextField).last, 'وهرا');
    await tester.pump();
    expect(_rowCount(tester), 1);

    await tester.tap(find.text('وهران'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The choice landed in the form: the field now reads the name back.
    expect(find.text('وهران'), findsOneWidget);
    expect(find.text('اختر الولاية'), findsNothing);
  });
  testWidgets('offline: the form commune picker reads the bundled asset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _deadApi();
    await _pump(tester, const ProjectNewScreen(), api, AuthState(api));

    // Pick a wilaya first: the commune sheet only opens once one is chosen.
    final wilayaField = find.text('اختر الولاية');
    await tester.ensureVisible(wilayaField);
    await tester.pump();
    await tester.tap(wilayaField);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'وهرا');
    await tester.pumpAndSettle();
    await tester.tap(find.text('وهران'));
    await tester.pumpAndSettle();

    // 1,541 communes ship as a 54 KB asset, so the second picker must fill
    // from the bundle on a dead connection — no request, no spinner forever.
    // The asset is read through the real file system, which the fake clock
    // cannot complete, so it is pre-warmed inside `runAsync`.
    await tester.runAsync(() => CommuneIndex.instance.load());
    await tester.pump();
    expect(CommuneIndex.instance.total, greaterThanOrEqualTo(1500),
        reason: 'the 1,541-commune asset did not load offline');

    final communeField = find.text('اختر البلدية (اختياري)');
    await tester.ensureVisible(communeField);
    await tester.pump();
    await tester.tap(communeField);
    await tester.pump();
    // The sheet awaits `forWilaya`, whose future was completed in the real
    // zone by the `runAsync` above; its continuation needs a real event-loop
    // turn, which the fake clock cannot give it.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final counts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => RegExp(r'^\d+ بلدية$').hasMatch(s));
    expect(counts, isNotEmpty,
        reason: 'the bundled commune asset did not load offline');
    final loaded =
        int.parse(counts.first.substring(0, counts.first.indexOf(' ')));
    expect(loaded, greaterThan(20),
        reason: 'a wilaya the size of وهران must list its communes');
  });

}
