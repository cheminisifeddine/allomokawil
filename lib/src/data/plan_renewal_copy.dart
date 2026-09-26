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
