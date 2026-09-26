// Proving that a subscription write landed, on the one screen where guessing
// wrong costs a man his money.
//
// Found 26 Sep 2026 by auditing the write-outcome contract. Five write paths
// re-read the server after `errWriteUnconfirmed` and tell the user which of
// three things is true — it landed, it is missing, or it is still unknown:
// `project_new_screen` (title match), `project_detail` (bid amount +
// worker id), `chat_screen` (content + sender), `review_screen` (project +
// rating), `verification_screen` (pending or verified). The sixth write in
// the app — the one the founder makes money from — had none of it. Its
// `_request` caught the failure, showed `errorCopy(e)`, and stopped.
//
// `S.errWriteUnconfirmed` is «انقطع الاتصال قبل تأكيد وصول طلبك. تحقّق من
// القائمة قبل إعادة المحاولة». On the subscription screen that instruction
// was **a lie with no way to follow it**: the user was told to check the
// list, and the list is `pending_request` — a single slot, not a list — which
// the app does re-read on the next `_load()`. The contractor never saw the
// toast outcome; he saw a fixed card and a redraw, and if the write had in
// fact landed, the only sign of it was a card he had no reason to re-read
// after being told his request might not have arrived.
//
// Worse, the naive fix is the wrong one. `pending_request` holds **one** row,
// so a contractor who already had a request waiting when he tapped «ادفع» is
// looking at a slot that was already occupied. If the write landed, the slot
// is the *same plan* he was already waiting on — and the re-read cannot tell
// "my new request arrived" from "the old one is still there". Answering
// `landed` on a plan match would tell a man his second payment was filed
// when the server may have rejected it. Answering `missing` would tell him
// to pay again for something he already paid for.
//
// So identity here is **change**, not equality: the row is mine only if the
// pending request is not the one that was already on screen before the tap.
// [pendingRequestIsMine] is that one question, asked of two snapshots of the
// same slot, and it is deliberately conservative — a request id the server
// did not send cannot be compared, so a snapshot whose id changed is
// evidence, and a snapshot whose id stayed the same is proof of nothing
// either way, which is what [WriteOutcome.unknown] is for.
//
// This file is pure. The screen takes the two snapshots and prints what
// comes out, so the rule is testable without a widget — the same split
// `quote_count_copy.dart` and `pending_request_copy.dart` use.
library;

import '../core/l10n/write_outcome.dart';
import '../models/plan.dart';

/// True when [fresh] is evidence that the write this screen just made landed.
///
/// The two snapshots are the same slot read twice: [before] is what the
/// catalogue held when the payment sheet was opened, [fresh] is what it
/// holds on the re-read after an unconfirmed write.
///
/// **The rule is a change in identity, never an equality:**
///
/// * A pending request that was there before the tap and is the same row
///   after it is **not** evidence of anything. It is the old request, still
///   waiting, and the write may have been rejected. The only honest answer
///   is that the app does not know.
/// * A slot that was **empty** before and is occupied after is the write
///   landing, and the id moving from nothing to something is the proof.
/// * A slot that moved to a **different** id is the write landing — the
///   server accepted a second request and either replaced or ordered the
///   slot. The contractor's money is accounted for by a row he can name.
///
/// Both landing cases need the id, because the id is the only fact that
/// separates "this is the request I just made" from "this is a request that
/// was already in flight". When [fresh] carries no id at all — an older
/// server, or a row the payload lost — the answer is a conservative **false**:
/// reporting `landed` for a row the app cannot identify is the one mistake
/// this whole file exists to prevent.
bool pendingRequestIsMine({
  PendingRequest? before,
  required PendingRequest? fresh,
}) {
  final freshId = fresh?.id;
  // No row, or a row with no usable id: nothing to identify.
  if (freshId == null || freshId <= 0) return false;
  final beforeId = before?.id;
  if (beforeId == null || beforeId <= 0) {
    // The slot was empty and now holds a row: the write landed.
    return true;
  }
  // Same row, still waiting: this is the request from before the tap.
  return freshId != beforeId;
}

/// Runs the honest re-read for a subscription write and classifies it.
///
/// [before] and [fetch] are the two halves of "did it land": [before] is the
/// pending request the catalogue already held when the contractor tapped
/// «ادفع», and [fetch] re-reads the same slot from the server. The return is
/// the same [WriteOutcome] the other five write screens speak, so the money
/// screen and the project screen cannot drift apart on what a confirmation
/// is allowed to say.
///
/// A failing [fetch] is [WriteOutcome.unknown] and never [WriteOutcome.missing]:
/// the phone is still offline, and telling a man who just handed over 30000
/// دج that his payment did not arrive is how he pays twice.
Future<WriteOutcome> resolveSubscriptionWriteOutcome({
  PendingRequest? before,
  required Future<BillingCatalogue> Function() fetch,
}) async {
  final BillingCatalogue fresh;
  try {
    fresh = await fetch();
  } catch (_) {
    return WriteOutcome.unknown;
  }
  return pendingRequestIsMine(before: before, fresh: fresh.pendingRequest)
      ? WriteOutcome.landed
      // A re-read that came back without my request: the write did not land
    // and retrying is safe. The predicate already refused the one case it
    // cannot rule on (an id that did not move), so this is a real "not found".
      : WriteOutcome.missing;
}
