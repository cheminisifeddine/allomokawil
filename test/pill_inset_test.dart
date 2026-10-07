// Three writers, one pill — and the thing R4 cannot see.
//
// `card_recipe_test.dart`'s R4 counts off-grid literals per file. It went
// green on `ui.dart` the moment `symmetric(horizontal: 10, vertical: 6)`
// became two identifiers, because `_literals()` skips identifiers **by
// design**. That is the exact blind spot the eleventh slice documented, and
// this file is the proof that it costs pixels: the three writers already
// agreed on the inset to the byte and still disagreed by 1 dp on the gap
// between the icon and the word.
//
// The fix was a named token (`AppTheme.pillPad` / `AppTheme.pillGap`). A token
// stops the *fifth* writer. What it does not stop is someone overriding one
// pill, so this asserts the property the ratchet structurally cannot: that the
// three pills are laid out at the same inset **and** put the same distance
// between icon and text, measured off real layout in real pixels.
//
// The two traps, both paid for while writing it:
//   * measure the *inner* box, not the outer rect. A pill's outer rect is its
//     content, and two pills with different-length words have different
//     widths, so comparing widths compares the Arabic. The gap is measured
//     between the Icon's box and the Text's box, which is what the eye reads.
//   * the icon is `size: 14` and the gap is `AppTheme.pillGap`; a trailing
//     `const SizedBox` is not a child with a rect of its own in some builds,
//     so the assertion is on the distance between the two *painted* boxes, and
//     a pill with no icon is excluded rather than measured against nothing.
//
// **Second blind spot, closed 9 Oct: a pill that was never written as one.**
// The three pills above all *were* `StatusPill`, so a guard that compares
// `StatusPill` against itself compares three instances of one widget. The
// verification screen's `_PartsStatusCard._part` hand-rolled its verdict pill —
// `symmetric(horizontal: 10, vertical: 5)`, icon 13, gap 5, `fsBadge` — in the
// **same `ListView`** as the real `StatusPill`s on `_DocCard`, so the defect
// was a disagreement *between two components* on a screen, not inside one. A
// per-file literal counter and a same-component comparison both miss it by
// construction — and so would a fixture *here*, which is why this file does
// not carry one. The guard for that defect is
// `test/verification_parts_pill_test.dart`: it boots the real screen and
// measures the parts row and the doc row **in the same tree**, because that
// adjacency is the whole defect. What this file still owns is the shared
// inset itself — so that when the parts row is fixed onto the token, the token
// it is fixed onto is the one measured here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart'
    show MetaChip;
import 'package:allomokawil/src/widgets/ui.dart';

/// The icon-to-word gap of the pill under [key], read off layout.
///
/// Returns null when the pill carries no icon, which is a legitimate state for
/// [StatusPill] but not one that can be compared to anything.
Future<double?> pillIconGap(WidgetTester tester, String text) async {
  final textFinder = find.text(text);
  expect(textFinder, findsOneWidget, reason: 'the pill text must exist to measure');
  final textBox = tester.getRect(textFinder);
  final iconFinder = find
      .ancestor(of: textFinder, matching: find.byType(Row))
      .first;
  final row = tester.widget<Row>(iconFinder);
  double? gap;
  for (final child in row.children) {
    if (child is Icon) {
      final iconRect = tester.getRect(
        find.descendant(of: iconFinder, matching: find.byWidget(child)),
      );
      // RTL: the icon leads on the start edge, which is the RIGHT one. So the
      // gap is text.left - icon.left in local terms — i.e. the distance from
      // the icon's far edge to the text's near edge, whichever side that is.
      gap = (textBox.left - iconRect.right).abs();
      if ((textBox.right - iconRect.left).abs() < gap) {
        gap = textBox.right - iconRect.left;
      }
    }
  }
  return gap;
}

void main() {
  group('every small pill is the same pill', () {
    testWidgets('the token is one number, and it is the measured one',
        (tester) async {
      expect(AppTheme.pillPad, const EdgeInsets.symmetric(horizontal: 10, vertical: 6));
      expect(AppTheme.pillGap, 6);
    });

    testWidgets('CategoryBadge and StatusPill agree on the icon gap',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              CategoryBadge(slug: 'electricite', label: 'كهرباء'),
              StatusPill(
                  label: 'مفتوح', icon: Icons.bolt_rounded),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final badgeGap = await pillIconGap(tester, 'كهرباء');
      final pillGap = await pillIconGap(tester, 'مفتوح');
      expect(badgeGap, isNotNull, reason: 'CategoryBadge always draws an icon');
      expect(badgeGap, closeTo(AppTheme.pillGap, 0.01),
          reason: 'the badge must sit on the token, not near it');
      expect(pillGap, badgeGap,
          reason: 'these two draw side by side on the worker filter strip and '
              'the project page; a 1 dp disagreement between neighbours reads '
              'as unfinished, not as a defect');
    });

    testWidgets('the project page place chip agrees with both', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: MetaChip(icon: Icons.place_outlined, text: 'باب الزوار'),
        ),
      ));
      await tester.pumpAndSettle();
      final metaGap = await pillIconGap(tester, 'باب الزوار');
      expect(metaGap, isNotNull, reason: 'this chip always draws its icon');
      expect(metaGap, closeTo(AppTheme.pillGap, 0.01),
          reason: 'the place chip sits in the same Wrap as the status pill and '
              'every trade badge');
    });

    testWidgets('all three pills share one inset, measured from the inner box',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              CategoryBadge(slug: 'electricite', label: 'كهرباء'),
              StatusPill(label: 'مفتوح'),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Compare each pill's *container padding*, not its rect: rects differ by
      // word length, paddings must not differ at all.
      final pads = <EdgeInsetsGeometry>[];
      for (final t in ['كهرباء', 'مفتوح']) {
        final finder = find.ancestor(
          of: find.text(t),
          matching: find.byType(Container),
        );
        // The pill's Container is the decorated one; the innermost above the
        // text is the answer, the others are the Row/Column wrappers.
        final c = tester.widget<Container>(finder.first);
        pads.add(c.padding!);
      }
      expect(pads[0], AppTheme.pillPad);
      expect(pads[1], AppTheme.pillPad);
      expect(pads[0], pads[1]);
    });
  });
}
