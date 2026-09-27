// How many wilayas a plan's work reaches, in the words the pricing card prints.
//
// Found on 27 Sep 2026, eighth in the same series: the server publishes a fact,
// the parser keeps it, and no screen reads it. `GET /api/mobile/plans` returns
// `wilaya_span` on every tier and `Plan.fromJson` parses it. Verified by grep
// across `lib/`, where the name appeared only in `models/plan.dart` and now
// here. Live values, read from the catalogue on 27 Sep 2026:
//
//     1 (free) · 1 (basic) · 2 (pro) · 3 (gold)
//
// Beside it, `quote_limit` has a usage bar, a left-count and a 402 paywall,
// and `portfolio_limit` has its own left-count line. Every limit on this payload
// was visible except the one a contractor is **comparing** when he decides
// between «محترف» at 3000 دج and «مؤسسة» at 6000 دج.
//
// And the number is not redundant with the `features` prose, which is the only
// thing the card printed before. `gold` promises «صدارة النتائج في ولايتك» —
// *your* wilaya, singular — while the server prices the plan at **three**. So
// the app was showing a customer a promise about one wilaya next to a price
// for three, and had no way to say which was true. The price is server-owned
// and so is the number beside it; only the sentence was missing.
//
// **Counted Arabic, from [arabicCounted]**, not a fourth hand-written copy of
// the agreement: `wilaya_span: 3` has to read «3 ولايات» and not «3 ولاية».
// That is the same defect `quote_count_copy.dart` and `commune_count_copy.dart`
// were each opened for, and the same one the live catalogue is most likely to
// expose — the free and basic tiers are both 1, so a 2 lands the moment the
// founder prices a fourth tier, and 3-10 is the range that is reached first.
//
// **Zero is silence, not «0 ولايات».** A span of one is already the floor —
// a plan cannot reach fewer wilayas than the one the contractor lives in — so
// a stored 0 is a server default rather than a claim, and printing it would
// tell a paying man his plan reaches nowhere. Same contract `photosAr`,
// `quotesAr` and `durationDaysAr` already have.
//
// ## What this file deliberately does NOT print: `search_boost`
//
// The same payload carries `search_boost` (0 free, 1 basic, 3 pro, 5 gold),
// and it is read by nothing either. It is left unread on purpose, and the
// reason is the rule this whole series keeps rediscovering: **a number the
// server sends is not a sentence the app may write about it.** `search_boost`
// is a ranking *weight* for a sort the client cannot see and the server does
// not describe. Every Arabic phrase available for it — «أولوية في نتائج
// البحث», «ترتيب متقدّم» — is a claim about *how* a result is ranked, and the
// payload says nothing about how. The free tier's own `features` already says
// «ظهور في نتائج البحث» in the founder's words, which is the one true
// sentence available, and it is already on the card.
//
// Printing a plausible phrase next to a weight is worse than printing nothing:
// it is a pricing claim, on the pricing screen, in the app's own voice, about
// an algorithm nobody in this repo can read. When BACKEND-API documents what
// the weight does, it ships as server prose in `features` and reaches every
// installed app with no release — the same path `renew_note_ar` and
// `note_ar` already take.
library;

import '../core/l10n/arabic_agreement.dart';

/// «ولاية واحدة» / «ولايتان» / «3 ولايات» / «11 ولاية» — how many wilayas a
/// plan's work reaches.
///
/// One branches before the rule and the bare singular goes in after it, which
/// is the trap `commune_count_copy.dart` documents: passing «ولاية واحدة» in as
/// the singular would be right at 1 and wrong for every value from 11 up, which
/// reuses that slot — «11 ولاية واحدة».
String wilayaSpanAr(int span) {
  if (span <= 0) return '';
  if (span == 1) return 'ولاية واحدة';
  return arabicCounted(span, 'ولاية', two: 'ولايتان', few: 'ولايات');
}

/// The line on the pricing card: «وصول في 3 ولايات».
///
/// [span] is `wilaya_span` exactly as D1 sends it. Null when the server sent
/// nothing usable, so the card drops the row rather than printing a gap — the
/// same contract `yearlyTermHintAr` and `termSavingLabel` already have, and
/// the reason both of those return null instead of an empty string.
String? planReachLineAr(int? span) {
  if (span == null) return null;
  final reach = wilayaSpanAr(span);
  if (reach.isEmpty) return null;
  return 'وصول في $reach';
}
