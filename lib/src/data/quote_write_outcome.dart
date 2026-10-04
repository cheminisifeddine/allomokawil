// Proving that a contractor's **bid** reached the server — the one write on the
// project detail screen whose re-read asks a question the market answers
// without the write.
//
// Found 4 Oct 2026 by the audit the last four ticks ended on. Every other write
// in this family re-reads with a predicate that can be *false* before the write
// is sent. `verificationLanded` asks whether the document queue **grew**.
// `resolveProjectEditOutcome` asks whether the row now **carries the values
// this form was sending**. `redeemLanded` asks whether the plan **moved**. The
// bid path asked:
//
//     rows.any((q) => q.amount == amt && (mine <= 0 || q.workerId == mine))
//
// and that predicate is **true before the contractor ever taps «إرسال العرض»**,
// for the same reason the edit path's was: the amount he is about to type is not
// a secret, and 70000 دج is a number a great many Algerian bids carry. Two
// things make it worse than the edit case, and both are measured on production,
// not argued:
//
//   * **the fallback drops identity.** `mine <= 0` — the branch taken whenever
//     `myProfile()` could not be read — matches on the **amount alone**. The
//     re-read then asks «does *anybody* on this job bid 70000?», which is a
//     question about the project, not about this contractor's write.
//
//   * **identical amounts are ordinary.** Measured 4 Oct on production: workers
//     **148** and **149** both hold a bid for **70000** on the same project, and
//     the list the re-read reads returns both rows. Amount is a number the
//     market sets; identity is not. The bid is also the one write a contractor
//     is most likely to have *already* filed once on the same job, which is the
//     decoy the amount test cannot see.
//
// The Worker refuses a second bid from the same worker on the same project —
// `لقد قدّمت عرضاً لهذا المشروع بالفعل`, measured — so the write that **cannot**
// land twice is the one the app reports as arriving when it never left the
// phone, and the retry it invites is refused before it is sent.
//
// **The rule is a difference, not an equality — the rule `redeem_outcome.dart`
// and `verification_write_outcome.dart` land on.** The phone already knows which
// bids were on screen when he tapped: [before]. The re-read returns [after]. A
// bid of **his**, carrying an id the earlier list did not hold, is his write. A
// bid that was already in [before] is somebody's — his own earlier attempt, or a
// neighbour's at the same figure — and is evidence of nothing about the POST
// that never answered.
//
// **Identity is required, and its absence is `unknown`, never a fallback.**
// The first version of this file read identity off the snapshots themselves,
// intersecting [before] and [after] on `id` — and that is wrong in the ordinary
// case, which is the common one: a contractor bidding for the first time has
// **no** bids in [before], so the intersection is empty, every bid is a rival's,
// and a bid that genuinely landed is reported as missing. Answering «did not
// arrive» for the write that did arrive is the expensive direction here, because
// the sentence it prints tells him to press send again on a job the server
// refuses a second bid on. So the worker id is asked of the caller, and when it
// cannot be established the honest answer is [WriteOutcome.unknown]: the phone
// cannot tell his bid from a neighbour's, and «unknown» is the only sentence
// that does not lie about which of the two it is.
//
// A re-read that fails is [WriteOutcome.unknown] for the same reason — «did not
// arrive» is what makes a man press send twice.
library;

import '../core/l10n/write_outcome.dart';
import '../models/quote_review.dart';

/// True when [after] holds a bid of [workerId]'s that [before] did not.
///
/// [before] and [after] are both required, for the reasons in the header:
/// [before] alone asserts the write in advance, and [after] alone asks a
/// question the market answers without the write.
///
/// A **null** [workerId] means the identity could not be established, and the
/// answer is **false** — never a widened match. The caller reads that as
/// [WriteOutcome.unknown] rather than [WriteOutcome.missing], and that is the
/// whole reason the parameter is nullable rather than defaulted: a widened
/// fallback is the bug this file exists to remove, and leaving the door open
/// for a caller that cannot prove identity is how it came back.
bool quoteLanded({
  required List<Quote> before,
  required List<Quote> after,
  required int? workerId,
}) {
  if (workerId == null || workerId <= 0) return false;
  // Only **his own** rows in [before] count as already-present. A neighbour's
  // bid at the same amount is not something this write overwrote, so it must
  // not enter the set — otherwise a first bid at a figure a rival already used
  // would compare against a row that was never his and the delta would be
  // computed over the wrong list.
  final alreadySent = {
    for (final q in before)
      if (q.workerId == workerId) q.id,
  };
  return after.any(
      (q) => q.workerId == workerId && !alreadySent.contains(q.id));
}

/// Runs the honest re-read for a bid that was not confirmed, and classifies it.
///
/// [identity] is this account's worker id, resolved by the caller because it
/// may need its own request. A failure inside it is **not** swallowed and
/// silently widened: it resolves to `null`, which [quoteLanded] reads as no
/// identity, and this returns [WriteOutcome.unknown] — the one answer that
/// reports nothing it cannot prove.
///
/// Same contract as every other write in the app: it must not throw, and a
/// second network failure while one is already being reported is
/// [WriteOutcome.unknown], never `missing`.
Future<WriteOutcome> resolveQuoteWriteOutcome({
  required List<Quote> before,
  required int? workerId,
  required Future<List<Quote>> Function() fetch,
}) async {
  if (workerId == null || workerId <= 0) return WriteOutcome.unknown;
  List<Quote> after;
  try {
    after = await fetch();
  } catch (_) {
    return WriteOutcome.unknown;
  }
  return quoteLanded(before: before, after: after, workerId: workerId)
      ? WriteOutcome.landed
      : WriteOutcome.missing;
}
