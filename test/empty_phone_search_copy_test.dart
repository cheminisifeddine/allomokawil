// The directory told a customer who pasted a phone number to «جرّب كلمة أقصر»
// — try a shorter word.
//
// Found 5 Oct 2026 on production, by reading the empty state against the
// matcher that decides it. `GET /api/mobile/workers/search` does not implement
// `q` at all (measured again this tick: `q=خالد` and `q=zzzzznotarealname` both
// return all **97** live rows), so `narrowWorkers` is the only thing that ever
// filters. That matcher has two arms — [workerMatchesQuery] tries the five text
// fields, then [workerPhoneMatches] tries the number — and the number arm has
// shipped since 5 Oct.
//
// The sentence the screen draws for "nothing matched" was written for the text
// arm and never learned there was a second one:
//
//   لا نتائج مطابقة
//   لا يوجد مقاول يطابق «0770123456».
//   جرّب كلمة أقصر أو امسح البحث
//
// He typed a number. There is no word to shorten, and the number he holds is
// the only handle he will ever have on that man. The line above it re-prints
// the number between «» where a name belongs — a word-search result quoted at a
// phone lookup.
//
// These tests pin the rule, which is deliberately narrow: the new sentence is
// claimed **only** for a query that is a number by the very predicate the
// matcher branches on, so it can never claim "a number search" for a word and
// never claims "no word matched" for a number.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/empty_phone_search_copy.dart';
import 'package:allomokawil/src/data/worker_phone_search.dart';

void main() {
  group('a number query owns its own sentence', () {
    test('the number a customer would actually type', () {
      // A full local number, exactly the shape a contact card produces.
      final msg = emptyPhoneSearchAr('0770123456');
      expect(msg, isNotNull);
      expect(msg, contains('لم يُعثر على رقم مطابق'));
    });

    test('it never says "try a shorter word" about a number', () {
      // The defect itself, as a one-line assertion.
      expect(emptyPhoneSearchAr('0770123456'), isNot(contains('كلمة')));
    });

    test('it does not echo the number the customer pasted', () {
      // What he pasted is his own business, and an empty state is the wrong
      // place to re-print a number he may have pasted by mistake.
      final msg = emptyPhoneSearchAr('0770123456')!;
      expect(msg, isNot(contains('0770123456')));
    });

    test('it points at fewer digits, which is the one move that helps', () {
      // Four remembered digits out of ten is the realistic input, so this is
      // advice the customer can act on in the box he is already looking at.
      expect(emptyPhoneSearchAr('0770123456'),
          contains('أرقامًا أقل من هذا الرقم'));
    });

    test('a four-digit fragment — the realistic memory — is a number too', () {
      expect(emptyPhoneSearchAr('0009'), isNotNull);
    });

    test('the shapes a number arrives in are all number queries', () {
      // Arabic-Indic, grouped, and pasted international: the three the
      // registration form itself has to survive.
      for (final q in <String>[
        '٠٥٥٠٠٠٠٠٠٩',
        '055 00 00 09',
        '+213 550 00 00 09',
        '00213550000009',
      ]) {
        expect(emptyPhoneSearchAr(q), isNotNull, reason: 'rejected: $q');
      }
    });
  });

  group('a word query is left to the screen it already has', () {
    test('plain Arabic', () {
      expect(emptyPhoneSearchAr('سباكة'), isNull);
    });

    test('a name', () {
      expect(emptyPhoneSearchAr('خالد رحماني'), isNull);
    });

    test('a word carrying digits is still a word, not a number', () {
      // `55abc` contributes digits under a looser test; the matcher answers it
      // on the text arm, so this must not claim a number search happened.
      expect(emptyPhoneSearchAr('55abc'), isNull);
      expect(emptyPhoneSearchAr('جيس 5'), isNull);
    });

    test('empty, blank and null', () {
      expect(emptyPhoneSearchAr(null), isNull);
      expect(emptyPhoneSearchAr(''), isNull);
      expect(emptyPhoneSearchAr('   '), isNull);
    });

    test('below the three-digit floor — not a number query yet', () {
      // One or two digits match a large share of the directory, so the matcher
      // does not treat them as numbers and neither may the copy.
      expect(emptyPhoneSearchAr('0'), isNull);
      expect(emptyPhoneSearchAr('55'), isNull);
    });
  });

  test('the copy branches on the same predicate the matcher uses', () {
    // This is the whole fix stated as a property. If these two ever disagree,
    // the directory is showing a word sentence for a number or vice versa —
    // which is the defect in the other direction.
    const queries = <String>[
      '0770123456',
      '055 00 00 09',
      '+213550000009',
      'سباكة',
      'خالد',
      '55abc',
      '0009',
      '0',
      '',
      '  ',
      'جيس',
      '0550000009',
    ];
    for (final q in queries) {
      final isNumberQuery = phoneQueryDigits(q.trim()) != null;
      final claimsNumberSearch = emptyPhoneSearchAr(q) != null;
      expect(claimsNumberSearch, isNumberQuery,
          reason: 'copy and matcher disagree on "$q"');
    }
  });

  test('every number shape the matcher accepts is one the copy can name', () {
    // Not "the same predicate" as an argument but as a check: sweep the live
    // directory's own phone shapes and confirm each one is claimed.
    for (final stored in <String>[
      '0550000009',
      '0770123456',
      '0661234567',
    ]) {
      expect(phoneQueryDigits(stored), isNotNull);
      expect(emptyPhoneSearchAr(stored), isNotNull);
    }
  });
}
