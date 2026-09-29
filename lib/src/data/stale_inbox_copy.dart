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

import 'read_age_ar.dart';

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

/// How old the conversations under the band actually are.
///
/// The **freshness half** of the family, and the ninth member to get it, after
/// the market, the projects list, the directory, the notifications, the two
/// home strips and the subscription catalogue. The band already says «هذه آخر
/// قائمة قرأناها» — *this is the last list we read* — which is true and answers
/// nothing: a refresh that failed four seconds ago and one that failed three
/// hours ago print the **same sentence**, and on an inbox that gap is the whole
/// question the user came here to ask.
///
/// It matters more here than on most siblings because this is the one list in
/// the app that is *moving*. A market of open projects changes when a client
/// posts one; a directory changes when a contractor signs up. An inbox changes
/// the moment the person you are talking to replies, and the whole reason to
/// open this tab is to find out whether they have. Telling someone their list
/// may be out of date, without saying how far out of date it is, leaves them to
/// guess between "I missed something while I was in another thread" and "this
/// is two hours old and there is no point re-opening the thread I left" — two
/// opposite conclusions drawn from one sentence that admits either.
///
/// **The rule is not this file's.** It is [readAgeAr], which the whole app
/// routes through so that a header, a market, a project list, a directory, two
/// home strips, a catalogue and now this inbox cannot each decide separately
/// what "old enough to mention" means. Null, clock skew and under-a-minute are
/// silence, and a band whose rows are still current keeps its own words.
String staleInboxAgeAr(DateTime? readAt, {DateTime? now}) =>
    readAgeAr(readAt, now: now);

/// The band line with its age, when the age is worth a word.
///
/// Same two rules as every sibling, and the second is the one that is easy to
/// get wrong:
///
///   * The age is **appended**, never substituted. The failure sentence names
///     the *kind* of failure `errorCopy` diagnosed, and the age says nothing
///     about it. A band that traded the reason for a timestamp would print
///     «قرأناها قبل 12 دقيقة» without saying *why* it might not be newer, and
///     «لم نتمكن من تحديث المحادثات» is the half that stops the banner reading
///     as a routine timestamp.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte. Every screenshot and every assertion the inbox tests were
///     written against has to survive unchanged, or this file quietly re-opens
///     a defect on a screen that is otherwise already correct.
///
/// The age is a second sentence rather than a clause inside the first because
/// Arabic wraps both, and a band that has to stay two lines tall on a 360 px
/// handset is the difference between a notice the reader takes seriously and
/// one he scrolls past.
String staleInboxLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleInboxLineAr(error);
  final age = staleInboxAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nقرأناها $age.';
}
