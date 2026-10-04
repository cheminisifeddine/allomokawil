// Which contractors the app is willing to call «أفضل المقاولين», and what
// makes a rating worth reading as a ranking.
//
// Found on 4 Oct 2026, the fourth member of the "the app trusts an order it
// does not own" class this repo has now paid for three times
// (`review_order.dart` 29 Sep, `project_order.dart` 4 Oct, and this one).
// The first two were **latent**: the wire happened to answer in the order the
// screen wanted and the defect would only surface the day a server `ORDER BY`
// changed. This one is **visible on production right now**.
//
// The strip under «أفضل المقاولين» draws `topWorkers`, which returned the
// server's order untouched. Measured over 50 live rows on allomokawil.com on
// 4 Oct, the twelve cards a client actually saw were:
//
//   1. مقاول أحمد        5.0   1 review    1 job   unverified
//   2. E2E اختبار…       5.0   1 review    1 job   unverified
//   3. E2E اختبار…       5.0   1 review    1 job   unverified
//   4. مقاول (5596)      5.0   1 review    1 job   unverified
//   5. مقاول (4223)      5.0   1 review    1 job   unverified
//   6. سعيد بوسعادة      4.9  15 reviews  28 jobs  verified
//   7. عمر بن علي        4.8  24 reviews  45 jobs  verified
//   …
//
// **Five of the first five cards a client ever sees were accounts with a single
// review, one completed job and no verified documents**, drawn above a
// 45-job verified pro — because the server sorts a mean over one review as if
// it were a mean over twenty-four. A mean is a claim about a *set*, and a set
// of one carries no information about the rest of the man's work; the app was
// printing it as the headline on the card a customer picks a tradesman from.
//
// This is the **exact** reading [WorkerProfile.hasRating] already refused to
// make. It folds `avg_rating: 0` to null because 0 is not a mean of a 1–5
// form. `avg_rating: 5.0` computed from one review is not a rank anybody can
// act on either, and it is the mirror of the same mistake: a real-looking
// number standing in for evidence that does not exist. The server sends both.
// The card already hides the 0; this file owns the other half.
//
// ## The rule is a PARTITION, and deliberately not a sort
//
// The first version of this file sorted each group by review count. Measured
// against the live rows, that was **worse than the bug it replaced**: within
// the rows that have real evidence the server already answers in strict
// rating order (4.9, 4.8, 4.7, 4.6, 4.5, 4.4, 4.3, 4.1, 4.0), with a paid
// `search_boost` (gold 5, pro 3, basic 1, free 0) interleaved. Sorting by
// evidence would have put a 4.7 with 30 reviews above a 4.9 with 15, i.e. the
// app would have started overruling the server's ranking — including the part
// of it the founder pays for. The server is the only party here that knows
// what its formula weighs; this app does not re-implement anybody's pricing
// model. So server order is **preserved exactly** inside each group, and the
// only thing this file decides is which group a contractor belongs to.
//
// Nothing is dropped either. A brand-new man with no reviews is a real man and
// the strip is where he gets found — which is why `topWorkers` fetches
// `limit * 4` when a wilaya is preferred, and that instinct is right. He goes
// last, not off-screen.
//
// No tie-break is needed, and that is the second thing the measurement settled:
// a stable partition never reorders rows, so the property `project_order.dart`
// needed `List.sort` and an id comparison to get is free here.
library;

import '../models/worker.dart';

/// The order the strip draws, with single-observation rows moved behind the
/// ones a customer can actually compare.
///
/// Server order is preserved inside each group — see the header for what that
/// costs and why it is the whole point.
List<WorkerProfile> evidenceBeforeAssertion(List<WorkerProfile> rows) {
  final proven = <WorkerProfile>[];
  final unproven = <WorkerProfile>[];
  for (final w in rows) {
    (w.totalReviews > 1 ? proven : unproven).add(w);
  }
  return <WorkerProfile>[...proven, ...unproven];
}
