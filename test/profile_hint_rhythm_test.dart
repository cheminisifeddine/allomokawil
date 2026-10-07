// `profile_edit_screen.dart` — the caption under a section heading was spaced
// by **two writers**, and the heading it belongs to fought its own padding.
//
// `_Hint` was `Padding(EdgeInsets.only(top: 2, bottom: 2))` around a caption.
// Measured on the real form at 392 logical, **both** call sites read the same:
//
//   SectionTitle bottom 200.0 -> hint top 202.0   (gap above  =  2.0)
//   hint height 40.0 -> grid/row top 254.0        (gap below  = 12.0)
//
// The 12 dp below the caption was `bottom: 2` **plus** a `SizedBox(height: 10)`
// sitting in the column beside it. Two writers for one visible gap — the third
// instance in this file, after the `30` + `SizedBox(height: 22)` clearance that
// `profile_edit_clearance_test.dart` already pinned.
//
// Why R4 could not see it, and why the counter's green was not reassuring:
//   * R4 reads off-grid literals **inside `EdgeInsets` constructors**. `2` is
//     one, so R4 did count it — but a count is not a comparison. It had no
//     second copy to compare against, because the `SizedBox(height: 10)` is
//     not an `EdgeInsets`. It saw 1 writer for a quantity 2 writers owned.
//   * `10` is off-grid as well and R4 never counted it at all, for the same
//     reason: `SizedBox(height: n)` is outside the expression R4 parses.
//   * So both halves of the double-write were priced at ~zero, and the file
//     still shipped a 2 dp pad under a heading whose own rule glues content to
//     the heading that introduces it.
//
// The fix is two moves, and the second is the one R4 would have disagreed with:
// the padding is gone, and the surviving gap is now `AppTheme.s12` rather than
// `10` — because the *measured* gap was already 12 dp, and `10` was only ever
// half of it. `s12` is what the sibling screen draws for the identical
// heading-caption-row stack (`verification_screen.dart:366`), so the two
// screens agree without either being hand-fitted.
//
// What this guard asserts, and why each part:
//   1. **Gap above = 0** on both call sites. Not "small": the heading owns the
//      space beneath it (`SectionTitle` pads `s4` *below* itself), so a child
//      pad adds air between a heading and its own caption. A test that allowed
//      "up to 4" would pass on the exact bug this file shipped.
//   2. **Gap below = s12**, read off the laid-out tree, not off a literal.
//   3. **One writer.** The gap below must come from a single widget, so a
//      `Padding` can never come back alongside the spacer and re-split 12 into
//      2 + 10 without either number changing.
//
// The lazy list is the reason case 2 needs its own pump: the price hint sits
// below the fold and is **not built at all** on first frame — measured
// `hint2 count=0` before the scroll, `1` after. A guard that read both in one
// frame would have been asserting against a widget that does not exist yet, and
// would have passed for the wrong reason if it had.
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
import 'package:allomokawil/src/screens/worker/profile_edit_screen.dart';
import 'package:allomokawil/src/widgets/category_grid.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// The two known Material warnings this screen always emits: a `ListTile`
/// inside a decorated `Container`, and the multi-exception wrapper around it.
/// Failing on anything else is the point of the drain.
void _drainKnownWarnings(WidgetTester tester) {
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    if (!'$e'.contains('ink splashes may be invisible') &&
        !'$e'.contains('Multiple exceptions')) {
      fail('unexpected exception on the profile screen: $e');
    }
  }
}

const _row = <String, Object?>{
  'id': 16,
  'user_id': 31,
  'full_name': 'علي بن علي',
  'bio': 'بناء وتشطيب',
  'specialties': ['painting'],
  'experience_years': 5,
  'price_range_min': 20000,
  'price_range_max': 60000,
  'service_radius_km': 30,
  'is_available': 1,
  'verification_status': 'verified',
  'avg_rating': 4.5,
  'total_reviews': 3,
  'total_completed_jobs': 7,
  'is_identity_verified': 1,
  'is_certificate_verified': 0,
  'user_wilaya': '16',
};

