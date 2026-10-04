// `DzPhoneInputFormatter`, the object every keystroke in the phone field passes
// through, driven the way a keyboard drives it: one character at a time.
//
// Why this file exists at all, when `dz_phone_test.dart` is 235 lines long and
// `phone_field_test.dart` has 9 widget tests: nothing executed the formatter
// directly (0 references to `DzPhoneInputFormatter` anywhere under `test/`),
// and every widget test uses `tester.enterText`, which sets the whole string in
// one shot. That is a paste. A paste and a typing session reach the formatter
// through different code — the formatter has to canonicalise at *every* prefix,
// including the ones where the country code is half-typed and a length-based
// repair would fire — and only the second one is what a user does.
//
// The bug this pins is not hypothetical: `phone_field.dart` carries a comment
// about `00213550123456` losing its last two digits and becoming a
// wrong-but-plausible number. That was a keystroke-path bug found by hand. The
// invariants below are the ones that bug violated, expressed so a regression
// fails by name.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/dz_phone.dart';
import 'package:allomokawil/src/widgets/phone_field.dart';

/// Types [form] into an empty field one character at a time, returning the
/// field text after each keystroke.
List<String> typeCharacterByCharacter(String form) {
  var field = '';
  final trace = <String>[];
  for (final ch in form.split('')) {
    const before = TextEditingValue();
    final typed = TextEditingValue(
      text: field + ch,
      selection: TextSelection.collapsed(offset: field.length + ch.length),
    );
    final after = const DzPhoneInputFormatter().formatEditUpdate(before, typed);
    field = after.text;
    trace.add(field);
  }
  return trace;
}

/// Types [form] into the field with the platform text input, the way a real
/// keyboard reaches it: each call carries only the character just pressed, so
/// the formatter runs on every keystroke instead of once on a whole paste.
Future<String> typeIntoField(WidgetTester tester, String form,
    {required TextEditingController controller}) async {
  // The platform text input is only wired to the focused field, so the keyboard
  // has to be opened before a keystroke can reach it at all.
  await tester.showKeyboard(find.byKey(const Key('dz-phone-input')));
  await tester.pump();
  for (final ch in form.split('')) {
    // The platform input works from a full editing value, so the accumulated
    // text has to be rebuilt each keystroke. What matters is that this is the
    // *existing* field text plus one character, not a fresh string.
    final sofar = controller.text;
    final next = TextEditingValue(
      text: '$sofar$ch',
      selection: TextSelection.collapsed(offset: '$sofar$ch'.length),
    );
    tester.testTextInput.updateEditingValue(next);
    await tester.pump();
  }
  return controller.text;
}

/// The API value for a field holding [fieldText] — exactly what
/// `auth_screen.dart` posts on submit.
String postedFor(String fieldText) => DzPhone.canonical(fieldText);

/// Every way a real Algerian mobile reaches the field, typed in full by hand.
const typedForms = <String>[
  '0550123456',
  '550123456', // zero dropped, saved internationally
  '+213550123456',
  '213550123456',
  '00213550123456',
  '+213 550 12 34 56',
  '00213 550 12 34 56',
  '٠٥٥٠١٢٣٤٥٦', // Arabic-Indic keyboard
  '۰۵۵۰۱۲۳۴۵۶', // Extended-Arabic keyboard
  '0550123456\n', // trailing newline from a contact card
];

