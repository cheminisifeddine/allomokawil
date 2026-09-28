// Answering «did my activation code work» when the app cannot ask the server.
//
// Found 28 Sep 2026 by auditing the write-outcome contract for a write the
// previous audit's grep never saw. `subscription_screen.dart`'s `_request` was
// fixed on 26 Sep and reported the sixth write. `_redeem` sat **forty lines
// below it, in the same file**, and had neither half of the contract.
//
// It has the worse half: `_redeem` printed `S.planCodeOk` — «تم تفعيل
// اشتراكك», *your subscription has been activated* — whenever
// `redeemActivationCode` returned null, which the repository does whenever the
// response carries no `plan` object. A null is not a success. It is the
// absence of evidence, and the app spent it on the strongest sentence the
// money screen owns: a claim a contractor with a 30000 دج plan reads as "I am
// paid".
//
// So this file answers the same question `pendingRequestIsMine` answers for the
// payment path, and it lands on the same rule: **identity here is a change,
// never an equality.** Two snapshots of the live plan, before and after the
// tap, and the redemption landed only if the plan row actually moved.
//
// Exactly two things on that row can move, and both are read here:
//
// * the **plan id** — an upgrade. `free_trial` → `pro` is the commonest
//   redemption of all, which is why this file has no "a free trial is never a
//   redemption" rule: that rule reads as correct, passes its own test, and
//   rejects every first purchase on the app.
// * the **expiry** — a renewal. A code for the plan he is already on is a
//   renewal, and a renewal that worked extends the end date while the id stays
//   put. This is the half an id-only rule gets wrong in the direction that
//   burns real money: a contractor renewing `pro` to `pro` would be told his
//   code did not work, every time, and codes are single-use — so he buys a
//   second one and the first was never actually redeemed.
//
// [codePlan] is the plan the redemption's **answer** named, and it is null on
// the unconfirmed path because no answer arrived. It is used to *narrow* the
// proof, never to require it: when it is known, the movement also has to have
// landed on the plan the code named, so an upgrade that landed on a
// *different* plan than the code claims is not reported as this code's work.
// When it is null the movement alone is the proof, which is sound because the
// redemption is the only write this screen makes at that moment.
//
// A failing re-read is [WriteOutcome.unknown] and never `missing`: the phone
// is still offline, and «the code did not work» is how a man buys a second code
// for a plan he already paid for.
library;

import '../core/l10n/write_outcome.dart';
import '../models/plan.dart';

/// What a re-read of the live plan proves about a redemption.
///
/// [before] is the plan the screen held when he tapped «تفعيل», [fresh] is what
/// the server holds now, and [codePlan] is the plan the redemption's answer
/// named — null when the answer never arrived.
///
/// The answer is a **change in the server's copy of the row**, never a claim
/// about the request. Status alone is never evidence: a `pro` row that was
/// already there says `pro` whether or not the code was ever read, and a
/// manually-upgraded contractor produces the identical payload to a renewal
/// that worked. Only the movement separates them.
///
/// Conservative in the direction that costs the user nothing — a payload
/// missing the fact that would prove the write (no snapshots, no expiry on a
/// same-plan renewal) answers `false`, which the caller renders as a retryable
/// miss. Reporting `landed` for a row the app cannot identify is the one
/// mistake this file exists to prevent.
bool redeemLanded({
  String? codePlan,
  required SubscriptionStatus? before,
  required SubscriptionStatus? fresh,
}) {
  if (fresh == null || before == null) return false;

  // A free plan has no expiry, so it can only ever prove an upgrade by id.
  final beforePlan = before.plan.trim();
  final freshPlan = fresh.plan.trim();
  final wanted = codePlan?.trim();

  // (1) The plan id moved. Only a real change counts: a row that already said
  // `pro` proves nothing about a `pro` code.
  if (freshPlan != beforePlan) {
    // When the answer named the plan, the movement has to be onto *that* plan.
    // A code for `pro` that moved him to `basic` is not this code working.
    if (wanted != null && wanted.isNotEmpty && freshPlan != wanted) return false;
    return true;
  }

  // (2) Same plan on both sides: this is a renewal, and a renewal that worked
  // extends the end date. Compared on the instant, not the printed day — a
  // day-granularity expiry means a renewal inside the same day lands on an
  // equal string, and calling that a failure would burn the code. A free plan
  // has no end date at all, so this is false for it, correctly: a trial cannot
  // be renewed by a code.
  final beforeEnd = before.expiresAtLocal;
  final freshEnd = fresh.expiresAtLocal;
  if (beforeEnd == null || freshEnd == null) return false;
  return freshEnd.isAfter(beforeEnd);
}

/// Runs the honest re-read for a code redemption and classifies it.
///
/// Same contract as every other write on this screen: a re-read that cannot be
/// completed is [WriteOutcome.unknown], never a `missing` the user is told to
/// act on by buying a second code.
Future<WriteOutcome> resolveRedeemWriteOutcome({
  String? codePlan,
  required SubscriptionStatus? before,
  required Future<SubscriptionStatus> Function() fetch,
}) async {
  final SubscriptionStatus fresh;
  try {
    fresh = await fetch();
  } catch (_) {
    return WriteOutcome.unknown;
  }
  return redeemLanded(codePlan: codePlan, before: before, fresh: fresh)
      ? WriteOutcome.landed
      : WriteOutcome.missing;
}
