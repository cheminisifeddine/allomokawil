// The pending card showed a man his plan, his amount, his method and the day —
// and not the number of the request he is waiting on.
//
// `PendingRequest.fromJson` has parsed `id` since the card was built, and it
// reached no screen: `grep -rn "request.id" lib/` returned nothing, so the field
// landed in a model and stopped there. Every other clause in the same card is
// server-owned and printed; the one value a human at the other end can look up
// is the one this repo dropped.
//
// It matters more than a missing badge because the card is a **receipt**. The
// body promises «سيصلك إشعار عند التفعيل», and the contractor's next move when
// the notification does not arrive is the support chat. What he says there is
// «حولت المبلغ، ما وضع طلبي؟» — and the only handle support can use to find
// the row is the request id. Without it, identification falls back to a phone
// number and a remembered date, which is exactly how a real payment waits a
// day and the man concludes the platform took his money.
//
// The live Worker was probed on 27 Sep 2026 while writing this, and the stored
// row does carry it: `POST /api/mobile/subscription` with `plan=pro&period=year`
// filed request **49**, and `GET /api/mobile/subscription` answered
// `pending_request = {"id": 49, "plan": "pro", "period": "year", ...}`.
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact `pending_request` object the live Worker filed, captured 27 Sep
/// 2026 from https://finili.medsaidkichene.workers.dev. `amount_paid` is 0
/// because no human has confirmed the transfer yet — which is why the amount
/// clause is absent below and why the number is the only handle on this row.
const Map<String, dynamic> _liveRow = {
  'id': 49,
  'plan': 'pro',
  'period': 'year',
  'amount_paid': 0,
  'payment_method': 'baridimob',
  'payment_reference': null,
  'created_at': '2026-09-27 02:17:47',
};

void main() {
  group('the live pending row carries a quotable number', () {
    test('the id the server filed reaches the model and the card', () {
      final r = PendingRequest.fromJson(_liveRow);
      expect(r.id, 49);
      expect(pendingRequestNumberAr(r.id), 'رقم الطلب 49');
    });

    test('it leads the receipt, so it is the clause a man reads out', () {
      final r = PendingRequest.fromJson(_liveRow);
      final facts = pendingFactsAr(
        numberLabel: pendingRequestNumberAr(r.id),
        planLabel: pendingPlanLabelAr(r.plan, 'محترف'),
        periodLabel: pendingPeriodLabelAr(r.period),
        amountLabel: pendingAmountLabelAr(r.amountDzd),
        methodLabel: pendingMethodLabelAr(r.method, (id) => 'بريدي موب (تحويل)'),
        dayLabel: formatPendingDay(r.createdAt),
      );
      expect(facts, startsWith('رقم الطلب 49'));
      // The amount is absent on this row (funds unconfirmed), so the number is
      // what is left to identify it by.
      expect(facts, isNot(contains('دج')));
    });
  });

  group('pendingRequestNumberAr', () {
    test('an absent id prints no clause at all', () {
      expect(pendingRequestNumberAr(null), isNull);
    });

    test('id 0 is absent, never «رقم الطلب 0»', () {
      // D1's autoincrement starts at 1, so 0 can only mean the field was not
      // sent. A man quoting request 0 at support gets somebody else's row.
      expect(pendingRequestNumberAr(0), isNull);
      expect(pendingRequestNumberAr(-7), isNull);
    });

    test('a row with no id still renders everything else it has', () {
      final r = PendingRequest.fromJson({
        'id': 0,
        'plan': 'basic',
        'payment_method': 'cash',
      });
      expect(pendingRequestNumberAr(r.id), isNull);
      final facts = pendingFactsAr(
        numberLabel: pendingRequestNumberAr(r.id),
        planLabel: pendingPlanLabelAr(r.plan, null),
        methodLabel: pendingMethodLabelAr(r.method, (id) => id),
      );
      expect(facts, 'basic · cash');
    });

    test('the number keeps western digits, because it is a database key', () {
      // Not routed through `arabicCounted`: an identifier read as ٤٣ cannot be
      // matched against the row D1 filed as 43.
      expect(pendingRequestNumberAr(43), contains('43'));
      expect(pendingRequestNumberAr(43), isNot(contains('٤٣')));
    });
  });
}
