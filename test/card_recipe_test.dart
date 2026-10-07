// One card recipe, one shape, and a guard that fails the build when a screen
// drifts back to "radius 14 here, 13 dp of inset there".
//
// Why this is a test and not a taste call: the same card was being drawn by
// hand in 20 files — three radii, six insets, four of them with a border that
// was the theme's but typed out again. Nobody reading a screen file could tell
// which numbers were the design and which were an accident. So the recipe is
// asserted twice: once as values (the tokens), once as pixels (a raster of a
// real AppCard), and once as source text (no screen may hand-roll the recipe).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/ui.dart';

// Lowered 164 -> 140 on 6 Oct: `project_new_screen.dart` went 24 -> 0.
// The file was not one list inset but four edge systems, and the two modal
// picker sheets disagreed with themselves (a search field at 18 over a list at
// 12, and a count line at 6). Counting literals is a text ratchet; the
// geometry guard that would have caught the disagreement is
// `test/project_new_edges_test.dart`.
// Lowered 101 -> 85 on 6 Oct: `customer_home_screen.dart` went 14 -> 2, and
// the two that remain are not column edges. Unlike the last three slices, this
// screen's column **agreed** at HEAD — but by coincidence: six writers had
// each typed their own `18` while the one band already using `AppTheme.gutter`
// agreed with the five that did not. R4 cannot tell agreement from
// disagreement, so this slice's real work is the geometry guard, not the count:
// `test/customer_home_column_test.dart`.
// Lowered 85 -> 81 on 6 Oct: `ui.dart` went 11 -> 9, and — for the first time
// in this sweep — the file with the **most** literals is not a screen at all.
// It is the shared widget kit, so the sweep's standing question ("is it one
// column or several?") does not apply: a widget with 25 callers has no column
// of its own. The question that *does* apply is which caller's column would
// break if one inset moved, and the answer was that all 25 inherited a 2 dp
// optical guess typed in `SectionTitle` since the design overhaul. The other
// two sites are renames to `gutter` — zero pixels by construction.
// What is left is mostly proportional: chip and pill padding, and the vertical
// `10` on `SectionTitle` that is the arithmetic keeping a 56 dp tap target
// inside its band (`tap_target_test.dart` measures that floor). Those are named
// proportions, not column edges, and this ratchet is counting them.
// `test/section_title_edge_test.dart` guards the horizontal.
// Lowered 81 -> 77 on 6 Oct: the auth form took the house field inset, and the
// phone field moved WITH it — the column was one system, not two, and sweeping
// `authInput` alone would have *created* the 2 dp disagreement the slice was
// removing. `authInput` and `DzPhoneField` had both spelled
// `symmetric(horizontal: 14, vertical: 18)` while `AppTheme.fieldPad` is
// `horizontal: s16`, so the first screen of the install was 2 dp narrower than
// every field the user is shown afterwards. The three fields agreed with each
// other, which is why R4 could not see it: the fix was "literal -> identifier"
// and `_literals()` skips identifiers by design. `test/auth_field_inset_test.dart`
// reads the padding now.
//
// The vertical `18` was left alone on purpose and is **still counted**, so this
// file now holds 8 of auth's 10. 18x2 + a ~15.5 dp body line is what carries
// those fields past `AppTheme.tapMin` = 56, and `tap_target_test.dart` +
// `tool/tap_target_audit.py` measure that floor for this row. That is the
// urgency-pill lesson from the `project_new` slice, and it is why a ratchet that
// counts tap-floor arithmetic is not wrong, only blunt.
// Lowered 77 -> 68 on 6 Oct: `worker_profile_screen.dart` went 9 -> 0, and four
// of its nine were not a drifted screen at all - two were `fromLTRB(18, 8, 18,
// 28)`, byte-identical to `AppTheme.pagePad`, a token two other files already
// call by name. So this file is the **first slice whose sites were mostly
// renames** and the count barely moved the design at all: a pixel test would
// have been the wrong instrument for most of it.
// The one number in the slice that was really a gap, `bottom: 10` between
// review cards, moved to `s12` with its skeleton twin, and the `7` in the
// rating pill to `s8`. Both were checked for a gesture detector first - the
// rule the `auth` slice wrote down, since that is what separates a real gap
// from the tap-floor arithmetic this ratchet also counts.
// `test/worker_profile_column_test.dart` guards the column, and its load-bearing
// assertion compares the loading frame against the loaded body **in the same
// test**, because two hand-typed constants drift apart silently.
// The ninth slice took it to 60 (`profile_screen`, 8 sites) and the three
// numbers it could not express through R4 all live in
// `test/account_column_test.dart` - see that file for why a count of 68 -> 60
// understates what was wrong here.
// Lowered 60 -> 51 on 6 Oct: the tenth slice, and the first one whose defect
// R4 could not see AT ALL - the trade strip that filters the browse list sat
// 4 dp outside that list, on a `14` living in `trade_filter_bar.dart` while
// the list read `18` in `browse_screen.dart`. A ratchet counts literals per
// file; it cannot compare two numbers in two files, and both went green the
// moment they became identifiers. So this slice's real work is
// `test/browse_column_test.dart`, and the count is the least interesting part
// again - but it fell to 51, not to the 53 the slice was planned for, because
// the pill's own `symmetric(horizontal: 14, vertical: 12)` stayed: that is the
// inside of a chip, a proportion rather than a column edge, and moving it
// would resize all sixteen trade pills to satisfy a counter.
// Lowered 51 -> 46 on 7 Oct: the eleventh slice, `auth_screen`, and the count
// fell by five rather than the eight its sites suggested. Three of the five
// were the kind this ratchet is worst at — `fromLTRB(18, 4, 18, 24)` and
// `fromLTRB(10, 8, 18, 4)` typed a correct `18` that `AppTheme.gutter` already
// names, so the sweep renamed numbers that were never wrong. The real defect
// was in the *second* number of the top bar: its end edge was 10 where the form
// under it was 18, an 8 dp disagreement between two rows R4 cannot compare
// because it counts literals per file and both became identifiers in the same
// commit. `test/auth_page_column_test.dart` is what holds that seam; the count
// is again the least interesting part.
//
// What stayed, and why. `auth_screen` keeps 3 of its 8:
//   * the mode switch's interior, now `AppTheme.s4` swept together with its own
//     5 dp segment gap so the two cannot disagree — the switch is a component,
//     and its 5 was a proportion inside it, not a column edge;
//   * `symmetric(horizontal: 2, vertical: 6)` on the remember row, which is the
//     tap-floor arithmetic `tool/tap_target_audit.py` settles by hand at
//     48 + 6x2 = 60;
//   * `symmetric(horizontal: 14, vertical: 12)` on `AuthNotice`, which was
//     called byte-identical to `chipTheme.padding`, the trade pill and one
//     banner in `project_detail_screen` — "four writers spelling one chip
//     inset". **That reading was wrong and the sixteenth slice corrected it:
//     `chipTheme` renders nothing at all** (no Material chip exists anywhere
//     in the app), so the number was shared by three *unrelated* components —
//     a red error banner (`rMd` + border), a pale amount panel (`rSm`, no
//     border) and a tappable filter pill (`rPill` + border). A token over all
//     three would have been three renames and zero pixels. `chipTheme` is now
//     deleted and the three keep their own insets, on purpose.
//
// Lowered 46 -> 40 on 8 Oct: the twelfth slice, `ui.dart`, and **`ui.dart` no
// longer appears in R4's list at all** — first file in the sweep to be fully
// off the counter, including its `SectionTitle` band, which is deliberate and
// argued below rather than swept.
//
// The count moved by six, not by the seven the sites implied, and the missing
// one is the whole point of the slice. The defect R4 could not see was `5`:
// `StatusPill`, `CategoryBadge` and the project page's `MetaChip` all spelled
// `symmetric(horizontal: 10, vertical: 6)` byte for byte and then disagreed
// on the gap between the icon and the word — two writers used `6`, this one
// used `5`. So the three files' ratchet rows were **identical and both green**
// while the pills drew 1 dp apart from each other, adjacent, on the worker's
// filter strip and the project page. Counting literals per file is blind to a
// disagreement *between* files by construction; a token makes it impossible and
// `test/pill_inset_test.dart` holds it there. The sixth swept literal is the
// `5` that became `pillGap`, and the three that answered to `pillPad` cost
// nothing but the six: the seventh was `SectionTitle`'s vertical `10`, which
// is tap arithmetic (`10 + 56 + 4`) and stays counted and recorded.
//
// What stayed, and why. `SectionTitle` keeps its band
// `fromLTRB(0, 10, 0, 4)` unchanged: the horizontal is already `0` and the
// vertical `10` is off-grid on purpose, because it is the arithmetic that
// holds a 56 dp action inside a 70 dp band. Re-gridding it would move every
// heading on eight screens to settle a question that is not this tick's.
// Lowered 40 -> 35 on 8 Oct: the thirteenth slice, `profile_edit_screen`, and
// the first slice where **the counter moved less than the defect** by exactly
// the amount it was built to miss. Three literals retired — `30` and the two
// `18`s — for a visible correction of **24 dp**.
//
// The page column read `EdgeInsets.fromLTRB(18, 4, 18, 30)` and then ended
// its children with `SizedBox(height: 22)`. The clearance under the last
// control was `30 + 22 = 52 dp` against **28** on the three sibling screens
// that pin the identical save bar, so the contractor's last input sat a hand's
// width further from the button than the same button on the screen he came
// from. The horizontal `18` was measured identical to that bar's own inset and
// became `AppTheme.gutter` by rename.
//
// **R4 could not have caught the `22`.** It reads literals inside `EdgeInsets`
// constructors, and a `SizedBox` is not an `EdgeInsets`: the counter was
// measuring one of two writers for a quantity neither of them owned. It also
// went green the instant `30` became `s28`, because `_literals()` skips
// identifiers by design — the same blind spot the `auth_screen` slice paid a
// whole tick for. `test/profile_edit_clearance_test.dart` asserts the laid-out
// clearance against the token instead, which is the thing the counter
// structurally cannot express.
// Lowered 24 -> 23 on 7 Oct: `empty_state.dart`'s `LoadingList` went from
// `EdgeInsets.all(18)` to `AppTheme.pagePad`, and that is the only count this
// slice moved. It is also the slice where R4's decrement is the *least* of
// what happened: the `18` was not wrong on the gutters — it agreed with
// `pagePad` there only because `gutter` happens to be 18 — and the two edges
// that actually differed were `8` and `28`, which R4 never read because they
// were spelled as an identifier in the token and never appeared in the source
// at all. So the literal that left is the one that was never the defect, and
// the defect was a pair of numbers this ratchet cannot see. Same shape as
// slice 14 (`chat_screen`'s `3`) and slice 15 (`auth_screen`'s `2`), and the
// third time the same lesson: the count goes down, and what it means is
// carried by `test/loading_list_column_test.dart`, which reads the skeleton's
// real card rect off the built tree and compares it to the token.
// fourth time the same lesson, and the second slice in a row where the literal
// that left was the ONLY thing wrong in the diff. `detect_location.dart`'s
// `DetectedPlaceNote` sat its Arabic sentence a single ladder step under the
// control it explains, while the budget row on that same form -- the same
// icon / gap / caption line, explaining the same kind of value to the same
// reader -- sat one step lower. R4 priced the note at exactly the same weight
// as its sibling's four defended and deliberate sites (the trade filter's
// `14 x 12`, the checkbox row's `6 x 2`), because a ratchet over literals
// cannot tell an unexplained value from an explained one.
// `test/detected_note_column_test.dart` reads the note's real band off the
// built tree and asserts the gap against `AppTheme.s8`.
//
// And once more, the count is the *least* of it: 16 -> 15 is one number in a
// text sweep, and what it stands for is a measurement that failed first, in
// the engine's own numbers, at `Expected: <8.0>  Actual: <6.0>`.
const int _offGridBudget = 14;

