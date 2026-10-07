// The client's first-run step row sits on the same row rhythm as its twin.
//
// Found on slice 30 (7 Oct 2026). `ClientStartCard`'s `_StepRow` is the numbered
// line a brand-new project owner reads between installing the app and hiring
// somebody. Its own class doc says what it is for: this card "is the client's
// half of that" -- the other half is the contractor's `_GettingStarted`
// checklist on the worker home, which the same comment names as the thing that
// arrived first. The two cards are the same shape on purpose: an icon bubble at
// the top, a heading, a caption, then a stack of one-line rows, then buttons.
//
// The row gap was painted `EdgeInsets.symmetric(vertical: 5)` -- off the 4 dp
// ladder, one step above the house step, with no comment defending it. The twin
// draws the same line with `AppTheme.s4`.
//
// **Why the pair, and not the number, is the oracle.** A ratchet can tell that
// `5` is off-grid; it cannot tell that the client's guide and the contractor's
// checklist disagree, and it cannot tell which of them is right. That is the
// same blind spot as slice 27's validity tick, slice 28's error band and slice
// 29's GPS note: the fix is "literal -> identifier", and `_literals()` skips
// identifiers by design, so the ratchet goes green the instant the defect is
// gone and stays green if it comes back as a different number. Only a second
// path to the same answer outlives that, and here the second path is a widget
// that already exists and already disagrees.
//
// **Every expectation is resolved from `AppTheme` or measured off the built
// tree, and no retired value is spelled anywhere** -- per
// `test/tile_label_fit_test.dart`'s stale-constant trap, and slice 23's rule
// that a comment quoting a retired off-grid literal is a live R4 count.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/client_start_card.dart';

/// The card on its own, at the app's logical size and in the direction every
/// sentence on it is read.
Future<void> _pumpCard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 850 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: ClientStartCard(
            onPost: () {},
            onBrowseWorkers: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The `Padding` that gives the numbered row its breathing room.
///
/// Searched **downward** from the row's own key, because the key is on
/// `_StepRow` and the `Padding` is what that widget *returns* -- it is a child,
/// not an ancestor. The first run of this file searched upward and found only
/// the card's own outer band, which is a different box with a different job,
/// and reported "the row carries no Padding of its own" on a row that plainly
/// had one. Of the candidates the one whose child is a `Row` is the row's own
/// band; the card wraps its whole body in one too, which is why the type alone
/// is not enough to identify this box.
Padding _rowBand(WidgetTester tester, int index) {
  final padded = find
      .descendant(
        of: find.byKey(Key('client-start-step-$index')),
        matching: find.byType(Padding),
      )
      .evaluate()
      .map((e) => e.widget)
      .whereType<Padding>();
  for (final p in padded) {
    if (p.child is Row) return p;
  }
  fail('the step row carries no Padding of its own, so its gap is being set by '
      'something else and this guard is measuring the wrong box');
}

/// The row's own laid-out rect -- the `Row` inside its band.
///
/// Measured off the **`Row` inside the band**, not off the keyed `_StepRow`.
/// The key is on the `_StepRow` widget, whose nearest render object is the
/// `Padding` -- and a `Padding`'s own padding is *inside* its rect, so reading
/// the keyed box makes two adjacent rows look like they touch (the first run of
/// this file reported a gap of exactly zero and would have "proved" a defect
/// that was not there). Reading the `Row` is the space a reader actually sees
/// between two lines.
Rect _rowContent(WidgetTester tester, int index) {
  final row = find.descendant(
    of: find.byWidget(_rowBand(tester, index)),
    matching: find.byType(Row),
  );
  // `.first`, not `.single`: the band holds the outer row *and* the inner one
  // that carries the icon and the title, and `single` throws on the second run
  // rather than failing the assertion. The outermost is the row whose top edge
  // is the step's top edge.
  final box = tester.renderObject<RenderBox>(row.first);
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  group('the client\'s step row is on the app\'s row rhythm', () {
    testWidgets('each row asks for the app\'s gap, and only that gap',
        (t) async {
      await _pumpCard(t);

      for (var i = 1; i <= clientStartSteps.length; i++) {
        final band = _rowBand(t, i);
        final inset = band.padding as EdgeInsets;
        debugPrint('ROW $i BAND = $inset');

        // The band is inside the card's own column, so it inherits the width.
        // A band that also pulls its own edge inside it narrows the Arabic the
        // reader is scanning down a list of steps.
        expect(inset.left, 0,
            reason: 'the row is inside the card\'s padding, so it inherits the '
                'column\'s width -- it must not pull its own edge inside it');
        expect(inset.right, 0, reason: 'and the far edge must agree');

        // The value, as a token and not as a number, so a future edit cannot
        // drift it quietly back off the ladder without turning a test red.
        expect(inset.top, AppTheme.s4,
            reason: 'the row\'s gap is the app\'s step, the one the contractor\'s '
                'twin checklist draws the same line with');
        expect(inset.bottom, AppTheme.s4, reason: 'the far edge must agree');
      }
    });

    testWidgets('consecutive rows are one house step apart, measured on the '
        'tree', (t) async {
      await _pumpCard(t);

      final gap = _rowContent(t, 2).top - _rowContent(t, 1).bottom;
      debugPrint('ROW-TO-ROW gap = $gap');

      expect(gap, AppTheme.s4 * 2,
          reason: 'each row contributes its own bottom gap and its neighbour its '
              'own top, so the space a reader sees between two lines is twice '
              'the step. This reads the laid-out content, not the request, so a '
              'gap contributed anywhere else in the column shows up here too');
    });
  });
}
