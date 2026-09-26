// One rule for "is there a review count to print?", in one place.
//
// Found on 26 Sep 2026. A rating row is gated on the **score**, never on the
// review count, because `avg_rating: 0` is the server's "nobody has rated me
// yet" sentinel rather than a mean — the review form is 1–5, so no set of
// reviews can average to zero. The count is a *different* field, and the two
// disagree in both directions:
//
//   * 7 reviews, no score  -> no stars at all. Nothing earned a score.
//   * a score, 0 reviews   -> the stars are real and the count is an absence.
//
// The second case is the one that used to print itself. `RatingStars` takes an
// `int?` count so a caller can pass nothing, but both live star rows passed the
// parsed `total_reviews`, which the parser defaults to `0` for an absent field.
// The row therefore drew four gold stars and «4.8 من 5» next to a literal
// **«(0)»** — a man somebody rated, scored, beside a claim that nobody rated
// him at all. Two verdicts in one row, both from the same payload.
//
// The screen reader was already honest about the same number: `A11y.rating`
// folds a count of zero to «لا مراجعات», and the pixels did not. One row,
// lying in two directions, in the two outputs of the same widget.
//
// So the rule lives here, and both the pixels and the label are built from it:
// a count of zero or less is not a count, it is the absence of one, and the
// only honest way to print an absence is to print nothing. Same rule
// `arabicCount` states for every other count in this app, and the fifth place
// a rating number could have been counted by hand.
library;

/// The count to print beside a score, or null when there is nothing to print.
///
/// A negative count is treated like zero: the field is non-nullable over the
/// wire, so a server that sends `-1` for "unknown" must not put `-1` in
/// parentheses either.
int? printableReviewCount(int count) => count > 0 ? count : null;
