// What «الرسائل» says when the list on screen is not the list on the server.
//
// Found 29 Sep 2026 while auditing a new surface, the fourth screen in the
// family the subscription bug opened. That one kept its data and hid the
// failure; this one does the **opposite** and is the worse half of the pair:
// it destroys the data *and* reports the failure, so nothing is left to doubt.
//
// The screen is built around a cache. `_cache` exists for one stated reason —
// "the last list that landed, kept so a re-read does not blank the screen",
// because the tab this inbox lives in re-reads it every time the app comes
// back to the foreground, and blanking the list on every unlock is a lurch no
// user should have to sit through. The cache does its job: a re-read that is
// *pending* falls back to it and the rows stay.
//
// The branch that never runs is the one that *fails*. The builder computes
//     waiting  -> _cache
//     error    -> null      (render the full-screen error)
//     data     -> snap.data
// and `convs == null` with `waiting == false` is the error state, which
// replaces the list with «تعذّر جلب الرسائل» and a retry button. So the exact
// case the cache was written for — rows on screen, server unreachable — is
// the one case that throws the rows away. `_arm`'s own `onError` does the
// honest half: it calls `_messages?.withdraw()` so the tab badge stops
// claiming a count the list can no longer show. The badge apologises while the
// list it was counting lies to the user with an empty screen.
//
// That is the part worth stopping on. This inbox has an outbox: messages that
// exist **only on this phone**, drawn as a per-row queued pill (see
// [queuedCountLabel]). Its doc comment says the inbox "is the last place a user
// can notice that a message never left". A failed refresh does not just hide
// history — it hides the one surface that admits unsent messages exist, and it
// does so at the exact moment the network is bad enough to be the reason they
// are unsent. The same bad connection that keeps a message from sending is the
// one that hides the evidence it never sent. A user whose message is stuck in
// the outbox is handed a screen that claims there is nothing there at all, and
// an empty inbox in this app is a *true* statement with a real meaning
// ("no conversations yet") — so the error view is the only thing standing
// between the user and a confident false belief, and it is the thing that
// collapses.
//
// The fix keeps the cache honest instead of discarding it. Rows on screen +
// a failed re-read = the rows are real and a newer read did not land, which is
// one sentence, and it is the same doubt `stale_catalogue_copy.dart` states for
// the screen that kept its data. Deliberately *not* the full-screen error: a
// dead inbox on a flaky network is worse than a stale one, and it throws away
// the only proof the user has that something is still waiting to send.
//
// A **first** read that fails has no cache and keeps the full-screen error —
// there is genuinely nothing to draw there, and the retry button is the whole
// answer. The branch is not weakened, it is drawn where the data is.
//
// Pure, so the wording is testable without pumping a widget — the same split
// `stale_catalogue_copy.dart` and `chat_preview_copy.dart` use.
library;

/// The line shown above a conversation list that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
String staleInboxLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so a bare
  // failure cannot produce a banner that explains nothing.
  if (reason.isEmpty) return 'هذه المحادثات قد لا تكون محدَّثة';
  return 'لم نتمكن من تحديث المحادثات — هذه آخر قائمة قرأناها. $reason';
}
