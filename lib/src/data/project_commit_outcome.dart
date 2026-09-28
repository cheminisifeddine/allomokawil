// Answering the three owner writes on the project detail screen, which are the
// only writes in the app that commit something the user cannot take back and
// the only ones that tell him to check a list that is not on screen.
//
// Found 28 Sep 2026 by auditing the write-outcome contract after the project
// *edit* path was repaired. Eight write paths re-read the server after
// `errWriteUnconfirmed` and say which of three things is true — it landed, it is
// missing, or it is still unknown: `project_new_screen` (create and edit),
// `project_detail` (submit a bid), `chat_screen`, `review_screen`,
// `verification_screen`, `subscription_screen`, `my_portfolio_screen`. The
// three writes immediately above the bid form on the same screen had none of
// it: `_accept`, `_complete` and `_cancel` each caught the failure, called
// `errorCopy(e)`, and returned.
//
// `errorCopy` returns an `ArabicCopyError`'s message verbatim, so the owner was
// told «انقطع الاتصال قبل تأكيد وصول طلبك. تحقّق من القائمة قبل إعادة
// المحاولة» — *check the list before retrying* — and the only list on the
// screen is the one that was never re-read. It is stale by construction: the
// re-read is the only thing that would have told the story, and the instruction
// asks the user to perform it by eye. This is the exact failure the write-outcome
// work exists to prevent, and it survived seven ticks because every previous
// item was a screen whose *first* write lacked the contract; this screen had a
// bid form that had it, forty lines below the accept button.
//
// The cost is not the sentence, it is what each retry can do:
//
//  * **Accept** is the only write in the product that commits a contract. The
//    screen's own comment says so. Its guard (`_acceptingQuoteId`) clears in
//    `finally`, so a stalled accept leaves the button live and the owner's next
//    move is the one the sentence tells him to make. He cannot see whether the
//    contractor is hired, and every *other* quote on screen still wears a live
//    accept button — a tap on the wrong one is a 409 he cannot explain.
//  * **Complete** is the only door into the review form. A stall told the owner
//    the project was not closed, he taps again, and the review the whole trust
//    model rests on may or may not have been written.
//  * **Cancel** is the mildest of the three and is included because the fix is
//    the same three lines: without it, this file would be a claim that "the
//    write-outcome contract is complete" while one quarter of one screen's
//    writes still lied.
//
// **The rule is a change in the server's copy of the row, never a claim about
// the request.** The phone cannot know what the Worker did; the only evidence
// available is the project as the server now holds it. So each predicate asks
// one question of that row, and a row that cannot answer it — for any reason
// other than "the write clearly did not land" — is [WriteOutcome.unknown],
// never a guess.
//
// Two answers are deliberately *not* [WriteOutcome.missing], because the copy
// for missing ends in «أعد المحاولة» and neither is retryable:
//
//  * the project is **committed to a different contractor** than the one being
//    accepted. The accept did not land; the row is now owned by somebody else.
//    Saying «not saved, retry» sends the owner back to press a button the
//    server will now refuse forever.
//  * the project is **cancelled** while a complete is unconfirmed. It cannot be
//    completed at all, so «retry» is a false promise about a control he can no
//    longer reach.
//
// Both are reported as their own sentence rather than as a degraded
// `unknown`: the app *does* know something true and specific, and
// [writeUnconfirmedUnknown]'s «تحقّق من القائمة» asks him to go and do the
// re-read this screen has already done for him.
library;

import '../core/l10n/strings.dart';
import '../core/l10n/write_outcome.dart';
import '../models/project.dart';

/// The three owner writes that change what a project *is* rather than what it
/// says.
///
/// Declared here so the screen cannot pass a fourth thing to a function that
/// answers for three, and so the switch in [projectCommitCopy] is total.
enum ProjectCommit {
  /// `POST /quotes/{id}/accept` — hire a contractor.
  accept,

  /// `POST /complete` — close the job, which opens the review.
  complete,

  /// `POST /cancel` — withdraw the job and its pending bids.
  cancel,
}