List<File> _sources() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return const <File>[];
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The text of the balanced `(...)` starting at [open] (the index of `(`).
String _balanced(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) return s.substring(open, i + 1);
    }
  }
  return s.substring(open);
}

/// A call's own arguments — nested children's arguments are not the call's.
List<String> _topLevelArgs(String s, int open) {
  final body = _balanced(s, open);
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  for (var i = 1; i < body.length - 1; i++) {
    final c = body[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  if (buf.toString().trim().isNotEmpty) parts.add(buf.toString().trim());
  return parts;
}

/// Numeric literals in [body]. `AppTheme.s16` is an identifier, not a 16.
Iterable<double> _literals(String body) sync* {
  for (final m
      in RegExp(r'[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?').allMatches(body)) {
    final t = m.group(0)!;
    if (RegExp(r'^[A-Za-z_]').hasMatch(t)) continue;
    yield double.parse(t);
  }
}

int _lineOf(String s, int index) => s.substring(0, index).split('\n').length;

void main() {
  group('the recipe is one set of values', () {
    test('one radius: 20, named once', () {
      expect(AppTheme.cardRadius, AppTheme.rLg);
      expect(AppTheme.cardRadius, 20);
      expect(AppTheme.rXs, 6);
      expect(AppTheme.rSm, 12);
      expect(AppTheme.rMd, 16);
      expect(AppTheme.rLg, 20);
      expect(AppTheme.rXl, 28);
      expect(AppTheme.rPill, 999);
    });

    test('one fill, one hairline, no shadow', () {
      expect(AppTheme.cardFill, AppTheme.surface);
      expect(AppTheme.cardLine, AppTheme.line);
      expect(AppTheme.cardLineWidth, 1);
      expect(AppTheme.cardShadow, isEmpty,
          reason: 'a drop shadow on this canvas is a grey smear; the hairline '
              'border does the separating');
    });

    test('three insets, all off the same 4 dp ladder', () {
      expect(AppTheme.cardPad, const EdgeInsets.all(16));
      expect(AppTheme.cardPadRail, const EdgeInsets.all(12));
      expect(AppTheme.cardPadRows,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
      for (final v in <double>[
        AppTheme.s4,
        AppTheme.s8,
        AppTheme.s12,
        AppTheme.s16,
        AppTheme.s20,
        AppTheme.s24,
        AppTheme.s28,
        AppTheme.s32,
      ]) {
        expect(v % 4, 0, reason: '$v is off the grid');
      }
      expect(AppTheme.cardPad, const EdgeInsets.all(AppTheme.s16));
      expect(AppTheme.cardPadRail, const EdgeInsets.all(AppTheme.s12));
      expect(AppTheme.cardPadRows.left, AppTheme.s16);
      expect(AppTheme.cardPadRows.right, AppTheme.s16);
      expect(AppTheme.cardPadRows.top, AppTheme.s8);
      expect(AppTheme.cardPadRows.bottom, AppTheme.s8);
    });

    test('the decoration getter is the recipe', () {
      final d = AppTheme.cardDecoration;
      expect(d.color, AppTheme.cardFill);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      expect(d.boxShadow, isEmpty);
      final b = d.border! as Border;
      expect(b.top.color, AppTheme.cardLine);
      expect(b.top.width, AppTheme.cardLineWidth);
    });

    test('a tinted card keeps the shape and only moves the colour', () {
      final d = AppTheme.cardDecorationOf(
          fill: AppTheme.dangerWash, border: AppTheme.danger);
      expect(d.color, AppTheme.dangerWash);
      expect((d.border! as Border).top.color, AppTheme.danger);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius),
          reason: 'the danger banner is still a card, not a new shape');
      expect(d.boxShadow, isEmpty);
    });
  });

  group('AppCard builds the recipe', () {
    testWidgets('default card: recipe fill, hairline, radius, cardPad',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(child: AppCard(child: Text('مرحبا'))),
        ),
      ));

      final container = tester.widget<Container>(find
          .descendant(
              of: find.byType(AppCard), matching: find.byType(Container))
          .first);
      expect(container.padding, AppTheme.cardPad);
      final d = container.decoration! as BoxDecoration;
      expect(d.color, AppTheme.cardFill);
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      expect((d.border! as Border).top.color, AppTheme.cardLine);
      expect((d.border! as Border).top.width, AppTheme.cardLineWidth);
      expect(d.boxShadow, isEmpty);
    });

    testWidgets('a tappable card is the same shape', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppTheme.bg,
          body: Center(
            child: AppCard(onTap: () => taps++, child: const Text('افتح')),
          ),
        ),
      ));
      final container = tester.widget<Container>(find
          .descendant(
              of: find.byType(AppCard), matching: find.byType(Container))
          .first);
      final d = container.decoration! as BoxDecoration;
      expect(d.color, AppTheme.cardFill,
          reason: 'the tap target must not change the paint');
      expect(d.borderRadius, BorderRadius.circular(AppTheme.cardRadius));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('rasterises as one surface with one hairline', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: key,
          child: const ColoredBox(
            color: AppTheme.bg,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 180,
                child: AppCard(child: Text('بطاقة')),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      late final int fillPx, linePx, bgPx;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final px = data!.buffer.asUint8List();
        var fill = 0, line = 0, bg = 0;
        // The modern accessors are 0..1 doubles; the raster is 0..255 bytes.
        bool near(int i, Color c) {
          final r = (c.r * 255).round();
          final g = (c.g * 255).round();
          final b = (c.b * 255).round();
          return (px[i] - r).abs() <= 4 &&
              (px[i + 1] - g).abs() <= 4 &&
              (px[i + 2] - b).abs() <= 4;
        }

        for (var i = 0; i < px.length; i += 4) {
          if (near(i, AppTheme.cardFill)) fill++;
          if (near(i, AppTheme.cardLine)) line++;
          if (near(i, AppTheme.bg)) bg++;
        }
        fillPx = fill;
        linePx = line;
        bgPx = bg;
        image.dispose();
      });

      expect(bgPx, greaterThan(1000), reason: 'the canvas is behind the card');
      expect(fillPx, greaterThan(30000),
          reason: 'the card body really paints the recipe fill');
      expect(linePx, greaterThan(0),
          reason: 'the hairline really paints — a borderless card would read '
              'as a hole in the page');
      expect(linePx * 20, lessThan(fillPx),
          reason: 'the border is a hairline, not a frame');
    });
  });

  group('no screen hand-rolls the recipe', () {
    final sources = _sources();

    test('the guard can see the app', () {
      expect(sources, isNotEmpty,
          reason:
              'run from the package root — test/card_recipe_test.dart reads '
              'lib/ as text');
      expect(sources.any((f) => f.path.endsWith('app_theme.dart')), isTrue);
    });

    test('R1 — a radius is named, never typed', () {
      final offenders = <String>[];
      for (final f in sources) {
        final s = f.readAsStringSync();
        for (final m
            in RegExp(r'BorderRadius\.circular\(\s*\d+\s*\)').allMatches(s)) {
          offenders.add('${f.path}:${_lineOf(s, m.start)} ${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'use AppTheme.rSm / rMd / rLg / rXl / rPill:\n'
              '${offenders.join('\n')}');
    });

    test('R2 — a surface card has one definition', () {
      final offenders = <String>[];
      final lookup = RegExp(r'BoxDecoration\(');
      for (final f in sources) {
        if (f.path.endsWith('app_theme.dart') || f.path.endsWith('ui.dart')) {
          continue;
        }
        final s = f.readAsStringSync();
        for (final m in lookup.allMatches(s)) {
          final block = _balanced(s, m.end - 1);
          if (RegExp(r'color:\s*AppTheme\.(surface|cardFill)\s*,')
                  .hasMatch(block) &&
              RegExp(r'borderRadius:\s*BorderRadius\.circular\(')
                  .hasMatch(block) &&
              RegExp(r'Border\.all\(\s*color:\s*AppTheme\.(line|cardLine)\b')
                  .hasMatch(block)) {
            offenders.add('${f.path}:${_lineOf(s, m.start)}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'this is AppTheme.cardDecoration (or cardDecorationOf with '
              'named overrides) — a screen that rebuilds it drifts:\n'
              '${offenders.join('\n')}');
    });

    test('R3 — every AppCard inset comes from the recipe', () {
      const allowed = <String>[
        'padding:AppTheme.cardPad',
        'padding:AppTheme.cardPadRail',
        'padding:AppTheme.cardPadRows',
        'padding:AppTheme.fieldPad',
        'padding:EdgeInsets.zero',
      ];
      final offenders = <String>[];
      for (final f in sources) {
        if (f.path.endsWith('ui.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in RegExp(r'AppCard\(').allMatches(s)) {
          for (final arg in _topLevelArgs(s, m.end - 1)) {
            if (!arg.startsWith('padding:')) continue;
            final flat = arg.replaceAll(RegExp(r'\s+'), '');
            if (!allowed.any(flat.startsWith)) {
              offenders.add('${f.path}:${_lineOf(s, m.start)} $flat');
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'cardPad / cardPadRail / cardPadRows, nothing else:\n'
              '${offenders.join('\n')}');
    });

    test('R4 — off-grid literal spacing has not gone up', () {
      var offGrid = 0;
      final sites = <String>[];
      final lookup =
          RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB|fromSTEB)\(');
      for (final f in sources) {
        if (f.path.endsWith('app_theme.dart')) continue;
        final s = f.readAsStringSync();
        for (final m in lookup.allMatches(s)) {
          final body = _balanced(s, m.end - 1);
          for (final v in _literals(body)) {
            if (v != 0 && v % 4 != 0) {
              offGrid++;
              sites.add('${f.path}:${_lineOf(s, m.start)} $v');
            }
          }
        }
      }
      expect(offGrid, lessThanOrEqualTo(_offGridBudget),
          reason: 'this number may only go down — it is the ratchet for the '
              'rest of the 8pt sweep (now $offGrid):\n'
              '${sites.take(12).join('\n')}');
    });

    // Added by the sixteenth slice. The `chipTheme` this file's own header
    // called "one of the four writers of 14 x 12" was consumed zero times, and
    // deleting it is only half the job: a deleted theme field is invisible, so
    // the next person to reach for a Material chip finds nothing to stop them
    // and the kit's own rule (top of `ui.dart`: chips inherit colour and
    // rendered white-on-white) has no machine check behind it. This is the
    // check that outlives the deletion.
    test('no Material chip has crept back in', () {
      // `Chip(` matches the bare widget too, so it is the whole family.
      final banned = RegExp(
          r'\b(?:RawChip|Chip|CustomChip|ChoiceChip|FilterChip|ActionChip|'
          r'InputChip)\s*\(');
      final offenders = <String>[];
      for (final f in sources) {
        final s = f.readAsStringSync();
        // Comments are how this app *documents* the ban — the kit header and
        // `trade_filter_bar` both say "deliberately NOT a ChoiceChip". Only
        // code counts, so blank out comments and keep every line break, which
        // is what makes `line` below still point at the real source line. A
        // strip that *removed* the newlines would report a plausible line for
        // the wrong piece of code, which is worse than no line at all.
        final lines = s.split('\n');
        final code = <String>[];
        var inBlock = false;
        for (final line in lines) {
          if (inBlock) {
            final end = line.indexOf('*/');
            if (end < 0) {
              code.add('');
              continue;
            }
            inBlock = false;
            code.add(' ' * end + line.substring(end + 2));
            continue;
          }
          final open = line.indexOf('/*');
          final slash = line.indexOf('//');
          if (open >= 0 && (slash < 0 || open < slash)) {
            inBlock = !line.substring(open + 2).contains('*/');
            code.add(slash >= 0 && slash < open
                ? line.substring(0, slash)
                : line.substring(0, open));
            continue;
          }
          code.add(slash < 0 ? line : line.substring(0, slash));
        }
        final stripped = code.join('\n');
        for (final m in banned.allMatches(stripped)) {
          offenders.add('${f.path}:'
              '${stripped.substring(0, m.start).split('\n').length} '
              '${m.group(0)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'this app builds its own chips and the theme says so. A '
              'Material chip inherits colour and rendered white-on-white '
              'before — use ui.dart\'s CategoryBadge/StatusPill or '
              'TradeFilterBar\'s _FilterPill:\n'
              '${offenders.join('\n')}');
    });

    // Added by the eighteenth slice, for the defect R4 priced at zero.
    //
    // The site was `fromLTRB(18, 12, 18, 28)` in `chat_list_screen.dart` and
    // `verification_screen.dart`, byte-identical to each other. Three of the
    // four edges ARE the house column — `18` is `AppTheme.gutter` and `28` is
    // `AppTheme.s28` — and only the top one disagreed, by 4 dp, with
    // `AppTheme.pagePad`'s `s8`. So both screens' first row sat 4 dp below
    // every other page column in the app.
    //
    // R4 read this as four counted literals and reported a decrement, and the
    // decrement was **the number going down, not the column agreeing**. That is
    // the same blind spot the sixteenth slice found from the other side: once
    // a column is spelled `AppTheme.pagePad` it stops counting, so the ratchet
    // cannot see a new screen hand-typing one, or an existing screen drifting
    // a token's *meaning* by editing `pagePad` for itself. This is the check
    // that outlives the fix, and it is deliberately a census over the source
    // rather than a measurement: a rendered column needs a booted screen per
    // screen, and the thing that must not come back is the literal.
    test('R5 — no screen hand-types the page column', () {
      // `pagePad` is `fromLTRB(gutter, s8, gutter, s28)`. A screen that writes
      // those four numbers out has re-derived the column and can disagree with
      // it on any of them — which is exactly what happened on the top edge.
      //
      // Read by VALUE, not by spelling: matching `EdgeInsets.fromLTRB(18,`
      // would pass the day the ladder moves `gutter` to 20 and miss every
      // column that is now quietly 2 dp narrow. So the four edges are resolved
      // the same way `tool/label_fit.py` resolves tokens, and a hand-typed
      // column is reported against the token it shadows.
      final ladder = sources
          .firstWhere((f) => f.path.endsWith('app_theme.dart'))
          .readAsStringSync();
      double tok(String name) {
        final m = RegExp('static const double $name\\s*=\\s*([\\d.]+)')
            .firstMatch(ladder);
        if (m == null) {
          throw StateError('card_recipe: $name left the ladder — R5 is stale');
        }
        return double.parse(m.group(1)!);
      }

      final g = tok('gutter');
      final top = tok('s8');
      final bot = tok('s28');
      final offenders = <String>[];
      final lookup = RegExp(r'EdgeInsets\.fromLTRB\(');
      for (final f in sources) {
        if (f.path.endsWith('app_theme.dart')) continue;
        final s = f.readAsStringSync();
        // Comments are how this app documents *why* a number is what it is —
        // `worker_profile_screen.dart` keeps the old literal spelled out in a
        // comment above the token it became. Only code counts, so blank the
        // comments out while keeping every newline, which is what keeps the
        // reported line pointing at real source.
        final lines = s.split('\n');
        final code = <String>[];
        var inBlock = false;
        for (final line in lines) {
          if (inBlock) {
            final end = line.indexOf('*/');
            if (end < 0) {
              code.add('');
              continue;
            }
            inBlock = false;
            code.add(' ' * end + line.substring(end + 2));
            continue;
          }
          final open = line.indexOf('/*');
          final slash = line.indexOf('//');
          if (open >= 0 && (slash < 0 || open < slash)) {
            inBlock = !line.substring(open + 2).contains('*/');
            code.add(slash >= 0 && slash < open
                ? line.substring(0, slash)
                : line.substring(0, open));
            continue;
          }
          code.add(slash < 0 ? line : line.substring(0, slash));
        }
        final stripped = code.join('\n');
        for (final m in lookup.allMatches(stripped)) {
          final block = _balanced(stripped, m.end - 1);
          // Four plain numbers is the whole signature: any identifier in an
          // edge position is the screen composing a column deliberately
          // (`fromLTRB(12, 0, 12, 24)` is an inset inside a card, not a page).
          final nums =
              RegExp(r'(?<![\w.])[\d.]+(?![\w.])').allMatches(block);
          if (nums.length != 4) continue;
          final v = nums.map((e) => double.parse(e.group(0)!)).toList();
          // Right edge too — three of four agreeing is what made this defect
          // invisible, so a column is only reported when the gutter pair AND
          // the bottom both match the token and only the TOP drifted.
          if (v[0] == g && v[2] == g && v[3] == bot && v[1] != top) {
            offenders.add('${f.path}:'
                '${stripped.substring(0, m.start).split('\n').length} '
                'fromLTRB(${v.join(', ')}) — AppTheme.pagePad is '
                'fromLTRB($g, $top, $g, $bot)');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'use AppTheme.pagePad. A hand-typed column agrees with the '
              'token on three edges and disagrees on the fourth, which is '
              'invisible until the one number moves:\n'
              '${offenders.join('\n')}');
    });
  });
}
