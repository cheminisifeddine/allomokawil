// The auth form's three stacked fields, measured against each other.
//
// Why this file exists. R4 counts off-grid **literals**, and in every slice of
// this sweep so far the count was blind to the actual defect: the fix is always
// "replace a number with an identifier", and `_literals()` skips identifiers by
// design. So R4 goes green whether the numbers agreed or disagreed. Every prior
// slice had to add a geometry guard next to the sweep for exactly this reason,
// and this is the first slice where the numbers R4 was counting turned out to
// be load-bearing on two axes at once.
//
// The defect this file pins. `authInput()` gives its two `TextField`s
// `contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18)`, and
// `DzPhoneField` — which sits between them — hardcodes the **identical**
// `symmetric(horizontal: 14, vertical: 18)`. So the three inputs a new user
// types into agree with each other at 14. But `AppTheme.fieldPad`, the house
// inset for every other field in this app, is
// `symmetric(horizontal: s16, vertical: 18)`. The whole auth form is therefore
// **2 dp narrower than every field the user is shown after they log in** — the
// first screen of the install measured against a different number than the rest
// of the product, and the agreement between the three fields hides the
// divergence from every reviewer and from R4.
//
// Why the vertical must not move with it. `18` is *deliberately* off-grid and is
// the **same named token** in both places: 18x2 plus a ~15.5 dp body line at
// 1.65 line-height is what carries these fields past `AppTheme.tapMin` = 56.
// `tap_target_test.dart` and `tool/tap_target_audit.py` both measure that floor
// and both hold an entry for this exact row. The obvious reading of "18 is not
// a multiple of 4, take it to 16" is the same mistake the `project_new_screen`
// slice made on the urgency pill and recorded in the backlog: **the number that
// looks like style is usually load-bearing.** So the horizontal is what this
// slice moves; the vertical is asserted unchanged rather than swept.
//
// The measurement traps, inherited and re-paid.
//   * `contentPadding` is consumed by the `InputDecorator` *inside* the
//     `TextField`, so `tester.getRect(find.byType(TextField))` answers the
//     **outer** field box and would compare each field against itself and pass
//     for any padding. What must line up is the inset, so it is read off the
//     decoration rather than guessed from a rect.
//   * and the glyph edge is *not* an alignment: `authInput` carries a
//     `prefixIcon`, so its text starts ~48 dp inside the box while the phone
//     field, which has no icon, starts at its own padding. Reading glyph
//     positions would have measured the icon and called it the column — the
//     exact mistake `section_title_edge_test.dart` was written to prevent.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/widgets/phone_field.dart';

/// Pumps the sign-up half of the form — the state with the most stacked fields,
/// so it is the state that can disagree with itself.
Future<void> _pumpSignUp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((_) async => http.Response('{}', 200,
        headers: {'content-type': 'application/json'})),
  );
  final auth = AuthState(api);

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
      home: const AuthScreen(mode: AuthMode.signUp),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The content padding of the phone field, read off its own `TextField`.
///
/// Cast, not assumed: `contentPadding` is declared `EdgeInsetsGeometry`, and
/// every writer in this file passes a literal `EdgeInsets`, so the cast is
/// exact here. `resolve()` would answer the same numbers for a `Directionality`
/// without asserting that.
EdgeInsets _phonePadding(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.byType(DzPhoneField),
      matching: find.byType(TextField),
    ),
  );
  return field.decoration!.contentPadding! as EdgeInsets;
}

/// The content padding of the two `authInput` fields — name and password.
///
/// Scoped by `descendant`, not by `find.byType(TextField)`: the phone field is
/// **also** a `TextField`, so an unscoped query returns three and the count
/// assertion below would have compared all three against the house token —
/// which happens to be the stronger assertion, but for the wrong reason and
/// with a misleading failure message. The first cut of this file did exactly
/// that and the failure read "expected 2, got 3" on a test about stacking.
List<EdgeInsets> _authPadding(WidgetTester tester) {
  return find
      .byType(TextField)
      .evaluate()
      .map((e) => e.widget)
      .whereType<TextField>()
      // Name and password only. The phone field is *also* a `TextField` and it
      // sits inside the same `Column`, so neither `find.byType(TextField)` nor
      // `descendant(of: Column)` excludes it — both return three. Subtracting
      // the phone field's own subtree is the scope that actually says "the two
      // `authInput` fields".
      .where((f) => find
          .descendant(of: find.byType(DzPhoneField), matching: find.byWidget(f))
          .evaluate()
          .isEmpty)
      .where((f) => f.decoration?.contentPadding != null)
      .map((f) => f.decoration!.contentPadding! as EdgeInsets)
      .toList();
}

