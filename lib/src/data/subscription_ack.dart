/// What the server answered when it accepted a payment request — and the one
/// number on that answer the app used to throw away.
///
/// Found 26 Sep 2026 by probing the live Worker with throwaway accounts
/// (requests 42+). `POST /api/mobile/subscription` answers
///
///     {"ok":true,"request_id":42,"status":"pending",
///      "period":"year","months":12,"amount_dzd":15000,"plan":{…},"payment":{…}}
///
/// `Repository.requestSubscription` returns that map. `_request()` on the
/// subscription screen then **ignores every field of it** and shows
/// `S.planRequestOk` — «أرسلنا طلبك، ويُفعَّل بعد تأكيد الدفع» — before reloading.
/// The response is the only place in the whole flow that states *how much money
/// to send*: the follow-up `GET /api/mobile/subscription` cannot repeat it,
/// because the pending row it answers carries `amount_paid: 0` until a human
/// confirms the transfer, and `pendingAmountLabelAr` correctly refuses to print
/// a zero.
///
/// So the number the man needs in order to actually pay — «حوّل 15000 دج» —
/// was in the app's hands for the duration of one `await` and then discarded,
/// and the screen that stands between him and support could not name the
/// figure. He taps **ادفع**, is told the request was received, and is told
/// nothing about what to send.
///
/// [SubscriptionAck] parses the answer and [subscriptionAckAr] turns it into the
/// one sentence. The amount printed is **the server's**, never the app's own
/// multiplication: the price on the payment sheet is computed from a catalogue
/// fetched earlier, and the figure that must be transferred is the one D1
/// computed at the moment of the write. When the two disagree the screen says
/// so rather than picking the flattering one.
library;

import '../core/format/money.dart';
import '../core/l10n/strings.dart';
import 'pending_request_copy.dart' show pendingPeriodLabelAr;

/// The accepted-request answer, as far as the app reads it.
///
/// Every field is optional. A server that answers `{"ok":true}` and nothing else
/// is a server this app must still survive, and the copy degrades to what it
/// shipped before rather than to a blank line.
class SubscriptionAck {
  const SubscriptionAck(
      {this.requestId, this.period, this.months, this.amountDzd});

  final int? requestId;

  /// The term the server says it filed, **verbatim**.
  ///
  /// Kept as the raw wire string for the same reason `PendingRequest.period` is:
  /// the live Worker answers an unrecognised `period` with `ok: true` and files
  /// the request as a month, so a client that names this term is naming what
  /// came back and never what it hoped for.
  final String? period;

  /// How many months the server says the term covers, when it says so.
  ///
  /// The `durations` catalogue publishes 1/3/6/12-month terms, but only `month`
  /// and `year` are buyable through the purchase sheet, so this is a receipt of
  /// the server's arithmetic rather than a term the user picked. It is not
  /// printed: [pendingPeriodLabelAr] already names the term in the two words
  /// the toggle used, and a second count beside it would be a second way to
  /// disagree about the same fact.
  final int? months;

  /// What D1 says the man has to send.
  final int? amountDzd;

  /// The decoded answer, or null when the response was not a JSON object.
  ///
  /// Takes the raw `Object?` the repository hands back rather than a typed map,
  /// because that is what the POST actually returns when it returns something
  /// unexpected — and a card that crashes on a malformed answer is worse than
  /// one that says what it knows.
  static SubscriptionAck? tryParse(Object? data) {
    if (data is! Map) return null;
    return SubscriptionAck.fromJson(Map<String, dynamic>.from(data));
  }

  factory SubscriptionAck.fromJson(Map<String, dynamic> json) =>
      SubscriptionAck(
        requestId: _intOrNull(json['request_id']),
        period:
            json['period'] is String ? (json['period'] as String).trim() : null,
        months: _intOrNull(json['months']),
        // `amount` as well as `amount_dzd`: the same alias the pending row
        // already accepts, because a Worker that renames the field on one
        // response and not the other is exactly the drift this repo refuses to
        // guess at. A missing amount is never read as zero.
        amountDzd: _intOrNull(json['amount_dzd']) ?? _intOrNull(json['amount']),
      );

