// What a contractor is owed an answer about: the payment he is waiting on.
//
// Found 26 Sep 2026 by auditing the models for fields the app parses and then
// never reads — the seventh field in a row where D1 sends it, the parser keeps
// it, and the screen drops it. This one is a **money** path, not a badge.
//
// `GET /api/mobile/subscription` answers a `pending_request` object, and
// `PendingRequest.fromJson` parses six facts off it: the request id, the plan
// id, the amount he paid (`amount_paid`/`amount_dzd`), the method he used, the
// moment he sent it and the term he filed. The subscription screen then rendered a fixed card:
//
//     const _PendingCard();
//
// A constructor call with no arguments, feeding a widget that prints two
// hard-coded sentences and never touches the object. So a man who paid 15000 دج
// by BaridiMob on the 12th read «استلمنا طلبك» — and could not tell which plan
// he bought, how much he sent, or how long it has been sitting there. If the
// amount on the card does not match what he transferred, **the app is the only
// place that could have told him**, and it was saying nothing.
//
// The card is not deleted. «طلبك قيد المراجعة» is the right thing to tell a
// contractor whose money has not cleared; the defect is that the one screen
// standing between him and support had no way to answer «how much did I send?».
//
// Everything here is pure: the screen passes the model in and prints what comes
// out, so the wording is testable without pumping a widget — the same split
// `quote_count_copy.dart` and `plan_renewal_copy.dart` use.
library;

import '../core/format/money.dart';
import '../models/plan.dart' show BillingPeriod, PendingRequest;

/// The plan a pending payment names, in the words the user sees.
///
/// Falls back to the raw id when the server sends one the catalogue does not
/// know: a plan renamed or withdrawn server-side must still be *identifiable*,
/// because that id is what support asks the man to quote. Printing an empty
/// line is the one outcome that makes the card useless.
String pendingPlanLabelAr(String planId, String? planNameAr) {
  final name = planNameAr?.trim();
  if (name != null && name.isNotEmpty) return name;
  final id = planId.trim();
  return id.isEmpty ? '—' : id;
}

/// `15000 دج` — the amount transferred, or null when the server sent none.
///
/// Null rather than `0 دج`: a missing amount is an unknown amount, and
/// «0 دج» on a payment the man already made is a statement, not an absence.
String? pendingAmountLabelAr(int? amountDzd) {
  if (amountDzd == null || amountDzd <= 0) return null;
  return Money.dzd(amountDzd);
}

/// `12-09-2026` — the day the request was filed, in the phone's timezone.
///
/// The same conversion `subscriptionEndDateLabel` performs, and for the same
/// reason: D1 writes UTC, Algiers is UTC+1, and a request filed at
/// `2026-09-12 23:30:00` belongs to the 12th here. Read as bare wall-clock the
/// card would show the wrong day for every request sent late in the evening.
///
/// Null in, null out, so an unreadable timestamp drops its clause rather than
/// printing the raw string at the user.
String? formatPendingDay(DateTime? local) {
  if (local == null) return null;
  final d = local.toLocal();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$day-$m-${d.year}';
}

/// «بريدي موب (تحويل)» — the Arabic name of the method he actually used.
///
/// [methodId] is the same `PaymentMethod.id` the payment sheet hands to
/// `POST /mobile/subscription`, and [labelFor] is the catalogue's own resolver,
/// so the label is the operator's wording and never a hand-written guess. A
/// method the catalogue does not know (server added one the app has not been
/// rebuilt for) falls back to the raw id, because «baridimob» is still
/// something support can act on where a blank line is not.
/// «اشتراك 6 أشهر» — the term the server says it filed, or null when it sent
/// none.
///
/// The pending card is the last thing a contractor sees before handing money to
/// support, and until now it named the **plan** and the **amount** but never
/// the **term** — the one fact that decides how much cover he just bought.
/// A man who transferred 8000 دج for six months was told «أساسي · بريدي موب ·
/// 12-09-2026» and nothing about the six.
///
/// The mapping is deliberately closed and the input is the raw wire string the
/// server sent, because that string is the whole problem. `GET
/// /api/mobile/plans` publishes four prepaid `durations` per plan (1/3/6/12
/// months, each cheaper than the last), but `BillingPeriod` — the enum the
/// purchase sheet sends — has two arms, so the app can only ever *ask* for a
/// month or a year. Probing the live Worker on 26 Sep showed the other side of
/// that: it accepts any unrecognised `period` with `ok: true` and files the
/// request as `month`. The card therefore reports **the stored period, not the
/// requested one**, which is the only figure that survives the round trip.
///
/// An id this app does not know returns null rather than a guess: the card then
/// prints what it knows and drops the clause, which is the correct rendering of
/// "the server filed something we cannot name" — and it is not a silent
/// downgrade to «شهري», which would be a claim the payload does not support.
String? pendingPeriodLabelAr(String? periodWire) {
  final wire = periodWire?.trim();
  if (wire == null || wire.isEmpty) return null;
  // The toggle's own words, not a fresh phrasing: the contractor picked «شهري»
  // or «سنوي» on the purchase sheet, so the card that reports the filed
  // request names the term in the same two words he tapped. `labelAr` is the
  // enum's existing copy — no second spelling of a term is introduced here.
  return switch (wire) {
    'month' => 'اشتراك ${BillingPeriod.month.labelAr}',
    'year' => 'اشتراك ${BillingPeriod.year.labelAr}',
    _ => null,
  };
}

