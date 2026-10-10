// The money/year parsing rules, checked against the shapes a number really
// arrives in on an Algerian phone — and against the rule the API enforces
// (`mobile.ts`), so app and server can never disagree about a budget or a quote.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/dz_number.dart';

/// Copies of the API's own checks, so this file is the contract and not just a
/// description of our own code.
bool serverAcceptsQuote(Object? amount) {
  final n = amount is String ? double.tryParse(amount) : amount as num?;
  return n != null && n.isFinite && n >= 1000;
}

/// Every shape a real amount arrives in, and the single integer all of them
/// mean. Keys are inputs, values are the dinars they stand for.
const shapes = <String, int>{
  '25000': 25000,
  '25 000': 25000,
  '25,000': 25000,
  '25.000': 25000,
  '25 000 دج': 25000,
  '25000 دج': 25000,
  '٢٥٠٠٠': 25000,
  '٢٥٠٠٠ دج': 25000,
  '۲۵۰۰۰': 25000,
  '25 000\u00A0دج': 25000,
  '25٬000': 25000,
  '\u200f25000': 25000,
  ' 25000 ': 25000,
  '00000': 0,
  '1000': 1000,
};

/// 10^n, so a "does this roof fit in the ceiling" case does not write a
/// literal that can drift from [DzNumber.maxDigits].
int pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

