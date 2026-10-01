// The review notification named a score the form cannot produce.
//
// Found on 1 Oct 2026 by auditing what the `clampRating` lift (commit `75cf44d`,
// three ticks ago) did not reach. That fix pinned a rating to the scale the row
// draws — glyphs, printed digits and the spoken label — because a payload
// carrying `7.5` drew `FFFFF` next to the text `7.5` and announced
// «التقييم 7.5 من 5». It was right about what it covered and silent about the
// rest: `grep clampRating` returned six call sites, and the fourth *rating
// surface in this app* is not one of them.
//
// It is [notification_body_copy.dart], and it is the one a contractor opens to
// find out how a customer rated his work. The Worker sends a bare fraction
// (`"body":"5/5"`) and the card turns it into a sentence — so the score is
// printed from the wire with **no upper bound at all**:
//
//   '7/5'  ->  «حصلت على تقييم 7 نجوم»      <- seven stars, out of five
//   '7/0'  ->  «حصلت على تقييم 7 من 0»       <- out of nothing
//
// The first is the contradiction `star_row_shape.dart` exists to prevent, on a
// second screen, in a different file, three ticks after it was fixed on the
// first. The review form is 1–5, so **no** payload should ever carry a 7 — but
// the whole reason `clampRating` exists is that the server is the only writer
// of that column and the phone does not get to assume it behaves. A drifted
// aggregate, a future ten-star form shipping before the client knows, a bad
// join: any of them prints the sentence beside a five-star row and tells a
// paying contractor his work was rated above the top of the scale.
//
// The second is `out == 0` — `_toInt` returns 0 for an unparseable or missing
// denominator, and `out == 0` is neither `null` nor `5`, so it fell through to
// the `من $out` arm. «من 0» is a score out of no scale at all, which is not a
// number to show a man deciding whether his work was appreciated.
//
// **Both are the same defect and get the same rule.** A fraction's numerator is
// pinned to its own denominator, exactly as a rating is pinned to the row's
// star count — and a scale of zero has no numerator to print, so it says the
// thing that is true instead of a count nobody can check.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/data/notification_body_copy.dart';

void main() {
  group('a score above its own scale is pinned, not printed', () {
    test('7/5 must not say seven stars', () {
      final shown = notificationBodyCopy('7/5', type: 'review_received');
      expect(shown, isNot(contains('7')),
          reason: 'the numerator was printed raw: "$shown"');
      expect(isArabicCopy(shown), isTrue, reason: shown);
    });

    test('the pinned score is the top of the scale the server stated', () {
      // The denominator is the server's own — a future ten-star form is a real
      // thing this app is written to survive — so 12/10 pins to 10, not to the
      // literal five the star row happens to draw.
      final shown = notificationBodyCopy('12/10', type: 'review_received');
      expect(shown, isNot(contains('12')), reason: shown);
      expect(shown, contains('10'), reason: shown);
    });

    test('a legal score on a wider scale is left alone by the pin', () {
      // The direction that matters: the pin bounds the score, it does not
      // filter it. 9/10 is inside a ten-star scale and must still be reported as
      // what it says, or the fix would have replaced a lie with a silence.
      final shown = notificationBodyCopy('9/10', type: 'review_received');
      expect(shown, contains('9'), reason: shown);
      expect(shown, contains('10'), reason: shown);
    });

    test('a wildly out-of-range numerator is still pinned', () {
      for (final body in ['100/5', '99/5', '6/5']) {
        final shown = notificationBodyCopy(body, type: 'review_received');
        final numerator = body.split('/').first;
        expect(shown, isNot(contains(numerator)),
            reason: '"$body" printed its numerator raw: "$shown"');
        expect(isArabicCopy(shown), isTrue, reason: shown);
      }
    });
  });

  group('a scale of zero is not a scale', () {
    test('7/0 does not print a score out of nothing', () {
      final shown = notificationBodyCopy('7/0', type: 'review_received');
      expect(shown, isNot(contains('0')), reason: shown);
      expect(isArabicCopy(shown), isTrue, reason: shown);
    });

    test('0/0 is answered with a line, not with a fraction', () {
      final shown = notificationBodyCopy('0/0', type: 'review_received');
      expect(shown.trim(), isNotEmpty);
      expect(isArabicCopy(shown), isTrue, reason: shown);
    });
  });

  // ── The gate that fires for a real score must keep firing ──────────────
  // A guard that simply stopped printing numbers would pass every test above
  // and ship a silent notification centre. These are the values the live API
  // really sends, and they are the ones the loop must not break.
  group('every score the live wire sends is unchanged', () {
    test('the two the Worker actually sent on 28 Sep', () {
      expect(notificationBodyCopy('5/5', type: 'review_received'),
          'حصلت على تقييم 5 نجوم');
      expect(notificationBodyCopy('3/5', type: 'review_received'),
          'حصلت على تقييم 3 نجوم');
    });

    test('the singular and dual arms still print no number', () {
      expect(notificationBodyCopy('1/5', type: 'review_received'),
          'حصلت على تقييم نجمة');
      expect(notificationBodyCopy('2/5', type: 'review_received'),
          'حصلت على تقييم نجمتين');
    });

    test('a legal score on a wider scale still reports the real pair', () {
      // The arm the denominator fix must not swallow: 8/10 is a true statement
      // about a ten-star form and has to survive as «من 10».
      final ten = notificationBodyCopy('8/10', type: 'review_received');
      expect(ten, contains('8'), reason: ten);
      expect(ten, contains('10'), reason: ten);
      expect(isArabicCopy(ten), isTrue, reason: ten);
    });

    test('the exact scale edge still prints, so the pin is not a filter', () {
      expect(notificationBodyCopy('5/5', type: 'review_received'),
          contains('5'));
    });
  });

  group('a person who wrote words keeps them', () {
    test('5/5 عمل ممتاز is a note, not a score', () {
      const mixed = '5/5 عمل ممتاز';
      expect(notificationBodyCopy(mixed, type: 'review_received'), mixed);
      expect(isBareRatingBody(mixed), isFalse);
    });

    test('the non-score types are untouched by any of this', () {
      expect(notificationBodyCopy('جاهز للبدء', type: 'new_quote'),
          'جاهز للبدء');
      expect(notificationBodyCopy('اختبار الإشعار', type: 'project_update'),
          'اختبار الإشعار');
    });
  });
}