  @override
  String toString() =>
      'SubscriptionAck(requestId: $requestId, period: $period, months: $months, '
      'amountDzd: $amountDzd)';
}

/// `أرسلنا طلبك — حوّل 15000 دج لتفعيل اشتراك سنوي` — or null when the server
/// named no amount.
///
/// **Null rather than a bare «تم» when the amount is missing or zero.** The
/// sentence exists to put the transfer figure in front of the man; without one
/// it is a confirmation with no content, and the caller is better off showing
/// the plain [S.planRequestOk] it always had. A zero is treated as absent for
/// the same reason [pendingAmountLabelAr] treats it as absent: `0 دج` on a
/// payment nobody has made is a statement, not a receipt.
///
/// The term is named through [pendingPeriodLabelAr] — the same mapping the
/// pending card uses, deliberately, so the sentence he reads now and the card
/// he reads after the reload cannot spell one term two ways. A term the server
/// filed as something this app cannot name drops the clause rather than
/// guessing «شهري».
String? subscriptionAckAr(SubscriptionAck? ack) {
  final amount = ack?.amountDzd;
  if (amount == null || amount <= 0) return null;
  final base = '${S.planRequestOk} — حوّل ${Money.dzd(amount)}';
  final term = pendingPeriodLabelAr(ack!.period);
  if (term == null) return base;
  return '$base لتفعيل $term';
}

/// The warning that the server's figure and the price on the sheet disagree —
/// or null when they agree, or when either is unknown.
///
/// This is the guard on the sentence above. The sheet's price is the app's own
/// arithmetic over a catalogue it fetched earlier; the amount in the answer is
/// D1's, computed at the moment of the write. Nothing today makes them differ,
/// which is exactly why the check exists: they differ the first time a price
/// changes in D1 while a contractor sits on a screen opened before the change,
/// and on a money screen the app must not quietly show either number alone.
///
/// Neither side is named the truth. The sentence reports both and tells him to
/// confirm with support, because the app cannot tell whether the catalogue is
/// stale or the request was mis-priced, and guessing wrong on this screen
/// costs a man real money.
/// The test key on the band that carries [subscriptionAmountMismatchAr].
///
/// The sentence used to be a toast, which put a price disagreement behind the
/// acknowledgement that named the transfer figure and then behind four seconds
/// of nothing. The warning is now a band, and it needs a name a test can hold
/// it by: the money text also appears inside the acknowledgement, so counting
/// occurrences of the figures cannot tell the two apart.
const String planPriceMismatchKey = 'plan-price-mismatch';

String? subscriptionAmountMismatchAr(int? quotedDzd, int? chargedDzd) {
  if (quotedDzd == null || chargedDzd == null) return null;
  if (quotedDzd <= 0 || chargedDzd <= 0) return null;
  if (quotedDzd == chargedDzd) return null;
  return 'تنبيه: المبلغ المطلوب ${Money.dzd(chargedDzd)} مختلف عن السعر '
      'المعروض ${Money.dzd(quotedDzd)} — تأكّد من المبلغ مع الدعم';
}

/// The figures of one price disagreement, held as **data** rather than as the
/// sentence.
///
/// The band above the plan card and the price printed on the card are the same
/// fact seen from two sides, and until now only one side knew it: the screen
/// kept the composed Arabic string and nothing else, so the card went on
/// drawing «3000 دج» at full weight in the same accent as a price it was
/// correct about. The two halves of one screen could contradict each other
/// with nothing marking which figure was in dispute.
///
/// Holding the figures instead of the copy is what lets the second half be
/// marked: [lineAr] is the band, [amountLineAr] is the mark on the card, and
/// both are derived from the same four numbers, so they cannot drift apart the
/// way a stored sentence and a hard-coded one would.
class PlanPriceDispute {
  const PlanPriceDispute({
    required this.planId,
    required this.periodWire,
    required this.quotedDzd,
    required this.chargedDzd,
  });

