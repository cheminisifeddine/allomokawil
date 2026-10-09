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
///
/// **The number used to be thrown away, and this file was the reason the fix
/// was obvious.** The sentence read
///
///     headerCount == 1 ? 'تقييم واحد' : 'تقييمات'
///
/// which is a hand-written copy of [arabicCounted] with one of its four arms
/// missing and no number at all in the remaining three. Measured on the
/// payloads this app really receives, for every count above one it printed
///
///     يظهر أعلاه تقييمات، ولم تظهر تقييماته هنا.
///
/// **«تقييمات» on its own is the plural with nothing to pluralise.** The
/// header two scrolls above says «(24)», the sentence cannot name the 24 it is
/// disagreeing about, and the customer is left counting a number he cannot
/// see. The defect was filed against the wrong thing for four days: the tests
/// on this arm (`reviews_section_contradiction_test.dart`) assert
/// `contains('تقييم واحد')` for one and `isNot(contains('تقييم واحد'))` for
/// twenty-four — **neither assertion can fail on this bug**, because both are
/// satisfied by a sentence with no number in it. A green guard over a sentence
/// that lost its number is the same shape as the phone-error-band guard
/// `dbf1531` found: the test was green and the widget was wrong.
///
/// It is also one function below [reviewsSectionPartialAr], which never made
/// the mistake — it counts through [reviewCountAr] and reads «يظهر 30 تقييماً
/// أعلاه». The same noun, the same number, the same sentence shape, written
/// twice, one correct. So the count now comes from the same helper:
///
///     2  ->  يظهر أعلاه تقييمان،      (dual, no number, the dual says two)
///     3  ->  يظهر أعلاه 3 تقييمات،    (broken plural, 3-10 and 103-110)
///     11 ->  يظهر أعلاه 11 تقييماً،  (counted singular, 11-102 and 111-202)
///     1  ->  يظهر أعلاه تقييم واحد،  (unchanged — a count of one reads
///                                       better in the word than in digits)
String? reviewsSectionUnbackedAr({required int headerCount}) =>
    headerCount > 0
        ? 'يظهر أعلاه ${_headerCountAr(headerCount)}، '
            'ولم تظهر تقييماته هنا. قد يكون الاتصال غير مستقر — أعد المحاولة.'
        : null;

/// The count this sentence names, read from the one place that owns it.
///
/// [reviewCountAr] is the same helper [reviewsSectionPartialAr] uses one
/// function below, so the two arms cannot drift apart a second time — which
/// is what they had already done once, in opposite directions, on the same
/// screen. `reviewCountAr` answers null for a count of zero or less; the gate
/// above has already returned for those, so the fallback is unreachable
/// rather than reachable-and-empty.
String _headerCountAr(int n) {
  if (n == 1) return 'تقييم واحد';
  return reviewCountAr(n) ?? '';
}

/// The sentence under a reviews list that is **shorter than the header claims**.
///
/// The third shape the two reads of one fact can disagree in, and the only one
/// the section was not watching for. Measured 5 Oct 2026 on production, over
/// every row of `GET /api/mobile/workers/search` carrying `total_reviews > 0`:
///
///   row      header claim   GET /workers/$id/reviews returns
///   id 5             (30)   1 card
///   id 3             (15)   1 card
///   id 4             (12)   1 card
///   id 1             (24)   0 cards   <- the arm that shipped 1 Oct
///   id 2, 6, 7, 8        --  0 cards   <- the same arm
///   the other 9 rows         equal or more
///
/// So 5 rows reached the empty-list arm added on 1 Oct, and **3 more rows did
/// not**: their list is not empty, so the section drew one card, drew no
/// indication that 29 of the 30 reviews the header is standing on are not on
/// this page, and said nothing at all. A customer reads «(30)» at the top and
/// one review below, and the only conclusion the page supports is that the other
/// 29 are a lie — or that the app lost them. Neither is the app's story to
/// leave unspoken, and unlike the empty case **here the customer can see a
/// number and count the difference for himself**.
///
/// The empty arm's reason for existing does not transfer, and the difference is
/// the whole design. There, the section was about to assert «لا تقييمات بعد» —
/// a claim about a man's reputation that the page above it denies — and any
/// hedge was better. Here the section draws real reviews and claims nothing
/// about the rest, which is true but reads as a bug: a truncated list with no
/// truncation is indistinguishable from a wrong one. So the honest answer is
/// an **annotation**, not a replacement: the cards stay exactly as they were,
/// and one line under them names the gap.
///
/// Which read is stale is still not knowable from here — the aggregate may lag
/// the list, or the list may be scoped to what this viewer may read — so the
/// sentence states the two numbers it actually holds and draws a conclusion
/// from neither. It must not say the reviews are missing, and it must not say
/// the header is wrong.
///
/// Null when the list is at least as long as the claim: that is the ordinary
/// case, it is true, and nothing is owed to the reader. This is the empty arm's
/// own contract — a null means *there is nothing to reconcile* — so a caller
/// that wants to draw nothing has one answer for both shapes rather than two
/// branches it could get differently.
String? reviewsSectionPartialAr({
  required int headerCount,
  required int shownCount,
}) {
  if (headerCount <= 0) return null;
  if (shownCount <= 0) return null;
  if (shownCount >= headerCount) return null;
  // Both counts are printed, so the reader can check the subtraction rather
  // than trust it, and the noun forms come from `reviewCountAr` rather than
  // being spelled again here — the agreement rule already exists and this is
  // the sixth file that used to keep a private copy of it.
  return 'يظهر ${_ratingCountAr(headerCount)} '
      'أعلاه، ودُكر منها ${_ratingCountAr(shownCount)} '
      'هنا. قد لا تظهر كل التقييمات — أعد المحاولة.';
}

/// «تقييم واحد» / «تقييمان» / «3 تقييمات» / «30 تقييماً».
///
/// Read from [reviewCountAr] rather than spelled here, so the noun this file
/// writes is the same noun the stats line writes three files up and the two
/// cannot drift. That helper already answers «تقييم» for the singular — a
/// count of one is not counted — which is why this sentence reads «يظهر تقييم
/// واحد» rather than «يظهر 1 تقييم».
String _ratingCountAr(int n) => reviewCountAr(n) ?? '';

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
