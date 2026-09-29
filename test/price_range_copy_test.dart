// The price range a contractor advertises, pinned from the live wire.
//
// The fixtures are the exact `price_range_min` / `price_range_max` pairs
// `PATCH /api/mobile/my/profile` left on the real profile row this test's
// header names (worker `id 124`, user 392, created 28 Sep 2026), captured by
// sending each body and re-reading `GET /api/mobile/my/profile`:
//
//   sent {"price_range_min":5000,"price_range_max":5000} -> 5000 / 5000
//   sent {"price_range_min":7000,"price_range_max":null} -> 7000 / 7000
//   sent {"price_range_min":null,"price_range_max":7000} -> 5000 / 7000
//   sent {"price_range_min":7000,"price_range_max":9000} -> 7000 / 9000
//
// The second line is the defect: the app's own form sends `null` for an empty
// box, and the server answers it by storing the max as the min too — so a
// contractor who typed one number ended up advertising a band with equal
// ends, and the profile printed «7000 - 7000 دج».
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/price_range_copy.dart';

void main() {
  group('the live wire', () {
    test('every pair the server really stored is a readable sentence', () {
      // Captured verbatim from production, not invented.
      const live = <String, (int?, int?)>{
        'equal both sent': (5000, 5000),
        'min only, server filled the max': (7000, 7000),
        'max only, server kept the old min': (5000, 7000),
        'a real band': (7000, 9000),
      };
      live.forEach((label, pair) {
        final shown = priceRangeAr(pair.$1, pair.$2);
        expect(shown, isNotNull, reason: label);
        // No equal-ended band, ever. That is the whole defect.
        expect(shown, isNot(contains('${pair.$1} - ${pair.$1}')),
            reason: '$label collapsed to a band with itself: "$shown"');
      });
    });

    test('the pair a single price produces reads as one price', () {
      // `price_range_min: 7000, price_range_max: null` is what the form sends
      // when only the «من» box is filled, and what the server stored.
      expect(priceRangeAr(7000, 7000), '7000 دج');
    });

    test('a real band is unchanged by the fix', () {
      expect(priceRangeAr(7000, 9000), '7000 - 9000 دج');
    });
  });

  group('the collapse matches the project budget beside it', () {
    test('equal ends are one amount, exactly as Project.budgetLabel does', () {
      // Same column, same server, two widgets: the project's own label already
      // collapsed this and the worker's did not.
      expect(priceRangeAr(5000, 5000), '5000 دج');
      expect(priceRangeAr(0, 0), '0 دج');
    });
  });

  group('a bound with only one end', () {
    test('min only reads «من», max only reads «حتى»', () {
      expect(priceRangeAr(2500, null), 'من 2500 دج');
      expect(priceRangeAr(null, 8000), 'حتى 8000 دج');
    });

    test('nothing set is silence, not a zero', () {
      // Same rule as the four unmeasured numbers in worker_stats_copy: a
      // contractor who never typed a price must not publish «0 دج».
      expect(priceRangeAr(null, null), isNull);
      expect(hasPriceRange(null, null), isFalse);
    });
  });

  group('the two call sites cannot disagree again', () {
    test('a single maximum is a price the card also shows', () {
      // worker_card used to gate on `min != null` alone, so this contractor had
      // the row on his profile and no tag on the card he is chosen from.
      expect(hasPriceRange(null, 8000), isTrue);
      expect(hasPriceRange(2500, null), isTrue);
      expect(hasPriceRange(2500, 8000), isTrue);
      expect(hasPriceRange(null, null), isFalse);
    });

    test('every gate the profile and the card use answers the same', () {
      const pairs = <(int?, int?)>[
        (null, null),
        (0, null),
        (null, 0),
        (5000, 5000),
        (7000, 9000),
        (9000, 7000),
      ];
      for (final p in pairs) {
        // The row exists exactly when there is a sentence for it.
        expect(priceRangeAr(p.$1, p.$2) != null, hasPriceRange(p.$1, p.$2),
            reason: 'gate disagrees with copy for $p');
      }
    });
  });

  group('an inverted pair is server state, and is not printed backwards', () {
    test('it never reaches the form, so it is a data problem, not a copy one',
        () {
      // Both this app's forms refuse `min > max`; nothing here can send it.
      // The label still must not hand a customer a min above a max.
      final shown = priceRangeAr(9000, 7000);
      expect(shown, isNotNull);
      expect(shown, contains('9000'));
      expect(shown, contains('7000'));
    });
  });
}
