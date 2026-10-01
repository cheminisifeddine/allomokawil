import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/models/plan_id.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plan id, pinned to the wire.
///
/// The payload ids below are the four `GET /api/mobile/plans` answers observed
/// live on 2 Oct 2026: `free_trial`, `basic`, `pro`, `gold`. If the Worker ever
/// renames a tier this file fails, which is the point — the alternative is an
/// app that quietly reads every row as a paid plan.

SubscriptionStatus _status(String plan, {String? expiresAt}) =>
    SubscriptionStatus.fromJson({
      'plan': plan,
      'name_ar': 'x',
      'status': 'active',
      'expires_at': expiresAt,
      'quote_limit': 3,
      'portfolio_limit': 5,
      'quotes_used_this_month': 1,
    });

void main() {
  group('PlanId.wire is the only spelling', () {
    test('free_trial is snake case, not freeTrial', () {
      // The dead `SubscriptionPlan` enum spelled this `freeTrial`, which the
      // Worker has never sent. If this ever passes, the id is being derived
      // from `name` again and the enum is back.
      expect(PlanId.freeTrial.wire, 'free_trial');
      expect(PlanId.freeTrial.wire, isNot(PlanId.freeTrial.name));
      expect(PlanId.perLead.wire, 'per_lead');
      expect(PlanId.perLead.wire, isNot(PlanId.perLead.name));
    });

    test('the single-letter values happen to agree with name', () {
      // basic/pro/gold/commission are one word, so `.name` would have been
      // correct by accident — the same accident that hid the other two.
      for (final id in [PlanId.basic, PlanId.pro, PlanId.gold, PlanId.commission]) {
        expect(id.wire, id.name);
      }
    });

    test('every arm round-trips through fromWire', () {
      for (final id in PlanId.values) {
        expect(PlanId.fromWire(id.wire), id, reason: 'wire of ${id.name}');
      }
    });
  });

  group('fromWire tolerates what the column actually arrives as', () {
    test('a padded id still reads as the plan it names', () {
      // Every other reader of this column in the app trims before comparing
      // (redeem_outcome.dart, pending_request_copy.dart,
      // quote_worker_trust.dart). `isFree` did not, so a padded row was the
      // trial to three call sites and a paid plan to the fourth.
      expect(PlanId.fromWire(' free_trial'), PlanId.freeTrial);
      expect(PlanId.fromWire('free_trial\n'), PlanId.freeTrial);
      expect(PlanId.fromWire('  basic  '), PlanId.basic);
    });

    test('null, empty and whitespace answer null, never the trial', () {
      expect(PlanId.fromWire(null), isNull);
      expect(PlanId.fromWire(''), isNull);
      expect(PlanId.fromWire('   '), isNull);
    });

    test('an id this app does not know stays unknown', () {
      expect(PlanId.fromWire('enterprise_plus'), isNull);
      expect(PlanId.fromWire('Free_Trial'), isNull); // case is not guessed at
    });
  });

  group('isFree answers one question', () {
    test('the trial and only the trial is free', () {
      expect(PlanId.freeTrial.isFree, isTrue);
      for (final id in [PlanId.basic, PlanId.pro, PlanId.gold, PlanId.perLead, PlanId.commission]) {
        expect(id.isFree, isFalse, reason: '${id.name} is a paid plan');
      }
    });
  });

  group('SubscriptionStatus.isFree no longer compares a raw String', () {
    test('the real free_trial row is free', () {
      expect(_status('free_trial').isFree, isTrue);
    });

    test('a padded trial is still free — the bug this fixed', () {
      // Before: `plan == 'free_trial'` was false here, so the row was a paid
      // plan, so `expiresAtLocal` was consulted and an unknown expiry was
      // parsed for a plan that never ends.
      final s = _status(' free_trial');
      expect(s.isFree, isTrue);
      expect(s.expiresAtLocal, isNull);
    });

    test('an id the app cannot read is NOT filed under the trial', () {
      // The dangerous direction: `PlanId.fromWire` returning `free_trial` for an
      // unknown id would tell a contractor paying 6000 دج he is on the trial
      // AND drop his expiry date — the one number the card exists to give.
      final s = _status('enterprise_plus', expiresAt: '2027-01-01 00:00:00');
      expect(s.isFree, isFalse);
      expect(s.expiresAtLocal, isNotNull);
    });

    test('a paid plan keeps its expiry, and the trial keeps none', () {
      expect(_status('pro', expiresAt: '2027-01-01 00:00:00').expiresAtLocal, isNotNull);
      // Even when the free row carries a stray expires_at: isFree is what
      // makes expiresAtLocal null, so the trial never prints an end date.
      expect(_status('free_trial', expiresAt: '2027-01-01 00:00:00').expiresAtLocal, isNull);
    });
  });
}
