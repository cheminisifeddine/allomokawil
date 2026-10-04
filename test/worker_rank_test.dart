// The strip under «أفضل المقاولين» must not rank a single opinion above
// twenty-four.
//
// Found on 4 Oct 2026 from 50 live rows on allomokawil.com, not from reading
// code: the unfiltered `topWorkers` answer opens with five accounts of
// `total_reviews: 1`, `total_completed_jobs: 1`, `verification_status:
// pending`, each carrying `avg_rating: 5.0`, above a verified contractor with
// 24 reviews and 45 completed jobs. The heading says *best*; a mean over one
// customer is not a ranking.
//
// The numbers below are the wire's own, transcribed from that payload — the
// point of the test is that it fails on the order the server actually sent, not
// on a hand-picked arrangement that would have passed either way.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/worker_rank.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/worker.dart';

WorkerProfile _w({
  required int id,
  required double rating,
  required int reviews,
  int jobs = 0,
  VerificationStatus status = VerificationStatus.verified,
}) =>
    WorkerProfile(
      id: id,
      userId: id * 10,
      fullName: 'مقاول $id',
      specialties: const ['painting'],
      experienceYears: 3,
      isAvailable: true,
      verificationStatus: status,
      avgRating: rating,
      totalReviews: reviews,
      totalCompletedJobs: jobs,
    );

void main() {
  group('evidenceBeforeAssertion', () {
    test('the live 4 Oct payload: five 1-review accounts stop being first', () {
      // Exactly the twelve rows the client saw, in the server's order.
      final live = <WorkerProfile>[
        _w(id: 14, rating: 5, reviews: 1, jobs: 1, status: VerificationStatus.pending),
        _w(id: 68, rating: 5, reviews: 1, jobs: 1, status: VerificationStatus.pending),
        _w(id: 71, rating: 5, reviews: 1, jobs: 1, status: VerificationStatus.pending),
        _w(id: 142, rating: 5, reviews: 1, jobs: 1, status: VerificationStatus.pending),
        _w(id: 143, rating: 5, reviews: 1, jobs: 1, status: VerificationStatus.pending),
        _w(id: 3, rating: 4.9, reviews: 15, jobs: 28),
        _w(id: 1, rating: 4.8, reviews: 24, jobs: 45),
        _w(id: 5, rating: 4.7, reviews: 30, jobs: 55),
        _w(id: 2, rating: 4.6, reviews: 18, jobs: 32),
        _w(id: 4, rating: 4.5, reviews: 12, jobs: 22),
        _w(id: 7, rating: 4.4, reviews: 10, jobs: 20),
        _w(id: 6, rating: 4.3, reviews: 8, jobs: 15, status: VerificationStatus.pending),
      ];

      final out = evidenceBeforeAssertion(live);

      expect(out.first.id, 3,
          reason: 'the highest server-ranked row with real evidence leads, '
              'not a 5.0 built from one review');
      expect(
        out.take(5).map((w) => w.id).toList(),
        [3, 1, 5, 2, 4],
        reason: 'the proven rows keep the server\'s own order — the app decides '
            'which group a contractor is in, not how he ranks inside it',
      );
      expect(
        out.take(5).every((w) => w.totalReviews > 1),
        isTrue,
        reason: 'no single-observation rating survives in the first five',
      );
    });

    test('server order inside the proven group is preserved, not re-sorted', () {
      // The measurement that killed the first version of the rule: the server
      // already answers 4.9, 4.8, 4.7… and a review-count sort would have put
      // this 4.7-with-30-reviews above this 4.9-with-15. Sorting would have
      // been *worse* than the bug, and would have overruled the paid
      // `search_boost` the founder buys.
      final live = <WorkerProfile>[
        _w(id: 3, rating: 4.9, reviews: 15),
        _w(id: 1, rating: 4.8, reviews: 24),
        _w(id: 5, rating: 4.7, reviews: 30),
        _w(id: 2, rating: 4.6, reviews: 18),
      ];

      expect(evidenceBeforeAssertion(live).map((w) => w.id).toList(),
          [3, 1, 5, 2]);
    });

    test('a single-observation row outranked nobody — it goes last', () {
      final out = evidenceBeforeAssertion(<WorkerProfile>[
        _w(id: 99, rating: 5, reviews: 1),
        _w(id: 8, rating: 4.1, reviews: 5),
      ]);

      expect(out.map((w) => w.id).toList(), [8, 99]);
    });

    test('nobody is dropped, including an unrated brand-new contractor', () {
      // A new man is a real man and the strip is where he is found — he goes
      // last, never off-screen. `avg_rating: 0` is the server's sentinel, not a
      // mean (see [WorkerProfile.hasRating]), and such a row must still draw.
      final out = evidenceBeforeAssertion(<WorkerProfile>[
        _w(id: 73, rating: 0, reviews: 0, status: VerificationStatus.pending),
        _w(id: 8, rating: 4.1, reviews: 5),
      ]);

      expect(out.map((w) => w.id).toList(), [8, 73]);
    });

    test('two identical rows do not swap between two reads', () {
      // A stable partition needs no tie-break — `List.sort` is not stable, and
      // this rule deliberately uses none.
      final rows = <WorkerProfile>[
        _w(id: 5, rating: 5, reviews: 1),
        _w(id: 4, rating: 5, reviews: 1),
      ];

      expect(evidenceBeforeAssertion(rows).map((w) => w.id).toList(), [5, 4]);
      expect(evidenceBeforeAssertion(rows).map((w) => w.id).toList(), [5, 4]);
    });

    test('an empty feed stays empty', () {
      expect(evidenceBeforeAssertion(const <WorkerProfile>[]), isEmpty);
    });

    test('the original list is not mutated', () {
      final rows = <WorkerProfile>[
        _w(id: 1, rating: 5, reviews: 1),
        _w(id: 2, rating: 4.5, reviews: 9),
      ];

      evidenceBeforeAssertion(rows);

      expect(rows.map((w) => w.id).toList(), [1, 2],
          reason: 'the caller keeps its own order; the repo owns this list');
    });
  });
}
