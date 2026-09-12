// The phone field as the user meets it: type, paste, switch to +213, and the
// Arabic error that appears when the number cannot be one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/text/dz_phone.dart';
import 'package:allomokawil/src/widgets/phone_field.dart';

/// The field inside the RTL page it actually lives in.
Widget host(TextEditingController c,
    {bool force = false, VoidCallback? onChanged}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DzPhoneField(
              controller: c,
              forceValidate: force,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}

TextField field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('dz-phone-input')));

String? errorText(WidgetTester tester) {
  final f = find.byKey(const Key('dz-phone-error'));
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data;
}

bool hasValidTick(WidgetTester tester) =>
    find.byIcon(Icons.check_circle_rounded).evaluate().isNotEmpty;

void main() {
  testWidgets(
      'a number pasted with spaces, dashes or a country code is accepted',
      (tester) async {
    for (final pasted in [
      '0550-12-34-56',
      '+213 550 12 34 56',
      '00213550123456',
      '٠٥٥٠١٢٣٤٥٦'
    ]) {
      final c = TextEditingController();
      await tester.pumpWidget(host(c));
      await tester.enterText(find.byKey(const Key('dz-phone-input')), pasted);
      await tester.pump();
      expect(c.text, '05 50 12 34 56', reason: 'paste of "$pasted"');
      expect(DzPhone.isValid(c.text), isTrue);
      expect(hasValidTick(tester), isTrue,
          reason: 'a correct number must show the confirmation tick');
      expect(errorText(tester), isNull);
    }
  });

  testWidgets('typing is grouped live as 0X XX XX XX XX', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c));
    await tester.enterText(find.byKey(const Key('dz-phone-input')), '055');
    await tester.pump();
    expect(c.text, '05 5');
    await tester.enterText(find.byKey(const Key('dz-phone-input')), '0550123');
    await tester.pump();
    expect(c.text, '05 50 12 3');
    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0550123456');
    await tester.pump();
    expect(c.text, '05 50 12 34 56');
  });

  testWidgets('the +213 chip switches the reading and keeps the digits',
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c));
    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0550123456');
    await tester.pump();
    expect(
        tester
            .widget<Text>(find.byKey(const Key('dz-phone-prefix-label')))
            .data,
        '0X');

    await tester.tap(find.byKey(const Key('dz-phone-prefix')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const Key('dz-phone-prefix-label')))
            .data,
        '+213');
    expect(c.text, '550 12 34 56',
        reason: 'the leading zero belongs to the 0X form');
    // Still the same, still valid number — the API receives the canonical form.
    expect(DzPhone.isValid(c.text), isTrue);
    expect(DzPhone.canonical(c.text), '0550123456');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('dz-phone-input')))
            .decoration!
            .hintText,
        S.phoneHintIntl);

    await tester.tap(find.byKey(const Key('dz-phone-prefix')));
    await tester.pumpAndSettle();
    expect(c.text, '05 50 12 34 56');
  });

  testWidgets('in +213 mode a nine-digit number is entered without the zero',
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c));
    await tester.tap(find.byKey(const Key('dz-phone-prefix')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '550123456');
    await tester.pump();
    expect(c.text, '550 12 34 56');
    expect(hasValidTick(tester), isTrue);
    expect(DzPhone.isValid(c.text), isTrue);
  });

  testWidgets('a landline is refused in Arabic, immediately', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c));
    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0212345678');
    await tester.pump();
    expect(errorText(tester), S.phoneInvalid);
    expect(hasValidTick(tester), isFalse);
  });

  testWidgets(
      'an unfinished number is not shouted at while typing, but is on blur',
      (tester) async {
    final c = TextEditingController();
    final other = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              DzPhoneField(controller: c),
              TextField(
                key: const Key('somewhere-else'),
                controller: other,
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.enterText(find.byKey(const Key('dz-phone-input')), '0550');
    await tester.pump();
    expect(errorText(tester), isNull, reason: 'still being typed - no red yet');

    // Tapping out of the field asks the question.
    await tester.tap(find.byKey(const Key('somewhere-else')));
    await tester.pumpAndSettle();
    expect(errorText(tester), S.phoneInvalid);

    // Finishing the number clears it without another round trip.
    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0550123456');
    await tester.pump();
    expect(errorText(tester), isNull);
    expect(hasValidTick(tester), isTrue);
  });

  testWidgets('an empty field only objects once submit was attempted',
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c, force: false, onChanged: () {}));
    expect(errorText(tester), isNull);

    await tester.pumpWidget(host(c, force: true));
    await tester.pump();
    expect(errorText(tester), S.phoneRequired);

    await tester.enterText(
        find.byKey(const Key('dz-phone-input')), '0770123456');
    await tester.pump();
    expect(errorText(tester), isNull);
    expect(hasValidTick(tester), isTrue);
  });

  testWidgets('it opens a phone keypad, laid out for digits in an RTL page',
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(c));
    final f = field(tester);
    expect(f.keyboardType, TextInputType.phone);
    expect(f.textDirection, TextDirection.ltr);
  });
}