/// True when the server's copy of the project proves the commit landed.
///
/// [workerId] is the contractor the owner was accepting and is only read for
/// [ProjectCommit.accept]; the other two commits do not name a worker.
///
/// **Every field that decides the answer, and nothing else.** `title`,
/// `budgetMin`, `images` and the rest are not compared: a stalled *accept* or
/// *cancel* does not change them, and a field that is identical in both
/// outcomes would be evidence for landing whether it landed or not.
bool projectCommitHolds(
  Project fresh,
  ProjectCommit what, {
  int? workerId,
}) =>
    switch (what) {
      // Hired, and hired *him*. `inProgress` with no worker, or `open` with a
      // worker the server kept from an earlier run, are both decoys: the status
      // alone would call a contract that was never signed a landing.
      ProjectCommit.accept => fresh.status == ProjectStatus.inProgress &&
          workerId != null &&
          fresh.selectedWorkerId == workerId,
      ProjectCommit.complete => fresh.status == ProjectStatus.completed,
      ProjectCommit.cancel => fresh.status == ProjectStatus.cancelled,
    };

/// The one answer that is neither «it landed» nor «you may retry».
///
/// A `missing` sentence ends in «أعد المحاولة», so a write that cannot be
/// retried must not be classified as one. Both cases here are the server
/// refusing the owner a second attempt, which is the opposite of what that
/// sentence promises.
enum CommitStall {
  /// The project is committed to a contractor other than the one being accepted.
  reassigned,

  /// The project is cancelled, so it can no longer be completed.
  uncancellable,
}

/// What a re-read proved about a commit whose answer never arrived.
typedef ProjectCommitResult = ({
  WriteOutcome outcome,

  /// The stall this row is in, or null when there is none.
  CommitStall? stall,
});

/// Classifies the server's copy of the project after an unconfirmed commit.
///
/// The ordering matters and is not incidental. [projectCommitHolds] is asked
/// first, so a row that *did* land is never described as stalled; then the two
/// stalls, which are only ever reached from a row that did not land; and only
/// then [WriteOutcome.missing], which is the one answer that promises a retry
/// and must be reached by a row that genuinely offers one.
///
/// A cancelled project answers [ProjectCommit.cancel] before it can be reported
/// as stalled, because a cancel that landed is a landed cancel whether or not
/// the caller was completing.
ProjectCommitResult classifyProjectCommit(
  Project fresh,
  ProjectCommit what, {
  int? workerId,
}) {
  if (projectCommitHolds(fresh, what, workerId: workerId)) {
    return (outcome: WriteOutcome.landed, stall: null);
  }
  if (what == ProjectCommit.accept &&
      fresh.selectedWorkerId != null &&
      (workerId == null || fresh.selectedWorkerId != workerId)) {
    return (outcome: WriteOutcome.unknown, stall: CommitStall.reassigned);
  }
  if (what == ProjectCommit.complete &&
      fresh.status == ProjectStatus.cancelled) {
    return (outcome: WriteOutcome.unknown, stall: CommitStall.uncancellable);
  }
  return (outcome: WriteOutcome.missing, stall: null);
}

/// The sentence for a commit the app re-read to find out about.
///
/// One function for all three writes, because the three differ only in the noun
/// the user is waiting on — the contract, the job, the withdrawal — and giving
/// each its own branch is how three of them drift.
///
/// A dedicated sentence for [WriteOutcome.landed], not
/// [S.writeUnconfirmedLanded]: that one is «وجدناه في القائمة», a claim about
/// *finding a row*, and the project was on screen the whole time. What changed
/// is what the row now **is**, and the copy has to name that, because the
/// owner pressed a button and needs to know which one worked. Same reason
/// [S.editUnconfirmedLanded] exists for the edit path.
String projectCommitCopy(ProjectCommitResult r, ProjectCommit what) {
  if (r.stall != null) {
    return r.stall == CommitStall.reassigned
        ? S.commitUnconfirmedReassigned
        : S.commitUnconfirmedUncancellable;
  }
  return switch (r.outcome) {
    WriteOutcome.landed => switch (what) {
        ProjectCommit.accept => S.acceptUnconfirmedLanded,
        ProjectCommit.complete => S.completeUnconfirmedLanded,
        ProjectCommit.cancel => S.cancelUnconfirmedLanded,
      },
    WriteOutcome.missing => switch (what) {
        ProjectCommit.accept => S.acceptUnconfirmedMissing,
        ProjectCommit.complete => S.completeUnconfirmedMissing,
        ProjectCommit.cancel => S.cancelUnconfirmedMissing,
      },
    WriteOutcome.unknown => S.commitUnconfirmedUnknown,
  };
}
