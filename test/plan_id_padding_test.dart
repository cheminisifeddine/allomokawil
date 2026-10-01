// `planById` compared the raw wire id, on the screen that prints a receipt.
//
// **Found with 0 unchecked items**, by reading the family the last item named:
// one column, several readers, no type making them agree. `plan` is read in
// four places on the subscription screen and in `plan_id.dart`. Three of the
// readers `.trim()` first — `pendingClaimFor`, the pending card's own label,
// and `PaymentOptions.labelFor` (which does `final key = id.trim()` before the
// same `m.id == key` shape). The fourth did not, and neither did the state
// flag.
//
// Two things were wrong, both on the money screen:
//
//  1. `planById` returning null made `pendingPlanLabelAr` fall back to the raw
//     wire id, so a padded `" pro"` printed `pro` — a Latin token — where
//     «محترف» belongs on the receipt the man screenshots to support his
//     payment.
//  2. `current.plan == plan.id` returning false dropped the «خطتك» pill, the
//     accent border, and the button label. A contractor **on pro** was shown
//     «ترقية — محترف» (*upgrade*) instead of «تجديد» (*renew*): his own tier
//     offered back to him for money, one tap from a second transfer.
//
// The rule under test: **a padded id is the plan it names.** Trimming is not
// cosmetic here; it is the difference between a receipt in Arabic and a Latin
// constant, and between renewing and buying the plan twice.
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/models/plan_id.dart';
import 'package:allomokawil/src/data/pending_request_copy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalogue as `GET /api/mobile/plans` sends it, with the `pro` tier the
/// money screen actually sells.
BillingCatalogue _catalogue({String currentPlan = 'free_trial'}) {
  return BillingCatalogue.fromJson({
    'currency': 'DZD',
    'commission_percent': 0,
    'commission_per_order': 0,
    'plans': [
      {
        'id': 'free_trial',
        'name_ar': 'مجان',
        'name_fr': 'Free',
        'price_month': 0,
        'price_year': 0,
        'quote_limit': 3,
        'portfolio_limit': 5,
        'search_boost': 0,
        'wilaya_span': 1,
        'features': <String>[],
      },
      {
        'id': 'pro',
        'name_ar': 'محترف',
        'name_fr': 'Pro',
        'price_month': 3000,
        'price_year': 30000,
        'quote_limit': -1,
        'portfolio_limit': 60,
        'search_boost': 3,
        'wilaya_span': 2,
        'features': <String>[],
      },
    ],
    'current': {
      'plan': currentPlan,
      'name_ar': '',
      'status': 'active',
      'starts_at': null,
      'expires_at': null,
      'quote_limit': 3,
      'portfolio_limit': 5,
      'quotes_used_this_month': 0,
      'renews_in_days': null,
    },
    'payment': {
      'methods': [
        {'id': 'baridi', 'label_ar': 'بريدي موب', 'instructions': '5566'},
      ],
      'support_phone': null,
    },
  });
}

