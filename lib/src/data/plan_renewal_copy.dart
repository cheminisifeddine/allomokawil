// What happens to a contractor's money when a plan runs out.
//
// Found on 26 Sep 2026, the same vein as `quote_limit` and `portfolio_limit`
// one cycle earlier: the server publishes a fact on the payload and the app
// throws it away. `GET /api/mobile/subscription` and `/api/mobile/plans` both
// return
//
//     "payment_style": "prepaid",
//     "auto_renew":   false,
//     "renew_note_ar": "الدفع مسبق لعدد من الأشهر — لا يوجد خصم تلقائي من البطاقة"
//
// and `BillingCatalogue` read **none** of the three: verified by grep across
// `lib/`, where the three names appear only in this file and in the model.
// Beside them, `note_ar` — the "no commission" promise — was read and printed
// in full on the same card. So the screen made its most reassuring promise and
// stayed silent on the one a man is actually anxious about before paying cash
// in Algeria: **nobody is going to charge my card again**.
//
// That silence is a trust defect, not a missing feature. The founder sells
// prepaid months by BaridiMob and cash; a contractor who is unsure whether
// something renews will not buy, and one who is told a month "just continues"
// will accuse us of taking money he did not agree to. The sentence belongs next
// to the price, before he pays — not in a terms page he will not open.
//
// **The wording is the server's, not ours.** [renewalNoteAr] returns the
// founder's own `renew_note_ar` verbatim so the promise can be changed in D1
// and reach every installed app, exactly like every price on this screen. What
// this file owns is the one thing prose cannot: [prepaidTermsAr], the counted
// Arabic for how many months a term covers, which is the noun the app has to
// get right when it prints the term itself.
library;

import '../core/format/money.dart';
import '../core/l10n/arabic_agreement.dart';
import '../models/plan.dart';

/// The server's renewal sentence, or null when it published none.
///
/// Null is not an empty line: [S]-style fallbacks are the screen's business,
/// and an absent note must be a *missing* note, never a blank row the user
/// reads as a message that failed to load.
String? renewalNoteAr(String? note) {
  if (note == null) return null;
  final v = note.trim();
  return v.isEmpty ? null : v;
}

/// «شهر واحد» / «شهران» / «3 أشهر» / «12 شهراً» — a prepaid term, counted.
///
/// Every other count in this app goes through [arabicCounted], and this is the
/// one that was about to be written by hand: `'$months شهر'` is wrong at every
/// value except one, and a term is **always** a number a contractor is
/// choosing deliberately — a 3-month term is 5% cheaper than three months
/// paid monthly, 6 months is 11%, 12 months is 17%, and that discount is
/// precisely the number this line has to attach to.
///
/// Zero months is not a term. Returns null rather than tripping the assert
/// inside [arabicCount], the same way [quoteDurationLineAr] drops its row
/// instead of printing a number that is not one.
String? prepaidTermsAr(int months) {
  if (months <= 0) return null;
  return arabicCounted(
    months,
    'شهراً',
    two: 'شهران',
    few: 'أشهر',
  );
}

/// The saving a term is worth, as the screen says it — «توفّر 500 دج» — or null
/// when the term is no cheaper than paying monthly.
///
/// **Null rather than «توفّر 0 دج».** A line announcing that nothing was saved
/// on the screen whose job is to talk someone into paying is worse than no
/// line: it reads as a broken calculation, and it is the same failure as
/// `savingFor` returning 0 and being printed unconditionally, which is why that
/// getter is only ever read through this shape.
String? termSavingLabel(int savingDzd) {
  if (savingDzd <= 0) return null;
  return 'توفّر ${Money.dzd(savingDzd)}';
}

/// How many months of the monthly price one year's price is, or null when it
/// is not a whole number of them.
///
/// The one place that decides, so no caller can do its own division and get a
/// different answer from a sibling card. Twelve monthly payments at
/// `price_month` is what a year *costs* without a discount, so the saving is
/// `price_month * 12 - price_year` and the months the year is worth are what
/// is left of that saving.
///
/// Null, not 0 and not a rounded guess, in three cases where the ratio is not a
/// whole number of months:
///
///   * a free plan (`price_month` is 0) — there is no month to be a fraction
///     of, and «سنة كاملة بسعر 0 شهر» is not a sentence;
///   * a yearly price that is **more** than twelve monthly payments, which is
///     a surcharge, not a term — the number of months would be negative and
///     the caller would print a discount nobody gets;
///   * a yearly price that is not a whole multiple, e.g. 10.5 months. Rounding
///     that to 10 or 11 puts a number on screen that the server never sent,
///     which is the whole class of bug this function exists to stop.
int? yearAsMonths(Plan plan) {
  final month = plan.priceMonth;
  final year = plan.priceYear;
  if (month <= 0 || year <= 0) return null;
  // Whole multiples only: 10 months at 1500 is 15000 exactly, and a 10.5-month
  // price is not a number of months this app can print.
  if (year % month != 0) return null;
  final months = year ~/ month;
  if (months < 1 || months > 12) return null;
  return months;
}

/// The sentence under the «سنوي» arm of the period toggle for one plan, or
/// null when the year's price is not a whole number of months of the monthly
/// one.
///
/// **This line used to be a hard-coded string constant** — `S.planYearlyHint`,
/// «سنة كاملة بسعر عشرة أشهر» — printed under the yearly option on every
/// plan, whatever the server had priced. The app models the yearly figure as
/// exactly twelve `price_month`s, and every paid plan on the live catalogue is
/// priced at exactly ten of them, so the sentence has been *true* since it was
/// written. It is still not a fact the app is allowed to know, and that is the
/// defect.
///
/// It is a pricing claim, on the pricing screen, printed by the client, about
/// money. Everything else on this card is server-owned on purpose — see the
/// file header — and this one line was a client-owned promise about a number
/// the server owns. The moment D1 prices a year at 11 months, or at 10.5, or
/// gives one plan twelve months and the next nine, the screen keeps saying
/// «ten months» on all of them, and a contractor deciding between plans is
/// told a discount that does not exist. No release, no test failure, no crash:
/// a wrong number, in the app's own voice, on the one card whose job is to be
/// right about money.
///
/// So the sentence is computed from the two prices the payload carries, and
/// **null** when the two do not divide into a whole number of months. A null is
/// not a gap: the caller drops the line, which is the correct rendering of
/// "we have nothing true to say about this year's price". The number of months
/// is the count [prepaidTermsAr] already knows how to say, so the hint cannot
/// disagree with the terms a term costs elsewhere in the app.
String? yearlyTermHintAr(Plan plan) {
  final months = yearAsMonths(plan);
  if (months == null) return null;
  return 'سنة كاملة بسعر ${prepaidTermsAr(months)}';
}
