// What the reviews section says when its own read and the profile header's read
// disagree about whether this contractor has any reviews at all.
//
// Found 1 Oct 2026 by asking the live API about the same man twice, which is
// the only way to see this defect: the header and the section are two separate
// reads of one fact, and nothing in the app ever made them agree.
//
//   GET /api/mobile/workers/1            -> avg_rating 4.8, total_reviews 24
//   GET /api/mobile/workers/1/reviews    -> []
//
// Both are 200. The screen then shows, on one page, the contractor the customer
// is deciding on:
//
//     ★★★★★  4.8  (24)          <- header, from /workers/:id
//     لا تقييمات بعد                 <- section, from /workers/:id/reviews
//     التقييم يُكتب بعد إنجاز العمل — ابدأ بالتواصل معه.
//
// So the app tells a customer that a man nobody has rated has 24 ratings, and
// then instructs him to message that contractor so he can be given his *first*
// review. He leaves to start a conversation about work he has already been
// reviewed for 24 times, and the contractor is asked to rate a job that is not
// his to rate.
//
// **Which read is wrong is not the app's business, and it must not guess.** The
// aggregate can be stale and the list correct; the list can be scoped to what
// the viewer may see and the aggregate be the whole truth. Either way the
// honest answer is the same: the screen holds two claims, they contradict, and
// the section is the one that must stop asserting "he has none".
//
// That is why this returns null rather than a string for the ordinary case. A
// null means *there is nothing to reconcile* — the header agrees he has no
// reviews, so the plain «لا تقييمات بعد» is the true sentence and the caller
// draws exactly what it always did. This file only owns the case the app could
// not previously express, which is the whole reason it exists.
//
// It is the same rule [profile_section_failure_test.dart] already established
// one arm over: a read that cannot be backed is not an answer. A 500 must not
// be drawn as "no reviews", and a list that contradicts the header must not be
// drawn as "no reviews" either — the two differ only in which body came back,
// not in what the app is entitled to claim.
library;

import 'review_count.dart';
import 'worker_stats_copy.dart';

/// The sentence for an empty reviews section whose emptiness contradicts the
/// profile header, or null when the two agree and the ordinary empty state is
/// true.
///
/// [headerCount] is the review count the header printed beside the stars, and
/// it is the *aggregate*, deliberately: it is what the customer has already
/// read above this section, so it is the claim that has to be honoured. A
/// non-positive count is not a contradiction and answers null — a man with no
/// reviews really does have none, and that is the honest answer.
String? reviewsSectionUnbackedAr({required int headerCount}) =>
    headerCount > 0
        ? 'يظهر أعلاه ${headerCount == 1 ? 'تقييم واحد' : 'تقييمات'}، '
            'ولم تظهر تقييماته هنا. قد يكون الاتصال غير مستقر — أعد المحاولة.'
        : null;

/// The title for that section, naming the state rather than the count.
const String reviewsSectionUnbackedTitle = 'تقييماته غير معروضة الآن';

/// «لا تقييمات بعد», read from the one place that owns it.
///
/// The section used to type this sentence into its own [Text] while five other
/// surfaces called [noRatingAr], so this file could have been edited and the
/// section would have kept the old words — the private-copy shape that
/// `worker_home_screen.dart` shipped yesterday for the trade line. It is read
/// here rather than written here, which is the only thing that stops it
/// drifting.
String get reviewsSectionEmptyTitle => noRatingAr();

/// The review count the header **actually printed**, or 0 when it printed none.
///
/// This is the fix for the hole the first version of this file left, and it
/// was this loop's own code that left it. The section was handed
/// `WorkerProfile.totalReviews` — the raw column — and told that was "the
/// aggregate the header already printed above this section". It is not, and
/// the two disagree in a case the model layer documents as real:
///
///   avg_rating: 0, total_reviews: 24
///
/// `avg_rating: 0` is the server's "nobody has rated me yet" sentinel, so
/// `WorkerProfile.hasRating` is false and the header pill draws
/// `noRatingAr()` — **«لا تقييمات بعد», with no stars and no count at all**.
/// Nothing about 24 was printed. [reviewsSectionUnbackedAr] would then fire on
/// the empty list and say «يظهر أعلاه 24 تقييماً» — telling the customer a
/// number is on screen when the sentence directly above it is the opposite,
/// and there is no number anywhere above it.
///
/// So the contradiction arm is only entitled to compare against a claim the
/// customer can actually see. Both of the header's conditions are applied
/// here, and both are the header's own: it draws a row only on `hasRating`,
/// and it prints a count only when that count is positive
/// ([printableReviewCount], which is what turns a stored 0 into an absence).
///
/// `review_count.dart` states that these two fields disagree **in both
/// directions** and that this is a real payload shape — "7 reviews, no score"
/// is listed there as its own case. That file fixed the case where a *score*
/// and a *zero count* meet. This is the other direction: a *count* and a
/// *missing score* meet, and it is the one that makes the arm introduced
/// yesterday claim something the screen never said.
int headerPrintedReviewCount({
  required bool hasRating,
  required int totalReviews,
}) =>
    hasRating ? printableReviewCount(totalReviews) ?? 0 : 0;
