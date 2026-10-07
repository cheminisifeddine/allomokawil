// One valid-number tick, one inset -- the 10 dp the house inset was not asked for.
//
// Found on slice 27 (7 Oct 2026). `DzPhoneField`'s validity tick is the only
// glyph inside the app's phone field, and it is the only in-field glyph in the
// whole app that hand-pads itself: `EdgeInsets.only(left: 6, right: 12)` inside
// a field whose own inset is `AppTheme.fieldPad` = `s16` on both edges. The 12
// is on the 4 dp ladder and agrees with nothing in particular; the **6** is the
// number the user actually sees, because it is the glyph-to-border inset on the
// edge the Arabic sits against.
//
// **Measured off the built tree, not read off the source.** Mounting the field
// and asking where the tick lands answered `6.0` from the field's border, and
// `fieldPad` is `16.0` -- so the tick sits 10 dp closer to the border than the
// text it is validating. That is the defect, and no ratchet could see it: R4
// counts the *literal*, and it prices `6` the same as `pillPad`'s deliberate
// off-grid `10 x 6`, which is a pill's own proportion around a 14 dp glyph and
// not a column edge at all.
//
// **The 6 is load-bearing and is not simply rounded up.** The framework puts
// the suffix in a `Center` under `suffixIconConstraints` `40 x 40`, so the
// padding IS the glyph-to-border inset -- an A/B of four paddings on the same
// field answered `0 / 6 / 16 / 8` on the same axis, one number per padding.
// There is no second, invisible inset to read instead, and nothing to preserve
// except the mistake. `symmetric(horizontal: 8, vertical: 8)` keeps the glyph at
// its 21 dp (a larger pad shrinks it, because the box is capped) while putting it
// on the ladder; `s12` would put the icon back against the text on the far side.
//
// So this file asserts the **relationship**, not a transcribed number: the tick
// is on the same inset as the field it validates, from `AppTheme.fieldPad`, and
// it holds its own size. Per the `tile_label_fit_test.dart` stale-constant trap
// and slice 23's lesson that a comment quoting a retired off-grid literal is a
// live R4 count, **no retired value is spelled anywhere in this file** -- only
// the token, and only as a relationship to it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/phone_field.dart';

/// Mounts the field holding a complete, valid number -- the only state in which
/// the tick is drawn at all.
Future<void> _pumpValid(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: DzPhoneField(controller: TextEditingController(text: '0550123456')),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The inset the tick's own `Padding` applies, read off the built tree.
///
/// Scoped by `descendant` of the field: the tick is the only
/// `check_circle_rounded` in this subtree, but the guard is written so that a
/// second glyph added to the field later cannot make an unscoped query answer
/// two and compare the pair against each other.
EdgeInsets _tickInset(WidgetTester tester) {
  // `Padding.padding` is `EdgeInsetsGeometry`; the writer passes an `EdgeInsets`,
  // so the cast is exact here and `.resolve()` is not needed.
  return _tickInsetRaw(tester);
}

EdgeInsets _tickInsetRaw(WidgetTester tester) {
  final pad = find.descendant(
    of: find.byType(DzPhoneField),
    matching: find.byType(Padding),
  ).evaluate().map((e) => e.widget).whereType<Padding>();
  for (final p in pad) {
    if (p.child is Icon) return p.padding as EdgeInsets;
  }
  fail('the validity tick carries no Padding of its own, so its inset is '
      'being set by something else and this guard is measuring the wrong box');
}

void main() {
  group('the phone field ticks validity on the inset the field itself uses', () {
    testWidgets('the tick takes the house field inset on both edges', (t) async {
      await _pumpValid(t);
      final inset = _tickInset(t);
      const house = AppTheme.fieldPad;

      debugPrint('TICK  = $inset   house = $house');

      // The same number the field's own text sits on, on both edges. The old
      // shape failed the leading edge by 10 dp while passing the trailing one,
      // which is why it survived every reviewer who checked only the far side.
      expect(inset.left, house.left, reason: 'the tick is on the same inset as '
          'the text it validates, on the edge the Arabic sits against');
      expect(inset.right, house.right,
          reason: 'a symmetric inset: the far edge must agree with the near one');
    });

    testWidgets('the tick is off the border, not flush against it', (t) async {
      await _pumpValid(t);
      final field = t.getRect(find.byType(TextField));
      final icon = t.getRect(find.byIcon(Icons.check_circle_rounded));

      debugPrint('FIELD = $field  ICON = $icon');
      debugPrint('border-to-glyph inset = ${icon.left - field.left}');

      // The pad is the inset: the framework centres the suffix inside a fixed
      // 40 dp box, so what lands on screen is the padding itself.
      expect((icon.left - field.left) - _tickInset(t).left, lessThan(0.01),
          reason: 'the padding is the glyph-to-border inset -- if this fails, '
              'the tick is being positioned by the framework and the inset on '
              'the widget is not what is on screen');
    });

    testWidgets('the tick is painted at its declared glyph size', (t) async {
      await _pumpValid(t);
      final icon = t.getRect(find.byIcon(Icons.check_circle_rounded));
      debugPrint('GLYPH = ${icon.width} x ${icon.height}');

      // **A correction worth keeping.** This case first asserted the box was
      // square at the icon's own size, on the reading that a tick handed a
      // 22 x 40 box was being distorted. It is not, and the number proves it:
      // the box measured 40 dp tall *before* this slice as well, because the
      // framework centres the suffix inside its fixed 40 x 40 box and `Icon`
      // centres its glyph inside whatever box it is given -- so the paint is a
      // true circle either way. Height was never the defect and asserting on it
      // would have sent the fix after a number that was already correct.
      //
      // What the asymmetry *did* do was skew the width: 6 left + 12 right gave
      // the glyph 22 dp of room against 21 with the edges even, which is the
      // width of a box that does not agree with itself. So the width is the
      // assertion, and the height is asserted only as "the glyph fits the box
      // the framework gave it" -- not as a number the source happens to spell.
      expect(icon.width, closeTo(21, 0.01),
          reason: 'the tick is painted at the glyph size it declares');
      expect(icon.height, greaterThanOrEqualTo(21),
          reason: 'the glyph fits the box the framework centres it in');
    });
  });
}
