// The price range a contractor advertises, in the form the numbers call for.
//
// Found on 28 Sep 2026 by driving the live profile PATCH, not by reading the
// screen. `PATCH /api/mobile/my/profile` answers 200 and the shape the server
// then *stores* is decided by the server, so the two values this app sends can
// come back as a pair that never existed in the form the contractor filled in.
//
// Three bodies, one row, one real account (`id 124`, created this tick):
//
//   sent {"price_range_min":5000,"price_range_max":5000}  -> 5000 / 5000
//   sent {"price_range_min":7000,"price_range_max":null}  -> 7000 / 7000
//   sent {"price_range_min":null,"price_range_max":7000}  -> 5000 / 7000
//
// The second line is the one that matters. **The form sends `null` for an
// empty box** (`Repository.updateMyProfile` sends every field unconditionally
// and null included, on purpose — see its doc comment), and the app's own
// validation only refuses `min > max`, so filling in the «من» box alone is a
// perfectly ordinary thing to do. The server answers that with a range whose
// two ends are the same number, and the profile the next customer opens reads
//
//     الخبرة            5 سنوات خبرة
//     نطاق الأسعار      7000 - 7000 دج
//
// **A range from a number to itself is not a price.** It tells the customer
// nothing he could not get from one number, and «7000 - 7000 دج» is not a
// string any Algerian writes — a man prices by «من 7000» or «حتى 7000» or a
// genuine band, and the hyphen-band with equal ends is the shape the app
// produced on its own. This is the sibling defect [worker_stats_copy] fixed for
// four unmeasured numbers, one row further down the very same card, and it is
// the same mistake in the other direction: those four printed a zero where a
// person had answered nothing, and this one prints a *range* where the person
// answered one number.
//
// The reason it survived this long is that the sibling rule is already
// correct one file over. `Project.budgetLabel` collapses `min == max` to a
// bare amount — a customer posting a budget and a contractor advertising a
// range were given the same column to answer with, and the project's own
// label handles the collapse while the worker's did not. Two fields the server
// holds the same way, one label that knew and one that did not, printed by two
// different widgets in two different screens. The fix is the same collapse,
// made into the rule both of them now read.
//
// The **inverted** pair is closed here too, for a different reason: nothing in
// this app can produce `min > max` (both forms refuse it), so an inverted
// pair is server state only. It is answered rather than passed through, so a
// bad row degrades into a sentence the customer can still read instead of a
// backwards band. It is not reachable from the form, and this file says so
// rather than implying the validation was missing.
library;

import '../core/format/money.dart';

/// «من 2500 دج» / «حتى 8000 دج» / «2500 - 6000 دج», and the collapse:
///
///   * null + null -> `null`, so the caller drops the row rather than print a
///     number nobody set. Same rule as [worker_stats_copy]’s four.
///   * min only   -> «من 2500 دج»
///   * max only   -> «حتى 8000 دج»
///   * both, equal-> «5000 دج» — **the collapse**, matching
///     `Project.budgetLabel`.
///   * both, real -> «2500 - 6000 دج»
///   * inverted   -> the honest single reading, see [_inverted].
String? priceRangeAr(int? min, int? max) {
  if (min == null && max == null) return null;
  if (min != null && max != null) {
    if (min == max) return Money.dzd(min);
    if (min > max) return _inverted(min, max);
    return '${Money.amountOnly(min)} - ${Money.dzd(max)}';
  }
  if (max != null) return 'حتى ${Money.dzd(max)}';
  return 'من ${Money.dzd(min!)}';
}

/// True when the pair carries any price at all — the one gate the two call
/// sites used to disagree about.
///
/// `worker_profile_screen` gated on `min != null || max != null`, and
/// `worker_card` gated on `min != null` alone. So a contractor who typed a
/// single **maximum** price saw the row on his own profile and not on the
/// card he is chosen from: the same man's range was on the profile page and
/// absent from the browse list, which is the list a customer actually picks
/// him out of. One boolean, read by both, is the fix — [hasPriceRange] is it.
bool hasPriceRange(int? min, int? max) => min != null || max != null;

/// The sentence for a range whose ends are the wrong way round.
///
/// Only server state reaches this, so it is written to be *readable* rather
/// than clever: the two numbers are the only two facts there are, and printing
/// them in the order they were given keeps a customer who does meet the row
/// from being told a min that is above the max. «من 8000 دج» understates what
/// he charges; «حتى 5000 دج» overstates it. Neither is true, and a price
/// range a customer uses to choose a tradesman is not a place to be wrong in
/// either direction, so the pair is printed as a band with the ends the way
/// they arrived rather than dressed up as a bound the data does not support.
///
/// This is the one branch here that is not a count and not a collapse, and it
/// exists so the function above never hands a caller a backwards range.
String _inverted(int min, int max) =>
    '${Money.amountOnly(min)} - ${Money.dzd(max)}';
