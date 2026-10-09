// What the contractor's search says when the market it searched is not the
// whole market.
//
// Found 10 Oct 2026, and it is the **second half** of an item this loop already
// shipped. `browseProjects(pages: 5)` was taught to record the pages it could
// not read — each one with its number, on the diagnostics channel, so «no
// results» stopped being a silent under-search *in the log*. That half is
// correct and it is green.
//
// **The log is not the screen, and that is the whole defect.** The record is
// written with `CrashReporter.active?.capture(...)`, which is null before boot
// installs the reporter and, more to the point, is a place only support can
// read. The return type is `List<Project>`: the count of lost pages has no
// path to the widget that renders the answer. So the contractor's own search
// still reads «لا نتائج مطابقة» — *nothing matches* — while three of the five
// pages of open projects he asked for never arrived.
//
// This is the shape the family keeps hitting, one layer down. A message written
// for a machine that reads it later, attached to a conclusion drawn for a person
// who reads it now. The repository does the honest thing and the honest thing
// has no way to arrive.
//
// The fix has to keep two truths apart, because they are different and the
// screen currently shows the second one for the first:
//
//   * **«nothing matches»** — the query was read in full and matched no row.
//     True, and the empty state with «مسح البحث» is exactly right.
//   * **«I could not read the whole market»** — the query was never applied to
//     four fifths of it. An *empty* result here is not a verdict, it is a
//     partial answer, and the two look identical on a 360 px screen and mean
//     opposite things.
//
// Note what is deliberately NOT here. The pages that answered empty are not
// lost and must never be counted: a wilaya with no open projects is an empty
// market, and saying «صفحتان لم تصل» over a genuinely empty one would be the
// mirror-image lie — a screen inventing a failure to excuse a result it does
// not like.
//
// Pure, so the wording is testable without pumping a widget — the split every
// sibling in the stale-*_copy family uses.
library;

import '../core/l10n/arabic_agreement.dart';

/// «صفحة واحدة» / «صفحتان» / «3 صفحات» / «11 صفحة».
///
/// **One branches before the rule and the bare singular goes in after it** — the
/// exact trap `commune_count_copy.dart` and `quote_count_copy.dart` both
/// document. [arabicCounted] reuses the singular slot for 11 and up, so passing
/// «صفحة واحدة» as the singular would print «11 صفحة واحدة».
///
/// Zero is silence: the caller only asks this about a loss, and a loss of no
/// pages is not a loss.
String lostPagesAr(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'صفحة واحدة';
  return arabicCounted(n, 'صفحة', two: 'صفحتان', few: 'صفحات');
}

/// The line shown when a search covered **part** of the market.
///
/// [lost] is how many of the pages the search asked for never answered, and
/// [total] is how many it asked for. The sentence names the gap in the
/// contractor's own vocabulary, because *how many* is what he acts on — a
/// missing page out of five is a hiccup, four out of five is a market he has
/// not seen.
///
/// [S.errUnexpected] is deliberately absent. This is not a failure to describe
/// with the generic unexpected-error sentence: nothing about *this* read was
/// unexpected, and «حدث خطأ غير متوقع» under a normal search would train him to
/// ignore the one band that is telling him something true.
String partialMarketLineAr({required int lost, required int total}) {
  if (lost <= 0) return '';
  final pages = lostPagesAr(lost);
  // A total the caller did not supply, or a loss that covers all of it: the
  // first is a caller's bug and the second is already covered by
  // `browseProjects` raising, so both fall back to the gap alone rather than
  // printing a denominator that cannot be true.
  final scope = (total > 0 && lost < total) ? ' من $total' : '';
  return 'تعذّر قراءة $pages$scope من نتائج البحث.'
      ' النتائج المعروضة قد تكون ناقصة.';
}

/// Whether a search that lost [lost] of [total] pages may say «لا نتائج».
///
/// **The rule is one line and it is the whole point of this file.** «لا نتائج
/// مطابقة» is a verdict about the market, and the app may only print a verdict
/// it is entitled to: a search that read every page it asked for has one, and a
/// search that did not has *no answer at all* about rows it never saw. So the
/// empty state is allowed only on a complete read, and a partial one is
/// annotated instead — the same split `staleMarketLineAr` makes for a feed
/// that failed to refresh.
///
/// Kept as its own predicate rather than left to each call site, because the
/// call site is where the temptation lives: the rows are in hand, the list is
/// empty, and `isEmpty` reads like a conclusion.
bool partialMarketMayClaimNoResults({required int lost, required int total}) {
  return lost <= 0;
}
