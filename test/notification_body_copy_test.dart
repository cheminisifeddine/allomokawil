// The sentence under a notification headline, pinned from the live wire.
//
// The fixtures in this file are the exact `body` values `/api/notifications`
// returned on 28 Sep 2026 for a quote, an accepted quote, a published project
// and two reviews — see the header of
// `lib/src/data/notification_body_copy.dart`. The review bodies are the reason
// this file exists: the Worker sends a bare `5/5`, and the card printed it.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/data/notification_body_copy.dart';

void main() {
  group('the live wire', () {
    test('every body the API really sends is answered in Arabic', () {
      // Captured verbatim from production, not invented.
      const live = {
        'new_quote': 'جاهز للبدء',
        'project_update': 'اختبار الإشعار',
        'quote_accepted': 'مبارك! تم اختيارك لتنفيذ المشروع',
        'review_received': '5/5',
      };
      live.forEach((type, body) {
        final shown = notificationBodyCopy(body, type: type);
        expect(shown, isNotEmpty, reason: type);
        expect(isArabicCopy(shown), isTrue,
            reason: '$type rendered non-Arabic: "$shown" (from "$body")');
      });
    });

    test('the review score is the only body the Worker sends as a fraction',
        () {
      // The three that carry a person\'s words must survive untouched.
      expect(notificationBodyCopy('جاهز للبدء', type: 'new_quote'),
          'جاهز للبدء');
      expect(notificationBodyCopy('اختبار الإشعار', type: 'project_update'),
          'اختبار الإشعار');
      expect(
          notificationBodyCopy('مبارك! تم اختيارك لتنفيذ المشروع',
              type: 'quote_accepted'),
          'مبارك! تم اختيارك لتنفيذ المشروع');
    });
  });

  group('a bare rating is named, never printed as a fraction', () {
    test('5/5 and 3/5, the two the live API actually sent', () {
      expect(notificationBodyCopy('5/5', type: 'review_received'),
          'حصلت على تقييم 5 نجوم');
      expect(notificationBodyCopy('3/5', type: 'review_received'),
          'حصلت على تقييم 3 نجوم');
    });

    test('the single-star and dual forms read as Arabic nouns', () {
      expect(notificationBodyCopy('1/5', type: 'review_received'),
          'حصلت على تقييم نجمة');
      expect(notificationBodyCopy('2/5', type: 'review_received'),
          'حصلت على تقييم نجمتين');
      expect(notificationBodyCopy('4/5', type: 'review_received'),
          'حصلت على تقييم 4 نجوم');
    });

    test('a numerator above its own scale is pinned, not printed', () {
      // **This assertion used to say the opposite**, which is the whole point:
      // it read '10/5' -> «10 نجوم» and passed, pinning ten stars onto a
      // five-star scale. The score came straight off the wire with nothing
      // bounding it, so a drifted aggregate told a contractor his work was
      // rated double the top of the scale the form can produce.
      //
      // The test above now carries `4/5` instead, and that is a real
      // consequence rather than tidying: pinning a five-star body to five makes
      // **the 11+ counted form of «نجمة» unreachable on this path**. It is
      // still reachable in the app — `arabicCounted` is shared — but it can no
      // longer be exercised through a bare `/5` fraction, and the clause is
      // recorded here rather than quietly deleted so nobody reads the removal
      // as coverage that was never there.
      expect(notificationBodyCopy('10/5', type: 'review_received'),
          'حصلت على تقييم 5 نجوم');
    });

    test('spaces around the slash are still a bare score', () {
      expect(notificationBodyCopy('  4 / 5 ', type: 'review_received'),
          'حصلت على تقييم 4 نجوم');
    });

    test('a fraction with a sentence is a person writing and is kept', () {
      // Anchored on purpose: "5/5 عمل ممتاز" is not a score, it is a note.
      const mixed = '5/5 عمل ممتاز';
      expect(notificationBodyCopy(mixed, type: 'review_received'), mixed);
      expect(isBareRatingBody(mixed), isFalse);
    });

    test('a number that merely contains a slash is not a score', () {
      expect(isBareRatingBody('5/5stars'), isFalse);
      expect(isBareRatingBody('1/2'), isTrue);
    });

    test('the denominator is the server\'s, not an assumed five', () {
      // A future ten-star form must not be described as out of five.
      final ten = notificationBodyCopy('8/10', type: 'review_received');
      expect(ten, contains('8'));
      expect(ten, contains('10'));
      expect(isArabicCopy(ten), isTrue);
    });
  });

  group('a missing body is still a line', () {
    test('a review with no body says so', () {
      final shown = notificationBodyCopy(null, type: 'review_received');
      expect(shown, 'لا تفاصيل');
      expect(isArabicCopy(shown), isTrue);
    });

    test('a message with no body points at the inbox, not at nothing', () {
      // "لا تفاصيل" on a new_message row would be a lie: the message is in
      // the inbox, unread. This is the one type the copy must not flatten.
      final shown = notificationBodyCopy(null, type: 'new_message');
      expect(shown, isNot('لا تفاصيل'));
      expect(shown, contains('الرسائل'));
      expect(isArabicCopy(shown), isTrue);
    });

    test('a blank or whitespace body is treated as no body', () {
      for (final blank in ['', '   ', '\n\t ']) {
        expect(notificationBodyCopy(blank, type: 'new_quote'), 'لا تفاصيل');
      }
    });

    test('an unknown type still gets a line', () {
      final shown = notificationBodyCopy(null, type: 'brand_new_event');
      expect(shown.isNotEmpty, isTrue);
      expect(isArabicCopy(shown), isTrue);
    });
  });

  group('never empty, never a fraction', () {
    test('no input at all produces a line, for every type the API sends', () {
      for (final type in const [
        'new_quote',
        'new_message',
        'project_update',
        'quote_accepted',
        'review_received',
      ]) {
        final shown = notificationBodyCopy(null, type: type);
        expect(shown.trim(), isNotEmpty, reason: type);
        expect(isArabicCopy(shown), isTrue, reason: type);
      }
    });

    test('nothing that reaches the user contains a bare x/y', () {
      const bodies = ['5/5', '3/5', ' 2 / 5 ', null, '', 'الجاهز'];
      for (final b in bodies) {
        expect(RegExp(r'^\s*[0-9]\s*/\s*[0-9]\s*$')
                .hasMatch(notificationBodyCopy(b, type: 'review_received')),
            isFalse,
            reason: 'a bare fraction reached the user for "$b"');
      }
    });
  });
}
