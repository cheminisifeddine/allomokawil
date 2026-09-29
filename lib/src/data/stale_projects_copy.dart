// What «مشاريعي» says when the list on screen is not the list on the server.
//
// Found 29 Sep 2026 while auditing a new surface, and the **sixth** screen in
// the family the subscription bug opened. Unlike the five before it, this one
// is not the worst of them and it is worth saying why, because the family is
// only useful if its members are ranked honestly.
//
// `worker_profile_screen`, `project_detail_screen` and `subscription_screen`
// keep a field and gate their body on a successful read. `chat_list_screen`
// had the field and then answered `null` on the failure branch, throwing the
// rows away in the one state the field existed for. `browse_screen` never had
// the field at all, and it is the worst of the six because it holds the
// *supply* — the first screen a client opens — so a network that blinked
// mid-pull told him there were no contractors. This screen is the remaining
// end of that spectrum.
//
// The defect is mechanically identical to the directory's: `_future` is
// re-assigned by every pull-to-refresh and by every status tab, and the
// builder's failure branch draws «تعذّر جلب المشاريع» over the whole list. A
// **pending** re-read therefore replaces the user's own projects with a
// shimmer, and a **failed** one replaces them with an error page.
//
// Why it is still worth fixing, and not the mildest member of the family: the
// rows it throws away are the only record the user has of jobs he posted or
// worked. There is no other surface in the app that lists them — the browse
// directory is the *marketplace*, not his history — so «تعذّر جلب المشاريع» is
// not a temporary inconvenience here, it is the list ceasing to exist. The
// severity difference against the directory is that a contractor whose
// projects vanish can still see open work, so he can carry on; a customer
// whose projects vanish cannot post, cannot re-open an offer he is choosing
// between, and cannot reach the detail screen at all. He is left with an app
// that appears to have forgotten him.
//
// And the tab strip makes it worse than a single screen, not better. The
// default tab is «مفتوح», and switching tabs is the screen's *primary*
// interaction: five pills, each a full re-read. A customer with four open
// projects who is choosing between contractors spends the whole of that
// decision flipping tabs on a connection that, in the shop, is one bar wide —
// and each flip that fails does not merely fail, it erases the list he is
// comparing offers on.
//
// The fix is the same split the directory landed on, for the same reason: a
// failed **first** read has nothing to draw and keeps the full-screen error;
// a failed **re-read** keeps the rows and states the doubt. Two different
// sentences about two different facts, and one EmptyView for both is a claim
// about the second it cannot support.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_directory_copy.dart`, `stale_catalogue_copy.dart` and
// `stale_inbox_copy.dart` use.
library;

// [readAgeAr] is the only dependency. The count grammar and the calendar-day
// boundary live two files behind it, and a hand-rolled copy of «قبل ساعتين» is
// how the subscription card came to call three hours «قبل 3 ساعت».
// `notification_copy.dart` stays imported for [relativeTimeAr], which this
// file's own documentation cites.
import 'notification_copy.dart';
import 'read_age_ar.dart';

/// The line shown above a project list that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
String staleProjectsLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a banner that explains nothing.
  if (reason.isEmpty) return 'هذه المشاريع قد لا تكون محدَّثة';
  return 'لم نتمكن من تحديث مشاريعك — هذه آخر نتيجة قرأناها. $reason';
}


/// How old the projects on screen actually are, in the app's own words.
///
/// The **freshness half** of the family, and the second member to get it after
/// `stale_market_copy.dart`. The line above says «هذه آخر نتيجة قرأناها» —
/// *these are the last result we read* — which is true and useless on its own.
/// A customer whose «مشاريعي» did not refresh is asking exactly one question:
/// *can I still act on this?* A list that failed four seconds ago and one that
/// failed forty minutes ago print the **same sentence**, and the second is the
/// one where an open project somebody else has already taken is a job he has to
/// restart from nothing.
///
/// So the doubt is stated with a number on it. Three outcomes:
///
///   * **`null` / under a minute** — the band is about a read that is *still
///     current*. A pull that failed on a slow connection while the list is two
///     seconds old is a hiccup, and printing «قبل 4 ثوانٍ» under it is a
///     reassurance dressed as a measurement. The band then says only what it
///     said before, which is the correct thing to say about a failure with no
///     consequence yet.
///   * **a minute and older** — «قبل 12 دقيقة», «قبل ساعتين», «أمس».
///   * **a year and older** — the calendar date, courtesy of [relativeTimeAr].
///     A list left unrefreshed across a whole year is not a latency problem and
///     must not be described in the vocabulary of one.
///
/// **Negative ages are clock skew, not the future.** A stamp ahead of the phone
/// is a broken clock somewhere between the server and the handset; ageing it
/// into «قبل -3 دقيقة» would be the app blaming the reader's phone for
/// somebody else's timestamp, so the skewed read is reported as current
/// (`''`) and the band keeps its own words.
String staleProjectsAgeAr(DateTime? readAt, {DateTime? now}) {
  // **The rule is not this file's.** It is [readAgeAr], which the whole app
  // routes through so that a header, a market, a project list and a directory
  // cannot decide separately what "old enough to mention" means. This function
  // survives because four screens and their tests call it by name; it is a
  // named alias, not a second implementation.
  return readAgeAr(readAt, now: now);
}

/// The band line with its age, when the age is worth a word.
///
/// Two rules, and the second is the one that is easy to get wrong:
///
///   * The age is **appended**, never substituted. The failure sentence is
///     still there — it names the *kind* of failure `errorCopy` diagnosed, and
///     the age says nothing about it. A band that traded the reason for a
///     timestamp would tell a customer his list is «قبل 12 دقيقة» without
///     saying *why* it is not newer, which is the half he can act on.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte. Not a shorter variant, not a trailing dash: the wording
///     the existing screenshots and tests of this screen were written against
///     has to survive unchanged, or this file quietly re-opens a defect on a
///     screen that is already correct.
///
/// The age is a separate sentence rather than a clause inside the first because
/// Arabic wraps both, and a band that has to stay two lines tall on a 360 px
/// handset is the difference between a notice a customer reads and a notice he
/// scrolls past.
String staleProjectsLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleProjectsLineAr(error);
  final age = staleProjectsAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
