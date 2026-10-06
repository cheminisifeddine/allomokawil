// The auth screen's page column, and the top bar that is supposed to sit on it.
//
// Why this file exists. The eleventh R4 slice found a defect in
// `auth_screen.dart` that **R4 cannot see and never could**: `_TopBar` painted
// its row at `EdgeInsets.fromLTRB(10, 8, 18, 4)` — 18 dp on the start edge and
// **10 dp on the end edge**, while the form directly under it was
// `fromLTRB(18, 4, 18, 24)`, 18 on both. So the back arrow and the brand mark
// sat 8 dp inside the column the whole screen is built on, and nothing in the
// app compared the two.
//
// R4 counts off-grid **literals** per file, and every one of those numbers here
// is on-grid except the two 18s, which are `AppTheme.gutter`. R4 went green on
// this file the moment the 18s were renamed, and stayed green while the row was
// still 8 dp misaligned — because `gutter` and `s8` are both *identifiers*, and
// `_literals()` skips identifiers by design. A ratchet that polices the
// spelling of a number is blind to the only case a user can see: two spellings
// of the same idea disagreeing.
//
// So the assertion is not "the count went down". It is that the header row and
// the form body under it resolve to the **same start inset**, read off the
// layout rather than off the source.
//
// The two measurement traps, both paid for while writing this:
//
//   * RTL. Every inset here is measured from the **start** edge, which in this
//     app is the RIGHT edge. Asserting `left` puts the arithmetic 356 dp out on
//     a 392 dp canvas and would fail for a reason that has nothing to do with
//     the seam under test. `test/browse_column_test.dart` records the same trap.
//   * the rect is not the inset. A `Padding` lays out at its parent's full
//     width and hands the inset to its child, so `getRect(find.byType(Padding))`
//     answers 0..392 for *both* the header and the body and would pass on the
//     broken build. What has to be compared is the rect of the element a reader
//     actually sees inside it — which is why this file compares the brand mark
//     and the mode switch rather than two `Padding`s.
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

/// Pump the auth screen at the golden's canvas (392x850, DPR 1.0, so 1 px = 1
/// dp) in Arabic, with a dead API so nothing depends on the network.
Future<void> _pump(WidgetTester tester, AuthMode mode) async {
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
      home: AuthScreen(mode: mode),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(tester.takeException(), isNull,
      reason: 'the auth screen threw while building');
}

/// The form body's own column: the rectangle the mode switch fills, which is
/// `crossAxisAlignment: stretch` across the whole scroll body.
///
/// Scoped by `ancestor` of a segment rather than found by type: the segment
/// itself is inset by the switch's own interior padding, and the fields under
/// it carry their own, so only this container is the body column. It is read
/// rather than typed, so the test states the *relationship* and not the number
/// — the number lives in `AppTheme`.
Rect _bodyColumn(WidgetTester tester) {
  final containers = find
      .ancestor(
          of: find.byKey(const Key('auth-tab-signup')),
          matching: find.byType(Container))
      .evaluate();
  expect(containers, hasLength(1),
      reason: 'exactly one Container wraps the mode switch — its padding is '
          'the switch interior, and the switch box is the form column');
  return tester.getRect(find.byWidget(containers.single.widget));
}

/// The header row's two painted edges, read off the two elements in that row
/// that are placed where they were put.
///
/// The brand `Image` box answers the **end** edge (the left one in this RTL
/// app: `Row` lays its first child at the start, so the `Spacer` puts the back
/// button at the right and the mark at the left). The back `IconButton` box
/// answers the **start** edge.
///
/// The `Image` **box** is measured, not its ink: `mark.png` carries transparent
/// margin inside its 44 dp box, so a pixel scan of the golden reads the painted
/// content ~5 dp inside the box and would have called a correct layout wrong.
double _headerEndX(WidgetTester tester) => tester.getRect(find.byType(Image)).left;

double _headerStartX(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('auth-back'))).right;

