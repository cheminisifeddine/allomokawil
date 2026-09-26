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
String? subscriptionAmountMismatchAr(int? quotedDzd, int? chargedDzd) {
  if (quotedDzd == null || chargedDzd == null) return null;
  if (quotedDzd <= 0 || chargedDzd <= 0) return null;
  if (quotedDzd == chargedDzd) return null;
  return 'تنبيه: المبلغ المطلوب ${Money.dzd(chargedDzd)} مختلف عن السعر '
      'المعروض ${Money.dzd(quotedDzd)} — تأكّد من المبلغ مع الدعم';
}

/// An int that stays null when the field is absent, unreadable or not a number.
///
/// Never `?? 0`: on this screen a zero would be printed as a price.
int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
