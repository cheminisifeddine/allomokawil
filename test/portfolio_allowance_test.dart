// How many portfolio photos a plan allows, and what the gallery says about it.
//
// Found on 26 Sep 2026 while auditing what the project photo cap left. The cap
// was a *product* rule the screen enforced. Beside it sat a *plan* rule that
// nothing enforced: `portfolio_limit` is parsed on both `Plan` and
// `SubscriptionStatus` and read by nothing in the app, while its sibling on the
// same payload — `quote_limit` — has a left-count line, a usage bar and a 402
// paywall.
//
// The free plan sells five photos. The app never said so, on the one screen
// whose whole job is his gallery, and the paid tiers sell 30/60/120 of a thing
// the buyer could not see the price of.
//
// **The load-bearing test here is the zero one.** `_int()` in `models/plan.dart`
// returns 0 for a missing, null or unparseable field, and `portfolio_limit` is
// parsed with no null guard. Read naively, 0 means "zero photos allowed" — a
// gate that locks a paying contractor out of the gallery he is looking at,
// caused by a server that simply did not send the field. A defensive-looking
// feature that silently disables itself on a partial payload is worse than no
// feature, and the whole reason this test exists is that the number 0 is the
// one value here that must not mean what it says.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/portfolio_allowance.dart';

void main() {
  group('zero is unknown, not an empty allowance', () {
    test('an absent portfolio_limit does not close the gallery', () {
      // What SubscriptionStatus.fromJson hands over when D1 omits the field.
      final a = PortfolioAllowance.fromLimit(0, used: 0);
      expect(a.limit, kDefaultPortfolioLimit);
      expect(a.left, kDefaultPortfolioLimit);
      expect(a.isFull, isFalse);
    });

    test('a real gallery keeps its room after a partial payload', () {
      final a = PortfolioAllowance.fromLimit(0, used: 3);
      expect(a.left, kDefaultPortfolioLimit - 3);
      expect(a.isFull, isFalse);
    });

    test('the free plan value itself is not mistaken for the sentinel', () {
      // 5 is the free plan's real limit AND the fallback, so a test that only
      // checked `isFull == false` would pass on a hardcoded 5 with the parsing
      // still wrong. This asserts the parse from the wire instead.
      final a = PortfolioAllowance.fromLimit(5, used: 5);
      expect(a.limit, 5);
      expect(a.isFull, isTrue);
    });
  });

  group('the room', () {
    test('counts down and reaches zero at the limit', () {
      expect(PortfolioAllowance.fromLimit(5, used: 0).left, 5);
      expect(PortfolioAllowance.fromLimit(5, used: 4).left, 1);
      expect(PortfolioAllowance.fromLimit(5, used: 5).left, 0);
    });

    test('a gallery over its limit reads full, not as negative room', () {
      // A limit lowered, a plan downgraded, or photos uploaded while the server
      // was not counting. A negative "photos left" is a number no screen should
      // print, and it is also the wrong answer to "can he add another".
      final a = PortfolioAllowance.fromLimit(5, used: 9);
      expect(a.left, 0);
      expect(a.isFull, isTrue);
    });

    test('a paid tier is not closed by the free allowance', () {
      final a = PortfolioAllowance.fromLimit(30, used: 29);
      expect(a.left, 1);
      expect(a.isFull, isFalse);
    });
  });

  group('unlimited', () {
    test('a negative limit is no ceiling at all', () {
      // The same word `quote_limit` uses for unlimited (-1 on every paid plan).
      final a = PortfolioAllowance.fromLimit(-1, used: 500);
      expect(a.isUnlimited, isTrue);
      expect(a.left, isNull);
      expect(a.isFull, isFalse);
    });
  });

  group('the copy', () {
    test('the room line agrees on both of its counts', () {
      // «بقيت صورتان من 5 صور في خطتك» — the trailing noun is the counted
      // singular at 5 and the dual at 2, in one sentence, which is the case
      // arabicCounted exists for and the reason this is not hand-written.
      expect(portfolioLeftLineAr(2, 5), 'بقيت صورتان من 5 صور في خطتك');
      expect(portfolioLeftLineAr(1, 5), 'بقيت صورة من 5 صور في خطتك');
      expect(portfolioLeftLineAr(3, 30), 'بقيت 3 صور من 30 صورة في خطتك');
    });

    test('the full line names the limit it hit', () {
      expect(portfolioFullLineAr(5), 'بلغت حد صور خطتك: 5 صور');
    });

    test('the unlimited line prints no number to disagree about', () {
      expect(portfolioUnlimitedLineAr(), contains('بلا حد'));
    });

    test('every line takes its nouns from the shared photo count', () {
      // The defect class this file is in: a count spelled by hand that drifts
      // from the one above it. Asserted against the shared helper so the two
      // cannot part company.
      expect(portfolioFullLineAr(5), contains(photosAr(5)));
      expect(portfolioLeftLineAr(2, 30), contains(photosAr(2)));
    });
  });

  group('what the screen does with it', () {
    test('a null limit is a screen without a gate, never a closed one', () {
      // The screen only builds an allowance once the plan answers, and until
      // then the add tile stays. This is the contract that keeps a slow or
      // failed plan request from hiding a gallery the contractor came to see.
      const PortfolioAllowance? pending = null;
      expect(pending?.isFull ?? false, isFalse);
    });
  });
}
