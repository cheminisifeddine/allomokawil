// What the notification centre says when the rows on screen are not the rows
// on the server.
//
// Found 29 Sep 2026 while auditing a new surface, the **eighth** screen in the
// family the subscription bug opened — and the only member of the family that
// fails **silently**. That difference is worth stating precisely, because the
// other seven were all fixed by "keep the rows and add a banner", and reading
// this screen as if it were simply one more of those would be a mistake about
// which bug it has.
//
// Seven screens destroy the data *and* report it: a failed re-read replaces the
// list with «تعذّر جلب …». That is loud and it is still wrong — the rows were
// real, the cache existed, and the honest state is "these are the last ones
// read". This screen keeps the rows and reports **nothing at all**, which is
// worse, because silence is indistinguishable from "nothing happened".
//
// The mechanism is one line. [NotificationsScreen._load] assigns `_error` on
// failure and never touches `_items`, and `_body` reads `_error` only inside
// `if (_items.isEmpty)`. A first read that fails therefore gets the full-screen
// error — correct, there is nothing to draw. A **failed refresh** on a
// populated list sets a field the body cannot reach, so the screen goes on
// drawing yesterday's rows with no qualification at all. The list is not
// wrong; it is *unlabelled*, and an unlabelled list is a claim.
//
// Why it is worse here than a stale screen anywhere else in the app, and why
// it is not "mild because the data survives": this is the only surface in the
// product whose entire job is to be the app's memory of what happened while it
// was closed. Its doc comment says exactly that. The home header paints an
// unread pip from the same rows, so a silent stale read here is the *input* to
// a number the user is looking at on the next screen, not a private list
// quietly going out of date.
//
// And this screen already knew the answer. `notification_count_trust.dart`
// exists — built to stop the header drawing an unverified count as a fact, and
// `NotificationsScreen` already calls `_trust.withdraw()` for the one failure
// it could see (the `_settleRead` re-read that could not run). A plain failed
// pull-to-refresh, the most ordinary failure there is, withdrew nothing. So the
// two halves of the same bug were both available: the trust flag is one call
// away, and the sentence is one line. Neither was made.
//
// The fix is the family's split, with the missing half added. A failed
// **first** read has nothing to draw and keeps the full-screen error. A failed
// **re-read** keeps the rows, states the doubt above them, **and** withdraws
// the pip's trust so the header stops painting a number in the same breath the
// centre is admitting it cannot check that number.
//
// Deliberately not phrased as an error. A notification that failed to load is
// not an emergency the user must act on — the app is telling him that what he
// is reading survived an earlier read, and the only thing being asked of him is
// to understand that there may be more he has not seen yet. `errorCopy`'s
// sentence describes the failure; this composes it with the half it cannot
// know, the same split every other member of the family uses.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_catalogue_copy.dart`, `stale_inbox_copy.dart` and
// `stale_projects_copy.dart` use.
library;

/// The line shown above a notification list that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that the rows in front of the reader survived an earlier read
/// — **and** that there may be notifications in there they have not seen,
/// which is the part a list that stays on screen can never say for itself.
String staleNotificationsLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so that a
  // bare failure cannot produce a banner that explains nothing.
  if (reason.isEmpty) return 'قد تكون هناك إشعارات لم تصلك بعد';
  return 'لم نتمكن من تحديث الإشعارات — هذه آخر قائمة قرأناها، وقد تكون هناك إشعارات لم تصلك بعد. $reason';
}
