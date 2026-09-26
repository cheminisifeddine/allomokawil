// How long a contractor says his job will take, in the form the number calls
// for.
//
// Found on 26 Sep 2026 while auditing what the gallery badge left. Same vein,
// fifth cycle down: a count is either delegated to `arabicCounted` or spelled
// out by hand, and every hand-written one so far has been wrong.
//
// The quote card on a client's own project carried one fixed noun:
//
//     Text('مدة الإنجاز: ${quote.estimatedDays} يوم')
//
// `يوم` is the bare singular, and this is the worst instance of the bug in the
// app so far because **it was wrong at every single value**, not two ranges out
// of four like the gallery tile was. Running the old expression over the whole
// range gives:
//
//   * 1  -> «1 يوم»    the singular is not counted; one is what «يوم» means
//   * 2  -> «2 يوم»    the dual is «يومين», and it takes no number with it
//   * 3  -> «3 يوم»    3-10 need the broken plural «أيام»
//   * 7  -> «7 يوم»    same
//   * 10 -> «10 يوم»   same
//   * 11 -> «11 يوم»   11 and up are counted singular, so the word is right
//   * 30 -> «30 يوم»   but the noun for 3-10 is wrong and the dual is wrong
//
// So «يوم» is the correct *word* for 1 and for 11+, and the wrong word for
// everything from 2 to 10 — which is why the line looks right at a glance and
// survives review: it is a real Arabic noun in every case, and the only thing
// that changes is whether a number is standing in front of it. A reviewer
// reading «مدة الإنجاز: 7 يوم» sees a real Arabic noun and moves on.
//
// The two ranges that were already right (1 and 11+) were right by accident:
// both take a counted singular, and that happens to be the word that was
// hard-coded. The most common value on the screen — 3 to 10, the ordinary
// answer for a repaint or a bathroom — was wrong for every contractor who
// gave one.
//
// **The range is not hypothetical.** The field is a plain number field
// validated only at `min: 1` (project_detail_screen.dart:431) and the value is
// stored per quote, so every real bid lands in the middle of it — 3 to 10 days
// is the ordinary answer for a repaint or a bathroom, and 1 is the shortest
// honest bid a contractor can write. The quote card is the row the whole
// marketplace turns on: a client picking between two contractors is comparing
// exactly this line, the amount and the name. It is the worst place in the app
// to hand him a sentence no Algerian would write.
//
// The agreement itself is not re-implemented here: it is [arabicCounted], the
// one the notification clock, the subscription countdown, the commune picker,
// the quote allowance and a contractor's own stats already share. This file
// owns only the nouns and the two cases that are not plain counts.
library;

import '../core/l10n/arabic_agreement.dart';

/// «يوم» / «يومين» / «3 أيام» / «11 يوم».
///
/// **The dual is «يومين», the same word the other two day counts in this app
/// already use** (the notification clock's «قبل يومين» and the subscription
/// card's «بعد يومين»). Arabic has two dual forms — «يومان» nominative and
/// «يومين» elsewhere — and the house choice here is the one already shipped
/// twice, so a third variant invented by this file would be a third thing to
/// keep in agreement. Both of those sites print the count after a preposition,
/// and so does this one; the same word is correct in all three.
///
/// **A count of zero or less is silence, not «0 أيام».** [arabicCount]
/// asserts on it, and a client holding a stale or hand-edited row would hit
/// that assert inside a widget build rather than a test. The line is the only
/// thing that prints this number, so returning the empty string here is what
/// removes the row rather than writing a lie into it — the same contract
/// `photosAr` and `quotesAr` already have.
String durationDaysAr(int n) {
  if (n <= 0) return '';
  return arabicCounted(n, 'يوم', two: 'يومين', few: 'أيام');
}

/// The full line on the quote card: «مدة الإنجاز: 3 أيام».
///
/// The label is kept verbatim and only the count is delegated, so a client
/// comparing two contractors still sees the same row in the same place.
///
/// [estimatedDays] is nullable because the contractor may leave the field
/// empty, and a null is the ordinary case — it has no Arabic form, and the one
/// it does have is a sentence about a number he never gave. The screen already
/// hides the row for a null; this returns the empty string so the call site
/// cannot reintroduce it.
String quoteDurationLineAr(int? estimatedDays) {
  if (estimatedDays == null) return '';
  final days = durationDaysAr(estimatedDays);
  if (days.isEmpty) return '';
  return 'مدة الإنجاز: $days';
}
