// The billing parsers cast the server's JSON by hand instead of reading it,
// and a cast is a crash the moment the payload stops being the shape the app
// expects. Five of them sat inside `lib/src/models/plan.dart`, all on the money
// screen — the one surface where a thrown exception is not a blank list but a
// contractor who cannot see what he is paying for.
//
// D1 is not obliged to answer with a String. Every one of these fields is
// nullable *in the payload* and the live Worker has already answered with a
// shape the app did not expect at least once this year: a subscription request
// filed with an unrecognised `period` came back `{"ok":true}` and stored as
// `month` (13 spellings probed, 26 Sep). Nothing guarantees the next one is a
// string.
//
// The cast that actually bites: `json['instructions'] as String?`. A nullable
// cast succeeds on null and on String, and **throws a TypeError on an int**.
// An account number arriving as a number is not a shape to guess at — but it is
// not a reason to lose the whole subscription screen either.
//
// The rule now: a field the payload may legitimately withhold or re-type is read
// through `_text`, which returns null for anything that is not a string. Null is
// the honest answer, and every caller already handles null — `instructions`
// null is what the screen already prints when no bank details are published.

import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentMethod survives a payload that is not shaped like the app', () {
    test('a numeric account number is unknown, not a crash', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{
        'id': 'baridimob',
        'label_ar': 'بريدي موب',
        // A CCP number sent as a number. `as String?` threw here.
        'instructions': 55667788,
      });
      expect(m.instructions, isNull);
      expect(m.id, 'baridimob');
      expect(m.labelAr, 'بريدي موب');
    });

    test('a map-valued instructions is unknown, not a crash', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{
        'id': 'baridimob',
        'instructions': <String, dynamic>{'rib': '55667788'},
      });
      expect(m.instructions, isNull);
    });

    test('a whitespace-only account number stays null, as before', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{
        'id': 'baridimob',
        'instructions': '   ',
      });
      expect(m.instructions, isNull);
    });

    test('a real account number is still read and trimmed', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{
        'id': 'baridimob',
        'instructions': '  55667788  ',
      });
      expect(m.instructions, '55667788');
    });

    test('a missing id does not become the literal string "null"', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{'label_ar': 'تحويل'});
      // `'${json['id']}'` on an absent id printed «null» into the method id,
      // which is then POSTed back as the payment method on the write path.
      expect(m.id, isNot('null'));
      expect(m.id.trim(), isEmpty);
    });

    test('a numeric id is read as its text, not thrown', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{'id': 7});
      expect(m.id, '7');
    });

    test('a method with no id is dropped: an empty label is not payable', () {
      // `labelAr` falls back to the id, so a row with neither leaves the sheet
      // offering a pay button labelled with nothing, and posting it sends an
      // empty `method` to the server. Dropped at the parser instead.
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'methods': [
          <String, dynamic>{'label_ar': 'تحويل'},
          <String, dynamic>{'id': 'baridimob', 'label_ar': 'بريدي موب'},
        ],
      });
      expect(o.methods.map((m) => m.id), ['baridimob']);
    });

    test('a whitespace-only id is dropped for the same reason', () {
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'methods': [
          <String, dynamic>{'id': '   ', 'label_ar': 'تحويل'},
        ],
      });
      expect(o.methods, isEmpty);
    });

    test('labelAr falls back to the id when the payload has no Arabic name', () {
      final m = PaymentMethod.fromJson(<String, dynamic>{'id': 'baridimob'});
      expect(m.labelAr, 'baridimob');
    });
  });

  group('PaymentOptions survives a payload that is not shaped like the app', () {
    test('a numeric support phone is dropped, not thrown', () {
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'support_phone': 555123456,
      });
      expect(o.supportPhone, isNull);
    });

    test('a missing support phone is null, not a crash', () {
      expect(PaymentOptions.fromJson(null).supportPhone, isNull);
    });

    test('a methods list holding a string does not take the screen down', () {
      // One malformed row must cost that row, not the whole sheet. The list
      // comprehension casts each entry `as Map` and a non-map entry throws.
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'methods': ['baridimob'],
      });
      expect(o.methods, isEmpty);
    });

    test('a string where methods should be a list is no methods at all', () {
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'methods': 'baridimob',
      });
      expect(o.methods, isEmpty);
    });

    test('one bad row is skipped and the good ones survive', () {
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'methods': [
          'not-a-map',
          <String, dynamic>{'id': 'baridimob', 'label_ar': 'بريدي موب'},
        ],
      });
      expect(o.methods.map((m) => m.id), ['baridimob']);
      expect(o.labelFor('baridimob'), 'بريدي موب');
    });

    test('a real phone string is still read', () {
      final o = PaymentOptions.fromJson(<String, dynamic>{
        'support_phone': '0555123456',
      });
      expect(o.supportPhone, '0555123456');
    });
  });

  group('SubscriptionStatus dates survive a payload that is not shaped', () {
    test('a numeric expires_at is unknown, not a crash', () {
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'pro',
        'expires_at': 20270901,
      });
      // The expiry card is the one thing this row is read for.
      expect(s.expiresAtLocal, isNull);
      expect(s.isExpired, isFalse);
      expect(s.expiryCountdownAr, isNull);
    });

    test('a numeric starts_at is unknown, not a crash', () {
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'pro',
        'starts_at': 20260901,
      });
      expect(s.startsAt, isNull);
    });

    test('a real date string is still read and drives the countdown', () {
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'pro',
        'expires_at': '2027-01-01 00:00:00',
      });
      expect(s.expiresAtLocal, isNotNull);
      expect(s.expiryCountdownAr, isNotNull);
    });
  });

  group('Plan copy survives a payload that is not shaped like the app', () {
    test('a numeric tagline is unknown, not a crash', () {
      final p = Plan.fromJson(<String, dynamic>{
        'id': 'pro',
        'name_ar': 'محترف',
        'tagline_ar': 42,
      });
      expect(p.taglineAr, isNull);
      expect(p.nameAr, 'محترف');
    });

    test('a numeric name_ar is read as text rather than thrown', () {
      final p = Plan.fromJson(<String, dynamic>{
        'id': 'pro',
        'name_ar': 42,
      });
      expect(p.nameAr, '42');
    });
  });

  group('The catalogue lists survive a payload that is not shaped', () {
    test('a plans list holding a string drops that row, keeps the rest', () {
      final c = PlanCatalogue.fromJson(<String, dynamic>{
        'plans': ['pro', <String, dynamic>{'id': 'basic'}],
      });
      expect(c.plans.map((p) => p.id), ['basic']);
    });

    test('a string where plans should be a list is an empty catalogue', () {
      final c = PlanCatalogue.fromJson(<String, dynamic>{
        'plans': 'pro',
      });
      expect(c.plans, isEmpty);
    });

    test('a payment block that is a string costs only the payment block', () {
      final cat = BillingCatalogue.fromJson(<String, dynamic>{
        'plans': [<String, dynamic>{'id': 'pro'}],
        'payment': 'baridimob',
      });
      expect(cat.plans.map((p) => p.id), ['pro']);
      expect(cat.payment.methods, isEmpty);
    });

    test('a current block that is a string reads as no plan at all', () {
      final cat = BillingCatalogue.fromJson(<String, dynamic>{
        'plans': const <dynamic>[],
        'current': 'pro',
      });
      // An unreadable `current` is the same row as an absent one, and that row
      // has always defaulted to the trial: a string is not a plan id, and
      // guessing «pro» would put a paid expiry card on a plan we cannot
      // evidence. The point of the assertion is that it no longer throws.
      expect(cat.current.plan, 'free_trial');
      expect(cat.current.isFree, isTrue);
    });
  });
}
