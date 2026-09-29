// The pixels behind `empty_copy_collapses_test.dart`.
//
// The measurement there is in logical pixels inside a bare `Column`, which is
// the right place to find out *whether* an empty `Text` costs height. It is
// not enough to ship, because the claim a user would make is about the wilaya
// sheet: "the row of communes closes up instead of starting with a band of
// nothing". So this drives the **real** `_CommuneSheet` on the real
// `ProjectNewScreen`, in the two states its count can be in, and photographs
// both.
//
// The two states are the two halves of the defect, and only one of them is
// avoidable:
//
//   * a search that matches nothing — `matches == 0`, so `communeCountAr`
//     answers `''` **by contract**, and the empty state is rendered above it.
//     This is the guaranteed case, and it is the one this fix is about.
//   * a search that matches something — the same line, with its count, so the
//     capture proves the guard did not take the line away when there *is* one.
//
// A one-sided capture passes just as happily on a count line that never draws
// at all, which is why both are shot and the second asserts the count is
// still on screen.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/communes.dart';
import 'package:allomokawil/src/screens/project/project_new_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

const _user = {
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
      if (req.url.path.endsWith('/api/login') ||
          req.url.path.endsWith('/api/register')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _user});
      }
      return _json(<Object?>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Opens the real wilaya sheet, types [query], and returns the PNG path.
Future<String> _shoot(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  required String name,
  required String query,
}) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  // The boundary wraps the WHOLE MaterialApp: a modal sheet is pushed into the
  // Navigator's overlay, a *sibling* of the home route, so a boundary on
  // `home` would photograph the dimmed form and none of the thing under test.
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: RepaintBoundary(key: key, child: MaterialApp(
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
    )),
  ));
  await _settle(tester);

  // The commune sheet is **two levels down**: a commune only means something
  // inside a wilaya, so the form has to have one first. The first run of this
  // file tapped the wilaya row, photographed the *wilaya* sheet, and both
  // captures were of a screen that has no count line at all — which is why
  // the assertions failed on a picture that looked plausible.
  final wilayaRow = find.text('اختر الولاية');
  if (wilayaRow.evaluate().isEmpty) {
    await tester.scrollUntilVisible(wilayaRow, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(wilayaRow);
  await tester.tap(wilayaRow, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // Pick the first wilaya in the sheet — a real one, so the commune sheet has
  // a dataset to answer from.
  final firstWilaya = find.byType(ListTile).first;
  await tester.tap(firstWilaya, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // Now open the commune sheet itself.
  final communeRow = find.text('اختر البلدية (اختياري)');
  await tester.scrollUntilVisible(communeRow, 260,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(communeRow);
  await tester.tap(communeRow, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  if (query.isNotEmpty) {
    // Scoped by the field's own hint: the sheet subtree holds more than one
    // `TextField` in some states, and `.first` was picking a different one, so
    // the query was being written into a controller the commune search never
    // reads. `controller: null` on the widget that was tapped is the tell.
    final field = find.ancestor(
      of: find.text('ابحث عن بلدية...'),
      matching: find.byType(TextField),
    );
    // Clear before typing. `enterText` replaces the controller, which fires
    // `onChanged` with the new value — but the first run of this file still
    // photographed `zzzqqq` in the *second* state, because a stale
    // `controller` from the previous tree was not the thing being written to.
    // `enterText` twice in a row does not land: the second call replaces the
    // controller before the frame that delivers the first `onChanged`, so the
    // state kept the cleared value and the sheet searched for nothing. One
    // call, one value.
    await tester.enterText(field, query);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }
  // The dataset is read from an asset on first use, and the sheet starts in
  // its loading state; a shot taken before that future lands photographs a
  // skeleton, which is exactly what the first run of this file did — both
  // captures came back as the form, and the "no match" state was never
  // rendered at all.
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)));
  await _settle(tester);
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  late final Uint8List png;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    png = bytes!.buffer.asUint8List();
    File(path).writeAsBytesSync(png);
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}




/// Dark-pixel count in a horizontal band, measured with the in-repo decoder.
///
/// **The widget tree cannot answer this.** `SizedBox.shrink()` and `Text('')`
/// are both real widgets, and `Text('')` is a real line box, so every widget
/// assertion in this file is satisfied with and without the guard — measured
/// on this tick, by sabotaging the guard and watching the file stay green. The
/// pixels are the only instrument that sees the difference.
///
/// The probe is a **separate tool**, not an escaped string in the Dart, for
/// the reason `tool/px_count.py` records: two earlier versions of that
/// measurement broke silently and a broken probe reporting `0` is
/// indistinguishable from a blank screen. `tool/band_ink.py` raises instead,
/// and the assertion below checks the tool answered at all.
int _bandInk(String png, double y0, double y1, double xFrom) {
  final r = Process.runSync(
      'python3',
      <String>['tool/band_ink.py', png, '$y0', '$y1', '$xFrom'],
      workingDirectory: Directory.current.path);
  final out = (r.stdout as String).trim();
  if (r.exitCode != 0 || out.isEmpty || int.tryParse(out) == null) {
    throw StateError('band_ink failed (exit ${r.exitCode}): '
        '${r.stdout}${r.stderr}');
  }
  return int.parse(out);
}

void main() {
  // The sheet reads the commune dataset from an asset on first use. Two things
  // have to be true before the shot means anything, and the first run of this
  // file had neither: `rootBundle` needs an initialised binding, and the load
  // is a *future* the sheet awaits. Both captures came back showing the form,
  // so the "no match" state was never rendered and the test passed on a
  // picture of the wrong screen.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CommuneIndex.instance.load();
    // Wilaya 1 is أدرار — the first in the taxonomy, and the one the sheet
    // below actually opens. Asserting on a different id proved nothing.
    expect(CommuneIndex.instance.countFor('1'), 16,
        reason: 'the dataset did not load, so the sheet would shoot a skeleton');
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  testWidgets('a search that matches nothing closes the count line up',
      (tester) async {
    final b = await _boot();
    // A Latin query the dataset cannot match, so `matches == 0` and the line
    // under the search field has nothing to say.
    final path = await _shoot(tester, b.api, b.auth,
        name: 'empty_count_01_no_match', query: 'zzzqqq');

    // The empty state is the real one, not a blank sheet: this is the state
    // where the count line used to leave a band above it.
    expect(find.text('لا توجد بلدية بهذا الاسم'), findsOneWidget,
        reason: 'the shot was taken in a state that is not the one under test');
    // **No count line at all**, anywhere in the sheet. This is the assertion
    // the change turns on — a line box with nothing in it is invisible from
    // the widget tree, so what is asserted is the absence of the `Text`, and
    // the PNG is what shows the band it used to occupy.
    final counts = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^(\d+ بلديات?|بلدية واحدة|بلديتان)$')
                .hasMatch((w.data ?? '').trim()));
    expect(counts, findsNothing,
        reason: 'a zero count must draw no line, not a line reading zero');

    // **The pixels, which is the only assertion that can see this at all.**
    //
    // The band is a fraction of the image, and it is the one the matching
    // state puts its count in — measured on that capture. Both states share
    // the sheet's geometry, so the same band is empty here.
    final bandInk = _bandInk(path, 0.325, 0.350, 0.76);
    expect(bandInk, 0,
        reason: 'the count band holds $bandInk dark pixels where the count is '
            'zero — the empty line is still reserving its box');
    // ignore: avoid_print
    print('SHOT $path');
  });

  testWidgets('a search that matches still prints its count', (tester) async {
    // The sheet picks the FIRST wilaya in the taxonomy, which is أدرار — not
    // Algiers. Its communes are therefore أقبلي / أولف / السبع …, so a query
    // written for Algiers matches nothing and this second state was
    // photographing the first one again. The count is 16 because أدرار has 16.
    //
    final b = await _boot();
    // A **matching** query this time, so `matches > 0` and the count line has
    // a number in it. The first version of this passed `query: ''` to mean "no
    // filter", but an empty query never reaches `enterText`, so the field kept
    // whatever the previous tree held and this second state was really the
    // first one again — two photographs of the same screen, and the control
    // that proves the guard did not eat the line was never exercised.
    final path = await _shoot(tester, b.api, b.auth,
        name: 'empty_count_02_with_match', query: 'أولف');

    // The control that matters: the guard must not remove the line when there
    // IS a count. A one-sided capture passes just as happily on a count line
    // that never draws at all, so the second state asserts it is there.
    final counts = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^(\d+ بلديات?|بلدية واحدة|بلديتان)$')
                .hasMatch((w.data ?? '').trim()));
    expect(counts, findsWidgets,
        reason: 'the count line is gone in the state that HAS a count — the '
            'guard took the line instead of only the hole');

    // The same band, in the state that has a count, holds ink. Without this
    // the assertion in the first test is satisfied by a screen that draws
    // nothing at all, which is the failure mode a one-sided capture has.
    final bandInk = _bandInk(path, 0.325, 0.350, 0.76);
    expect(bandInk, greaterThan(100),
        reason: 'the count band is empty in the state that HAS a count, so '
            'the band measured in the first test is measuring nothing');
    // ignore: avoid_print
    print('SHOT $path');
  });
}