void main() {
  group('planById resolves a padded id', () {
    test('a plan id that arrives padded is the plan it names', () {
      final cat = _catalogue();
      expect(cat.planById(' pro')!.nameAr, 'محترف');
    });

    test('padding is the case, not the exception: every whitespace form', () {
      final cat = _catalogue();
      for (final padded in [' pro', 'pro ', ' pro ', '\tpro\n']) {
        expect(cat.planById(padded)?.nameAr, 'محترف',
            reason: 'id «$padded» must resolve');
      }
    });

    test('an id that is only whitespace resolves to nothing', () {
      // Not the free plan, not `pro` — nothing. An empty id is not a plan,
      // and returning a plan for it would put a name on the receipt that the
      // server never filed.
      expect(_catalogue().planById('   '), isNull);
      expect(_catalogue().planById(''), isNull);
    });

    test('an id the catalogue does not carry is still null', () {
      expect(_catalogue().planById('enterprise'), isNull);
      expect(_catalogue().planById('gold'), isNull);
    });

    test('the free plan resolves like any other, padded or not', () {
      final cat = _catalogue();
      expect(cat.planById('free_trial')!.isFree, isTrue);
      expect(cat.planById(' free_trial ')!.isFree, isTrue);
    });
  });

  group('isCurrentPlan is the card state, not a label', () {
    test('the tier the subscription is on is marked current', () {
      final cat = _catalogue(currentPlan: 'pro');
      expect(cat.isCurrentPlan(cat.planById('pro')!), isTrue);
      expect(cat.isCurrentPlan(cat.planById('free_trial')!), isFalse);
    });

    test('a padded current.plan still marks the right card', () {
      // The regression. Untrimmed this is false, and the man on pro is handed
      // «ترقية — محترف» instead of «تجديد» on his own tier.
      final cat = _catalogue(currentPlan: ' pro');
      expect(cat.isCurrentPlan(cat.planById('pro')!), isTrue);
      expect(cat.isCurrentPlan(cat.planById('free_trial')!), isFalse);
    });

    test('an empty current.plan marks nothing', () {
      final cat = _catalogue(currentPlan: '   ');
      expect(cat.isCurrentPlan(cat.planById('pro')!), isFalse);
      expect(cat.isCurrentPlan(cat.planById('free_trial')!), isFalse);
    });

    test('agreement with isFree holds for padded and unpadded rows alike', () {
      // The two facts are derived from the same column by different code. They
      // must not disagree about what plan this is.
      for (final wire in ['free_trial', ' free_trial ', 'pro', ' pro ']) {
        final cat = _catalogue(currentPlan: wire);
        final isTrial = cat.current.isFree;
        expect(cat.isCurrentPlan(cat.planById('free_trial')!), isTrial,
            reason: 'free tier marking must match isFree for «$wire»');
        expect(cat.isCurrentPlan(cat.planById('pro')!), !isTrial,
            reason: 'paid tier marking must match isFree for «$wire»');
      }
    });
  });

  group('the receipt a padded id used to corrupt', () {
    PendingRequest pendingWithPlan(String plan) => PendingRequest.fromJson({
          'id': 49,
          'plan': plan,
          'amount_dzd': 15000,
          'method': 'baridi',
          'created_at': '2026-10-02 10:00:00',
          'period': 'month',
        });

    test('a padded plan id prints the Arabic name, not the wire id', () {
      final cat = _catalogue();
      final nameAr = cat.planById(pendingWithPlan(' pro').plan)?.nameAr;
      final label = pendingPlanLabelAr(pendingWithPlan(' pro').plan, nameAr);
      expect(label, 'محترف');
      // The exact failure: the raw Latin id reaching a receipt.
      expect(label, isNot('pro'));
    });

    test('an id with no Arabic name still falls back, and still trimmed', () {
      final cat = _catalogue();
      final request = pendingWithPlan(' enterprise ');
      final label = pendingPlanLabelAr(
          request.plan, cat.planById(request.plan)?.nameAr);
      // Unknown plan: the fallback exists so the fact is not dropped, but it
      // must not print the padding the server sent.
      expect(label, 'enterprise');
    });

    test('the claim that blocks a second payment already trimmed', () {
      // Pins the reader that was already correct, so the fix does not become a
      // reason to change it: the padded id claims the same plan the card marks.
      final claim = pendingClaimFor(pendingWithPlan(' pro'));
      expect(claim!.plan, 'pro');
      expect(claim.covers('pro', BillingPeriod.month.wire), isTrue);
    });
  });

  group('the law, stated once', () {
    test('PlanId.fromWire and planById agree on a padded id', () {
      // Two readers of the same column, and they must not disagree about
      // which plan arrived.
      final cat = _catalogue();
      expect(PlanId.fromWire(' pro'), PlanId.pro);
      expect(cat.planById(' pro')!.id, PlanId.pro.wire);
    });

    test('an unknown plan is not silently filed under the trial', () {
      expect(PlanId.fromWire(' enterprise '), isNull);
      expect(_catalogue(currentPlan: ' enterprise ').current.isFree, isFalse,
          reason: 'unreadable id must not suppress a paid plan’s expiry');
    });
  });
}
