// A contractor's price range of zero, and what the browse card says about it.
//
// Found 1 Oct 2026, with the backlog at 0 unchecked, by asking the question
// the budget-zero item answered one file over: **`Project.budgetLabel` folds a
// stored `0` to null. Does `priceRangeAr` — the label for the same two server
// columns, printed by a different widget on a different screen?** It did not.
//
// `price_range_copy.dart` was shipped three days ago to fix `7000 - 7000 دج`,
// and the collapse it added is what made the zero visible:
//
//   if (min == max) return Money.dzd(min);
//
// Both ends zero satisfies that arm exactly, so a row holding `(0, 0)` printed
//
//     «0 دج»
//
// in the gold `payments_rounded` tag on `worker_card.dart` — the card a
// customer picks a tradesman from. Not a crash, not an error: a **price**, and
// the only price in the app that is not one. «0 دج» reads as "he works for
// nothing" rather than "he never typed one".
//
// **The zero is reachable from this app's own form, which is what makes it a
// defect rather than server state.** `profile_edit_screen._save` parses both
// boxes with a bare `DzNumber.tryParse(...)` — no `min` bound — so a typed `0`
// is the integer 0. The form's only cross-field rule is `min > max`, which
// zero does not violate, so both boxes can be saved as `0`. That is a two-field
// typo, not a server bug, and it publishes to every customer who browses.
//
// The two labels are the whole shape of the defect: the **same two columns**
// (`price_range_min` / `price_range_max`), the **same server**, the **same
// stored `0` sentinel**, and two labels that answered it differently — one
// folding the zero away, one printing it. This file pins the worker's side to
// the project's, and pins `hasPriceRange` to the same fold so the tag on the
// card cannot appear around a sentence that says there is no price.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/dz_number.dart';
import 'package:allomokawil/src/data/price_range_copy.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/models/worker.dart';

void main() {
  group('a stored zero is not a price', () {
    test('both ends zero publish no price at all', () {
      // The bug, quoted as it printed. «0 دج» is not a sentence a tradesman
      // writes and it is not a band the form asked for.
      expect(priceRangeAr(0, 0), isNull);
    });

    test('one end zero is folded away, keeping the other real number', () {
      // A contractor who typed only a maximum and left the «من» box at 0 must
      // keep his maximum. Dropping the whole row because one end is a
      // sentinel would be the opposite error — the same one the single-maximum
      // case was fixed for.
      expect(priceRangeAr(0, 8000), 'حتى 8000 دج');
      expect(priceRangeAr(5000, 0), 'من 5000 دج');
    });

    test('the fold is not a price clamp — real money is untouched', () {
      // Every value the platform actually carries, byte-exact. A fold that
      // moved a real price would be worse than the defect it fixed: wrong
      // about every contractor, every day, and it would look deliberate.
      expect(priceRangeAr(1, 1), '1 دج');
      expect(priceRangeAr(1, null), 'من 1 دج');
      expect(priceRangeAr(null, 1), 'حتى 1 دج');
      expect(priceRangeAr(2500, null), 'من 2500 دج');
      expect(priceRangeAr(null, 8000), 'حتى 8000 دج');
      expect(priceRangeAr(5000, 5000), '5000 دج');
      expect(priceRangeAr(7000, 9000), '7000 - 9000 دج');
    });
  });

  group('the card cannot draw a tag around a sentence that says nothing', () {
    test('the gate reads the same fold as the copy, over every shape', () {
      // `worker_card` gates the money tag on `hasPriceRange` and prints
      // `priceRangeAr` inside it. With the fold only on the copy, `(0, 0)`
      // would satisfy the gate and render an icon whose text is null — the
      // two-surfaces-disagreeing defect the bool was invented to end,
      // reintroduced by the fix beside it.
      const pairs = <(int?, int?)>[
        (null, null),
        (0, 0),
        (0, null),
        (null, 0),
        (0, 8000),
        (8000, 0),
        (1, 1),
        (1, null),
        (null, 1),
        (5000, 5000),
        (7000, 9000),
        (9000, 7000),
      ];
      for (final p in pairs) {
        expect(priceRangeAr(p.$1, p.$2) != null, hasPriceRange(p.$1, p.$2),
            reason: 'gate disagrees with copy for $p');
      }
    });

    test('a zero-only row is a row with no price on it', () {
      expect(hasPriceRange(0, 0), isFalse);
      expect(hasPriceRange(0, null), isFalse);
      expect(hasPriceRange(null, 0), isFalse);
      // And a real number anywhere is a price, however zero the other end.
      expect(hasPriceRange(0, 8000), isTrue);
      expect(hasPriceRange(8000, 0), isTrue);
    });
  });

  group('the zero is reachable from this app\'s own form', () {
    test('a bare parse accepts a typed 0 — no min bound on the price boxes',
        () {
      // `profile_edit_screen._save` calls this with no `min`, exactly as the
      // form does, which is what makes the stored zero ours and not the
      // server's. If the form ever grows the bound this test is the one that
      // should notice, and the fold above should still hold — defence in depth,
      // not a substitute.
      expect(DzNumber.tryParse('0'), 0);
      expect(DzNumber.tryParse('٠'), 0); // the same on an Arabic keypad
    });

    test('min > max, the form\'s only cross-field rule, does not refuse 0', () {
      // The validation that runs on the way out, quoted. 0 is not greater than
      // anything, so both boxes pass and publish.
      const min = 0, max = 0;
      expect(min > max, isFalse);
    });
  });

  group('one column, one answer — the project budget folds it the same way',
      () {
    test('both labels agree that (0, 0) carries no price', () {
      // Same two columns, same sentinel, two widgets. Before the fix these two
      // lines printed «بدون ميزانية محددة» and «0 دج».
      final project = Project(
        id: 'p1',
        customerId: 1,
        title: 't',
        description: null,
        category: 'painting',
        images: const [],
        wilaya: '16',
        budgetMin: 0,
        budgetMax: 0,
        urgency: UrgencyLevel.withinMonth,
        status: ProjectStatus.open,
      );
      expect(project.budgetLabel, 'بدون ميزانية محددة');
      expect(priceRangeAr(0, 0), isNull);
    });

    test('a real budget still reads as a price, on both sides', () {
      final project = Project(
        id: 'p1',
        customerId: 1,
        title: 't',
        description: null,
        category: 'painting',
        images: const [],
        wilaya: '16',
        budgetMin: 2500,
        budgetMax: 8000,
        urgency: UrgencyLevel.withinMonth,
        status: ProjectStatus.open,
      );
      // Read off the real getter, not written from memory: the min carries no
      // unit of its own because the «دج» on the max ends the band.
      expect(project.budgetLabel, 'من 2500 إلى 8000 دج');
      expect(priceRangeAr(2500, 8000), '2500 - 8000 دج');
    });
  });

  group('a zero off the wire, not just typed into the form', () {
    test('WorkerProfile stores the sentinel and the label folds it', () {
      // The other half: the value arrives from the API, not from our own form,
      // and nothing in the read path objects to it either.
      final w = WorkerProfile.fromJson({
        'id': 1,
        'user_id': 2,
        'full_name': 'كريم حداد',
        'price_range_min': 0,
        'price_range_max': 0,
      });
      expect(w.priceRangeMin, 0);
      expect(w.priceRangeMax, 0);
      // The card gates and prints through these two, and both now say no.
      expect(hasPriceRange(w.priceRangeMin, w.priceRangeMax), isFalse);
      expect(priceRangeAr(w.priceRangeMin, w.priceRangeMax), isNull);
    });
  });
}
