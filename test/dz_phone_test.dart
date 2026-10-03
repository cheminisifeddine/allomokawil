// The rules in lib/src/core/text/dz_phone.dart, checked against the forms an
// Algerian number actually arrives in — and against the rule the API enforces,
// so the app and the server can never drift into disagreeing about what a valid
// number is.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/dz_phone.dart';

/// A copy of `normalizeDzPhone` + `DZ_PHONE_RE` from `workers/mobile.ts`. This
/// test is the contract: if the server rule changes, it fails here first.
String serverNormalize(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.startsWith('213') && digits.length > 9) {
    return '0${digits.substring(3)}';
  }
  return digits;
}

bool serverAccepts(String raw) =>
    RegExp(r'^0[5-7]\d{8}$').hasMatch(serverNormalize(raw));

/// Every shape a real Algerian number arrives in, and the single canonical form
/// all of them must collapse to.
const shapes = <String, String>{
  '0550123456': '0550123456',
  '0550 12 34 56': '0550123456',
  '0550-12-34-56': '0550123456',
  '0550.12.34.56': '0550123456',
  '+213 550 12 34 56': '0550123456',
  '+213550123456': '0550123456',
  '00213 550 12 34 56': '0550123456',
  '213550123456': '0550123456',
  '550123456': '0550123456',
  '٠٥٥٠١٢٣٤٥٦': '0550123456',
  '٠٥٥٠ ١٢ ٣٤ ٥٦': '0550123456',
  ' 0550123456 ': '0550123456',
};

