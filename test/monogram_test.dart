// The round avatar's letter. A name pasted out of Facebook or WhatsApp is
// bracketed with invisible direction marks that Dart's `trim()` does not remove,
// and the avatar was painting one of them — a blank navy circle in every place
// the app shows who a person is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/monogram.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// The characters that paint nothing, spelled out rather than interpolated, so
/// this test fails by name if one of them is ever removed from the rule.
const rlm = '\u200F';
const lrm = '\u200E';
const zwsp = '\u200B';
const zwnj = '\u200C';
const zwj = '\u200D';
const wj = '\u2060';
const alm = '\u061C';
const bom = '\uFEFF';

/// A name as it is actually stored: whatever the user typed or pasted, trimmed
/// of whitespace and nothing else (`auth_screen.dart:164`).
String stored(String raw) => raw.trim();

/// Does the character paint anything a person could read?
bool paintsSomething(String ch) =>
    ch.trim().isNotEmpty && ch.runes.isNotEmpty;

void main() {
  group('a name is stored verbatim, marks and all', () {
    // Proves the premise rather than assuming it: the app really does keep the
    // invisible characters, so the avatar has to cope with them.
    test('trim() leaves a direction mark in place', () {
      expect(stored('$rlm' 'محمد'), startsWith(rlm));
      expect(stored('$rlm' 'محمد').runes.first, 0x200F);
    });
  });

  group('a pasted Arabic name still gets its real initial', () {
    const shapes = <String, String>{
      'RLM (U+200F), the Facebook/WhatsApp bracket': rlm,
      'LRM (U+200E)': lrm,
      'ZWSP (U+200B)': zwsp,
      'ZWNJ (U+200C)': zwnj,
      'ZWJ (U+200D)': zwj,
      'word joiner (U+2060)': wj,
      'Arabic letter mark (U+061C)': alm,
      'BOM (U+FEFF)': bom,
    };

    shapes.forEach((label, mark) {
      test('$label before محمد gives م', () {
        expect(Monogram.of('$mark' 'محمد'), 'م');
      });
      test('$label twice still gives م', () {
        expect(Monogram.of('$mark$mark' 'محمد'), 'م');
      });
    });

    test('marks before a Latin name give the Latin letter', () {
      expect(Monogram.of('$rlm' 'Yacine'), 'Y');
    });
    test('a mark between words does not become the initial', () {
      // «مد‌MARKحمد» — the mark is inside, so the first *visible* rune is م.
      expect(Monogram.of('$zwj' 'سعيد'), 'س');
    });
  });

  group('a name with nothing visible never paints a blank circle', () {
    test('a lone RLM falls back to ؟', () {
      expect(Monogram.of(rlm), Monogram.fallback);
      expect(Monogram.of(rlm), '؟');
    });
    test('several marks and a space fall back to ؟', () {
      expect(Monogram.of('$rlm $lrm $zwsp '), '؟');
    });
    test('an empty name and a marks-only name agree', () {
      expect(Monogram.of(''), Monogram.of('$bom$zwj '));
    });
  });

  group('names with nothing special are untouched', () {
    test('a normal Arabic name gives its first letter', () {
      expect(Monogram.of('محمد بن علي'), 'م');
    });
    test('a normal Latin name gives its first letter', () {
      expect(Monogram.of('Yacine B'), 'Y');
    });
    test('a soft hyphen mid-name does not hide the first letter', () {
      // U+00AD is a real formatting char but not a leading one — «Moham-ed»
      // must still show M.
      expect(Monogram.of('Moh\u00ADamed'), 'M');
    });
    test('a supplementary-plane character is not cut in half', () {
      // 'name[0]' would split a surrogate pair; runes do not.
      expect(Monogram.of('𝒜🏽чение'), '𝒜');
    });
    test('a name that is only whitespace falls back', () {
      expect(Monogram.of('   '), '؟');
    });
  });

  group('the widget paints what the rule returns', () {
    // The rule is only worth anything if the avatar actually shows it, and the
    // old bug was a widget bug: the helper was right in the empty case and the
    // blank circle appeared anyway.
    testWidgets('a pasted name shows a readable letter, not a blank circle',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InitialAvatar(name: '\u200F' 'محمد')),
      ));
      final shown = tester.widget<Text>(find.byType(Text));
      expect(shown.data, 'م');
      expect(paintsSomething(shown.data!), isTrue,
          reason: 'an avatar must never paint a zero-width glyph');
    });

    testWidgets('a marks-only name shows the Arabic question mark',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InitialAvatar(name: '\u200F\u200E ')),
      ));
      expect(tester.widget<Text>(find.byType(Text)).data, '؟');
    });

    testWidgets('an empty name still shows ؟ (unchanged behaviour)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: InitialAvatar(name: '   ')),
      ));
      expect(tester.widget<Text>(find.byType(Text)).data, '؟');
    });
  });
}
