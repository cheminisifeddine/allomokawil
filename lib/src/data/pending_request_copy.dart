// What a contractor is owed an answer about: the payment he is waiting on.
//
// Found 26 Sep 2026 by auditing the models for fields the app parses and then
// never reads — the seventh field in a row where D1 sends it, the parser keeps
// it, and the screen drops it. This one is a **money** path, not a badge.
//
// `GET /api/mobile/subscription` answers a `pending_request` object, and
// `PendingRequest.fromJson` parses five facts off it: the request id, the plan
// id, the amount he paid (`amount_paid`/`amount_dzd`), the method he used and
// the moment he sent it. The subscription screen then rendered a fixed card:
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
String? pendingMethodLabelAr(String? methodId, String? Function(String) labelFor) {
  if (methodId == null) return null;
  final id = methodId.trim();
  if (id.isEmpty) return null;
  return labelFor(id);
}

/// The receipt under the pending title, joined from the facts that arrived.
///
/// **Every clause is dropped when its own field is missing**, which is the
/// whole point: this payload is server-controlled, and a line built from absent
/// fields would print «—» three times in a row to a man waiting to hear whether
/// his bank transfer landed. The server sends five facts and may send none, so
/// this returns null and the card falls back to its two fixed sentences — the
/// behaviour that shipped before, which is the correct rendering of "we do not
/// know yet".
String? pendingFactsAr({
  String? planLabel,
  String? amountLabel,
  String? methodLabel,
  String? dayLabel,
}) {
  final parts = [
    if (planLabel != null) planLabel,
    if (amountLabel != null) amountLabel,
    if (methodLabel != null) methodLabel,
    if (dayLabel != null) dayLabel,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