void main() {
  group('the auth form sits on the house field inset', () {
    testWidgets('all three stacked fields take the house field inset',
        (tester) async {
      await _pumpSignUp(tester);

      expect(find.byType(DzPhoneField), findsOneWidget,
          reason: 'sign-up must show the phone field for this to be a '
              'three-field column');

      final auth = _authPadding(tester);
      expect(auth, hasLength(2),
          reason: 'name + password both use authInput()');

      final phone = _phonePadding(tester);

      debugPrint('auth fields: ${auth.map((e) => '$e').join(' | ')} '
          'phone=$phone house=${AppTheme.fieldPad}');

      for (final p in <EdgeInsets>[...auth, phone]) {
        expect(p, AppTheme.fieldPad,
            reason: 'every field on the auth form takes the one house inset, '
                'so the first screen the user sees is not 2 dp narrower than '
                'every field they see afterwards; got $p, '
                'house=${AppTheme.fieldPad}');
      }
    });

    testWidgets('the three fields share one left edge as boxes',
        (tester) async {
      await _pumpSignUp(tester);

      // The **outer** boxes, not the glyphs. Two traps, both paid for here:
      //
      //  * `authInput` carries a `prefixIcon`, so its glyphs start ~48 dp
      //    inside the box while the phone field, which has no icon, starts at
      //    its own padding. Comparing glyph x would be measuring the icon.
      //  * the phone field's visible edge is the **decorated `Container`** it
      //    wraps its `TextField` in, which carries a 1 dp `fieldLine` border.
      //    The `TextField` inside it is laid out at the same inset, but its own
      //    rect is not the box a reader sees. The first cut of this test
      //    compared the `TextField` and read a 1 dp misalignment that was the
      //    border, not a defect — so the assertion moved to the element that
      //    owns the visible edge.
      final phoneBox = tester.getTopLeft(find.byType(DzPhoneField)).dx;

      final authBoxes = <double>[];
      for (final f in find.byType(TextField).evaluate()) {
        final inside = find
            .descendant(
                of: find.byType(DzPhoneField), matching: find.byWidget(f.widget))
            .evaluate()
            .isNotEmpty;
        if (inside) continue;
        authBoxes.add(tester.getTopLeft(find.byWidget(f.widget)).dx);
      }

      expect(authBoxes, hasLength(2),
          reason: 'name + password, with the phone field excluded by scope');
      expect(authBoxes, everyElement(closeTo(phoneBox, 0.01)),
          reason: 'the three inputs are stacked in a single column and must '
              'start at the same x; name/password=$authBoxes '
              'phone=$phoneBox');
    });

    testWidgets('the vertical padding still clears the 56 dp tap floor',
        (tester) async {
      await _pumpSignUp(tester);

      // 18 dp of vertical padding is not decoration: it is what carries these
      // fields past `AppTheme.tapMin`. Asserted rather than swept.
      expect(AppTheme.fieldPad.top, AppTheme.gutter,
          reason: 'the vertical field padding is the named 18, not an '
              'off-grid literal — the urgency-pill lesson from the '
              'project_new slice applies to every 18 that clears a tap floor');

      for (final p in <EdgeInsets>[..._authPadding(tester), _phonePadding(tester)]) {
        expect(p.top, AppTheme.gutter,
            reason: 'the auth fields keep their 56 dp floor; got top=${p.top}');
      }

      final height = tester.getSize(find.byType(TextField).first).height;
      expect(height, greaterThanOrEqualTo(AppTheme.tapMin),
          reason: 'an auth field must render at or above the 56 dp tap floor; '
              'got $height');
    });
  });
}
