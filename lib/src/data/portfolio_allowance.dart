// How many portfolio photos a plan allows, in one place.
//
// Found on 26 Sep 2026 while auditing what the project photo cap left. Same
// shape of defect one layer up: the cap was a *product* rule that the screen
// enforced, and next to it sat a *plan* rule that nothing enforced at all.
//
// `portfolio_limit` is parsed on two models — `Plan` and `SubscriptionStatus`
// — and **read by nothing in the app**. Verified by grep across `lib/`: the
// field appears only in `models/plan.dart`, in four test fixtures, and in the
// comments of `photo_count_copy.dart`. Meanwhile its sibling on the very same
// payload, `quote_limit`, has a left-count line on the dashboard, a usage bar
// on the subscription card and a 402 paywall on the bid button. Two limits,
// one endpoint, one of them invisible.
//
// So the free plan — `portfolio_limit: 5` — sold a man five photos and the app
// never said so, on the one screen whose entire job is his gallery. A
// contractor who wanted to know how many he was allowed to add had exactly one
// way to find out: upload until the server refused, which is a 500 or a silent
// no-op, not an answer. And the paid tiers sell 30, 60 and 120, so the thing
// they are selling more of is a thing the buyer cannot see the price of.
//
// **Zero means UNKNOWN, and that is the whole reason this file exists.**
// `_int()` in `models/plan.dart` returns 0 for a missing, null or unparseable
// value, and `portfolio_limit` is read with no null guard. Read naively, 0 is
// "allowed zero photos" — a gate that locks a paying contractor out of the
// gallery he is looking at, and does it on a server that simply did not send
// the field. The quote side gets away with the same parser because
// `quoteLimit` has an explicit `== null ? 3 :` default and a negative means
// unlimited. This file gives the portfolio side that default, explicitly, so
// "no field" can never be read as "no allowance".
//
// The gate is client-side and the backend does not enforce it, so this is a UI
// affordance, not a paywall: it stops the contractor hitting a wall he cannot
// see coming and points him at the plan that lifts it. If BACKEND-API later
// enforces the limit server-side, the number this reads is the same one.
library;

import 'photo_count_copy.dart';

/// The limit to assume when the server sent none.
///
/// Five, not unlimited: it is the free plan's real value, and it is the only
/// assumption here that fails *open* — a contractor who is actually on a paid
/// plan is under no stop until the server starts answering, and a contractor
/// who is genuinely on free is held to the allowance he was sold. Assuming
/// "unlimited" instead would make the limit permanent and invisible, which is
/// the defect this file was opened to remove.
const int kDefaultPortfolioLimit = 5;

/// A plan's portfolio allowance, resolved against the server's own value.
class PortfolioAllowance {
  const PortfolioAllowance({required this.limit, required this.used});

  /// Builds from a raw `portfolio_limit` as D1 sends it.
  ///
  /// A negative is the same word as `quote_limit` uses for unlimited, so it is
  /// honoured here rather than treated as a wall. A zero — which is what
  /// `_int` hands back for an absent field — is **not** zero: it becomes
  /// [kDefaultPortfolioLimit], because the alternative is a gate that reads
  /// "0 allowed" on a server that simply did not answer.
  factory PortfolioAllowance.fromLimit(int limit, {required int used}) =>
      PortfolioAllowance(
        limit: limit == 0 ? kDefaultPortfolioLimit : limit,
        used: used,
      );

  final int limit;
  final int used;

  /// True when the plan sets no ceiling (a negative `portfolio_limit`).
  bool get isUnlimited => limit < 0;

  /// How many more photos fit, or null when there is no ceiling to fit under.
  ///
  /// Floors at zero for the same reason `projectPhotoRoom` does: a gallery
  /// already over its limit (a limit lowered, a plan downgraded, photos
  /// uploaded while the server was not counting) must read as full, not as a
  /// negative number of free slots.
  int? get left {
    if (isUnlimited) return null;
    final room = limit - used;
    return room < 0 ? 0 : room;
  }

  /// The moment the add tile has to stop offering itself.
  ///
  /// Exactly the condition `project_photo_limit.dart` gates on, and for the
  /// same reason: a tile that is not there reads as a broken screen, which is
  /// why [portfolioFullLineAr] says what happened instead.
  bool get isFull => !isUnlimited && (left ?? 1) <= 0;
}

/// «بقيت صورتان من 5 صور في خطتك» — the room, on the gallery header.
///
/// Mirrors `quotesLeftLineAr`, which is the same construction on the other
/// limit: two counts, both from [photosAr], neither spelled by hand. Both
/// nouns in one sentence is the case [arabicCounted] exists to get right, and
/// «5» is the value that makes the trailing noun flip to counted singular.
String portfolioLeftLineAr(int left, int limit) =>
    'بقيت ${photosAr(left)} من ${photosAr(limit)} في خطتك';

/// The header when the ceiling is not a ceiling: «صور بلا حد في خطتك».
///
/// No count is printed, so nothing can disagree about it — the same decision
/// `unlimitedQuotesUsageAr` makes for a paid plan, and for the same reason: a
/// number standing where a count should be is worse than no number.
String portfolioUnlimitedLineAr() => 'صور بلا حد في خطتك';

/// The header when the gallery is full: «بلغت حد صور خطتك: 5 صور».
///
/// The limit is named, because the line it replaces is a count of what he has
/// and a silent replacement would read as a bug rather than a limit.
String portfolioFullLineAr(int limit) =>
    'بلغت حد صور خطتك: ${photosAr(limit)}';
