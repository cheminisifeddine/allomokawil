// The wording and the rule for a thread older than the phone drew.
//
// Two things are tested here and only one of them is a sentence. The sentence
// is `partialThreadLineAr`; the rule is `partialThreadMayClaimComplete`, and
// that is the one that can keep a bug dead on its own — a correct Arabic
// string wired to a screen that never draws it passes everything below and
// ships nothing. `partial_thread_paging_test.dart` closes that half with a
// widget case.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/partial_thread_copy.dart';

void main() {
  group('undrawnMessagesAr', () {
    test('the count agrees with the number — the family rule', () {
      // 1 and 2 omit the number, 3-10 take the broken plural, 11+ take the bare
      // singular. `arabicCounted` owns the rule; this pins the nouns.
      expect(undrawnMessagesAr(1), 'رسالة واحدة');
      expect(undrawnMessagesAr(2), 'رسالتان');
      expect(undrawnMessagesAr(3), '3 رسائل');
      expect(undrawnMessagesAr(10), '10 رسائل');
      expect(undrawnMessagesAr(11), '11 رسالة');
      // **103 takes the broken plural, not the singular.** A counted noun is
      // decided by its last two digits, so the plural window repeats every
      // hundred — 103 counts exactly as 3 does. The test I wrote first asserted
      // «103 رسالة» on the English reading ("11 and up is singular"), which is
      // the mistake `arabic_count.dart` documents having already been made once
      // in this codebase. `lostPagesAr` answers «103 صفحات» here for the same
      // reason.
      expect(undrawnMessagesAr(103), '103 رسائل');
    });

    test('one never borrows the singular slot 11+ reuses', () {
      // The trap `lostPagesAr` documents: passing «رسالة واحدة» in as the
      // singular prints «11 رسالة واحدة».
      expect(undrawnMessagesAr(11), isNot(contains('واحدة')));
      expect(undrawnMessagesAr(21), isNot(contains('واحدة')));
      expect(undrawnMessagesAr(103), isNot(contains('واحدة')),
          reason: 'the plural window repeats every hundred');
    });

    test('nothing undrawn is silence, never «0 رسائل»', () {
      expect(undrawnMessagesAr(0), '');
      expect(undrawnMessagesAr(-1), '');
    });
  });

  group('partialThreadLineAr', () {
    test('says the thread is long and that older words are missing', () {
      final line = partialThreadLineAr(undrawn: 340, drawn: 100);
      expect(line, contains('طويلة'));
      expect(line, contains('340'));
      expect(line, contains('100'), reason: 'names the gap as a range');
      expect(line, matches(RegExp(r'[\u0600-\u06FF]')));
    });

    test('never promises a gesture the app does not implement', () {
      // **This test is here because the first draft shipped one.** The sentence
      // said «اسحب للأعلى لقراءة الأقدم» — *swipe up to read older* — and
      // `chat_screen.dart` has no `ScrollNotification` listener, no load-older
      // and no way to fetch further: `grep` for all three returns nothing. A
      // band that names an action the app cannot perform is the same defect as
      // the silent truncation, one layer up — the user tries it, nothing
      // happens, and concludes the app is broken rather than incomplete.
      //
      // So the promise is pinned as *absent*. If a load-older ever ships, this
      // test fails and the copy can honestly go back to offering it.
      final line = partialThreadLineAr(undrawn: 340, drawn: 100);
      expect(line, isNot(contains('اسحب')));
      expect(line, isNot(contains('لقراءة')));
    });

    test('nothing undrawn is no band at all', () {
      // Every ordinary thread, including the 100-message one that fits
      // exactly. A band about nothing would train the reader to ignore the
      // one notice that is true.
      expect(partialThreadLineAr(undrawn: 0, drawn: 100), '');
    });

    test('a missing drawn count degrades rather than lying', () {
      expect(partialThreadLineAr(undrawn: 5, drawn: 0),
          isNot(contains('من 0')));
    });
  });

  group('partialThreadMayClaimComplete', () {
    test('a complete read may say it is complete', () {
      expect(partialThreadMayClaimComplete(undrawn: 0), isTrue);
    });

    test('a truncated read may NOT — the rule is the file', () {
      // «كل الرسائل» is a verdict about the conversation. A read that stopped
      // at its page budget has no answer at all about rows it never saw.
      expect(partialThreadMayClaimComplete(undrawn: 1), isFalse);
      expect(partialThreadMayClaimComplete(undrawn: 340), isFalse);
      expect(partialThreadMayClaimComplete(undrawn: -1), isTrue,
          reason: 'impossible input, and it must match '
              'partialMarketMayClaimNoResults, which answers true for it too');
    });
  });
}
