// What «ابحث عن مقاول» says when the list on screen is not the list on the
// server.
//
// Found 29 Sep 2026 while auditing a new surface, and the **fifth** screen in
// the family the subscription bug opened — but the worst of them, because this
// one has no cache to lose in the first place. See the note on `_future` in
// `browse_screen.dart` for the mechanical version of this.
//
// The two screens before it each had something to hold on to.
// `worker_profile_screen`, `project_detail_screen` and `subscription_screen`
// keep a field, and a failed *re-read* falls back to it while a failed *first*
// read is reported — a good split, because the field is exactly the rows the
// user was already reading. `chat_list_screen` had the same field and then
// answered `null` on the failure branch, throwing the rows away in the one
// state the field existed for; that one shipped 29 Sep and left an amber band.
//
// This screen never had the field. `_future` is re-assigned by every pull, by
// every submitted search, by clearing the box, and by changing a filter chip,
// and the builder's failure branch draws «تعذّر جلب المقاولين» over the whole
// feed. So the defect is bigger than a lost cache: a **pending** re-read
// replaces a list of contractors with a shimmer, and a **failed** one replaces
// it with an error page. The last-touched, still-warm list of pros is not a
// thing this screen can show.
//
// Why the directory is the worst surface in the app to do it on. The
// contractor directory is the **first** screen a client opens to find
// somebody — it is the marketplace, the reason the app is installed, and the
// only read a customer makes who is not here to chat. And it is the read most
// likely to fail at the exact moment it matters: a client standing in a
// basement shop with one bar of signal opens «ابحث عن مقاول» to price a job
// they are standing in, and the list the app throws away is the list he came
// for. The other screens in this family hold history the user already has —
// his conversations, his own projects, his own subscription. This one holds
// the *supply*, and supply the user cannot see does not exist.
//
// The fix is the same split the inbox landed on, and for the same reason: a
// failed **first** read has nothing to draw and keeps the full-screen error;
// a failed **re-read** keeps the rows and states the doubt. The two are
// different sentences about different facts, and a screen that draws one
// EmptyView for both is making a claim about the second it cannot support.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_catalogue_copy.dart`, `stale_inbox_copy.dart` and `price_range_copy.dart`
// use.
library;

// [readAgeAr] is the only dependency. The count grammar and the calendar-day
// boundary live two files behind it, and a hand-rolled copy of «قبل ساعتين» is
// how the subscription card came to call three hours «قبل 3 ساعت».
// `notification_copy.dart` stays imported for [relativeTimeAr], which this
// file's own documentation cites.
import 'notification_copy.dart';
import 'read_age_ar.dart';

/// The line shown above a contractor list that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
String staleDirectoryLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a banner that explains nothing.
  if (reason.isEmpty) return 'هذه القائمة قد لا تكون محدَّثة';
  return 'لم نتمكن من تحديث القائمة — هذه آخر نتيجة قرأناها. $reason';
}


// ── The freshness half ───────────────────────────────────────────────────
//
/// How old the contractor list on screen actually is, in the app's own words.
///
/// The **third** member of the family to get this half, after
/// `stale_market_copy.dart` and `stale_projects_copy.dart`, and on the screen
/// it matters most. [staleDirectoryLineAr] already says «هذه آخر نتيجة
/// قرأناها» — *these are the last result we read* — which is true and answers
/// none of the question the band forces on the reader.
///
/// On this screen that question has a sharper edge than on its siblings. Every
/// other member of the family holds the reader's *own* history: his messages,
/// his projects, his subscription. This one holds the **supply** — the
/// contractors who registered last week, and whose availability, price band and
/// phone number change without any push the app can send. A directory that
/// failed to refresh four seconds ago and one that failed an hour ago print
/// the **same sentence**, and only one of them is a client standing in a
/// basement shop with one bar of signal, pricing a job he is standing in,
/// looking at a contractor who may have been booked since this morning.
///
/// So the doubt is stated with a number on it. Three outcomes:
///
///   * **`null` / under a minute** — nothing. The band is about a read that is
///     still *current*; a pull that failed on a slow connection while the list
///     is two seconds old is a hiccup, and printing «قبل 4 ثوانٍ» under it is a
///     reassurance dressed as a measurement. The band then says only what it
///     said before, which is the correct thing to say about a failure with no
///     consequence yet.
///   * **a minute and older** — «قبل 12 دقيقة», «قبل ساعتين», «أمس».
///   * **a year and older** — the calendar date, courtesy of [relativeTimeAr].
///     A directory left unrefreshed across a whole year is not a latency
///     problem and must not be described in the vocabulary of one.
///
/// **Negative ages are clock skew, not the future.** A stamp ahead of the
/// phone is a broken clock somewhere between the server and the handset;
/// ageing it into «قبل -3 دقيقة» would be the app blaming the reader's phone
/// for somebody else's timestamp, so the skewed read is reported as current
/// (`''`) and the band keeps its own words.
String staleDirectoryAgeAr(DateTime? readAt, {DateTime? now}) {
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
///     timestamp would tell a client his list is «قبل 12 دقيقة» without saying
///     *why* it is not newer, which is the half he can act on.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte. Not a shorter variant, not a trailing dash: the wording
///     this screen's existing screenshot and tests were written against has to
///     survive unchanged, or this file quietly re-opens a defect on a screen
///     that is already correct.
///
/// The age is a separate sentence rather than a clause inside the first
/// because Arabic wraps both, and a band that has to stay two lines tall on a
/// 360 px handset is the difference between a notice a client reads and a
/// notice he scrolls past.
String staleDirectoryLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleDirectoryLineAr(error);
  final age = staleDirectoryAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
