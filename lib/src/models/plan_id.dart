// The identity of a subscription plan, in one place.
//
// Found on 2 Oct 2026 by grepping for the plan id. `enums.dart` has carried
// `enum SubscriptionPlan { freeTrial, basic, pro, gold, perLead, commission }`
// since before this file's siblings existed, and it has **exactly one
// reference in the repository: its own declaration**. Nothing imports it, no
// test names it, no screen can reach it. Dead.
//
// **Why dead code like this is not harmless.** Its two camelCase values spell
// the wire id wrong. `GET /api/mobile/plans` answers `free_trial` (observed
// live, 2 Oct, alongside `basic`, `pro`, `gold`), so `SubscriptionPlan
// .freeTrial.name` is `'freeTrial'` — a value the server has never sent and
// never will. An enum whose `.name` can never match its own column is the same
// shape as the dead `case 'inprogress'` arm in `StatusPill.project` that this
// loop found and fixed last tick, one file over: a second spelling of a value,
// sitting next to the code that reads it, and nothing to make them agree.
//
// So it is replaced rather than deleted. An enum in, one wire value out, is the
// contract `ProjectStatus` and `UrgencyLevel` already keep (`wire` +
// `fromWire`), and having it here means the id is *named* once — the failure
// mode is not "someone compares a String to the wrong spelling", it is "the
// spelling lives in two places and no type stops them drifting".
//
// The alternative was to leave the id as a bare `String` and simply delete the
// dead enum. That was rejected: the app already holds a parser for every other
// enumerated column it reads, and the one bare compare it was replacing is
// exactly why the money screen needed looking at. See [SubscriptionStatus
// .isFree], which this is the reason for.
library;

import 'dart:core';

/// A plan id as `GET /api/mobile/plans` publishes it, and as
/// `GET /api/mobile/subscription` echoes it back in `current.plan`.
enum PlanId {
  freeTrial('free_trial'),
  basic('basic'),
  pro('pro'),
  gold('gold'),
  perLead('per_lead'),
  commission('commission');

  const PlanId(this.wire);

  /// The only string this plan may be sent as, and the only string the app
  /// answers it with.
  ///
  /// Snake case, because that is what the Worker sends. `freeTrial` and
  /// `perLead` are the two values that make this a getter rather than `=> name`.
  final String wire;

  /// Reads a plan id, or null when the server named something this app does not
  /// know.
  ///
  /// **Trimmed, because every other reader of this column in the app trims
  /// and this one did not.** `redeem_outcome.dart` and
  /// `pending_request_copy.dart` both `.trim()` the plan string before
  /// comparing, and `quote_worker_trust.dart` does the same for the
  /// verification column — the app's own law, established three times, which
  /// `isFree` was quietly the exception to.
  ///
  /// **Null rather than a guess, for the reason `expiresAtLocal` already
  /// documents.** A plan the app cannot name is not free: reporting an
  /// unreadable id as `free_trial` would tell a contractor who is paying
  /// 6000 دج a month that he is on the trial, and would suppress his expiry
  /// date — the one number the card exists to give. Unknown stays unknown and
  /// the caller decides what to claim, which is the opposite of a silent
  /// downgrade.
  static PlanId? fromWire(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    for (final id in PlanId.values) {
      if (id.wire == v) return id;
    }
    return null;
  }

  /// Whether this plan is the one nobody pays for.
  ///
  /// One arm, because it is a question with one answer. The paid plans are not
  /// enumerated here on purpose — a paid plan is "not the trial", and the
  /// moment the founder sells a fifth paid tier nothing in this file should
  /// need to know its name.
  bool get isFree => this == PlanId.freeTrial;
}
