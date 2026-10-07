// `profile_edit_screen.dart` — one clearance, two writers.
//
// The gap between the last control of this form and the pinned save bar was
// **52 dp**, written in two places that neither claimed to be the column: the
// list's own `EdgeInsets.fromLTRB(18, 4, 18, 30)` and a trailing
// `SizedBox(height: 22)` between the last field and the `]`. The three sibling
// screens that pin the identical bar sit on 28 (`project_detail`,
// `worker_profile`, both `AppTheme.pagePad`) and 36 (`project_new`).
//
// Why the existing ratchet cannot see this, and why the fix was not a rename:
//   * R4 counts off-grid literals **inside `EdgeInsets` constructors**, so it
//     saw the `30` and never saw the `22` — it was measuring one of two
//     writers for a quantity neither of them owned. The one number that
//     described the gap was not one of the numbers R4 reads.
//   * R4 also went **green the instant the `30` became an identifier**, because
//     `_literals()` skips identifiers by design — the same blind spot the
//     `auth_screen` slice paid a whole tick for.
//
// So this guard asserts the thing the counter structurally cannot: that the
// laid-out clearance **equals the house token**, read off the widget tree.
//
// The measurement traps, all three paid for on the first draft:
//   * **A bare `MaterialApp` answers the wrong numbers.** `AppTheme.light`
//     sets `toolbarHeight: 60`; the default Material 3 AppBar is 56, which
//     moves every control on the screen by 4 dp. Measured both ways on the
//     first draft and the numbers disagreed.
//   * **The probe must prove it is at maximum extent.** The first draft
//     dragged once and reported a 238 dp clearance, because the fling had not
//     been settled and the list had barely moved — a real number for a
//     *mid-scroll* frame, which is not the quantity the reader sees. The test
//     now flings, settles, drags again and asserts the card's bottom did not
//     move; only then does it read the clearance.
//   * **The clearance is `sticky.top - card.bottom`**, and the card is found as
//     an *ancestor* `Container` of the `SwitchListTile`: the switch is the last
//     control of the form, and the `Container` around it is the thing whose
//     bottom edge is what the reader sees.
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
Future<void> _pumpForm(WidgetTester tester, {Size logical = const Size(392, 648)}) async {
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      http.Response json(Object b) => http.Response(
          jsonEncode(b), 200,
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

/// The last control of the form — the availability switch — inside its card.
Finder _lastCard() => find
    .ancestor(
      of: find.byType(SwitchListTile),
      matching: find.byType(Container),
    )
    .first;

/// The top edge of the pinned bar. `StickyCta` is the widget, so this is a
/// single finder and it cannot miss — the earlier `hitTestable()` dance was an
/// attempt to be clever about a name that resolves directly.
Rect _sticky(WidgetTester tester) => tester.getRect(find.byType(StickyCta));

/// `ListView.padding` is an `EdgeInsetsGeometry`, not an `EdgeInsets`, so
/// `.bottom` does not exist on it — it has to be **resolved** first. Reading
/// `.resolve(TextDirection.rtl)` keeps the test honest about direction without
/// changing a number (the bottom inset is the same either way).
EdgeInsets _listInset(ListView list) =>
    list.padding!.resolve(TextDirection.rtl);

void main() {
  testWidgets(
      'the gap between the last control and the pinned save bar is the house '
      'token, and nothing else', (tester) async {
    await _pumpForm(tester);

    final list = tester.widget<ListView>(find.byType(ListView).first);
    // A `ListView` hands its padding to an internal `SliverPadding`, so
    // `ListView.padding` is null on some paths; this one carries it, and the
    // assertion below is deliberately made on the **inset** rather than on a
    // rect, because a `Padding` lays out at its parent's full width and its
    // own rect answers the screen to itself.
    expect(list.padding, isNotNull,
        reason: 'the form is a ListView; its padding must be readable');
    expect(
      _listInset(list).bottom,
      AppTheme.s28,
      reason: 'the clearance to the pinned bar is the house bottom inset. It '
          'was 30 plus a trailing SizedBox(height: 22) = 52 dp, against 28 on '
          'the two sibling screens that pin the identical bar.',
    );

    // Now the laid-out truth, off the tree, at **maximum** scroll.
    await tester.fling(
        find.byType(ListView).first, const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    _drainKnownWarnings(tester);
    final settled = tester.getRect(_lastCard()).bottom;
    // Prove we are at the end. A fling that has not been read at max extent
    // measures a mid-scroll frame, which is how the first draft of this file
    // reported a 238 dp "clearance" on a screen whose clearance is 28.
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    _drainKnownWarnings(tester);
    expect(tester.getRect(_lastCard()).bottom, settled,
        reason: 'the list must be at maximum extent before the clearance is '
            'read, or the number describes a frame the reader never sees');

    final clearance = _sticky(tester).top - tester.getRect(_lastCard()).bottom;
    expect(clearance, moreOrLessEquals(AppTheme.s28, epsilon: 0.01),
        reason: 'the visible gap under the last control must equal the token. '
            'A trailing spacer plus the padding is two writers for one column: '
            'measured at 52.0 before the fix.');
  });

  testWidgets('the form and the pinned bar share one horizontal inset',
      (tester) async {
    await _pumpForm(tester);
    await tester.fling(find.byType(ListView).first, const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    _drainKnownWarnings(tester);

    // R4 cannot compare a number in this file with a number in `ui.dart`. This
    // can, and it is the assertion the tenth slice's `browse_column_test.dart`
    // was built for: the strip's inset equals the list's.
    final card = tester.getRect(_lastCard());
    final button = tester.getRect(find.byType(PrimaryButton));

    // RTL: the start edge here is the **right** one. Asserting `left` would
    // fail for a reason that has nothing to do with the seam.
    expect(card.right, moreOrLessEquals(392 - AppTheme.gutter, epsilon: 0.01),
        reason: 'the form body sits on the page gutter');
    expect(button.right, moreOrLessEquals(392 - AppTheme.gutter, epsilon: 0.01),
        reason: 'the pinned button sits on the same gutter, so the save control '
            'cannot be narrower than the field above it');
    expect((card.right - button.right).abs(), lessThan(0.01),
        reason: 'one column: the button and the form agree on the start edge');
  });

  testWidgets('no trailing spacer writes a second clearance after the fix',
      (tester) async {
    await _pumpForm(tester);
    // The clearance is the list's bottom inset and nothing else. If a spacer
    // ever comes back under the last card, this is the assertion that catches
    // it — and it is written against **geometry**, not against the source, so
    // a spacer that only appears at one viewport still fails.
    final list = tester.widget<ListView>(find.byType(ListView).first);
    await tester.fling(find.byType(ListView).first, const Offset(0, -3000), 3000);
    await tester.pumpAndSettle();
    _drainKnownWarnings(tester);
    final clearance =
        _sticky(tester).top - tester.getRect(_lastCard()).bottom;
    expect(clearance, moreOrLessEquals(_listInset(list).bottom, epsilon: 0.01),
        reason: 'the visible gap IS the padding: nothing else may add to it');
  });
}
