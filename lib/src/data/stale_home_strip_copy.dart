// What the client home says when a strip is showing rows the server no longer
// confirms.
//
// Found 29 Sep 2026 while auditing a new surface, and the **seventh** screen in
// the family the subscription bug opened. This one is on a different axis from
// the six before it, which is why it needs its own module rather than a seventh
// argument to one of them: the other six each hold *one* list, and each had to
// be told the truth about a single read. This screen holds **two** strips
// behind **one** gesture, and they can fail independently — the contractors
// call can die while the projects call answers, and the sentence has to be
// about the strip it is drawn on rather than about the screen.
//
// The defect is the family's usual shape, and pull-to-refresh is where it
// bites. `_refresh` re-arms all three reads behind the one gesture the user
// reaches for first, and each strip's failure branch draws a full
// `EmptyView` — so a network that blinked during a pull replaced «أفضل
// المقاولين» with a wifi-off card and told a client there were no contractors
// on the home screen he opens first, and replaced «مشاريعي الأخيرة» with
// «تعذّر جلب المشاريع» and hid the three jobs he had posted. The rows on both
// strips were real; they were simply the last ones the phone read.
//
// Why this one is worth a fix when the family is otherwise exhausted: the
// contractors strip is the *supply*, and it is duplicated — a client who loses
// it here can still walk into «ابحث عن مقاول», one tap away. The projects
// strip is not, and it is the same "only record" problem the «مشاريعي» screen
// has. So the honest ranking is: fixing this half fixes the copy the user
// cannot get anywhere else, and fixing the other half fixes the copy they can.
//
// The split is the family's split, unchanged: a failed **first** read has
// nothing to draw and keeps the full-screen error; a failed **re-read** keeps
// the rows and states the doubt. One `EmptyView` for both is a claim about the
// second that it cannot support.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_directory_copy.dart`, `stale_catalogue_copy.dart`,
// `stale_inbox_copy.dart` and `stale_projects_copy.dart` use.
library;

import 'read_age_ar.dart';

/// Which strip a stale sentence is being composed for.
///
/// Carried as an enum rather than as two free functions because the call site
/// has to *choose*, and a choice expressed as a boolean reads wrong at the
/// call site in a way that lets the two get swapped.
enum StaleHomeStrip {
  /// «أفضل المقاولين» — the supply. A client who loses it can still open the
  /// directory, so the sentence says where to go instead of only apologising.
  contractors,

  /// «مشاريعي الأخيرة» — the user's own jobs. Nothing else in the app lists
  /// them, so the sentence has to reassure that they are still there.
  projects,
}

/// The line shown above a strip that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
String staleHomeStripLineAr(String error, StaleHomeStrip strip) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a band that explains nothing.
  if (reason.isEmpty) {
    return switch (strip) {
      StaleHomeStrip.contractors => 'قد لا تكون هذه المقاولين محدَّثة',
      StaleHomeStrip.projects => 'قد لا تكون مشاريعك محدَّثة',
    };
  }
  return switch (strip) {
    StaleHomeStrip.contractors =>
      'لم نتمكن من تحديث قائمة المقاولين — هذه آخر نتيجة قرأناها. $reason',
    StaleHomeStrip.projects =>
      'لم نتمكن من تحديث مشاريعك — هذه آخر نتيجة قرأناها. $reason',
  };
}

/// How old the rows under a strip actually are, in the app's own words.
///
/// The **freshness half** of the family, and the fourth member to get it after
/// `stale_market_copy.dart`. The band already says «هذه آخر نتيجة قرأناها» —
/// *these are the last result we read* — which is true and useless on its own.
/// A pull that failed four seconds ago and one that failed forty minutes ago
/// print the **same sentence**, and on this screen the gap between them is
/// exactly what the user has to decide on.
///
/// It matters more here than on the siblings because the two strips fail for
/// different reasons and the consequences are not symmetric. The projects
/// strip is the user's own jobs and nothing else in the app lists them, so an
/// old one may be a job somebody else already took. The contractors strip is
/// *supply* and is duplicated one tap away in «ابحث عن مقاول», so its band
/// exists to reassure rather than to warn. Both get the same number for the
/// same reason: a doubt without a magnitude is not actionable, and the copy
/// that has been on screen for two days must not read like one that just
/// happened.
///
/// **The rule is not this file's.** It is [readAgeAr], which the whole app
/// routes through so a header, a market, a project list, a directory and now
/// these two strips cannot each decide what "old enough to mention" means.
/// Null, clock skew and under-a-minute are silence, and a band whose rows are
/// still current keeps its own words.
String staleHomeStripAgeAr(DateTime? readAt, {DateTime? now}) =>
    readAgeAr(readAt, now: now);

/// The band line with its age, when the age is worth a word.
///
/// Same two rules as every sibling, and the second is the easy one to get
/// wrong:
///
///   * The age is **appended**, never substituted. The failure sentence names
///     the *kind* of failure `errorCopy` diagnosed and the age says nothing
///     about it. A band that traded the reason for a timestamp would tell a
///     client his jobs are «قبل 12 دقيقة» without saying *why* they are not
///     newer, which is the half he can act on.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte, through [staleHomeStripLineAr]. Not a shorter variant,
///     not a trailing dash: the wording the existing tests and screenshots of
///     this screen were written against has to survive unchanged, or this
///     quietly re-opens a defect on a screen that is already correct.
///
/// The age is a separate sentence rather than a clause inside the first
/// because Arabic wraps both, and a band that has to stay two lines tall on a
/// 360 px handset is the difference between a notice a client reads and one he
/// scrolls past.
String staleHomeStripLineWithAgeAr(
  String error,
  DateTime? readAt,
  StaleHomeStrip strip, {
  DateTime? now,
}) {
  final base = staleHomeStripLineAr(error, strip);
  final age = staleHomeStripAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
