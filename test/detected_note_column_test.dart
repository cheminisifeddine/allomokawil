// The GPS note is on the same column as the control it explains.
//
// Found on slice 29 (7 Oct 2026). `DetectedPlaceNote` is the quiet Arabic line
// that appears under «حدّد موقعي تلقائياً» once the phone's GPS has filled the two
// pickers above it: it says the wilaya was *detected*, never *chosen*, because a
// wilaya the app guessed must not look like one the user picked. It is painted
// as `Padding(EdgeInsets.only(top: <gap>))` around a row of `icon 15 / gap 6 /
// caption`.
//
// **The sibling it disagrees with is in the same screen, in the same column.**
// `project_new_screen.dart` explains a value the same way twice: the budget row
// (`SizedBox(height: 8)` then `icon 16 / gap 6 / caption`, under the two money
// fields) and this note (then `icon 15 / gap 6 / caption`, under the GPS
// button). One of those gaps is the house step off the 4 dp ladder and the other
// is a value one step under it, so on the one form that explains two different
// values to the same reader, the two explanations start at different heights.
//
// **Why R4 counted it and could not price it.** The ratchet in
// `test/card_recipe_test.dart` does read this literal -- it is one of the 16 --
// but it counts, it does not compare. A decrement proves a literal left; it does
// not prove the column agrees. The same blind spot as slice 28's phone-field
// error band and slice 27's tick: the fix is "literal -> identifier", and
// `_literals()` skips identifiers by design, so the ratchet goes green the
// instant the defect is gone and stays green if it comes back as a different
// number. What outlives the fix is below.
//
// **Every expectation is resolved from `AppTheme` or measured off the built
// tree, and no retired value is spelled anywhere** -- per
// `test/tile_label_fit_test.dart`'s stale-constant trap, and slice 23's rule
// that a comment quoting a retired off-grid literal is a live R4 count.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/location/locator.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/detect_location.dart';

const _place = DetectedPlace(
  wilayaId: '16',
  wilayaName: 'الجزائر',
  commune: 'باب الوادي',
  lat: 36.75,
  lng: 3.06,
  seatKm: 2.1,
  communeFromDevice: true,
);

/// The note on screen under a control, at the app's own logical size and RTL --
/// the direction every sentence on this screen is read in.
Future<void> _pumpNote(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 850 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: AppTheme.tapMin, color: AppTheme.surface),
              DetectedPlaceNote(place: _place),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The `Padding` that wraps the note's `Row`, scoped to the note's own icon so
/// a padded `Row` in another subtree cannot be read as this one.
Padding _noteBand(WidgetTester tester) {
  final padded = find
      .ancestor(
        of: find.byIcon(Icons.my_location_rounded),
        matching: find.byType(Padding),
      )
      .evaluate()
      .map((e) => e.widget)
      .whereType<Padding>();
  for (final p in padded) {
    if (p.child is Row) return p;
  }
  fail('the note carries no Padding of its own, so its gap is being set by '
      'something else and this guard is measuring the wrong box');
}

/// The note's own laid-out rect, RTL.
///
/// Measured off the **`Row` inside the band**, not the icon and not the
/// `Padding`: the `Padding` starts where the control ends, so reading it would
/// report a gap of zero no matter what the band says, and the icon is a 15 dp
/// glyph leading the row at the trailing edge, so its rect is the *text's* start
/// edge and not the row's. Both mistakes were made in the first run of this file
/// and are why it now names which box it reads.
Rect _noteRect(WidgetTester tester) {
  final row = find.descendant(
    of: find.byWidget(_noteBand(tester)),
    matching: find.byType(Row),
  );
  final box = tester.renderObject<RenderBox>(row);
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  group('the GPS note is on the control\'s own column', () {
    testWidgets('the gap under the control is the app\'s gap', (t) async {
      await _pumpNote(t);

      final control = t.getRect(find.byType(Container).first);
      final note = _noteRect(t);
      final gap = note.top - control.bottom;
      debugPrint('NOTE gap = $gap');

      // The other explanation on this screen -- the budget row under the two
      // money fields -- draws the same icon / gap / caption line and sits the
      // house step below its fields. Two explanations, one reader, one screen:
      // they start at the same height.
      expect(gap, AppTheme.s8,
          reason: 'the note explains the value in the control above it, so it '
              'sits one app gap below that control -- a second step means the '
              'two explanations on this form start at different heights');
    });

    testWidgets('the note is flush with the control it explains', (t) async {
      await _pumpNote(t);

      final control = t.getRect(find.byType(Container).first);
      final note = _noteRect(t);
      debugPrint('CONTROL ${control.left}..${control.right}   '
          'NOTE ${note.left}..${note.right}');

      // The band is inside the screen's column already, so it inherits the
      // column's width. A band that also pulls its own edge inside it moves the
      // Arabic sentence away from the control it is talking about.
      expect(note.left, control.left,
          reason: 'the sentence and the button it describes share one edge');
      expect(note.right, control.right, reason: 'and the far edge agrees');
    });

    testWidgets('the band moves itself down only', (t) async {
      await _pumpNote(t);

      final inset = _noteBand(t).padding as EdgeInsets;
      debugPrint('BAND = $inset');

      expect(inset.left, 0,
          reason: 'the note is inside the screen\'s column, so it inherits the '
              'column\'s width -- it must not pull its own edge inside it');
      expect(inset.right, 0, reason: 'the far edge must agree with the near one');
      expect(inset.top, AppTheme.s8,
          reason: 'the gap it does own is the app\'s gap, asserted as a token '
              'rather than a number so a future edit cannot drift it quietly');
    });
  });
}
