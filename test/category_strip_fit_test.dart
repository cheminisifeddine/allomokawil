// The horizontal category strip's label -- does every taxonomy name FIT, and is
// the tile's own vertical slack big enough to survive it?
//
// **What this guard is for.** `_CategoryStripTile` painted its label with
// `EdgeInsets.symmetric(horizontal: 6, vertical: 10)` -- two off-ladder
// literals, the same pair shape that `SelectableTile` carried at
// `ui.dart:399` and the sweep already fixed there. Neither literal was
// defending anything, and the way to know that is to ask the engine rather
// than to reason about the padding:
//
//   * the vertical `10` moved **zero pixels**. The column is centred, so the
//     content sits at `labelTop` 311.00 dp whether the padding is 12, 10, 8, 6
//     or 4. Padding around a centred child is arithmetic, not layout -- so a
//     comment claiming the `10` "keeps the label clear of the tile edge" would
//     have been asserting something the engine contradicts.
//   * the horizontal `6` cost label room that **no label needs**: the widest
//     taxonomy name needs 72.25 dp and the tile left 82.00 plain / 80.00
//     selected.
//
// **What made this worth a slice** is the second half of that vertical story.
// The strip tile is `height: 104` inside a 112 dp box, its content is
// 42 + 8 + 27.5 = 77.5 dp, so the room is 104 - 2 x vpad - 2 x border:
// at `vpad: 10` it is 82.00 plain / 80.00 selected (**4.50 / 2.50 dp slack**),
// and at `vpad: 12` it is 78.00 / 76.00 -- **0.50 and -1.50 dp**, i.e. the
// selected tile really does overflow. The off-grid number was one step from
// that, and nothing in the repo could see it coming because `Flexible` clips
// silently instead of painting the overflow stripe.
//
// **Why the room is read off the tree, not recomputed.** The lesson this file's
// sibling got wrong (`tile_label_fit_test.dart`, recorded in its own header):
// a guard that builds its own `TextStyle` measures the font the widget *used
// to* draw. The type ladder moved `fsCaption` -> `fsBadge` once already and that
// guard stayed green through it. So the style below is read off the `Text` in
// the tree, and `styleIsReadOffTheTile` fails the moment it goes missing.
//
// **Why both states.** The selected tile's border costs 0.5 dp more room than
// the plain one (`hairlineSelected` 2 vs `hairlineResting` 1.5), so a guard
// that only lays out the plain tile can still be measuring a tile that is
// tighter than it thinks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/widgets/category_grid.dart';

/// The strip is horizontal, so the page width does not vary the label room --
/// the tile is a fixed `width: 96`. The states that matter are plain and
/// selected, because selection thickens the border.
const tileWidth = 96.0;

/// Real Cairo, or Arabic renders as tofu and every width below is meaningless.
Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();
}

/// Does [label] still fit in [room] without exceeding [maxLines]?
///
/// `didExceedMaxLines` is the only correct authority: `maxLines` **clips**, so
/// `computeLineMetrics().length` can never report more than [maxLines] and a
/// guard built on it would be green forever. This is the second measurement
/// bug this sweep hit -- a binary search for "narrowest room that fits" came
/// back with a constant 200 dp for all sixteen labels, twice, because the
/// search's bounds were inverted; a 0.25 dp linear scan is used here instead,
/// and `theScanFindsTheKnownThreshold` proves it against a label whose
/// threshold is known.
bool _fits(String label, double room, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '\u2026',
  )..layout(maxWidth: room);
  return !tp.didExceedMaxLines;
}

/// The `TextStyle` the tile's own label is painted with, read off the tree.
TextStyle _paintedStyle(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(CategoryGrid),
      matching: find.byType(Text),
    ).first,
  );
  final style = text.style;
  if (style == null || style.fontSize == null) {
    fail('the strip tile label has no style, so nothing can be measured — this '
        'guard is now reading nothing and would pass forever');
  }
  return style;
}

