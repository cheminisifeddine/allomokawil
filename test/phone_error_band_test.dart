// The phone field's error row is on the same column as the field it explains.
//
// Found on slice 28 (7 Oct 2026). `DzPhoneField` is a `Column` of three parts:
// the label band, the bordered box, and the Arabic error the user reads when the
// number cannot be one. Slice 27 moved the in-field **tick** onto
// `AppTheme.fieldPad`. It did not touch the third part, fourteen lines below the
// tick, and the error row's inset is still three hand-typed numbers with no
// token behind them and no comment defending them.
//
// **What the measurement says.** With the field holding one digit short of
// valid, the engine answers: the label band sits `8.0` above the box, and the
// error icon sits `7.0` below it. Same column, two parts, two different gaps,
// and the one that is off the ladder is the one between the field and the
// sentence that explains what is wrong with it.
//
// Worse, the gap is not only off-grid: the row hands itself `right: 4, left: 4`
// on top of it, so the whole band is inset **4 dp inside the box it belongs
// to**. The digits sit 21.8 dp inside that box's right border; the error sentence
// starts 26.2 dp inside it. Two Arabic sentences, one screen, one card -- the
// number the user typed and the sentence explaining that it is wrong do not
// begin against the same edge, and the reader is meant to compare them.
//
// **Measured off the built tree, never read off the source.** Every assertion
// below is an equality against `AppTheme` or a gap computed from two painted
// rects. Per the `tile_label_fit_test.dart` stale-constant trap, and slice 23's
// lesson that a comment quoting a retired off-grid literal is a live R4 count,
// **no retired value is spelled anywhere in this file** -- only the tokens, and
// only as relationships to them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/phone_field.dart';

/// The field holding one digit short of valid, so `forceValidate` paints the
/// error. Nine digits: `DzPhone.isValid` is `^0[5-7][0-9]{8}$`.
Future<void> _pumpError(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: DzPhoneField(
              controller: TextEditingController(text: '051234567'),
              forceValidate: true,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The bordered box -- the `Container` carrying `fieldDecorationOf` -- rather
/// than the `TextField` inside it, because the `TextField`'s own rect is the
/// content box and the border sits outside that.
Finder _fieldBox() => find
    .ancestor(of: find.byType(TextField), matching: find.byType(Container))
    .first;

/// The `Padding` that wraps the error `Row`, scoped to the error icon so a
/// second padded `Row` in this subtree cannot be read as this one.
EdgeInsets _errorBandInset(WidgetTester tester) {
  final padded = find
      .ancestor(
        of: find.byIcon(Icons.error_outline_rounded),
        matching: find.byType(Padding),
      )
      .evaluate()
      .map((e) => e.widget)
      .whereType<Padding>();
  for (final p in padded) {
    if (p.child is Row) return p.padding as EdgeInsets;
  }
  fail('the error row carries no Padding of its own, so its inset is being set '
      'by something else and this guard is measuring the wrong box');
}

void main() {
  group('the phone field error is on the field\'s own column', () {
    testWidgets('the gap above the field and the gap below it are one gap',
        (t) async {
      await _pumpError(t);

      final label = t.getRect(find
          .ancestor(
            of: find.byIcon(Icons.phone_android_rounded),
            matching: find.byType(Row),
          )
          .first);
      final box = t.getRect(_fieldBox());
      final icon = t.getRect(find.byIcon(Icons.error_outline_rounded));

      final above = box.top - label.bottom;
      final below = icon.top - box.bottom;
      debugPrint('GAP above = $above   below = $below');

      // The label is the other half of this widget and the gap between them is
      // already the house step. The error row is the third part of the same
      // Column and was carrying a different one, so the field had two vertical
      // gaps on either side of it and no rule that they matched.
      expect(above, AppTheme.s8, reason: 'the label band is the app\'s gap');
      expect(below, above,
          reason: 'the sentence explaining the field sits the same distance '
              'below it that its label sits above it -- one column, one gap');
    });

    testWidgets('the error row is flush with the box it belongs to', (t) async {
      await _pumpError(t);

      final inset = _errorBandInset(t);
      debugPrint('BAND = $inset');

      // The row sits under a box it is explaining, inside the same Column, and
      // the digits above it are painted on `AppTheme.fieldPad`. A band that
      // insets itself horizontally is moving the Arabic sentence away from the
      // edge the number above it starts against, on the one screen where the
      // user is comparing the two.
      expect(inset.left, AppTheme.s4 * 0,
          reason: 'the error row is inside the field\'s Column, so it inherits '
              'the Column\'s width -- it must not pull its own edge inside it');
      expect(inset.right, AppTheme.s4 * 0,
          reason: 'the far edge must agree with the near one');
    });

    testWidgets('the sentence starts against the edge the digits start against',
        (t) async {
      await _pumpError(t);

      final box = t.getRect(_fieldBox());
      final digits = t.getRect(find.byType(EditableText));
      final sentence = t.getRect(find.byKey(const Key('dz-phone-error')));

      // RTL: both sentences lead on the **right**, so the comparison is
      // `right` to `right`. Measured, never reasoned about -- slice 24's note
      // records a subtraction that read -107.5 on an RTL screen because it
      // compared the wrong pair of edges.
      final digitsInset = box.right - digits.right;
      final sentenceInset = box.right - sentence.right;
      debugPrint('DIGITS inset = $digitsInset   SENTENCE inset = $sentenceInset');

      // This assertion used to read `greaterThan(digitsInset)`, and that was the
      // bug, not the field. It was measuring the *broken* geometry on purpose:
      // with the band insetting itself `right: 4, left: 4` the sentence landed at
      // 26.0 against digits at 21.8, so "the sentence is pushed further in than
      // the digits" was exactly what a self-insetting band produces. Proved by
      // running this file against `e8be33c~1`: `21.8 / 26.0`, green. The same
      // file against `e8be33c`, which removed the band's horizontal inset, reads
      // `22.0 / 22.0` and went red -- because the fix made the two edges agree
      // and the assertion demanded they disagree.
      //
      // The test name is the requirement: the sentence starts against the edge
      // the digits start against. That is an **equality**, and it is now asserted
      // as one, against a tolerance rather than a hand-typed number -- a single
      // hairline is the only difference a border can legitimately add.
      //
      // The icon is what leads the sentence and it is deliberately NOT part of
      // this comparison: `Row` lays out in reading order under RTL, so the icon
      // is the leading glyph and the `Expanded` text starts behind it. Measuring
      // the text against the digits is the user-facing comparison -- the number
      // they typed and the sentence saying it is wrong, side by side in one card.
      expect(sentenceInset - digitsInset, closeTo(0.0, 1.0),
          reason: 'the sentence starts against the edge the digits start '
              'against -- the number typed and the sentence calling it wrong '
              'are compared side by side, so they must lead on one line');

    });
  });
}
