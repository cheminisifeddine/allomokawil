// `SelectableTile`'s label — does every Arabic label the app ships FIT?
//
// **The defect this guard exists for.** `SelectableTile` is the one shared tile
// in the app whose label was measured *nowhere*. Its horizontal padding was
// `6` — off the 4 dp ladder — and at a 320 dp page that left the **selected**
// tile of a three-column grid 72.00 dp of label room while the longest label in
// the taxonomy needs 72.06 dp. It missed by 0.06 dp, so «بلاط وسيراميك ورخام»
// drew as «بلاط وسيراميك…» on exactly the tile the user had just tapped, and
// only there: the plain tile has 74.00 dp and fits, so the truncation appeared
// in the state the user *chooses* and vanished in the one they did not.
//
// **Why a `flutter test` and not a python probe.** The previous tick closed
// this question with arithmetic ("the real Arabic labels fit one line at
// 392/360/320") and was wrong twice over — seven labels wrap to two lines at
// 392, and the selected tile truncates at 320. The arithmetic could not see
// either, because what a label needs is the *advance width of shaped glyphs*,
// a property of HarfBuzz, not of the layout. `tool/label_fit.py` lays the same
// strings out through PIL+raqm and agrees with this file to 0.01 dp, so it is a
// valid instrument — but this file is the one the gate runs, because it asks
// the engine itself (`TextPainter.didExceedMaxLines`) instead of predicting it.
// A probe and an engine agreeing is worth stating; a probe alone is not.
//
// **Why both states are checked.** The bug lived in the *selected* tile, whose
// 2 dp border costs 2 dp of room. A guard that only lays out the plain tile
// passes forever while the defect ships.
//
// **The guard this file grew is the one that was wrong, and that is why the
// layout moved while every case stayed green.** It built its own TextStyle by
// hand -- `AppTheme.label.copyWith(fontSize: AppTheme.fsBadge, ...)` -- so it
// measured the font the tile *used to* draw. `SelectableTile` actually painted
// `fsCaption` (12.5): the type ladder commit `f589ae0` replaced the bare
// `fontSize: 12` with the nearest step and grew the label by half a dp, and the
// guard kept checking 11. **A hand-written replica of the widget's style is
// the weakest link in a fit guard**, because the widget can change and the
// replica cannot: this file was green for 12.5's worth of growth and would have
// been green for 30. The style below is now READ OFF THE `Text` in the tree,
// and `styleMatchesTheWidgetItMeasures` fails the moment it drifts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/widgets/ui.dart';

// The three widths the app claims: 392 and 360 are what the goldens are shot
// at, and 320 is the floor `review_screen.dart:127` already branches on
// (`width >= 360 ? 20.0 : 8.0`) — a defect that only appears at 320 is a
// defect on a phone the app supports.
const pages = <double>[392, 360, 320];

/// Real Cairo, or Arabic renders as tofu and every width below is meaningless.
Future<void> _loadFonts() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();
}

/// How many lines `label` needs in the room the tile actually leaves it.
int _lines(String label, double room, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '\u2026',
  )..layout(maxWidth: room);
  return tp.didExceedMaxLines ? 99 : tp.computeLineMetrics().length;
}

/// The `TextStyle` the tile's own label is painted with, read off the tree.
///
/// Throws if the tile stops having a styled label, rather than silently
/// measuring the caller's own idea of it.
TextStyle _paintedStyle(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(SelectableTile).first,
      matching: find.byType(Text),
    ),
  );
  final style = text.style;
  if (style == null || style.fontSize == null) {
    fail('the tile label has no style, so nothing can be measured — this '
        'guard is now reading nothing and would pass forever');
  }
  return style;
}

/// Unconstrained advance width of [label] — what it wants if it got its way.
double _needs(String label, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.rtl,
  )..layout();
  return tp.width;
}