  /// Which plan card the mark belongs on, and for which term.
  ///
  /// Both, because the card list re-renders with whatever term the toggle is
  /// on: a disagreement found on the monthly term must not paint a strike
  /// through the yearly figure, which was never the number in dispute. The
  /// `period` is the **wire** string rather than the enum so this file keeps no
  /// dependency on the model layer that already owns it.
  final String planId;
  final String periodWire;

  /// The price the app quoted, off a catalogue read earlier.
  final int quotedDzd;

  /// What D1 computed at the moment of the write.
  final int chargedDzd;

  /// The dispute between the two, or null when there is none.
  ///
  /// The same four refusals as [subscriptionAmountMismatchAr] — an unknown or
  /// non-positive figure on either side, or two equal figures — because a
  /// dispute over a price nobody has heard of is not a dispute. Never built
  /// around a zero: `0 دج` on a payment nobody made is a statement, not a
  /// receipt.
  static PlanPriceDispute? between({
    required String planId,
    required String periodWire,
    required int? quotedDzd,
    required int? chargedDzd,
  }) {
    if (subscriptionAmountMismatchAr(quotedDzd, chargedDzd) == null) return null;
    return PlanPriceDispute(
      planId: planId,
      periodWire: periodWire,
      quotedDzd: quotedDzd!,
      chargedDzd: chargedDzd!,
    );
  }

  /// Whether this dispute is the one to draw on [planId] at [periodWire].
  bool appliesTo(String planId, String periodWire) =>
      this.planId == planId && this.periodWire == periodWire;

  /// Whether this dispute is about the term currently being drawn, whatever
  /// card it belongs to.
  ///
  /// The band's question, and it is deliberately not [appliesTo]: the band
  /// names no plan, so it must survive looking at another tier, and it must
  /// still go away when the term changes — its sentence quotes "the price
  /// displayed", and on the other term a different price is the one displayed.
  /// One dispute, two questions, one answer each, both derived here so a
  /// screen cannot come along and pick the looser one.
  bool appliesToTerm(String periodWire) => this.periodWire == periodWire;

  /// The band's sentence. Delegated, never re-written, so the two copies of
  /// this fact cannot be reworded apart by a later tick.
  String get lineAr => subscriptionAmountMismatchAr(quotedDzd, chargedDzd)!;

  /// The one line the card prints under its own price.
  ///
  /// It names the amount and stops. It does not say «not this one» in words,
  /// because the strike through the figure above it already says that and
  /// saying it twice is how a screen ends up explaining itself; and it does
  /// not repeat the band, because the band is still on screen, four lines
  /// above, naming both figures and telling him to confirm with support.
  String get amountLineAr => 'المبلغ المعتمد ${Money.dzd(chargedDzd)}';

  @override
  String toString() => 'PlanPriceDispute(plan: $planId/$periodWire, '
      'quoted: $quotedDzd, charged: $chargedDzd)';
}

/// The test key on the line a card prints under a price its own band disputes.
String planDisputedAmountKey(String planId, String periodWire) =>
    'plan-disputed-amount-$planId-$periodWire';

/// The test key on the same line inside the payment sheet, which is a separate
/// route and a separate instance of the same fact.
///
/// Distinct from [planDisputedAmountKey] on purpose: a modal sheet does not
/// remove the screen behind it, so both instances are in the tree at once and
/// one shared key would make `findsOneWidget` fail for the right reason and
/// `findsNWidgets` impossible to write.
const String planDisputedSheetAmountKey = 'plan-disputed-sheet-amount';

/// An int that stays null when the field is absent, unreadable or not a number.
///
/// Never `?? 0`: on this screen a zero would be printed as a price.
int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
