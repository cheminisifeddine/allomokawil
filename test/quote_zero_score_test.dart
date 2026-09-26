// A bid said «0.0 out of five» for a contractor who does have reviews — the
// same verdict the browse card printed, one layer over, still live.
//
// The last cycle folded `WorkerProfile.avgRating` to null so a stored `0` could
// not be printed as a score. It did not fold [Quote.workerAvgRating], which was
// a non-nullable `double` defaulting to `0`. Two models, one wire value, two
// opposite answers about whether a score exists.
//
// The old bid-card guard was `quote.workerTotalReviews > 0`, which is a
// *different field* from the score. A payload that says "he has reviews" and
// omits the score therefore sailed past the guard and printed five empty stars
// and «0.0» — for a man somebody actually did rate. That payload is the whole
// reason this test exists; it is a shape the old code got wrong in the
// opposite direction from the one already fixed.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/models/worker.dart';

const _projectId = 'b0b5644a223e43f37bf8d675bfb78ae509c184c0869d31103748489b45ece551';

/// Straight off `GET /api/mobile/projects/{id}/quotes`, with the review
/// fields open so each case can be stated exactly.
Map<String, dynamic> _row({
  double? avgRating = 0,
  int? totalReviews = 0,
  int id = 13,
  String name = 'مقاول تجربة',
  String verification = 'pending',
}) =>
    <String, dynamic>{
      'id': id,
      'project_id': _projectId,
      'worker_id': 16,
      'amount': 75000,
      'message': 'جاهز للبدء فوراً',
      'estimated_days': 5,
      'status': 'pending',
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'worker_full_name': name,
      'worker_avatar_url': null,
      'worker_avg_rating': avgRating,
      'worker_total_reviews': totalReviews,
      'worker_verification_status': verification,
    };

Quote _parse(Map<String, dynamic> json) => Quote.fromJson(json);

void main() {
  group('the sentinel is refused on the bid too', () {
    test('the live payload says "not rated" rather than "rated 0.0"', () {
      // The exact row in `live_payload_models_test.dart`, which is the wire.
      final q = _parse(_row());
      expect(q.workerTotalReviews, 0);
      expect(q.workerAvgRating, isNull,
          reason: 'a 0 from the server is "never rated", not a mean');
      expect(q.hasRating, isFalse);
    });

    test('a real score is kept, decimals and all', () {
      final q = _parse(_row(avgRating: 4.5, totalReviews: 3));
      expect(q.workerAvgRating, 4.5);
      expect(q.hasRating, isTrue);
      // 0.5 is the boundary the old `> 0` could have destroyed if it had been
      // written as a rounding or truncation; the fold must not touch it.
      final half = _parse(_row(avgRating: 0.5, totalReviews: 1));
      expect(half.workerAvgRating, 0.5);
    });

    test('a missing field is null, and so is a 0, and neither is a score', () {
      final missing = _row()..remove('worker_avg_rating');
      expect(_parse(missing).workerAvgRating, isNull);
      expect(_parse(_row(avgRating: 0)).hasRating, isFalse);
    });

    test('both models read one wire value the same way', () {
      // The drift this file exists to stop: `WorkerProfile` already folds 0 to
      // null. If these two ever disagree again the card and the bid disagree
      // about the same man on two screens he is chosen from.
      final profile = WorkerProfile.fromJson(<String, dynamic>{
        'id': 16,
        'user_id': 9,
        'full_name': 'مقاول تجربة',
        'avg_rating': 0,
        'total_reviews': 0,
        'total_completed_jobs': 0,
      });
      final quote = _parse(_row());
      expect(profile.hasRating, quote.hasRating);
      expect(profile.avgRating, quote.workerAvgRating);
    });
  });

  group('the divergence the old guard got wrong', () {
    // `worker_total_reviews > 0` was the gate. These two cases are the ones it
    // answered wrongly, and they are why the gate is now the score itself.
    test('reviews without a score is NOT printed as «0.0»', () {
      final q = _parse(_row(avgRating: 0, totalReviews: 7));
      expect(q.workerTotalReviews, 7,
          reason: 'the count really does say he has reviews');
      expect(q.hasRating, isFalse,
          reason: 'but there is no score to print, so no stars either');
    });

    test('a score with no count still prints the stars', () {
      // The mirror image, so the new gate cannot be quietly replaced by a
      // count check in the other direction.
      final q = _parse(_row(avgRating: 4.8, totalReviews: 0));
      expect(q.hasRating, isTrue);
    });
  });

  group('what the card says instead', () {
    test('the honest sentence carries no score in it', () {
      expect(noRatingAr(), 'لا تقييمات بعد');
      expect(noRatingAr(), isNot(contains('0')));
      expect(noRatingAr(), isNot(contains('0.0')));
    });
  });
}
