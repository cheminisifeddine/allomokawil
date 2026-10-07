// The card's column on the sign-in screen: everything inside `AppCard` starts
// on the same line, at both edges.
//
// Why this file exists. The fifteenth R4 slice found a defect in
// `auth_screen.dart` that **R4 counted and still could not see**: the
// «remember me» row held `EdgeInsets.symmetric(horizontal: 2, vertical: 6)`.
// R4 read the `2`, went green the instant it stopped being a literal — and the
// `2` was pushing the row's content **2 dp inside** the column every other
// element in that card sits on.
//
// The measurements, off the booted screen at 392 dp / DPR 1.0, RTL:
//
//   AppCard outer box            18.0 .. 374.0
//     content  = left+1+16, right-1-16    35.0 .. 357.0
//   «رقم الهاتف» label icon      right 357.0   ok
//   the phone field             right 357.0   ok
//   «كلمة المرور» label icon     right 357.0   ok
//   the password field          right 357.0   ok
//   the error notice            right 357.0   ok
//   «تذكرني»                    left   37.0   <-- 2 dp in, alone
//   its Checkbox                right 355.0   <-- 2 dp in, the same 2
//
// Two dp is not a defect a user can name. It is the kind that makes a column
// read as *unfinished*, which is the argument `AppTheme.pillGap` was written
// for after three pill writers disagreed by 1 dp. The same slice's other
// finding was two danger icons at 16 dp and 20 dp on this same screen — nobody
// noticed that one either, and the count went green over it too.
//
// So the assertion is not "R4 went down". It is that the elements of this card
// resolve to the ONE content inset, read off the layout tree.
//
// Three traps, all paid for while writing this:
//
//   * RTL. Start is the RIGHT edge here. `auth_page_column_test.dart` records
//     the same trap: asserting `left` puts the arithmetic 356 dp out on a
//     392 dp canvas and fails for a reason that has nothing to do with the
//     seam under test.
//   * the rect is not the inset. `AppCard` is a decorated box, so its rect is
//     the OUTER edge. The content line is one `cardLine` border and one
//     `cardPad` in from it. The test resolves that from the theme rather than
//     hard-coding 35.0, so this keeps meaning "they agree" if the recipe's own
//     numbers ever move.
//   * RTL runs the rows in both directions at once. In one row the leading
//     element is on the right (the field labels' icon, the Checkbox), in the
//     other it is on the left (`«تذكرني»` trails a Checkbox that precedes it).
//     So "compare every element's `right`" fails on three correct elements and
//     would have had me "fixing" a column that was already aligned.
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
import 'package:allomokawil/src/widgets/ui.dart';

/// The sign-in screen at the goldens' canvas (392x850, DPR 1.0, so 1 px = 1 dp)
/// in Arabic, with a dead API so nothing depends on the network.
Future<void> _pumpSignIn(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392, 850);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((_) async => http.Response('{}', 200,
        headers: {'content-type': 'application/json'})),
  );
  await tester.pumpWidget(AppScope(
    api: api,
    auth: AuthState(api),
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
      home: const AuthScreen(mode: AuthMode.signIn),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(tester.takeException(), isNull,
      reason: 'the auth screen threw while building');
}

void main() {
  group('the sign-in card draws one column', () {
    testWidgets('every element in the card starts on the content line',
        (tester) async {
      await _pumpSignIn(tester);

      // The card's own outer box, and the one content inset inside it: a 1 dp
      // `cardLine` border and `cardPad`. Resolved, not typed in.
      final card = tester.getRect(find.byType(AppCard));
      final contentLeft = card.left + AppTheme.cardLineWidth + AppTheme.cardPad.left;
      final contentRight =
          card.right - AppTheme.cardLineWidth - AppTheme.cardPad.right;
      expect(contentLeft, closeTo(35.0, 0.01),
          reason: 'the measured content line; if this moved, the numbers in '
              'the header comment moved with it and the fix changed');

      // Leading elements: their START edge is the right one, in RTL.
      // `_FieldLabel` is Padding > Row > [Icon, SizedBox, Expanded(Text)], so
      // the icon is the text's *sibling*, not its descendant — `find.descendant`
      // finds nothing and the failure would read as a missing icon.
      Icon labelIcon(String label) => tester
          .widget<Icon>(find
              .descendant(
                  of: find
                      .ancestor(of: find.text(label), matching: find.byType(Row))
                      .first,
                  matching: find.byType(Icon))
              .first);

      final leading = <String, double>{
        'the «رقم الهاتف» label icon': tester.getRect(find.byWidget(
            labelIcon('رقم الهاتف'))).right,
        'the «كلمة المرور» label icon': tester.getRect(find.byWidget(
            labelIcon('كلمة المرور'))).right,
        'the phone field': tester.getRect(find.byType(DzPhoneField)).right,
        'the password field':
            tester.getRect(find.byType(TextField).last).right,
        // The `Checkbox` is the *leading* child of its row in RTL — it sits at
        // the right, before the label. Its own box is 48 dp because the Material
        // checkbox pads itself; only its outer edge is on the column.
        'the «remember me» Checkbox':
            tester.getRect(find.byType(Checkbox)).right,
      };
      for (final e in leading.entries) {
        expect(e.value, closeTo(contentRight, 0.01),
            reason: '${e.key} starts at ${e.value.toStringAsFixed(1)}, the '
                'column starts at ${contentRight.toStringAsFixed(1)} — 2 dp '
                'off here is what the slice was');
      }

      // Trailing elements of their own rows: their END edge is the right one.
      final trailing = <String, double>{
        'the «تذكرني» label': tester.getRect(find.text('تذكرني')).left,
      };
      for (final e in trailing.entries) {
        expect(e.value, closeTo(contentLeft, 0.01),
            reason: '${e.key} ends at ${e.value.toStringAsFixed(1)}, the '
                'column ends at ${contentLeft.toStringAsFixed(1)} — this is '
                'the element that was 2 dp in');
      }
    });

    testWidgets('the remember row still clears the 56 dp tap floor',
        (tester) async {
      // The reason the vertical `6` stays off the ladder. If this ever fails,
      // the sweep renamed a tap target's padding into an off-grid one and
      // dropped the row under `AppTheme.tapMin`.
      await _pumpSignIn(tester);
      final row = tester.getRect(
          find.ancestor(of: find.byType(Checkbox), matching: find.byType(InkWell)));
      expect(row.height, greaterThanOrEqualTo(AppTheme.tapMin),
          reason: 'the «remember me» row is a tap target, not a label: '
              '${row.height} dp, the floor is ${AppTheme.tapMin}');
    });
  });
}
