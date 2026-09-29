// What the subscription screen says when the numbers on it stopped being fresh.
//
// Found 29 Sep 2026 while auditing the third screen in the family the profile
// bug opened (`worker_profile_screen` and `project_detail_screen` already gate
// their body on a successful read; this one does not).
//
// The screen holds a catalogue. `_load()` keeps the old one when a refresh
// fails — deliberately, and correctly: throwing away a paying contractor's
// plan, price and quota because a cell network blinked would be worse than
// showing him last month's truth. That decision is the whole reason the
// screen is worth auditing at all.
//
// The defect is the *other* half of the same decision. `_load()` sets `_error`
// on failure and that field is read in **exactly one place**: inside the
// `catalogue == null` branch of `build()`. A failed *first* load is therefore
// reported. A failed *refresh* — the refresh button, a pull-to-refresh, the
// reload that follows every payment request and every redeemed code — falls
// through to a body that renders `_catalogue` and never mentions the failure
// again. The contractor is shown his real plan, real price and real quota
// with no indication that a re-read he just performed failed.
//
// On this screen that silence is not cosmetic, it is a money claim. The three
// facts a contractor acts on when he decides whether to pay are the price on
// the card, the pending payment waiting on him, and how many quotes he has
// left this month. A refresh fails, the app says nothing, and he upgrades
// against a price the server has since moved — the exact mismatch the ack
// comparison below the payment sheet exists to catch, arriving by silence
// instead of by a wrong number.
//
// The fix is not to blank the screen. A dead screen on a failed refresh is a
// worse answer than a stale one, and it would throw away a plan he already
// paid for. The fix is to say the truth about the data in front of him: these
// are the figures from the last successful read, and there has been a failure
// since. What he does with that is his decision, and it is a different
// decision from the one he makes against a screen that never admits a doubt.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `quote_count_copy.dart` and `pending_request_copy.dart` use.
library;

import 'read_age_ar.dart';

/// The line shown above a catalogue that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which is
/// itself a sentence ending in an action. This is the other half — the part
/// that says *what the reader is looking at*, which `errorCopy` has no way to
/// know: it describes a failure, never the survival of a previous success.
String staleCatalogueLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a banner that explains nothing.
  if (reason.isEmpty) return 'هذه البيانات قد لا تكون محدَّثة';
  return 'لم نتمكن من تحديث بياناتك — هذه أرقام آخر قراءة ناجحة. $reason';
}

/// How old the figures under the catalogue band actually are.
///
/// The **freshness half** of the family, and the sixth member to get it, after
/// the market, the projects list, the directory, the notifications and the
/// two home strips. The band already says «هذه أرقام آخر قراءة ناجحة» — *these
/// are the figures from the last successful read* — which is true and useless
/// on its own. A re-read that failed four seconds ago and one that failed
/// forty minutes ago print the **same sentence**, and on this screen the gap
/// between them is the whole decision.
///
/// It matters more here than on any sibling, because this is the one surface
/// where a stale number is money. Every other member of the family shows a
/// list the user is reading; this one shows **a price, a pending payment and
/// a remaining quota**. A contractor deciding whether to pay BaridiMob against
/// a price he read this morning and one he read last month are not making the
/// same decision, and the band currently gives him no way to tell which he is
/// looking at. The ack comparison further down the sheet exists to catch
/// exactly this mismatch, and it can only catch what the user is willing to
/// challenge — so the doubt has to be priced in words before the payment, not
/// discovered after it.
///
/// **The rule is not this file's.** It is [readAgeAr], which the whole app
/// routes through so a header, a market, a project list, a directory, two home
/// strips and now this catalogue cannot each decide what "old enough to
/// mention" means. Null, clock skew and under-a-minute are silence, and a
/// band whose figures are still current keeps its own words.
String staleCatalogueAgeAr(DateTime? readAt, {DateTime? now}) =>
    readAgeAr(readAt, now: now);

/// The band line with its age, when the age is worth a word.
///
/// Same two rules as every sibling, and the second is the easy one to get
/// wrong:
///
///   * The age is **appended**, never substituted. The failure sentence names
///     the *kind* of failure `errorCopy` diagnosed and the age says nothing
///     about it. A band that traded the reason for a timestamp would tell a
///     contractor his quota is «قبل 12 دقيقة» without saying *why* it might
///     have changed underneath him, and «لم نتمكن من تحديث بياناتك» is the
///     half that keeps the banner from reading as a routine timestamp.
///   * Under a minute, undatable and absent stay **exactly the old line**,
///     byte for byte, so every assertion the previous tick wrote still holds
///     and no band ever gains a second sentence it has nothing to say.
String staleCatalogueLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleCatalogueLineAr(error);
  final age = staleCatalogueAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
