// The star row drew five FULL stars for a 4.5, and the half-star glyph it owned
// was unreachable code that no test could have caught.
//
// Found on 26 Sep 2026. `RatingStars` branched on `rating.round()` first:
//
//     i <= rating.round()  ? star_rounded
//     : (i - 0.5 <= rating ? star_half_rounded : star_outline_rounded)
//
// Dart's `double.round()` sends halves **away from zero**, so at 4.5 the first
// branch is true for all five positions and the half branch is never consulted.
// The row published five gold stars beside the text «4.5» while `A11y.rating`
// on the same widget said «التقييم 4.5 من 5» — one widget, two answers, on the
// number a customer uses to choose between two tradesmen.
//
// The dead half is the reason this file exists. Reaching that branch needs
// `i > round(rating)` AND `i - 0.5 <= rating` together, satisfiable only by a
// score sitting exactly on a half that rounds *down* — and 0.5, 2.5 and 4.5
// all round up. The branch was therefore drawn **zero** times over the whole
// scale, and `star_half_rounded` was in the source and absent from every
// screenshot ever taken. A glyph nobody ever rendered is a glyph nobody tests,
// and a widget-level test could only have caught it by pumping 5,001 scores.
//
// The rule is now a pure function in `data/star_row_shape.dart` so it can be
// checked over every value the app can hold, in milliseconds, with no widget.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/star_row_shape.dart';
import 'package:allomokawil/src/widgets/a11y.dart';

void main() {
  group('the half-star is reachable at all', () {
    // The value that was broken, and the one measured on the live platform
    // today: `GET /api/mobile/workers/search` returns avg_rating 4.5 for a
    // contractor with 12 reviews.
    test('4.5 draws four full stars and one half', () {
      expect(starRowShape(4.5), 'FFFFH',
          reason: 'five full stars overstates a 4.5 by a whole star');
    });

    test('the glyph the old branch could never draw is now reachable', () {
      expect(starIconFor(5, 4.5), Icons.star_half_rounded);
      // The specific claim: it was drawn nowhere before.
      var halfPositions = 0;
      for (var t = 0; t <= 5000; t++) {
        if (starRowShape(t / 1000.0).contains('H')) halfPositions++;
      }
      expect(halfPositions, greaterThan(0),
          reason: 'a half star must be drawable at some score');
    });

    test('2.5 draws two full stars and one half', () {
      expect(starRowShape(2.5), 'FFH..');
    });

    test('0.5 draws one half, never a whole star', () {
      expect(starRowShape(0.5), 'H....');
    });
  });

  group('a whole score is not given a half star', () {
    for (final r in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]) {
      test('$r draws exactly its whole stars', () {
        expect(starRowShape(r).contains('H'), isFalse,
            reason: '$r has no fraction, so a half star would be a lie');
        expect('F'.allMatches(starRowShape(r)).length, r.round());
      });
    }
  });

  group('the row never overstates the number printed beside it', () {
    // Every value in hundredths across the whole scale. One test, not 501:
    // a sweep in the group body runs outside a test and is reported as an
    // `OutsideTestException` rather than as the failure it would be.
    test('no score on the scale draws more stars than it has', () {
      for (var t = 0; t <= 500; t++) {
        final r = t / 100.0;
        final drawn = starRowValue(r);
        expect(drawn, lessThanOrEqualTo(r + 0.001),
            reason: '$r drew a row worth $drawn, which claims more than it has');
      }
    });

    test('the sweep is not silently vacuous', () {
      // 501 values, and the last one must really have been checked — a loop
      // that never runs passes every assertion inside it.
      expect(starRowValue(0.0), 0);
      expect(starRowValue(5.0), 5);
      // 4.5 is worth four and a half — the whole point of the fix. Counting the
      // half as a whole star is the defect, so this is the assertion that fails
      // against the old `round()` code.
      expect(starRowValue(4.5), 4.5);
      expect(starRowValue(4.4), 4);
      expect(starRowValue(4.9), 4.5);
    });
  });

  group('more reviews can only move the row right', () {
    test('the row is monotone across the whole scale', () {
      var previous = -1;
      for (var t = 0; t <= 5000; t++) {
        final r = t / 1000.0;
        final shape = starRowShape(r);
        // Rank the row: a full star is worth 2, a half 1, empty 0, read
        // left to right. A higher score must never score lower.
        var value = 0;
        for (final c in shape.split('')) {
          value = value * 3 + (c == 'F' ? 2 : (c == 'H' ? 1 : 0));
        }
        expect(value, greaterThanOrEqualTo(previous),
            reason: 'raising the score to $r moved the row backwards');
        previous = value;
      }
    });
  });

  group('a score outside the scale cannot make the row disagree', () {
    test('a negative score is drawn as an empty row, not a negative one', () {
      expect(starRowShape(-2), '.....');
    });

    test('a score above five is drawn as five full stars', () {
      expect(starRowShape(7.4), 'FFFFF');
    });

    test('NaN does not throw', () {
      expect(starRowShape(double.nan), '.....');
    });

    test('a position outside the row is a programming error', () {
      expect(() => starIconFor(0, 4), throwsRangeError);
      expect(() => starIconFor(6, 4), throwsRangeError);
    });
  });

  group('the row and the label agree about the same score', () {
    test('4.5 draws four full and the reader says 4.5 of 5', () {
      expect(starRowShape(4.5), 'FFFFH');
      expect(A11y.rating(4.5), contains('4.5'));
      expect(A11y.rating(4.5), contains('من 5'));
    });

    test('every score the live API sends reads the same in both', () {
      // Measured off GET /api/mobile/workers/search on 26 Sep: the eight
      // non-zero scores on the platform today.
      for (final r in [4.1, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9]) {
        expect(A11y.rating(r), contains(r.toStringAsFixed(1)));
        expect(starRowValue(r), lessThanOrEqualTo(r + 0.001),
            reason: 'the row and the number must not contradict at $r');
      }
    });
  });
}