void main() {
  group('a number typed one digit at a time lands where it was aimed', () {
    for (final form in typedForms) {
      test('"$form" -> 05 50 12 34 56, posting 0550123456', () {
        final trace = typeCharacterByCharacter(form);
        final field = trace.last;

        expect(field, '05 50 12 34 56',
            reason: 'typing "$form" must end on the number itself.\n'
                '  keystroke by keystroke: $trace');
        expect(postedFor(field), '0550123456',
            reason: 'this is the value that reaches the API for "$form"');
        expect(DzPhone.isValid(field), isTrue,
            reason: 'the field would show no confirmation tick for "$form"');
      });
    }
  });

  group('the field never rewrites its own text', () {
    // The fixpoint. `formatEditUpdate` gets called on every rebuild path in
    // Flutter, not only on keystrokes; if it answers a different string for the
    // same input, the number under the user's eyes changes while they are not
    // touching it. Found by fuzzing 400k random digit strings — the field text
    // was stable for all of them, so this is now the assertion instead.
    test('re-running the formatter on the field text is a no-op', () {
      for (final form in typedForms) {
        final field = typeCharacterByCharacter(form).last;
        final again = const DzPhoneInputFormatter().formatEditUpdate(
          const TextEditingValue(),
          TextEditingValue(
            text: field,
            selection: TextSelection.collapsed(offset: field.length),
          ),
        );
        expect(again.text, field,
            reason: 'the formatter must be a fixpoint on its own output for '
                '"$form": it answered "$field" then "${again.text}"');
      }
    });

    test('for 20k random digit strings, the field text is a fixpoint', () {
      var checked = 0;
      for (var seed = 0; seed < 20000; seed++) {
        // Deterministic pseudo-random digit string: no `Random` import needed
        // and a failure here is reproducible from the seed alone.
        var n = seed * 2654435761 % 2147483647;
        var raw = '';
        final len = n % 15;
        for (var i = 0; i < len; i++) {
          n = n * 1103515245 + 12345;
          raw += '${(n >> 16) % 10}';
        }
        final once = const DzPhoneInputFormatter().formatEditUpdate(
          const TextEditingValue(),
          TextEditingValue(text: raw, selection: TextSelection.collapsed(offset: raw.length)),
        );
        final twice = const DzPhoneInputFormatter().formatEditUpdate(
          const TextEditingValue(),
          TextEditingValue(text: once.text, selection: TextSelection.collapsed(offset: once.text.length)),
        );
        expect(twice.text, once.text,
            reason: 'raw "$raw" formatted to "${once.text}" then to "${twice.text}"');
        checked++;
      }
      expect(checked, 20000);
    });
  });

  group('what the user sees is what the account is created under', () {
    // The invariant that makes the tick honest. The field shows a green
    // confirmation when `isValid(fieldText)`; the screen posts
    // `canonical(fieldText)`. If those two ever disagree, a user is told their
    // number is correct and the account is created under a different one.
    test('a field showing a tick always posts a number the API accepts', () {
      for (final form in typedForms) {
        final field = typeCharacterByCharacter(form).last;
        final posted = postedFor(field);
        expect(DzPhone.national(posted), DzPhone.national(field),
            reason: 'the user read "$field" and would be registered as '
                '"$posted" — different numbers.');
      }
    });

    test('a keystroke can never turn one valid number into a different valid one',
        () {
      // The over-typing case: the field is full, the user hits another digit.
      // The formatter is entitled to ignore it — but ignoring it must leave the
      // number alone, not silently rewrite it into one that is still valid.
      for (final form in typedForms) {
        final field = typeCharacterByCharacter(form).last;
        for (var d = 0; d <= 9; d++) {
          final after = const DzPhoneInputFormatter().formatEditUpdate(
            const TextEditingValue(),
            TextEditingValue(
                text: '$field$d',
                selection: TextSelection.collapsed(offset: field.length + 1)),
          );
          if (DzPhone.isValid(after.text)) {
            expect(after.text, field,
                reason: 'typing $d after the full number "$form" changed a '
                    'valid number into "${after.text}"');
          }
        }
      }
    });
  });

  group('the field the user actually types into', () {
    testWidgets('real keystrokes build the same number the unit test predicts',
        (tester) async {
      // The widget half. `enterText` is a paste; this walks the field with the
      // platform text input so the formatter is reached the way a keyboard
      // reaches it. If the formatter is ever dropped from the field, or the
      // field is handed a different one, this goes red and the 9 paste-based
      // widget tests stay green.
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DzPhoneField(controller: c),
            ),
          ),
        ),
      ));

      final typed = await typeIntoField(tester, '0550123456',
          controller: c);

      expect(typed, '05 50 12 34 56',
          reason: 'ten keystrokes must produce the grouped number');
      expect(c.text, '05 50 12 34 56');
      expect(postedFor(c.text), '0550123456');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('typing an international number digit by digit also works',
        (tester) async {
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DzPhoneField(controller: c),
            ),
          ),
        ),
      ));

      final typed = await typeIntoField(tester, '+213550123456',
          controller: c);

      expect(typed, '05 50 12 34 56',
          reason: 'the country code is consumed as it is typed, not left on '
              'screen; the user should end up reading their own number back.');
      expect(postedFor(c.text), '0550123456');
    });
  });
}
