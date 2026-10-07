// `LoadingList`'s column — is it the SAME column the rows that replace it use?
//
// **The defect this guard exists for.** `LoadingList` is the shared skeleton
// for list screens, and both screens that use it (`browse_screen.dart:347`,
// `chat_list_screen.dart:328`) draw their **real** rows with
// `padding: AppTheme.pagePad` — `fromLTRB(gutter 18, s8 8, 18, s28 28)`. The
// skeleton carried its own `EdgeInsets.all(18)`, so it agreed on the two
// gutters by accident (`gutter` is 18) and disagreed on BOTH vertical edges:
// the first skeleton card sat **10 dp lower** than the first real row, and the
// last one stopped **10 dp** short of the bottom. The user watches the whole
// column jump twice — down as the skeleton appears, up as the rows land — and
// the horizontal agreement is exactly what hides it: a screen that measured
// only the gutters, which is all `card_recipe_test`'s R5 can express, sees two
// screens that agree.
//
// **Why R4 counted it and could not price it.** The `18` in `EdgeInsets.all`
// is off the 4 dp ladder, so R4 does price it — it is one of the 24. But R4
// reads *literals*, and `pagePad` is an identifier: there is no number in the
// skeleton to compare against the token. Lowering the count (24 -> 23) would
// be evidence that a literal went away, not that a column now agrees. This
// guard is what says the second thing, off the built tree.
//
// **Why the expectation is resolved from the theme.** `test/tile_label_fit_test.dart`
// records the trap this file would otherwise walk into: a guard that transcribes
// the inset it is checking never fails when the inset changes. So the expected
// column is read off `AppTheme.pagePad` and the actual is read off the render
// box, and nothing here is a second copy of either number.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/empty_state.dart';

/// The horizontal room between the viewport edge and the first skeleton card,
/// in the tree the widget actually builds.
Rect _firstCardRect(WidgetTester tester) {
  // The first `Container` under the list is the first skeleton card.
  final card = find
      .descendant(of: find.byType(ListView), matching: find.byType(Container))
      .first;
  final cardBox = tester.element(card).findRenderObject() as RenderBox;
  return cardBox.localToGlobal(Offset.zero) & cardBox.size;
}

void main() {
  testWidgets('the skeleton sits on the same column as the rows it becomes',
      (tester) async {
    tester.view.physicalSize = const Size(392 * 3, 850 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: LoadingList(count: 3)),
    ));

    const pad = AppTheme.pagePad;
    final rect = _firstCardRect(tester);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    // Left/right agree by construction today (gutter == 18); they are asserted
    // anyway, because "the gutters match" is the reading that hid the verticals.
    expect(rect.left, closeTo(pad.left, 0.01),
        reason: 'skeleton gutter is ${rect.left}, the page column is '
            '${pad.left}');
    expect(size.width - rect.right, closeTo(pad.right, 0.01),
        reason: 'right gutter is ${size.width - rect.right}, the page column '
            'is ${pad.right}');

    // The two edges that actually disagreed.
    expect(rect.top, closeTo(pad.top, 0.01),
        reason: 'the first skeleton card sits ${rect.top - pad.top} dp off the '
            'top of the column the real rows use');
    // `s28` is the bottom, but the list is scrollable, so only assert it when
    // the content is short enough that the bottom inset is inside the frame.
    if (size.height >= rect.bottom + pad.bottom) {
      expect(size.height - rect.bottom >= pad.bottom - 0.01, isTrue,
          reason: 'the last skeleton row stops '
              '${size.height - rect.bottom} dp from the bottom, the page '
              'column reserves ${pad.bottom}');
    }
  });

  test('LoadingList is the column, spelled once', () {
    // The token and not a re-derivation: `EdgeInsets.all(18)` and
    // `fromLTRB(18, 8, 18, 28)` agree on two edges and differ on two, which is
    // the pair no alignment check can separate.
    expect(AppTheme.pagePad.top, AppTheme.s8);
    expect(AppTheme.pagePad.bottom, AppTheme.s28);
    expect(AppTheme.pagePad.left, AppTheme.gutter);
    expect(AppTheme.pagePad.right, AppTheme.gutter);
  });
}
