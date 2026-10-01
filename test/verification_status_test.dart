// Verification status had four parsers, and the one the contractor's own
// home screen used never trimmed.
//
// Found 2 Oct 2026 by extending the search the plan-id item opened the night
// before: *one column, two names, several readers, no type making them
// agree.* `GET /api/mobile/workers/top` sends `verification_status`
// (observed live, 2 Oct: `'pending'`) and `GET /api/mobile/projects/{id}
// quotes` sends `worker_verification_status`. The same fact, two column
// names, and this app read it four ways:
//
//   1. `WorkerProfile._vd`     — no trim  -> ' verified ' == pending
//   2. `Quote.workerVerificationStatus` — a raw String, compared by the
//      trust widget in three separate places, each re-implementing the trim
//   3. `quoteWireVerification` — a fourth copy, added "for tests", which is
//      how a private function becomes a permanent second implementation
//   4. `VerificationStatus` — the enum itself, which had **no parser at all**
//
// The visible cost: a verified contractor whose row is padded read as
// **pending** on his own home screen. The «مقاول موثّق» pill disappeared and
// «غير موثّق» was drawn instead — while his bid card, going through the
// trimming string path, showed the green tick **at the same moment**. Two
// screens, one man, two answers, and the customer is the one who has to
// decide which to believe.
//
// `dossierUnderReview` makes it worse, because `pending` is also what
// `verificationPendingDocs` counts against: a padded verified profile can be
// told his papers are «قيد المراجعة» — the state a man is told to wait in.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/models/worker.dart';

/// One live worker row, the two columns the two models read.
WorkerProfile _worker(String? verification, {int pendingDocs = 0}) =>
    WorkerProfile.fromJson({
      'id': 14,
      'user_id': 9,
      'full_name': 'كريم حداد',
      'verification_status': verification,
      'verification_pending_docs': pendingDocs,
    });

Quote _quote(String? wire) => Quote.fromJson({
      'id': 13,
      'project_id': 'abc',
      'worker_id': 16,
      'amount': 75000,
      'worker_full_name': 'مقاول تجربة',
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': wire,
    });

void main() {
  group('the two models read one column, one way', () {
    test('the three states survive the round trip through both parsers', () {
      const pairs = {
        'verified': VerificationStatus.verified,
        'pending': VerificationStatus.pending,
        'rejected': VerificationStatus.rejected,
      };
      pairs.forEach((wire, expected) {
        expect(VerificationStatus.fromWire(wire), expected, reason: 'wire «$wire»');
        expect(_worker(wire).verificationStatus, expected,
            reason: 'WorkerProfile, wire «$wire»');
        expect(_quote(wire).workerVerificationStatus, expected,
            reason: 'Quote, wire «$wire»');
      });
    });

    test('the wire spelling is published, so the two models can be compared',
        () {
      for (final v in VerificationStatus.values) {
        expect(VerificationStatus.fromWire(v.wire), v,
            reason: '«${v.name}» must survive its own wire value');
      }
    });
  });

  group('padding, which is what the bug was', () {
    // The whole defect in four lines: `' verified '` is not `'verified'`, and
    // the reader that did not trim answered "pending" for a verified man.
    test('a padded verified is verified on both surfaces, not pending', () {
      for (final padded in const [' verified', 'verified ', '  verified  ']) {
        expect(VerificationStatus.fromWire(padded), VerificationStatus.verified,
            reason: '«$padded»');
        expect(_worker(padded).verificationStatus, VerificationStatus.verified,
            reason: 'WorkerProfile, «$padded» — was pending before 2 Oct');
        expect(_quote(padded).workerVerificationStatus,
            VerificationStatus.verified,
            reason: 'Quote, «$padded»');
      }
    });

    test('a padded rejected is rejected, so it never claims to be a queue',
        () {
      expect(_worker(' rejected ').verificationStatus,
          VerificationStatus.rejected);
    });

    test('padding cannot fake a verified — the guard does not get looser', () {
      for (final v in const ['verified\n', '\tverified\r', 'VERIFIED',
        'unverified', 'verified verified']) {
        final parsed = VerificationStatus.fromWire(v);
        if (v.trim() == 'verified') {
          expect(parsed, VerificationStatus.verified);
        } else {
          expect(parsed, isNot(VerificationStatus.verified), reason: '«$v»');
        }
      }
    });
  });

  group('what an unreadable value is allowed to claim', () {
    test('absent, empty and junk are pending — asked, not answered', () {
      for (final v in const [null, '', '   ', 'junk', '1', 'vérifié']) {
        expect(VerificationStatus.fromWire(v), VerificationStatus.pending,
            reason: '«$v»');
        expect(_worker(v).verificationStatus, VerificationStatus.pending);
      }
    });

    // A verified contractor with a paper trail in the queue must not be told
    // he is waiting: he is verified, and the count is a different question.
    test('a padded verified with queued docs is not "under review"', () {
      final w = _worker(' verified ', pendingDocs: 2);
      expect(w.verificationStatus, VerificationStatus.verified);
      expect(w.dossierUnderReview, isFalse,
          reason: '«قيد المراجعة» would be a lie about a verified man');
    });

    test('a genuinely pending profile with queued docs is still under review',
        () {
      final w = _worker('pending', pendingDocs: 2);
      expect(w.dossierUnderReview, isTrue);
    });
  });

  group('the two columns the server actually sends', () {
    test('the quote payload key is the one the model reads', () {
      // A rename on the Worker would land here as pending rather than as a
      // crash, which is the documented behaviour — but the *key* is pinned so
      // the rename cannot happen silently.
      expect(_quote('verified').workerVerificationStatus,
          VerificationStatus.verified);
    });
  });
}