/// The clause that tells a contractor his term was filed as something else.
///
/// Only fires on a payload whose `period` is non-empty and is not one of the
/// two arms the app understands. That is not a shape the test suite can invent:
/// it is what the **live** Worker returns for every spelling outside
/// `month`/`year` — `6month`, `quarter`, `3m`, `durations` and ten others all
/// answered `ok: true` and stored `period: "month"`, so a 6-month purchase
/// arrives here looking exactly like a monthly one.
///
/// The sentence is the honest one: this row is **one month**, whatever was
/// asked for. It does not name the six, because the payload does not say which
/// term was attempted, and guessing would put a number on a money screen that
/// no one here can evidence. The contractor's next move is the same either way
/// — quote the row to support — and now the card states the term in words
/// instead of leaving it to be inferred from an amount.
String? pendingPeriodMismatchNoteAr(String? periodWire) {
  final wire = periodWire?.trim();
  if (wire == null || wire.isEmpty) return null;
  if (wire == 'month' || wire == 'year') return null;
  return 'سُجِّل هذا الطلب لمدة شهر واحد — تأكّد من المدة مع الدعم';
}

/// The name of the method, resolved against the catalogue.
String? pendingMethodLabelAr(String? methodId, String? Function(String) labelFor) {
  if (methodId == null) return null;
  final id = methodId.trim();
  if (id.isEmpty) return null;
  return labelFor(id);
}

/// «رقم الطلب 43» — the one number support asks a man to quote, or null.
///
/// **Why this is on the card at all.** `PendingRequest.fromJson` has parsed
/// `id` since the pending card was first built, and it has never reached a
/// screen: grepping `request.id` across `lib/` returns nothing, so the field is
/// read into a model and printed nowhere. That is the same shape as the
/// `quote_limit` and `wilaya_span` defects, but this one lands on a **receipt**.
/// The card's body promises a notification when the plan is activated, and the
/// contractor's next move when it does not arrive is to open the chat and say
/// «my payment went, what now?» — and the only handle he has to give support is
/// the request id, which the app parsed and then dropped on the floor. Without
/// it support has to identify the row by phone number and a date the man
/// cannot remember, which is how a legitimate request sits unconfirmed for a
/// day and the man concludes the platform took his money.
///
/// The number is the server's own, verbatim, for the same reason every other
/// clause here is: it is the key D1 files the row under, so it is the one value
/// a human at the other end can look up.
///
/// **Null for a non-positive id, and the id is never invented.** A payload with
/// no id, an id of `0`, or an id that did not parse produces no clause rather
/// than «رقم الطلب 0» — printing a placeholder a man could quote to support is
/// worse than leaving the number off, because support would look it up and find
/// someone else's row. Ids are D1's autoincrement and start at 1, so zero and
/// negatives can only mean "absent", never "request zero".
///
/// The clause is built from the raw int rather than through [arabicCounted]:
/// this is an identifier, not a counted quantity, so «3 طلبات» would be a
/// different sentence about a different thing and the digits must stand alone
/// with no Arabic-Indic substitution that would stop matching the database.
String? pendingRequestNumberAr(int? id) {
  if (id == null || id <= 0) return null;
  return 'رقم الطلب $id';
}

