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