/// Drives the real screen to the loaded form state, logged in as a contractor.
/// A bare `MaterialApp` answers the wrong numbers here — `AppTheme.light` sets
/// `toolbarHeight: 60` against Material's default 56 — so the theme is applied
/// for the same reason `profile_edit_clearance_test.dart` applies it.
Future<void> _pumpForm(WidgetTester tester,
    {Size logical = const Size(392, 648)}) async {
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      http.Response json(Object b) => http.Response(jsonEncode(b), 200,
          headers: {'content-type': 'application/json'});
      if (req.url.path.endsWith('/api/login')) {
        return json({
          'token': 'tok',
          'user': {
            'id': 31,
            'phone': '0773000000',
            'email': null,
            'full_name': 'مستخدم',
            'type': 'worker',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (req.url.path.contains('/my/profile')) return json(_row);
      return json(<Object>[]);
    }),
  );
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AppScope(api: api, auth: auth, child: const ProfileEditScreen()),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  _drainKnownWarnings(tester);
}

Finder _heading(String arabic) => find.widgetWithText(SectionTitle, arabic);

void main() {
  testWidgets(
      'the specialty caption is glued to its heading, and the gap under it '
      'is one writer worth of s12', (tester) async {
    await _pumpForm(tester);

    final hint = find.textContaining('اختر كل المهن');
    expect(hint, findsOneWidget,
        reason: 'the first caption is built on the first frame; the second is '
            'not, and is deliberately covered by its own case below');

    // --- gap ABOVE: exactly zero, not "small".
    //
    // `SectionTitle` already pads `s4` beneath itself, so the heading owns the
    // space under it. The old `Padding(top: 2)` put 6 dp of air between a
    // heading and the caption it introduces. Asserting `lessThanOrEqualTo(4)`
    // would have passed on the shipped bug — measured at 2.0 — so this is
    // pinned to zero.
    final above =
        tester.getRect(hint).top - tester.getRect(_heading('تخصصاتك')).bottom;
    expect(above, moreOrLessEquals(0.0, epsilon: 0.01),
        reason: 'a section heading is glued to the content it introduces. The '
            'caption carried `Padding(top: 2)`, measured 2.0 dp of air.');

    // --- gap BELOW: the house token, read off the tree.
    //
    // This is the quantity that had two writers. The visible gap was 12.0 dp
    // split as `bottom: 2` (inside the caption) + `SizedBox(height: 10)` (in
    // the column). The fix keeps the 12 dp the reader already saw and drops
    // the 2, so `s12` is the *measured* gap and not a new design decision.
    final below =
        tester.getRect(find.byType(CategoryGridMultiTiles)).top -
            tester.getRect(hint).bottom;
    expect(below, moreOrLessEquals(AppTheme.s12, epsilon: 0.01),
        reason: 'the gap under the caption is one writer on the ladder. It '
            'measured 12.0 dp before the fix, written twice as 2 + 10.');

    // --- ONE writer.
    //
    // The assertion the arithmetic above cannot make: `2 + 10 = 12` and
    // `12` alone are the same picture, so a gap check passes either way. What
    // must not come back is a padding that re-splits the number silently — the
    // exact failure, invisible to every assertion above, that shipped here.
    final paddings = find
        .ancestor(of: hint, matching: find.byType(Padding))
        .evaluate();
    expect(paddings, isEmpty,
        reason: 'the caption must not wrap itself in a Padding. A child pad is '
            'a second writer for the column: it was `top: 2, bottom: 2` and '
            'the bottom half silently split the gap the spacer also claims.');
  });

  testWidgets('the price caption obeys the same rhythm, once it is built',
      (tester) async {
    await _pumpForm(tester);

    // This caption is **below the fold of a lazy list**. Measured: 0 built on
    // the first frame, 1 after the scroll. A single-frame guard over both call
    // sites would have been reading a widget that did not exist — so this one
    // scrolls it into build first and asserts on what is really there.
    final hint = find.textContaining('اتركهما فارغين');
    expect(hint, findsNothing,
        reason: 'precondition, and the reason this case exists: the list is '
            'lazy, so the second caption must NOT be built before the scroll. '
            'If this ever fails the screen grew a non-lazy column and the '
            'scroll below is no longer the only way to reach it.');

    await tester.scrollUntilVisible(hint, 200.0,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    _drainKnownWarnings(tester);
    expect(hint, findsOneWidget);

    final above =
        tester.getRect(hint).top - tester.getRect(_heading('أسعارك (دج)')).bottom;
    expect(above, moreOrLessEquals(0.0, epsilon: 0.01),
        reason: 'same rule as the specialty caption: no pad between a heading '
            'and its own caption.');

    expect(
      find.ancestor(of: hint, matching: find.byType(Padding)),
      findsNothing,
      reason: 'same one-writer rule; both call sites share `_Hint`, so a pad '
          'that came back would appear on both.',
    );
  });

  testWidgets('the caption is spaced from the grid by s12 on the ladder, not '
      'by an off-grid literal', (tester) async {
    await _pumpForm(tester);

    // The surviving writer is a `SizedBox(height: 10)` -> `s12`. Read the real
    // widget, so the assertion is about the gap the reader sees and not about
    // a token that a future edit could set to anything at all.
    final hint = find.textContaining('اختر كل المهن');
    final hintBottom = tester.getRect(hint).bottom;
    final gridTop = tester.getRect(find.byType(CategoryGridMultiTiles)).top;
    expect(gridTop - hintBottom, moreOrLessEquals(AppTheme.s12, epsilon: 0.01));

    // And the spacer that owns it is on the ladder: `AppTheme.s12 % 4 == 0` is
    // the property the whole 4 dp grid rests on, checked against the value the
    // screen actually uses rather than against a literal in this file.
    expect(AppTheme.s12 % 4, 0,
        reason: 'every gap in the app comes off the 4 dp ladder');
  });
}