/// The receipt under the pending title, joined from the facts that arrived.
///
/// **Every clause is dropped when its own field is missing**, which is the
/// whole point: this payload is server-controlled, and a line built from absent
/// fields would print «—» three times in a row to a man waiting to hear whether
/// his bank transfer landed. The server sends six facts and may send none, so
/// this returns null and the card falls back to its two fixed sentences — the
/// behaviour that shipped before, which is the correct rendering of "we do not
/// know yet".
String? pendingFactsAr({
  String? planLabel,
  String? amountLabel,
  String? methodLabel,
  String? dayLabel,
  String? periodLabel,
  String? numberLabel,
}) {
  final parts = [
    if (numberLabel != null) numberLabel,
    if (planLabel != null) planLabel,
    if (periodLabel != null) periodLabel,
    if (amountLabel != null) amountLabel,
    if (methodLabel != null) methodLabel,
    if (dayLabel != null) dayLabel,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The plan and term a **pending request** has already claimed, or null when
/// nothing is pending.
///
/// The one question the subscription screen never asked, and the answer is a
/// double payment. A contractor who taps «ترقية» on «محترف» files request 49
/// and the reload draws the receipt for it at the top of the page — and four
/// lines lower the very same card still offers a live «ترقية — محترف»
/// button, because the plan list is drawn from `catalogue.purchasable` and
/// nothing on it had ever looked at the pending row. Tapping that button
/// files a **second** request for the same plan and the same term, and D1 has
/// no reason to refuse it.
///
/// The card he is looking at is not a receipt any more. It is a receipt *and*
/// a button that asks for the same money twice, on one screen, with the
/// receipt drawn close enough to the button to be read as confirmation that
/// the first one worked.
///
/// **The rule is scoped to plan AND term, and both are the server's.** A
/// monthly request does not block the yearly price of the same plan: those are
/// two different products, and the man who filed the month may well be
/// deciding on the year. The scope is the same pair `_disputeFor` already
/// scopes a price to, which is not a coincidence — it is the pair that makes a
/// purchase the *same purchase*.
///
/// A term the server filed as something this app cannot name blocks
/// **nothing**: guessing which term «quarter» meant and locking the man out of
/// the one product he came for is a worse outcome than a rare double request,
/// and an unknown term is already reported to him as a mismatch
/// ([pendingPeriodMismatchNoteAr]).
///
/// The plan id is compared trimmed, because a payload that pads `plan` with a
/// space is the same plan, and a false mismatch would leave him free to file
/// the duplicate this function exists to prevent.
PendingClaim? pendingClaimFor(PendingRequest? request) {
  if (request == null) return null;
  final plan = request.plan.trim();
  if (plan.isEmpty) return null;
  return PendingClaim(plan: plan, periodWire: request.period?.trim());
}

/// One plan at one term, already claimed by a request awaiting payment.
///
/// Immutable and comparable so the screen can ask [covers] the same question
/// the band asks of a price, rather than re-deriving it inline a second time.
class PendingClaim {
  const PendingClaim({required this.plan, required this.periodWire});

  /// The plan id exactly as the server filed it, trimmed. Never normalised
  /// past that: the catalogue's own ids are the matching vocabulary.
  final String plan;

  /// The raw wire term, or null when the row carries none.
  ///
  /// Null is **not** month. A row with no `period` has an unknown term, and a
  /// [PendingClaim] with a null term blocks no card — see [covers].
  final String? periodWire;

  /// True when this claim is the purchase this card is offering.
  ///
  /// Both halves must match, and the null check is on **this** field, not on
  /// the argument. Written as `periodWire != null` the parameter shadows the
  /// field, the condition is always true, and the analyzer is right to call it
  /// dead: the intent — a claim with no term blocks nothing — then rests
  /// entirely on the string comparison happening to fail. The test passed
  /// anyway (`null == 'month'` is false), which is exactly why this is worth
  /// fixing rather than silencing: the behaviour was correct by accident, and
  /// an accidental correctness is one edit away from a wrong one.
  ///
  /// A null term answers false for every card rather than falling back to
  /// `month`: the app cannot tell whether the server stored a month or lost
  /// the field, and locking the man out of both terms on a guess is the worse
  /// of the two errors.
  bool covers(String planId, String term) {
    final claim = periodWire;
    if (claim == null) return false;
    return plan == planId.trim() && claim == term;
  }

  @override
  String toString() => 'PendingClaim(plan: $plan, period: $periodWire)';
}

/// The sentence under a plan card whose purchase is already pending — or null
/// when there is no quotable number to name.
///
/// It exists because a disabled button with no explanation is a bad app, and
/// «ترقية» on a card a man has already paid for is a worse one. The receipt at
/// the top of the screen says the request is under review; this repeats the
/// fact on the card itself, in the number support will ask him for, so the
/// reason the button is dead is on the same card as the button.
///
/// Null when the id is absent or non-positive, for the same reason
/// [pendingRequestNumberAr] refuses to invent one: a placeholder number a man
/// reads out loud to support sends them to somebody else's row. The button
/// stays dead either way — this is a sentence, not the guard.
String? planAlreadyRequestedAr(int? requestId) {
  final n = pendingRequestNumberAr(requestId);
  if (n == null) return null;
  return 'طلبتَ هذا الاشتراك بالفعل — $n قيد المراجعة';
}
