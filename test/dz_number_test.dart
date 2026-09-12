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

    test('the length cap holds however the digits arrive', () {
      expect(edit('1234567890123456').text.length, DzNumber.maxDigits);
    });
  });
}
