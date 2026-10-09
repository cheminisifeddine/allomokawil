// A search that could not read the whole market must not say it found nothing.
//
// `browseProjects` has recorded every page it lost since a previous tick —
// each one with its number, on the diagnostics channel — and that half is
// correct. **The log is not the screen, and that is the whole defect.** The
// return type was `List<Project>`: the count of lost pages had no path to the
// widget that prints the answer, so a contractor searching «دهان» while three of
// five pages were down was told «لا نتائج مطابقة» — *nothing matches* — which
// is a verdict about a market he was not allowed to read.
//
// Two tests here are the ones that matter: the wording obeys the count, and the
// **predicate** refuses the verdict. A correct sentence wired to an unchanged
// screen passes the first and ships nothing.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/data/partial_market_copy.dart';

void main() {
  group('lostPagesAr', () {
    test('the count agrees with the number — the family rule', () {
      // 1 and 2 omit the number («صفحة واحدة», «صفحتان»), 3-10 take the broken
      // plural, 11+ take the bare singular. `arabicCounted` owns that rule; this
      // pins the *nouns*, which is what this file owns.
      expect(lostPagesAr(1), 'صفحة واحدة');
      expect(lostPagesAr(2), 'صفحتان');
      expect(lostPagesAr(3), '3 صفحات');
      expect(lostPagesAr(10), '10 صفحات');
      expect(lostPagesAr(11), '11 صفحة');
      expect(lostPagesAr(103), '103 صفحات');
    });

    test('one never borrows the singular slot 11+ reuses', () {
      // The trap `commune_count_copy.dart` and `quote_count_copy.dart` both
      // document: passing «صفحة واحدة» in as the singular prints «11 صفحة
      // واحدة».
      expect(lostPagesAr(11), isNot(contains('واحدة')));
      expect(lostPagesAr(21), isNot(contains('واحدة')));
    });

    test('no loss is silence, never «0 صفحات»', () {
      // The caller only asks about a loss; a zero has nothing to announce.
      expect(lostPagesAr(0), '');
      expect(lostPagesAr(-1), '');
    });
  });

  group('partialMarketLineAr', () {
    test('names the gap AND that the rows may be short', () {
      final line = partialMarketLineAr(lost: 3, total: 5);
      expect(line, contains('تعذّر'));
      expect(line, contains('ناقصة'),
          reason: 'the half that tells him his results are incomplete');
      expect(line, matches(RegExp(r'[\u0600-\u06FF]')));
    });

    test('a full loss does not print an impossible denominator', () {
      // `lost == total` means every page asked for died, which
      // `browseProjects` already turns into a raised error — so this branch is
      // a caller's mistake. It must degrade to the gap, never to «3 من 3».
      final line = partialMarketLineAr(lost: 3, total: 3);
      expect(line, isNot(contains('من 3')));
      expect(line, contains('3 صفحات'));
    });

    test('a missing total degrades to the gap rather than lying', () {
      expect(partialMarketLineAr(lost: 2, total: 0), isNot(contains('من 0')));
    });

    test('no loss is no band', () {
      // A complete read must be byte-for-byte unchanged: a band about nothing
      // on an ordinary search would train the contractor to ignore the one
      // notice that is telling him something true.
      expect(partialMarketLineAr(lost: 0, total: 5), '');
    });

    test('never uses the generic unexpected-error sentence', () {
      // Nothing about this read was *unexpected* — three pages answering is a
      // normal day — so «حدث خطأ غير متوقع» under a normal search would be a
      // false alarm on the one band a reader is meant to believe.
      final line = partialMarketLineAr(lost: 2, total: 5);
      expect(line, isNot(contains(S.errUnexpected)));
    });
  });

  group('partialMarketMayClaimNoResults', () {
    test('a search that read every page may say nothing matches', () {
      expect(partialMarketMayClaimNoResults(lost: 0, total: 5), isTrue);
    });

    test('a search that lost a page may NOT', () {
      // THE assertion. «لا نتائج مطابقة» is a statement about the market, and
      // the app is only entitled to make it about a market it read in full.
      expect(partialMarketMayClaimNoResults(lost: 1, total: 5), isFalse);
      expect(partialMarketMayClaimNoResults(lost: 4, total: 5), isFalse);
    });

    test('pages that answered EMPTY do not block the verdict', () {
      // The mirror-image lie, and the reason a lost page is not simply "any
      // short result": a wilaya with no open projects is an empty market, and
      // four pages answering `[]` truthfully is a *complete* search of a market
      // that has nothing in it.
      expect(partialMarketMayClaimNoResults(lost: 0, total: 5), isTrue,
          reason: 'an empty page is an answer');
    });
  });
}
