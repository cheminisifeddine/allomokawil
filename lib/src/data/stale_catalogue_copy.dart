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
