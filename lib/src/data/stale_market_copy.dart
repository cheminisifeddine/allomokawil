// What the contractor's market says when the open projects on screen are not
// the open projects on the server.
//
// Found 29 Sep 2026 while auditing the remaining `_future` / `FutureBuilder`
// surfaces, and it is the **ninth** screen in the family the subscription bug
// opened. It is also the one with the most room left in it, because this feed
// is re-issued by *more* controls than any sibling has:
//
//   * pull-to-refresh ([_refresh] -> [_reload]),
//   * every filter change — a trade chip and a wilaya, two of them,
//   * the location fix landing late, [_seedFromPlace] dropping `_projects`,
//   * the empty state's own «تحديث» button,
//   * and the profile-save path, [_editProfile].
//
// The defect is the family's usual shape and it is one line deep. `snap
// .hasError` returns a `SliverToBoxAdapter` holding a full-screen
// `EmptyView` — «تعذّر جلب المشاريع» over the entire list — so *every* one of
// those six controls, on a connection that blinks, replaced the market the
// contractor was reading with an error page. And unlike the eight before it,
// there is a **pending** failure too, which is the one that costs him a screen
// rather than a list: `_reload` installs a new `_projects` and the builder's
// first line is `if (snap.connectionState != ConnectionState.done) return
// Skeleton`, so a filter tap or a pull replaced twenty warm rows with a
// skeleton and stayed there for as long as the request took.
//
// Why this one is worth the tick over its siblings, and it is not the
// severity that decides it:
//
//   * **It is the only read in the family that a *visitor* can lose.** The
//     market is public — the feed is served to a guest with no account at all
//     (`initState` reads the profile only when `!widget.guest`) — so this is
//     the first screen in the sequence where a failed refresh can happen to
//     somebody who has never signed in and has no other copy of anything.
//   * **It is the supply a contractor earns on.** An open project across town
//     is the only reason the tab exists; the browse directory shows the same
//     rows but a contractor is not sent there to look for work, he is sent here.
//   * **And it is the last of the family.** After this one the `FutureBuilder`
//     surfaces left in the app are the four that already keep a cache and gate
//     their body on a successful read (`profile_screen`'s plan row,
//     `verification_screen`, `project_detail_screen`, `worker_profile_screen`),
//     which is the correct shape and is not a defect.
//
// The fix is the family's split, unchanged, for the same reason every time: a
// failed **first** read has nothing to draw and keeps the full-screen error; a
// failed **re-read** keeps the rows and states the doubt, and a **waiting**
// re-read keeps the rows too rather than throwing them away for a shimmer.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_directory_copy.dart`, `stale_catalogue_copy.dart`, `stale_inbox_copy.dart`,
// `stale_projects_copy.dart`, `stale_home_strip_copy.dart` and
// `stale_notifications_copy.dart` use. Seven siblings, eight lines of argument,
// and this file is the ninth.
library;

// [readAgeAr] is the only dependency. The count grammar and the calendar-day
// boundary live two files behind it, and a fifth hand-rolled copy of
// «قبل ساعتين» is how the subscription card ended up calling three hours
// «قبل 3 ساعت». `notification_copy.dart` stays imported for [relativeTimeAr],
// which this file's own documentation cites.
import 'notification_copy.dart';
import 'read_age_ar.dart';

/// The line shown above the open-project feed that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
///
/// The wording is deliberately the directory's («تحديث القائمة») rather than
/// the «مشاريعي» screen's («تحديث مشاريعك»): this is **not** the user's own
/// project list, it is the open market every other contractor is bidding on.
/// Saying «مشاريعك» here would be the same family-of-one confusion the
/// `stale_home_strip_copy.dart` enum exists to prevent — two strips, two
/// sentences, and a sentence that names the wrong list is worse than no
/// sentence at all, because it is confidently wrong.
String staleMarketLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a band that explains nothing.
  if (reason.isEmpty) return 'هذه المشاريع قد لا تكون محدَّثة';
  return 'لم نتمكن من تحديث القائمة — هذه آخر نتيجة قرأناها. $reason';
}

/// How old the open projects on screen actually are, in the app's own words.
///
/// The **freshness half** of the family, and the ninth member to get it. The
/// band above says «هذه آخر نتيجة قرأناها» — *these are the last result we
/// read* — which is true and useless on its own. A contractor reading a market
/// he is about to bid on is asking one question: *how wrong can this be?* A
/// list that failed to refresh four seconds ago and one that failed forty
/// minutes ago print **the same sentence**, and the second one is the one where
/// an open project somebody else has already taken is a bid he lost.
///
/// So the doubt is stated with a number on it. Three outcomes:
///
///   * **`null` / under a minute** — the band is about a read that is *still
///     current*. A pull that failed on a slow connection while the list is two
///     seconds old is a hiccup, and printing «قبل 4 ثوانٍ» under it is a
///     reassurance dressed as a measurement. The screen then says only what it
///     said before, which is the correct thing to say about a failure with no
///     consequence yet.
///   * **a minute and older** — «قبل 12 دقيقة», «قبل ساعتين», «أمس».
///   * **a year and older** — the calendar date, courtesy of
///     [relativeTimeAr]. A market left unrefreshed across a whole year is not
///     a latency problem and must not be described in the vocabulary of one.
///
/// **Negative ages are clock skew, not the future.** A stamp ahead of the phone
/// is a broken clock somewhere between the server and the handset; ageing it
/// into «قبل -3 دقيقة» would be the app blaming the reader's phone for
/// somebody else's timestamp, so the skewed read is reported as having no age
/// (`''`) and the band keeps its own words.
String staleMarketAgeAr(DateTime? readAt, {DateTime? now}) {
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
///     timestamp would tell a contractor his list is «قبل 12 دقيقة» without
///     saying *why* it is not newer, which is the half he can act on.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte. Not a shorter variant, not a trailing dash: the wording
///     every screenshot and every test of the eight siblings was written
///     against has to survive unchanged, or this file quietly re-opens a
///     defect on seven screens that are already correct.
///
/// The age is a separate sentence rather than a clause inside the first
/// because Arabic wraps both, and a band that has to stay two lines tall on a
/// 360 px handset is the difference between a notice a contractor reads and a
/// notice he scrolls past.
String staleMarketLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleMarketLineAr(error);
  final age = staleMarketAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