void main() {
  group('every shape an Algerian number arrives in', () {
    shapes.forEach((input, expected) {
      test('"$input" -> $expected', () {
        expect(DzPhone.canonical(input), expected);
        expect(DzPhone.isValid(input), isTrue,
            reason: 'a real mobile number must never be rejected');
      });
    });

    test('the app never sends the API something it would reject', () {
      // The invariant that matters end to end: whatever the field accepted, the
      // API must store. Canonicalise here, then run the server's own regex.
      for (final input in shapes.keys) {
        expect(serverAccepts(DzPhone.canonical(input)), isTrue,
            reason: 'the app must not send an unacceptable number: "$input"');
      }
    });

    test('the app is friendlier than the server in exactly two named places',
        () {
      // Documented, not accidental. The API rejects both of these and it should:
      // it cannot tell "550123456 with the zero dropped" from a typo. The app
      // can, because it has the field and the +213 chip in front of the user.
      expect(serverAccepts('550123456'), isFalse);
      expect(DzPhone.canonical('550123456'), '0550123456');
      expect(serverAccepts('00213 550 12 34 56'), isFalse);
      expect(DzPhone.canonical('00213 550 12 34 56'), '0550123456');
    });

    test(
        'for every number the API accepts, the app computes the identical form',
        () {
      // Guards against the app "helpfully" transforming a number the server is
      // already happy with — that is how a user ends up locked out of their own
      // account with a number that is correct.
      var compared = 0;
      for (final input in shapes.keys) {
        if (!serverAccepts(input)) continue; // the two documented repairs above
        compared++;
        expect(DzPhone.canonical(input), serverNormalize(input),
            reason: 'diverged on "$input"');
      }
      expect(compared, greaterThanOrEqualTo(8),
          reason: 'the comparison must not be vacuous');
    });
  });

  group('rejections, with the same rule the API uses', () {
    const bad = <String>[
      '',
      '   ',
      '055012345', // one digit short
      '05501234567', // one digit too many
      '0212345678', // landline (02x) — the API takes mobiles only
      '0312345678', // landline (03x)
      '0412345678', // landline (04x)
      '0850123456', // not an Algerian operator prefix
      'abc',
      '05501234ab', // letters pasted out of a message
    ];

    for (final input in bad) {
      test('"$input" is rejected here and by the server', () {
        expect(DzPhone.isValid(input), isFalse);
        expect(DzPhone.isValid(input), serverAccepts(input));
      });
    }

    test('a number longer than 10 digits is not silently trimmed into a pass',
        () {
      // 05501234567 canonicalises to itself (there is no country code to strip),
      // so it stays invalid instead of becoming 0550123456 by accident.
      expect(DzPhone.canonical('05501234567'), '05501234567');
      expect(DzPhone.isValid('05501234567'), isFalse);
    });
  });

  group('grouping shown while typing', () {
    test('local: 0X XX XX XX XX, progressive', () {
      expect(DzPhone.groupLocal('0'), '0');
      expect(DzPhone.groupLocal('05'), '05');
      expect(DzPhone.groupLocal('055'), '05 5');
      expect(DzPhone.groupLocal('0550'), '05 50');
      expect(DzPhone.groupLocal('05501234'), '05 50 12 34');
      expect(DzPhone.groupLocal('0550123456'), '05 50 12 34 56');
      expect(DzPhone.groupLocal('0550-12-34-56'), '05 50 12 34 56');
      // A leading `+213` or a stray country code does not survive grouping.
      expect(DzPhone.groupLocal('+213 550 12 34 56'), '05 50 12 34 56');
      expect(DzPhone.groupLocal('00213550123456'), '05 50 12 34 56');
    });

    test('international: +213 then 550 12 34 56', () {
      expect(DzPhone.groupIntl('5'), '5');
      expect(DzPhone.groupIntl('550123456'), '550 12 34 56');
      expect(DzPhone.groupIntl('+213 550 12 34 56'), '550 12 34 56');
      // The reflex leading zero is dropped rather than left in the field.
      expect(DzPhone.groupIntl('0550123456'), '550 12 34 56');
    });

    test('nothing is invented for an empty field', () {
      expect(DzPhone.groupLocal(''), '');
      expect(DzPhone.groupIntl(''), '');
      expect(DzPhone.national(''), '');
    });

    test('national() is the nine digits after +213', () {
      expect(DzPhone.national('0550123456'), '550123456');
      expect(DzPhone.national('+213 550 12 34 56'), '550123456');
    });
  });

  group('every public entry point folds Arabic-Indic digits', () {
    // **The 38th tick's item, measured first.** `canonicalFromDigits` was
    // public, its docstring said callers may hand it the raw field text, and it
    // did not fold what an Arabic keypad produces:
    //
    // ```text
    // in="٠٥٠١٢٣٤٥٦" digits="050123456" fromDigits="<empty>"
    //                    canonical="050123456" groupLocal="" national="50123456"
    // ```
    //
    // The defect is not that one method is strict. It is that a method called
    // `canonical\u2026` differs from its sibling `canonical` on **exactly the
    // input Algerian keyboards produce**, while sharing the signature and the
    // promise. `groupLocal`, `groupIntl` and `national` all funnel through it,
    // so a screen that reached for any of them with `controller.text` \u2014 which
    // is what `phone_field.dart`'s own docstring invites \u2014 got an **empty
    // field** for a number the API would have accepted.
    //
    // Held as a property of the *whole* public surface, not of one method: any
    // method that answers \"what number is this?\" must give the same answer for
    // the same number however it is written, and that is checkable without
    // knowing which of them a future screen will pick.
    const arabicIndic = '\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666';
    const persian = '\u06f5\u06f5\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6';
    const spaced = '\u0665\u0665\u0660 \u0661\u0662 \u0663\u0664 \u0665\u0666';

    // Each spelling of one real number, and the answer every entry point owes.
    const same = <String, String>{
      arabicIndic: '0550123456',
      persian: '0550123456',
      spaced: '0550123456',
    };

    for (final entry in same.entries) {
      test('"${entry.key}" is answered the same way by all of them', () {
        // The entry point a screen is told to use.
        expect(DzPhone.canonical(entry.key), entry.value);
        expect(DzPhone.isValid(entry.key), isTrue);
        // And the four that share its name and are one word away from it. This
        // is the pair the 37th tick proved safe when reached through `digits`
        // and that nobody executed directly \u2014 `canonical` folded upstream and
        // every assertion stayed green through a whole regression of this one.
        expect(DzPhone.canonicalFromDigits(entry.key), entry.value,
            reason: 'the public door every other entry point funnels through '
                'answers nothing for an Arabic-Indic number.');
        expect(DzPhone.groupLocal(entry.key), '05 50 12 34 56');
        expect(DzPhone.groupIntl(entry.key), '550 12 34 56');
        expect(DzPhone.national(entry.key), '550123456');
      });
    }

    test('the two shapes the item named, as a user reaches them', () {
      // `phone_field.dart` tells callers to send `canonical(controller.text)`,
      // 20 lines above a formatter whose own variable is called `digits`. The
      // docstring and the variable disagree, and the docstring is what a new
      // screen copies \u2014 so both spellings are asserted here rather than one.
      for (final raw in <String>['\u0665\u0665\u0660\u0661\u0662\u0663\u0664'
          '\u0665\u0666', '550123456']) {
        expect(DzPhone.groupLocal(DzPhone.digits(raw)), '05 50 12 34 56',
            reason: 'the field must still show a number when the field text is '
                'in Arabic-Indic digits; an empty field teaches the user the '
                'number is wrong.');
        expect(DzPhone.groupLocal(raw), '05 50 12 34 56',
            reason: 'and the formatter\'s own name is not the caller\'s '
                'promise: whatever a screen hands it, it answers the number.');
      }
    });

    test('the fold is idempotent, so no entry point can double-fold', () {
      // Folding inside `canonicalFromDigits` is safe only because
      // `ArabicSearch.normalize` is. If a future fold were not, `canonical`
      // \u2014 which folds, then calls this \u2014 would fold twice on the way in.
      for (final raw in <String>[
        arabicIndic,
        persian,
        '550123456',
        '+213 550 12 34 56',
        ' 0550123456 ',
      ]) {
        expect(DzPhone.canonical(DzPhone.canonical(raw)), DzPhone.canonical(raw),
            reason: 'canonical() is no longer idempotent on "$raw".');
      }
    });
  });
}