void main() {
  group('every shape a real amount arrives in', () {
    shapes.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(DzNumber.tryParse(input), expected);
        // Leading zeros survive the fold and are dropped by the integer.
        expect(int.parse(DzNumber.digits(input)), expected);
      });
    });

    test('the parser this replaced really did drop them', () {
      // Documented, not assumed: this is the bug the loop was opened for. A
      // bare ASCII integer survived `int.tryParse` (surrounding whitespace
      // aside); every other shape above came back null, and a null budget was
      // then treated as an empty field — the typed amount silently vanished
      // from the posted project.
      const survived = {'25000', '1000', '00000', ' 25000 '};
      for (final input in shapes.keys) {
        if (survived.contains(input)) continue;
        expect(int.tryParse(input.trim()), isNull,
            reason: 'int.tryParse must be the thing that failed: "$input"');
      }
      for (final input in ['٢٥٠٠٠', '25 000', '25.000', '25 000 دج']) {
        expect(int.tryParse(input.trim()), isNull, reason: input);
      }
    });

    test('the fold agrees with the API about every shape', () {
      for (final input in shapes.keys) {
        final value = DzNumber.tryParse(input)!;
        expect(serverAcceptsQuote(value), value >= 1000,
            reason: 'the folded value must be judged on its value alone: '
                '"$input" -> $value');
      }
    });
  });

  group('values the app refuses instead of guessing', () {
    test('a fractional amount is null, never rounded', () {
      // 25,5 dinars is not 255 dinars. Truncating a price the user typed is
      // worse than asking again.
      for (final input in ['25,5', '25.5', '25,75', '٢٥,٥', '25٫5', '1.5']) {
        expect(DzNumber.hasFraction(input), isTrue, reason: input);
        expect(DzNumber.tryParse(input), isNull, reason: input);
      }
    });

    test('grouping triplets are not mistaken for a fraction', () {
      for (final input in ['25,000', '1.500', '٢٥٠٬٠٠٠']) {
        expect(DzNumber.hasFraction(input), isFalse, reason: input);
      }
      expect(DzNumber.tryParse('1.500'), 1500);
    });

    test('nothing numeric in it -> null', () {
      for (final input in ['', '   ', 'دج', 'abc', 'ميزانية', '-,']) {
        expect(DzNumber.tryParse(input), isNull, reason: '"$input"');
      }
    });

    test('more digits than any real budget -> null, not a wrapped number', () {
      expect(DzNumber.tryParse('999999999999'), 999999999999);
      expect(DzNumber.tryParse('9999999999999'), isNull);
    });

    test('a ROOF refuses what a floor would have accepted', () {
      // The defect this file exists beside: `min:` was on the bid amount and
      // the bid duration and `max:` on neither, so anything clearing the floor
      // shipped. `999999999999` dinars and a four-hundred-billion-day job were
      // both "valid" submissions.
      expect(DzNumber.tryParse('${DzNumber.maxAmountDzd + 1}',
          max: DzNumber.maxAmountDzd), isNull);
      expect(DzNumber.tryParse('${DzNumber.maxAmountDzd}',
          max: DzNumber.maxAmountDzd), DzNumber.maxAmountDzd);
      expect(DzNumber.tryParse('${DzNumber.maxDurationDays + 1}',
          max: DzNumber.maxDurationDays), isNull);
      expect(DzNumber.tryParse('${DzNumber.maxDurationDays}',
          max: DzNumber.maxDurationDays), DzNumber.maxDurationDays);
    });

    test('the box width reaches the validator, not just the keyboard', () {
      // `maxDigits` used to stop at the formatter: a field could be narrowed
      // to 4 digits and `tryParse` went on accepting the parser ceiling. The
      // two disagreed and only the parser's answer shipped.
      expect(
          DzNumber.tryParse('12345', maxDigits: DzNumber.durationDigits),
          isNull);
      expect(
          DzNumber.tryParse('3650', maxDigits: DzNumber.durationDigits), 3650);
      // It defaults to the ceiling, so a field with no box of its own is
      // unchanged -- the parameter is additive, not a new default.
      expect(DzNumber.tryParse('123456789012'), 123456789012);
    });

    test('each declared box width is wide enough for the roof it carries', () {
      // A box narrower than its own roof could never accept the largest legal
      // value, which would make the roof unreachable and the field a lie.
      expect(DzNumber.amountDigits,
          greaterThanOrEqualTo('${DzNumber.maxAmountDzd}'.length));
      expect(DzNumber.durationDigits,
          greaterThanOrEqualTo('${DzNumber.maxDurationDays}'.length));
      expect(DzNumber.experienceDigits,
          greaterThanOrEqualTo('${DzNumber.maxExperienceYears}'.length));
    });

    test('the roofs are inside the ceiling, so the cap can never be the roof', () {
      expect(DzNumber.maxAmountDzd, lessThan(pow10(DzNumber.maxDigits)));
      expect(DzNumber.maxDurationDays, lessThan(pow10(DzNumber.maxDigits)));
    });

    test('min and max bounds are enforced, inclusively', () {
      expect(DzNumber.tryParse('999', min: 1000), isNull);
      expect(DzNumber.tryParse('1000', min: 1000), 1000);
      expect(DzNumber.tryParse('٠', min: 1), isNull);
      expect(DzNumber.tryParse('٧١', max: DzNumber.maxExperienceYears), isNull);
      expect(DzNumber.tryParse('70', max: DzNumber.maxExperienceYears), 70);
    });
  });

  group('the live input formatter', () {
    TextEditingValue edit(String text) =>
        DzNumberInputFormatter().formatEditUpdate(
            const TextEditingValue(), TextEditingValue(text: text));

    test('Arabic-Indic digits become ASCII as they are typed', () {
      expect(edit('٢٥٠٠٠').text, '25000');
      expect(edit('٨').text, '8');
      expect(edit('۲۵۰').text, '250');
    });

    test('separators, units and bidi marks never reach the controller', () {
      expect(edit('25 000 دج').text, '25000');
      expect(edit('25.000').text, '25000');
      expect(edit('\u200f25000').text, '25000');
    });

    test('a fractional paste is refused, leaving the field as it was', () {
      const before = TextEditingValue(
          text: '2500', selection: TextSelection.collapsed(offset: 4));
      final after = const DzNumberInputFormatter()
          .formatEditUpdate(before, const TextEditingValue(text: '25,5'));
      expect(after.text, '2500');
    });

    test('the caret ends up after the last digit', () {
      final v = edit('٢٥٠');
      expect(v.selection.baseOffset, 3);
    });

    // **This test used to pin the defect.** It asserted the pasted 16-digit
    // string came back as 12 digits -- i.e. that an over-long paste was
    // silently truncated, which is what let a value on screen differ from the
    // value sent. It was green because the bug was the expectation.
    //
    // The cap now holds by REFUSING: the field keeps what it had and the
    // screen's validation is still the thing that explains why it will not
    // send. One field, one paste, one answer -- the same rule the fraction
    // branch above already followed, and the same rule its own comment called
    // "worse than asking again".
    test('an over-long paste is refused, leaving the field as it was', () {
      const before = TextEditingValue(
          text: '2500', selection: TextSelection.collapsed(offset: 4));
      final after = const DzNumberInputFormatter().formatEditUpdate(
          before, const TextEditingValue(text: '1234567890123456'));
      expect(after.text, '2500',
          reason: 'nothing may be dropped without saying so');
    });

    test('a value exactly at the cap is still accepted', () {
      // The refusal is on the OVERFLOW, not on long numbers: a 12-digit paste
      // is a number this app accepts and must keep accepting, or the fix has
      // cost a real amount its last legal value.
      final atCap = '1' * DzNumber.maxDigits;
      expect(edit(atCap).text, atCap);
    });

    test('one digit over the cap is refused, and one under is not', () {
      const f = DzNumberInputFormatter();
      final over = f.formatEditUpdate(
          const TextEditingValue(), TextEditingValue(text: '1234567890123'));
      expect(over.text, isEmpty, reason: 'the overflow is not accepted');
      expect(edit('123456789012').text, '123456789012');
    });

    test('a narrowed box refuses at its OWN width, not at the parser ceiling',
        () {
      // `NumberField.maxDigits` is threaded into the formatter, so a 4-digit
      // duration field must refuse 5 digits even though the parser would take
      // them. This is the knob the audit found passed by 0 of 7 call sites.
      const f = DzNumberInputFormatter(maxDigits: DzNumber.durationDigits);
      final over = f.formatEditUpdate(
          const TextEditingValue(), TextEditingValue(text: '12345'));
      expect(over.text, isEmpty);
      expect(f
              .formatEditUpdate(const TextEditingValue(),
                  const TextEditingValue(text: '3650'))
              .text,
          '3650');
    });

    test('an over-long paste of Arabic-Indic digits is refused too', () {
      // The fold runs before the length check, so the cap must be judged on
      // the folded digits -- otherwise ١٢ pasted digits read as 12 ASCII ones
      // and slip past the very gate meant to stop them.
      const before = TextEditingValue(text: '8');
      final after = const DzNumberInputFormatter().formatEditUpdate(
          before, TextEditingValue(text: '١' * (DzNumber.maxDigits + 1)));
      expect(after.text, '8');
    });
  });
}