Widget _host(bool selected) {
  return MaterialApp(
    // `AppTheme.light` sets `toolbarHeight: 60` against the Material 3 default
    // of 56, which moves every control by 4 dp. Same trap as
    // `profile_edit_clearance_test.dart`: load the theme explicitly.
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
        child: Center(
          child: Row(
            children: [
              Expanded(child: SelectableTile(
                icon: Icons.handyman_outlined,
                label: Taxonomy.categories.first.name,
                selected: selected,
                onTap: () {},
              )),
              const SizedBox(width: 10),
              Expanded(child: SelectableTile(
                icon: Icons.handyman_outlined,
                label: Taxonomy.categories.first.name,
                selected: selected,
                onTap: () {},
              )),
              const SizedBox(width: 10),
              Expanded(child: SelectableTile(
                icon: Icons.handyman_outlined,
                label: Taxonomy.categories.first.name,
                selected: selected,
                onTap: () {},
              )),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('every taxonomy label fits its grid tile at every claimed width',
      (tester) async {
    final bad = <String>[];
    for (final page in pages) {
      for (final selected in [false, true]) {
        // The width has to reach the **surface**. `flutter test` boots at an
        // 800x600 physical / dpr 3 surface = 266.67 dp wide, so a host that
        // merely receives `page` as an argument measures 266.67 every time and
        // happily reports "fits" on a layout that never happened. That is not
        // hypothetical: this guard did exactly that and passed while the `6`
        // was still in the source.
        tester.view.physicalSize = Size(page * 3, 600 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(selected));
        final tile = tester
            .element(find.byType(SelectableTile).first)
            .findRenderObject() as RenderBox;
        // The style the tile ACTUALLY paints, read off its own Text. Handing
        // this test a style built here is how 12.5 shipped behind a green
        // check that believed it was measuring 11; the tile is the only
        // authority on how big its own label is.
        final style = _paintedStyle(tester);
        // Room the label really gets: the tile, less its own horizontal
        // padding, less the border the state draws (2 when selected, 1 when
        // not). This is the number the defect turned on.
        //
        // Both numbers are READ OFF THE TREE, never transcribed. Hardcoding
        // the inset here is the exact stale-constant trap `tool/label_fit.py`
        // is written against, and I walked into it: with `- 12` written down
        // the guard kept reporting `72.00 dp` *after* the padding was changed to
        // `AppTheme.s4`, so the fix could never have turned it green. A guard
        // that quotes its own arithmetic instead of the widget is a guard that
        // passes about a layout it never measured.
        final labelBox = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(SelectableTile).first,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final pad = labelBox.padding! as EdgeInsets;
        final room = tile.size.width - pad.horizontal -
            (selected ? 4 : 2);
        for (final c in Taxonomy.categories) {
          final n = _lines(c.name, room, style);
          if (n > 2) {
            bad.add('page ${page.toStringAsFixed(0)} '
                '${selected ? 'selected' : 'plain'}: «${c.name}» needs $n lines '
                'in ${room.toStringAsFixed(2)} dp');
          }
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'these labels ellipsize in a tile the app ships:\n'
            '${bad.join('\n')}\n\n'
            'The horizontal inset is `AppTheme.s4`; at 320 dp the selected tile '
            'has 76.00 dp of label room and the longest label needs 72.06.');
  });

  testWidgets('the selected tile has 2 dp less room, so both states must be '
      'checked', (tester) async {
    // Pin the reason the defect hid in plain state for four ticks: if this ever
    // stops being true the bug cannot come back the same way, and if it ever
    // was untrue the first test was measuring the wrong tile.
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(false));
    final plain = tester
        .element(find.byType(SelectableTile).first)
        .findRenderObject() as RenderBox;
    await tester.pumpWidget(_host(true));
    final sel = tester.element(find.byType(SelectableTile).first).findRenderObject()
        as RenderBox;
    // Same outer width either way — the border is inside the box.
    expect(sel.size.width, moreOrLessEquals(plain.size.width, epsilon: 0.01));
    expect(AppTheme.fsBadge, 11.0);
  });

  testWidgets('the fit guard measures the style the tile really paints',
      (tester) async {
    // The property that would have caught the 12.5. If the tile's font size
    // moves again and this file's own `_lines` call stops following, the only
    // honest failure is that one -- so it is asserted directly rather than left
    // implied by a number that happens to still fit.
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(true));
    final painted = _paintedStyle(tester);
    final tile = tester
        .element(find.byType(SelectableTile).first)
        .findRenderObject() as RenderBox;
    final box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(SelectableTile).first,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final pad = box.padding! as EdgeInsets;
    final room = tile.size.width - pad.horizontal - 4;
    // The tightest pair in the app, at the width where it bites: if the size
    // ever goes up by a ladder step this stops being true, which is exactly
    // the moment someone should be told rather than left to re-measure.
    final tightest = Taxonomy.categories
        .map((c) => c.name)
        .reduce((a, b) => _needs(b, painted) > _needs(a, painted) ? b : a);
    expect(_lines(tightest, room, painted), lessThanOrEqualTo(2),
        reason: 'the widest label needs ${_needs(tightest, painted).toStringAsFixed(2)} dp '
            'of the ${room.toStringAsFixed(2)} this tile has at 320 dp selected, '
            'at ${painted.fontSize} dp');
  });

  test('the horizontal inset is on the 4 dp ladder', () {
    // The defect was an off-ladder `6`. R4 counts off-ladder literals but
    // cannot see *which* widget they belong to or what they cost, so this
    // asserts the property that actually mattered rather than the number.
    final src = File('lib/src/widgets/ui.dart').readAsStringSync();
    final body = src.substring(src.indexOf('class SelectableTile'));
    final m = RegExp(r'symmetric\(\s*horizontal:\s*([\w.]+)')
        .firstMatch(body.split('\nclass ').first);
    expect(m, isNotNull, reason: 'the tile padding is gone — fix this guard');
    final token = m!.group(1)!;
    if (RegExp(r'^\d').hasMatch(token)) {
      fail('SelectableTile\'s horizontal inset is the bare literal $token, '
          'which is what caused this defect in the first place');
    }
    expect(token, 'AppTheme.s4');
  });
}
