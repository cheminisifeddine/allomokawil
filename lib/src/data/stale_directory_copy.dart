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
