// The header's location pill was never a pill.
//
// `card_recipe_test.dart`'s R4 counts off-grid literals. It has been counting
// this one for weeks — `symmetric(horizontal: 12, vertical: 7)` at
// `customer_home_screen.dart:1187` — and priced it at one line among 23, the
// same price as the `14 x 12` on the trade filter and the `6 x 2` on the auth
// checkbox row, every one of which carries a paragraph explaining why it is
// off the ladder on purpose. This one carries none. It was not a decision; it
// was a pill that was written before the kit had a name for one.
//
// **What the number hid.** The app already has the answer written down:
// `AppTheme.pillPad` = `symmetric(horizontal: 10, vertical: 6)` with
// `AppTheme.pillGap` = 6 and a 14 dp glyph — and `StatusPill` and
// `CategoryBadge` both use them. So the same idea, the wilaya the user is
// registered in, is drawn at **three** different geometries depending on where
// it appears:
//
//   * this header ............ 12 x 7 inset, 15 dp glyph, 5 dp gap
//   * `StatusPill` / badge ... 10 x 6 inset, 14 dp glyph, 6 dp gap
//   * `_FilterPill` .......... 14 x 12 inset, 16 dp glyph, 7 dp gap (a tap
//     target, and deliberately a different thing — see its own doc comment)
//
// The filter pill is a **target** and is *supposed* to be the bigger one. This
// header pill is **not tappable** — nothing wraps it in a `GestureDetector`
// and it has no `onTap` — so it is a label wearing a pill's clothes, and on
// that reading it should be on the token the other labels are on. It is also
// the one a user sees first: it is in the header of the customer home, above
// the fold, before any list has loaded.
//
// **What R4 structurally cannot see**, which is why this file exists rather
// than a decrement. R4 counts literals inside `EdgeInsets.*`; `AppTheme.pillPad`
// is an *identifier*, and `_literals()` skips identifiers by design — so moving
// this site onto the token would have taken the ratchet 23 -> 21 while changing
// nothing about whether the three pills agree. That is the same blind spot
// `pill_inset_test.dart` documents for the word pills, and the same one slice 23
// hit from the other side: the numbers that were *wrong* were spelled as an
// identifier and never appeared in source for R4 to read.
//
// **So the assertion is equality, not a constant.** The expected inset is
// resolved from `AppTheme.pillPad` and compared against the padding actually
// on the widget, and the glyph/gap are read off the built tree the way
// `pill_inset_test.dart` reads them. Nothing here transcribes 10, 6, 14 or 12:
// a test that wrote the expected numbers down would have passed before the fix
// and after it, and would keep passing through any future drift, which is the
// stale-constant trap `tile_label_fit_test.dart` records.
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
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';

const _me = <String, Object?>{
  'id': 30, 'phone': '0773000000', 'email': null, 'full_name': 'زبون تجربة',
  'type': 'customer', 'avatar_url': null, 'wilaya': '16', 'commune': null,
  'created_at': '2026-09-11 20:00:00', 'updated_at': '2026-09-11 20:00:00',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _me});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.contains('/workers/top')) return _json(<Object>[]);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

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
      home: const CustomerHomeScreen(),
    ),
  ));
  // Bounded, not pumpAndSettle: the shimmer skeletons animate forever.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The `Container` that draws the header's location pill.
///
/// Narrowed by a predicate rather than by "the nearest ancestor": the pill
/// sits *inside* the header's own gradient `Container`, and `find.ancestor`
/// walks up through both, so an unfiltered ancestor finder matches the header
/// too and the assertion below would then read the header's decoration — a
/// plausible-looking measurement of the wrong box. `padding != null` is what
/// actually distinguishes the pill: the header has none.
Finder _headerPill() => find.ancestor(
      of: find.byIcon(Icons.location_on_rounded),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.padding != null,
      ),
    );

void main() {
  group("the header's location pill is the app's pill", () {
    testWidgets('it sits on the shared token, not its own numbers',
        (tester) async {
      await _pumpHome(tester);

      expect(find.byIcon(Icons.location_on_rounded), findsOneWidget,
          reason: 'the header pill is what is under test');

      final pill = _headerPill();
      expect(pill, findsOneWidget);
      final box = tester.widget<Container>(pill);
      final padding = box.padding!;
      const want = AppTheme.pillPad;

      // Resolved from the token on both sides: the failure prints the two
      // EdgeInsets, so the message is the disagreement itself and not a
      // re-typing of either number.
      expect(padding, want,
          reason: 'the wilaya pill is a label, so it is the pill the other '
              'labels use — AppTheme.pillPad. A private inset here is what '
              'made the same idea three different sizes.');

      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.borderRadius,
          BorderRadius.circular(AppTheme.rPill),
          reason: 'radius was already on the token; the inset was not, which '
              'is what made it look deliberate');
    });

    testWidgets('it is a label, so it is not a tap target', (tester) async {
      // The reason the filter pill's bigger 14 x 12 does not bind here is that
      // that one IS tappable. If this pill ever grows an onTap this argument
      // stops applying, and it is written down so the next reader knows the
      // exemption was earned rather than assumed.
      await _pumpHome(tester);
      final pill = _headerPill();
      final taps = find.descendant(of: pill, matching: find.byType(GestureDetector));
      final ink = find.descendant(of: pill, matching: find.byType(InkWell));
      expect(taps, findsNothing,
          reason: 'a tappable pill is held to the tap recipe, not to '
              'pillPad');
      expect(ink, findsNothing);
    });

    testWidgets('the icon sits a pillGap from the word, measured off layout',
        (tester) async {
      // The inset is one half of a pill; the gap between the glyph and the word
      // is the other, and it is the half a reader actually sees as
      // "unfinished". This site drew it at 5 while `StatusPill` and
      // `CategoryBadge` draw `AppTheme.pillGap` — the same 1 dp disagreement
      // slice 11 fixed inside the kit, arriving again on a screen nobody had
      // compared.
      //
      // Measured between the two *painted* boxes, not from the source text:
      // a `SizedBox` gap has no rect of its own in some builds, so asserting
      // on the widget would pass for any value. `pill_inset_test.dart` records
      // that trap.
      await _pumpHome(tester);

      final iconRect =
          tester.getRect(find.byIcon(Icons.location_on_rounded));
      final textRect = tester.getRect(find.descendant(
        of: _headerPill(),
        matching: find.text('الجزائر'),
      ));
      // RTL: the glyph leads on the START edge, which is the RIGHT one, so the
      // near edge of the glyph is its `left` and the near edge of the word is
      // its `right`. Reading it the other way round is what produced -107.5
      // here — a number large enough to look like a real measurement of a
      // different thing, which is the shape a bad test hides in.
      final gap = iconRect.left - textRect.right;

      expect(gap, closeTo(AppTheme.pillGap, 0.01),
          reason: 'measured from the icon\'s far edge to the word\'s near '
              'edge; the engine said $gap, the kit says ${AppTheme.pillGap}');
    });
  });
}