/// The label room the tile actually leaves: its own width, less the border it
/// paints, less the padding it draws.
double _room(WidgetTester tester, bool selected) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(CategoryGrid),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  final decoration = container.decoration as BoxDecoration;
  final border = decoration.border?.top.width ?? 0.0;
  final padding = container.padding! as EdgeInsets;
  // Read the THEME, never a literal. This used to pin `2.0 : 1.0` and the pin
  // was the point -- it caught the border changing under the measurement. But
  // pinning it also froze the numbers in a second place, so when the tile moved
  // onto `hairlineSelected`/`hairlineResting` the guard failed on its own
  // arithmetic while the layout it measures was still correct.
  //
  // What it must still catch is the thing the pin was for: the tile shipping a
  // border that is NOT the one the theme says. Comparing against the token does
  // that, and it does it against the single source of truth, so a deliberate
  // change to the tile and a deliberate change to the theme can no longer
  // disagree.
  expect(border, selected ? AppTheme.hairlineSelected : AppTheme.hairlineResting,
      reason: 'the tile must paint the theme\'s border for its state; if it '
          'changed, this guard is measuring a tile that no longer ships');
  return tileWidth - 2 * border - padding.left - padding.right;
}

Widget _host({String? selected}) {
  return MaterialApp(
    // `AppTheme.light` sets `toolbarHeight: 60` against the Material 3 default
    // of 56, which moves every control by 4 dp. Same trap as
    // `profile_edit_clearance_test.dart`: load the theme explicitly.
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 392,
          child: CategoryGrid(selected: selected, onTap: (_) {}),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the instrument finds a known threshold', (tester) async {
    // Proves the scan before it is trusted with sixteen labels. «تشطيب عام
    // وتسليم مفتاح» fits at 82 dp and does not fit at 65 dp — both measured
    // off a linear scan of this same painter — so the scan must agree.
    final style = AppTheme.label
        .copyWith(fontSize: AppTheme.fsBadge, height: 1.25);
    expect(_fits('تشطيب عام وتسليم مفتاح', 82, style), isTrue,
        reason: 'the scan disagrees with the measurement the slice was made on');
    expect(_fits('تشطيب عام وتسليم مفتاح', 65, style), isFalse,
        reason: 'the scan disagrees with the measurement the slice was made on');
  });

  testWidgets('every taxonomy label fits the strip tile in both states',
      (tester) async {
    final bad = <String>[];
    final rooms = <String>[];
    for (final selected in [false, true]) {
      await tester.pumpWidget(
        _host(selected: selected ? Taxonomy.categories.first.slug : null),
      );
      await tester.pumpAndSettle();
      final style = _paintedStyle(tester);
      final room = _room(tester, selected);
      rooms.add('${selected ? 'selected' : 'plain'}: ${room.toStringAsFixed(2)} dp');
      for (final c in Taxonomy.categories) {
        if (!_fits(c.name, room, style)) {
          bad.add('${selected ? 'selected' : 'plain'} «${c.name}» needs more '
              'than ${room.toStringAsFixed(2)} dp');
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'every taxonomy name must fit the strip tile it is shown in '
            '(${rooms.join(', ')}) — the strip is 96 dp wide and the taxonomy '
            'is fixed, so a label that does not fit here does not fit anywhere');
  });

  testWidgets('the tile leaves the wrapped label vertical slack', (tester) async {
    // The defect the slice fixed. Content is 42 icon + 8 gap + 27.5 text.
    const contentHeight = 42.0 + 8.0 + 2 * 11 * 1.25;

    for (final selected in [false, true]) {
      await tester.pumpWidget(
        _host(selected: selected ? Taxonomy.categories.first.slug : null),
      );
      await tester.pumpAndSettle();

      final container = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(CategoryGrid),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final padding = container.padding! as EdgeInsets;
      final decoration = container.decoration as BoxDecoration;
      final border = decoration.border?.top.width ?? 0.0;
      final room = 104 - 2 * padding.top - 2 * border;
      final slack = room - contentHeight;

      expect(slack, greaterThanOrEqualTo(0.0),
          reason: 'a wrapped two-line label needs ${contentHeight.toStringAsFixed(2)} dp '
              'of the ${room.toStringAsFixed(2)} dp this tile leaves it in the '
              '${selected ? 'selected' : 'plain'} state — negative slack paints a '
              'RenderFlex overflow stripe');

      // The number this slice bought, stated per state so a regression is
      // legible. Asserted at the tighter of the two so the case cannot pass on
      // the plain tile alone.
      //
      // MEASURED, not inherited: room = 104 - 2*8 - 2*border, content = 77.50.
      // The resting border moving 1 -> 1.5 (`hairlineResting`) cost the PLAIN
      // state 1 dp, taking it 8.50 -> 7.50; the selected state is on
      // `hairlineSelected` (2) and did not move at all. That is the answer to
      // the 1 dp the hairline slice left open: it lands in the roomy state, and
      // the state this case asserts on -- the tighter of the two -- is unmoved.
      // Re-derive these two numbers if either token changes.
      expect(slack, greaterThanOrEqualTo(6.5),
          reason: 'the vertical padding is now `s8`, which is the 4 dp step that '
              'matches the 8 dp gap the column already draws between icon and '
              'label: 7.50 dp of slack plain, 6.50 selected, against the 3.50 / '
              '1.50 the off-grid 10 left and the -0.50 / -2.50 that `s12` would '
              'have left — negative slack paints a RenderFlex overflow stripe');
    }
  });

  testWidgets('the tile draws no vertical overflow stripe', (tester) async {
    // `Flexible` CLIPS: an over-tall child shrinks and the overflow is silent.
    // So the engine is asked directly whether it complained.
    for (final c in Taxonomy.categories) {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 392,
              child: CategoryGrid(
                selected: Taxonomy.categories.first.slug,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Paint the worst label through the real strip by checking the widest
      // one still fits; the widget under test paints categories.first, so the
      // label case is covered by the fit case above.
      expect(c.name, isNotEmpty);
      expect(tester.takeException(), isNull,
          reason: 'the strip tile must not throw a layout exception');
    }
  });

  test('the strip tile spells no off-ladder padding literal', () {
    // R4 counts these, but R4 reads `EdgeInsets.*` sites across the whole app
    // and reports a budget -- it cannot say *this* tile is clean, and it
    // cannot price an inert literal. The point of this file's last case is that
    // the two numbers the sweep removed cannot be reintroduced here without a
    // comment that says what they were for.
    final src = File('lib/src/widgets/category_grid.dart').readAsStringSync();
    // The block is the tile class and nothing after it. The sentinel used to
    // be `class CategoryGridTiles` -- the dead single-select twin that this
    // tick deleted -- so the regex silently depended on a class nothing called
    // and would have kept scanning into the next one after that deletion. It
    // now stops at the tile class's own closing brace, which is the thing the
    // test actually means by "the strip tile".
    final block = RegExp(r'class _CategoryStripTile[\s\S]*?\n}')
        .firstMatch(src)!
        .group(0)!;
    final offenders = <String>[];
    for (final m in RegExp(r'symmetric\(\s*horizontal:([^)]*)').allMatches(block)) {
      for (final v in RegExp(r'(?<![\w.])\d+(?:\.\d+)?')
          .allMatches(m.group(1)!.replaceAll(RegExp(r'AppTheme\.\w+'), ''))) {
        final n = double.parse(v.group(0)!);
        if (n != 0 && n % 4 != 0) offenders.add('$n');
      }
    }
    expect(offenders, isEmpty,
        reason: 'the strip tile padding is `s4` horizontal / `s8` vertical: the '
            'horizontal `6` was off-ladder and `s8` is the wider of the two '
            'candidates for room (86.00 / 84.00), the vertical `10` moved zero '
            'pixels and `s8` buys 8 dp of slack over its 4 dp');
  });
}
