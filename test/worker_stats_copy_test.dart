// A contractor's own numbers, in the four forms Arabic counts.
//
// Found on 26 Sep 2026, one file over from the subscription countdown. Four
// screens printed `'${worker.experienceYears} سنة خبرة'` and friends by string
// interpolation: one fixed noun for every count, so «3 سنة خبرة» and «11 سنة
// خبرة» for a noun whose plural is «سنوات», and «3 تقييم» for a noun whose
// plural is «تقييمات». These are the four numbers a customer reads before he
// sends anyone a message.
//
// The second defect is the one worth the file: the profile cover printed
// `'استجابة خلال ${worker.responseTimeHours ?? 0}h'`, so every new account —
// nobody has ever timed a reply — announced «استجابة خلال 0h». The app was
// asserting a measured fact on the profile a customer picks from, about a man
// who has not answered a single message.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/worker_stats_copy.dart';

void main() {
  group('experience', () {
    test('1 / 2 / 3-10 / 11+ each take their own form', () {
      expect(experienceYearsAr(1), 'سنة خبرة');
      expect(experienceYearsAr(2), 'سنتان خبرة');
      expect(experienceYearsAr(3), '3 سنوات خبرة');
      expect(experienceYearsAr(10), '10 سنوات خبرة');
      expect(experienceYearsAr(11), '11 سنة خبرة');
      expect(experienceYearsAr(25), '25 سنة خبرة');
    });

    test('the singular is never counted with a 1', () {
      expect(experienceYearsAr(1), isNot(contains('1 ')));
    });

    test('zero experience is no line, not «0 سنة خبرة»', () {
      expect(experienceYearsAr(0), isNull);
      expect(experienceYearsAr(-1), isNull);
    });
  });

  group('completed jobs', () {
    test('the participle rides in the plural too', () {
      expect(completedJobsAr(1), 'مشروع منجز');
      expect(completedJobsAr(2), 'مشروعان منجزان');
      // Not «3 مشروع منجز» — the whole line is the thing being counted.
      expect(completedJobsAr(3), '3 مشاريع منجزة');
      expect(completedJobsAr(11), '11 مشروع منجز');
    });

    test('a contractor who has finished nothing prints nothing', () {
      expect(completedJobsAr(0), isNull);
    });
  });

  group('review count', () {
    test('تقييم takes تقييمات for 3-10', () {
      expect(reviewCountAr(1), 'تقييم');
      expect(reviewCountAr(2), 'تقييمان');
      expect(reviewCountAr(4), '4 تقييمات');
      expect(reviewCountAr(12), '12 تقييم');
    });

    test('no reviews is no line', () {
      expect(reviewCountAr(0), isNull);
    });
  });

  group('service radius, the last unmeasured number printing a zero', () {
    test('an unset radius is no row, not «0 كم»', () {
      // The defect: `POST /api/register` sends no radius, the parser gave the
      // absent field a 0, and the public profile printed
      // «نصف قطر الخدمة: 0 كم» — a claim about a man's own business that
      // nobody made.
      expect(serviceRadiusAr(null), isNull);
    });

    test('a stored 0 is a server default, not a decision', () {
      // The slider's floor is 1, so this app cannot save a 0. Reading it as
      // «he will not travel» would be reading a default as an answer.
      expect(serviceRadiusAr(0), isNull);
      expect(serviceRadiusAr(-5), isNull);
    });

    test('the kilometres agree with the number', () {
      expect(serviceRadiusAr(1), 'كيلومتر واحد');
      expect(serviceRadiusAr(2), 'كيلومترين');
      expect(serviceRadiusAr(5), '5 كيلومترات');
      expect(serviceRadiusAr(10), '10 كيلومترات');
      expect(serviceRadiusAr(11), '11 كيلومتر');
      expect(serviceRadiusAr(30), '30 كيلومتر');
    });

    test('the singular is never counted with a 1', () {
      expect(serviceRadiusAr(1), isNot(contains('1 ')));
    });

    test('it is the shared rule, not a second one', () {
      // 10 is plural, 11 is counted singular — the boundary every other count
      // in this app already shares.
      expect(serviceRadiusAr(10), '10 كيلومترات');
      expect(serviceRadiusAr(11), '11 كيلومتر');
    });
  });

  group('reply speed, where a null was printing a lie', () {
    test('an unmeasured reply is dropped, not printed as zero', () {
      // The defect: this used to render «استجابة خلال 0h» for every account
      // that had never been timed.
      expect(responseTimeAr(null), isNull);
    });

    test('a reply inside the hour is «أقل من ساعة», not «0 ساعة»', () {
      // 0 here is a *measurement* that came back under an hour, which is a
      // different fact from having no measurement at all. Both used to print 0.
      expect(responseTimeAr(0), 'أقل من ساعة');
    });

    test('a measured reply agrees with itself', () {
      expect(responseTimeAr(1), 'ساعة');
      expect(responseTimeAr(2), 'ساعتين');
      expect(responseTimeAr(5), '5 ساعات');
      expect(responseTimeAr(24), '24 ساعة');
    });
  });

  group('the counts here are the same rule the notification clock uses', () {
    test('the hours boundary is the shared one, not a second one', () {
      // 10 is plural, 11 is counted singular. If this file ever grows its own
      // threshold, this is the test that notices.
      expect(responseTimeAr(10), '10 ساعات');
      expect(responseTimeAr(11), '11 ساعة');
      expect(experienceYearsAr(10), '10 سنوات خبرة');
      expect(experienceYearsAr(11), '11 سنة خبرة');
    });
  });
}
