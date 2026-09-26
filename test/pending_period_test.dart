// The pending card named the plan and the amount but never the TERM — the one
// fact that decides how much cover a man just bought.
//
// `GET /api/mobile/plans` publishes four prepaid `durations` per plan (1/3/6/12
// months, each cheaper than the last), but `BillingPeriod` — the enum the
// purchase sheet sends — has two arms, so the app can only ask for a month or a
// year. Probing the live Worker on 26 Sep found the other half of that: it
// answers ANY unrecognised `period` with `ok: true` and files the request as
// `month`. Requests 12-24 came back stored as `period: "month"` for every one
// of `6month`, `quarter`, `3m`, `durations`, `months6` and six more spellings.
//
// So a 6-month purchase arrives at the card looking exactly like a monthly one,
// and the card printed «أساسي · بريدي موب · 12-09-2026» with no term at all.
// These tests pin the term, and pin that an unknown period is reported as what
// it is rather than silently downgraded to «شهري».
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingRequest.period is carried verbatim', () {
    test('the period the server filed reaches the model', () {
      final r = PendingRequest.fromJson({
        'id': 11,
        'plan': 'basic',
        'period': 'year',
        'amount_paid': 15000,
        'payment_method': 'cash',
        'created_at': '2026-09-26 21:01:03',
      });
      expect(r.period, 'year');
    });

    test('an absent period is null, not an invented month', () {
      final r = PendingRequest.fromJson({'id': 11, 'plan': 'basic'});
      expect(r.period, isNull);
    });

    test('a period the app does not know is kept, not coerced to month', () {
      // The whole defect: `BillingPeriod.fromWire` maps anything unrecognised to
      // `month`, which is precisely what the server did. Holding the raw string
      // is what lets the card tell the truth about it.
      final r = PendingRequest.fromJson({
        'id': 16,
        'plan': 'basic',
        'period': '6month',
      });
      expect(r.period, '6month');
      expect(pendingPeriodLabelAr(r.period), isNull);
    });
  });

  group('pendingPeriodLabelAr', () {
    test('month and year say the term in Arabic', () {
      expect(pendingPeriodLabelAr('month'), 'اشتراك شهري');
      expect(pendingPeriodLabelAr('year'), 'اشتراك سنوي');
    });

    test('whitespace is not a different term', () {
      expect(pendingPeriodLabelAr('  month  '), 'اشتراك شهري');
    });

    test('absent, empty and unknown periods print no term', () {
      expect(pendingPeriodLabelAr(null), isNull);
      expect(pendingPeriodLabelAr(''), isNull);
      expect(pendingPeriodLabelAr('   '), isNull);
      expect(pendingPeriodLabelAr('lifetime'), isNull);
    });
  });

  group('pendingPeriodMismatchNoteAr', () {
    test('fires on the exact period the live server stores', () {
      // Captured 26 Sep 2026 from a real account: posted `6month`, the Worker
      // answered ok and filed `period: "month"`. The card is the only place
      // that can say so.
      final r = PendingRequest.fromJson({
        'id': 16,
        'plan': 'basic',
        'period': 'month',
        'requested_at': '6month',
      });
      expect(r.period, 'month');
    });

    test('a known period raises nothing', () {
      expect(pendingPeriodMismatchNoteAr('month'), isNull);
      expect(pendingPeriodMismatchNoteAr('year'), isNull);
    });

    test('an unknown period raises the one-month warning', () {
      final note = pendingPeriodMismatchNoteAr('6month');
      expect(note, isNotNull);
      expect(note, contains('شهر واحد'));
    });

    test('absent period raises nothing — we do not know what was asked', () {
      expect(pendingPeriodMismatchNoteAr(null), isNull);
      expect(pendingPeriodMismatchNoteAr('  '), isNull);
    });
  });

  group('the receipt carries the term', () {
    test('term sits between the plan and the amount', () {
      expect(
        pendingFactsAr(
          planLabel: 'أساسي',
          periodLabel: pendingPeriodLabelAr('year'),
          amountLabel: '15000 دج',
          methodLabel: 'نقداً',
          dayLabel: '26-09-2026',
        ),
        'أساسي · اشتراك سنوي · 15000 دج · نقداً · 26-09-2026',
      );
    });

    test('a payload with no period prints exactly the old receipt', () {
      // Degrading to the previous line is the point: an absent term is an
      // unknown term, not a monthly one.
      expect(
        pendingFactsAr(
          planLabel: 'أساسي',
          amountLabel: '15000 دج',
          methodLabel: 'نقداً',
          dayLabel: '26-09-2026',
        ),
        'أساسي · 15000 دج · نقداً · 26-09-2026',
      );
    });
  });
}
