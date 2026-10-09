// What the chat says when the thread it drew is not the whole thread.
//
// Found 10 Oct 2026, by measuring the live API instead of reading the client
// — and the measurement is the point, because the code looks correct.
//
// **The server caps a thread read at 100 rows and returns the OLDEST 100.**
// Measured against production with a throwaway conversation carrying 150
// messages: a plain `GET /api/messages/38` answered **100 rows, ids 45..144**,
// while the thread held ids up to 174. The newest thirty messages — the ones
// the user was looking at, the ones the customer is waiting on a reply to —
// were simply not in the answer. `?limit=200` changed nothing, so the cap is
// the server's and not a default the client is allowed to raise.
//
// This is the **same defect the market search had, and it is worse**, for one
// reason the market case did not have: there, a lost page made the app claim a
// market was empty. Here, a lost page does not make the app claim anything —
// it makes the app *agree with a lie the other party can see*. The customer
// reads «وصلت» on a message the contractor never received, and the contractor
// re-opens the thread to find the last thing he said is four days old. The
// screen is not wrong about the rows it drew; it is silent about the rows it
// did not draw, and silence about the newest messages reads as «we are done
// talking».
//
// `Repository.messages` already had the repair half: an `after` cursor, so a
// caller *could* walk back. It is used for exactly one thing — re-checking
// whether a message this phone sent arrived (`resolveWriteOutcome`) — which is
// a question about one row. Opening the thread, the thing a person does, was
// a single unbounded read. So the capability existed and the screen that needed
// it never called it.
//
// The fix is deliberately two parts, because they answer different questions:
//
//   * **Walk the tail.** `ThreadReadResult` pages backward from the newest
//     message until the server stops handing back a full page, so the thread a
//     user opens holds what he came to read. This is a repair and it is silent:
//     nobody needs a band for «the messages are here».
//   * **Say so when even that is not enough.** A thread far longer than the
//     pages a phone will hold has messages that will not be drawn, and for
//     those the band is the only honest signal — same rule, same shape, same
//     split as `partial_market_copy.dart`: a verdict may only be printed by a
//     read that covered the thing it is a verdict about.
//
// Pure copy, no I/O: the split every sibling in the stale-*_copy family uses,
// and the reason the wording is testable without pumping a widget.
library;

import '../core/l10n/arabic_agreement.dart';

/// «رسالة واحدة» / «رسالتان» / «3 رسائل» / «11 رسالة».
///
/// **One branches before the rule and the bare singular goes in after it** —
/// the exact trap `lostPagesAr` and `commune_count_copy.dart` all document:
/// [arabicCounted] reuses the singular slot for 11 and up, so passing
/// «رسالة واحدة» as the singular would print «11 رسالة واحدة».
///
/// Zero is silence: the caller only asks this about messages it did not draw.
String undrawnMessagesAr(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'رسالة واحدة';
  return arabicCounted(n, 'رسالة', two: 'رسالتان', few: 'رسائل');
}

/// The line shown when a thread is longer than the read that opened it.
///
/// [undrawn] is how many messages the phone knows about and did not draw, and
/// [drawn] is how many it did — because a customer who has been told «some
/// messages are not shown» reasonably asks «which ones?», and «the 340 oldest»
/// is the answer he can act on. It names the gap in his own vocabulary
/// because *how many* is what he tells the contractor on the phone.
String partialThreadLineAr({required int undrawn, required int drawn}) {
  if (undrawn <= 0) return '';
  final hidden = undrawnMessagesAr(undrawn);
  final scope = drawn > 0 ? ' من $drawn' : '';
  // **No gesture is promised, because none is wired.** The first draft said
  // «اسحب للأعلى لقراءة الأقدم» and it was fiction: `chat_screen.dart` has no
  // `ScrollNotification` listener, no load-older and no way to fetch further —
  // `grep` for all three returns nothing. A band that names an action the app
  // does not perform is the same defect as the silent truncation, one layer up:
  // it moves the failure from «you were not told» to «you were told to do
  // something impossible», which is worse, because the user now tries it, sees
  // nothing happen, and concludes the app is broken rather than incomplete.
  // The sentence therefore states the fact and stops.
  return 'هذه المحادثة طويلة. $hidden$scope رسائل أقدم من المعروض،'
      ' ولم تظهر هنا.';
}

/// Whether a thread read that left [undrawn] messages undrawn may still call
/// itself complete.
///
/// **The rule is one line and it is the whole point of this file.** «كل
/// الرسائل» is a verdict about the conversation, and the app may only print a
/// verdict it is entitled to: a read that drew everything has one, and a read
/// that dropped rows has *no answer at all* about messages it never saw. Kept
/// as its own predicate rather than left to the call site, because the call
/// site is where the temptation lives — the rows are in hand and `every()` or
/// `isEmpty` reads like a conclusion.
bool partialThreadMayClaimComplete({required int undrawn}) {
  // `<= 0` and **not** `== 0`, matching `partialMarketMayClaimNoResults`
  // exactly. A negative count cannot be produced — [ThreadReadResult.undrawn]
  // starts at 0 and only ever grows — so the two spellings are the same
  // function on every input that exists. They are pinned equal because the
  // first draft of the test here asserted a negative count is *incomplete*,
  // which would make this file disagree with its own sibling for no reason a
  // user could ever observe.
  //
  // And the lenient reading is the right one even so: a caller bug should
  // produce the *quieter* screen, not a band announcing messages the app has
  // no reason to believe exist.
  return undrawn <= 0;
}
