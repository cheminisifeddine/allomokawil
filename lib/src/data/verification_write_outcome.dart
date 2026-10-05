// Answering «did my documents arrive» when the server never said.
//
// Found 28 Sep 2026 by auditing the write-outcome contract for the writes it
// still could not vouch for. The verification screen *has* the contract — it
// catches `errWriteUnconfirmed`, re-reads the profile and prints a verdict —
// and that is exactly why the broken half survived: the path looks complete, so
// every read of the file stops at "it re-reads the server" and never asks
// **what it compared**.
//
// It compared this:
//
//     return p.verificationStatus == VerificationStatus.pending ||
//         p.verificationStatus == VerificationStatus.verified;
//
// A brand-new contractor is stored as `verification_status = 'pending'`.
// **Every one of them.** The model says so in so many words —
// [WorkerProfile.verificationPendingDocs]: "a brand-new profile is stored as
// 'pending', exactly like a submitted dossier. Without this count the UI has to
// guess, and it guesses wrong in both directions" — and the *same screen*, 40
// lines below, correctly renders the other half off
// [WorkerProfile.dossierUnderReview], which is `pending && pendingDocs > 0` for
// precisely that reason.
//
// So the re-read answered **true for a contractor who has sent nothing at
// all**, and the app then printed [S.writeUnconfirmedLanded] —
// «وجدناه في القائمة — الطلب وصل بنجاح» — to a man whose ID card never left
// his gallery. The write it is answering is the trust gate of the whole
// marketplace: he is told his papers are with the reviewer, waits 48 hours,
// and nobody ever looks at them. A second submission is worse, because the
// second attempt hits the same predicate and is also called a landing, so the
// app can say "arrived" as many times as he retries and be wrong every time.
//
// This file is the same rule the display half already uses, made explicit,
// and then made *stricter than the display* where the two could disagree.
//
// **The rule is a change in the server's copy of the row, never an
// equality** — the rule `redeem_outcome.dart` and `subscription_write_outcome
// .dart` landed on, and for the same reason: a `pending` profile is the
// untouched state of every contractor in the product, so asking "is it
// pending?" asks a question whose answer is yes before anyone taps anything.
// The proof is a difference between the profile the screen was showing when he
// tapped — [before] — and the one the re-read returned — [after].
//
// Four things on that row can move, and all four are read here:
//
//   1. the **queue grew** — more document rows are waiting for a reviewer;
//   2. the **status moved** — a reviewer reached a verdict, so the dossier is
//      `verified` or `rejected` instead of the `pending` everybody starts at;
//   3. the **identity half** was accepted;
//   4. the **documents half** was accepted.
//
// Parts 2-4 are reviewer decisions, and a reviewer can only decide on a
// dossier that exists — which is why they are evidence at all, given that
// [before] is never `dossierUnderReview` (the form is not on screen while it
// is). One of them is soft and is named here rather than hidden: when the
// contractor was on this screen *after a refusal*, a flag flipping could in
// principle be a reviewer finishing an older filing rather than this one. The
// app cannot tell those apart from the phone, so it takes the answer that
// costs the user nothing — see below.
//
// **A missing write is safe to report; a false landing is not.** Every other
// file in this family lands the ambiguity in the user's favour, and this one
// does too: reporting a landing that did not happen costs a man his
// verification, while reporting a write as missing when it landed costs him
// one re-send of three documents into a queue a reviewer has not opened yet.
// So the only sentence he is ever shown as certain is one backed by a moved
// field. A row that came back **identical** is the one thing that proves
// nothing arrived — the server did not change — and that is
// [WriteOutcome.missing], the retryable answer.
//
// A re-read that fails is [WriteOutcome.unknown] and never `missing`: the
// phone is still offline, and «did not arrive» is how a man deletes the only
// copy of his ID card and starts again from a photocopy.
library;

import '../core/l10n/strings.dart';
import '../core/l10n/write_outcome.dart';
import '../models/worker.dart';

/// Did the document queue grow between two reads?
///
/// Both counts must be **real**. `verificationPendingDocs` is nullable (a
/// route that does not send it has not measured it), and comparing two nulls
/// with `>` answers "no" while comparing null to a number throws in Dart, so
/// the honest question is asked explicitly rather than by operator luck: an
/// unknown count can never be evidence that a filing landed.
bool _queueGrew(int? after, int? before) =>
    after != null && before != null && after > before;

/// True when [after] proves the documents this screen just sent arrived.
///
/// [before] is the profile the screen was drawing when the contractor tapped
/// «إرسال المستندات», [after] is what the re-read returned. Both halves are
/// required: a predicate that took only [after] would be the one this file
/// replaces, and a predicate that took only [before] would be asserting the
/// write in advance.
///
/// Every field that can move is asked, and nothing else: `bio`, `experience
/// years` and the rest do not change because a dossier was filed, and a field
/// that reads the same in both outcomes is evidence of nothing either way.
bool verificationLanded({
  required WorkerProfile before,
  required WorkerProfile after,
}) =>
    // (1) The queue grew. The strongest of the four, and the one that fires on
    // the ordinary path: a filing that reached the server put more document
    // rows in front of the reviewer than there were before.
    _queueGrew(after.verificationPendingDocs, before.verificationPendingDocs) ||
        // (2) A reviewer reached a verdict. The dossier left the `pending`
        // every profile in the product starts at, so this is a real movement
        // even though `pending` on its own never was.
        after.verificationStatus != before.verificationStatus ||
        // (3, 4) One of the two halves was accepted. The API splits the
        // dossier per document, so this is how a partial approval looks.
        after.identityVerified != before.identityVerified ||
        after.certificateVerified != before.certificateVerified;

/// Runs the honest re-read for a dossier and classifies what it proved.
///
/// Same contract as every other write in the app: it must not throw, and a
/// second network failure while we are already reporting one is
/// [WriteOutcome.unknown] — never `missing`.
Future<WriteOutcome> resolveVerificationWriteOutcome({
  required WorkerProfile before,
  required Future<WorkerProfile> Function() fetch,
}) async {
  final WorkerProfile after;
  try {
    after = await fetch();
  } catch (_) {
    return WriteOutcome.unknown;
  }
  return verificationLanded(before: before, after: after)
      ? WriteOutcome.landed
      : WriteOutcome.missing;
}

/// The sentence for a dossier the app re-read to find out about.
///
/// One function, and not [writeOutcomeCopy], because the shared line is a
/// claim about *finding a row* — «وجدناه في القائمة» — and the profile was
/// on screen for the entire send. What changed is the document queue, and the
/// contractor needs to know which button worked: the screen swaps the form for
/// a receipt, and only one of these two sentences is true.
///
/// [WriteOutcome.unknown] keeps the shared sentence on purpose, and for the
/// reason it is shared: a re-read that could not run is a dead connection, and
/// «تحقّق من القائمة» names the one action that is still true — the list this
/// screen re-reads the moment it reopens.
String dossierOutcomeCopy(WriteOutcome outcome) => switch (outcome) {
      WriteOutcome.landed => S.dossierUnconfirmedLanded,
      WriteOutcome.missing => S.dossierUnconfirmedMissing,
      WriteOutcome.unknown => writeOutcomeCopy(WriteOutcome.unknown),
    };