void main() {
  group('the auth page is one column', () {
    testWidgets('the top bar and the form under it share both edges',
        (tester) async {
      // Both edges, both modes. The defect this file was written for was on the
      // **end** edge only — the start edge was already on the gutter — so
      // asserting one edge would have shipped it.
      for (final mode in AuthMode.values) {
        await _pump(tester, mode);

        final body = _bodyColumn(tester);
        final start = _headerStartX(tester);
        final end = _headerEndX(tester);

        debugPrint('auth ${mode.name}: body ${body.left}..${body.right} '
            'header start=$start end=$end gutter=${AppTheme.gutter}');

        expect(start, closeTo(body.right, 0.01),
            reason: 'the back control is the header row\'s start edge and must '
                'sit on the form column\'s start edge; ${mode.name}: '
                'start=$start body right=${body.right}');
        expect(end, closeTo(body.left, 0.01),
            reason: 'the brand mark is the header row\'s end edge and must sit '
                'on the form column\'s end edge — this is the defect the '
                'eleventh slice shipped, 10 dp of inset against the body\'s '
                '18; ${mode.name}: end=$end body left=${body.left}');
      }
    });

    testWidgets('both rows sit on the house gutter, not beside it',
        (tester) async {
      await _pump(tester, AuthMode.signIn);

      final body = _bodyColumn(tester);
      expect(body.right, closeTo(392 - AppTheme.gutter, 0.01),
          reason: 'the form body takes AppTheme.gutter on the start edge');
      expect(body.left, closeTo(AppTheme.gutter, 0.01),
          reason: 'and on the end edge — a column that is only half on the '
              'gutter is the defect, not a style');
      expect(_headerStartX(tester), closeTo(392 - AppTheme.gutter, 0.01),
          reason: 'the header row takes the same gutter on the start edge');
      expect(_headerEndX(tester), closeTo(AppTheme.gutter, 0.01),
          reason: 'and on the end edge, which is where it did not');
    });

    testWidgets('the switch keeps its own interior padding on the grid',
        (tester) async {
      await _pump(tester, AuthMode.signIn);

      // The switch's interior and the gap between its two segments were both a
      // literal `5`. They were swept together, and this is what stops one of
      // them moving without the other: two segments flush against each other
      // read as one control.
      //
      // The container's rect is NOT its content box — it carries a 1 dp
      // `Border.all`, so its box is 2 dp wider than what it lays out inside.
      // Measuring the rect and calling the difference the padding read 5 on a
      // build where the padding was 4. The padding is read off the widget, and
      // the rect is only used for the gap *between* the two segments, which
      // sits inside the border on both sides and so cancels.
      final container = tester
          .widget<Container>(
            find
                .ancestor(
                    of: find.byKey(const Key('auth-tab-signup')),
                    matching: find.byType(Container))
                .first,
          );
      expect(container.padding, const EdgeInsets.all(AppTheme.s4),
          reason: 'the switch pads its segments by AppTheme.s4, one named '
              'value, so the interior cannot drift off the grid on its own');

      final segment = tester.getRect(find.byKey(const Key('auth-tab-signup')));
      final other = tester.getRect(find.byKey(const Key('auth-tab-signin')));
      expect(segment.left - other.right, AppTheme.s4,
          reason: 'the gap between the two segments is the same AppTheme.s4, '
              'so the interior and the gap cannot disagree');
    });

    testWidgets('the back control still clears the 56 dp tap floor',
        (tester) async {
      await _pump(tester, AuthMode.signIn);

      // Asserted, not swept. This is the urgency-pill lesson applied to the
      // other end of this screen: a header that moves its inset must not
      // shrink the control the user leaves the screen with.
      final size = tester.getSize(find.byKey(const Key('auth-back')));
      expect(size.height, greaterThanOrEqualTo(AppTheme.tapMin),
          reason: 'the back control must stay at or above the 56 dp floor; '
              'got ${size.height}');
    });
  });
}
