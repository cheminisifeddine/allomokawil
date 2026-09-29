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
