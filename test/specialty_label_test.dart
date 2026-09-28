// The one line under a contractor's name, which is the only place the app says
// what trade he works in.
//
// Found on 28 Sep 2026, on the live API rather than on a reading of the code.
// The card built this line as `specialties.take(2).join(' · ')` — no ellipsis,
// no count. The row that proved it is real: contractor خالد رحماني, verified,
// 4.6★ over 18 reviews, 32 completed jobs, returned by
// `/api/mobile/workers/search?wilaya=16` with
// `["painting","wallpaper","tiling_marble"]`. The card printed two of those
// three and deleted the third with no trace.
//
// The browse screen filters by trade, so the trades a contractor carries
// decide whether a customer searching that trade finds him at all. He was
// returned as the top tiling result and the one line that would have said so
// is the line that dropped it.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/specialty_label.dart';
import 'package:allomokawil/src/data/taxonomy.dart';

void main() {
  group('the row that proved it, verbatim from the live API', () {
    test('a three-trade contractor is not shown as a two-trade one', () {
      // The exact specialties of خالد رحماني, worker id 2, wilaya 16.
      final label = SpecialtyLabel.of(['painting', 'wallpaper', 'tiling_marble']);
      expect(label, contains(Taxonomy.categoryName('painting')));
      expect(label, contains(Taxonomy.categoryName('wallpaper')));
      // The trade that was being deleted is now accounted for by a count
      // rather than by nothing at all.
      expect(label, contains('+1'));
    });

    test('the silent two-trade truncation is gone in every direction', () {
      // One over: the smallest case the old `take(2)` could hide.
      expect(SpecialtyLabel.of(['painting', 'wallpaper', 'carpentry_aluminum']),
          '${Taxonomy.categoryName('painting')} · ${Taxonomy.categoryName('wallpaper')} +1');
      // Many over: the card must not print a list, but it must not lie either.
      final five = SpecialtyLabel.of([
        'painting', 'plumbing', 'electrical', 'tiling_marble', 'carpentry_aluminum',
      ]);
      expect(five, startsWith(Taxonomy.categoryName('painting')));
      expect(five, contains('+3'));
    });
  });

  group('what it printed before, and must still print', () {
    test('an already-correct line is unchanged', () {
      expect(SpecialtyLabel.of(['painting']), Taxonomy.categoryName('painting'));
      expect(
        SpecialtyLabel.of(['painting', 'plumbing']),
        '${Taxonomy.categoryName('painting')} · ${Taxonomy.categoryName('plumbing')}',
      );
    });

    test('no trades at all is a word, not a count', () {
      // A zero is the absence of a count, the rule every other count in this
      // app follows. «+0» would be worse than silence.
      expect(SpecialtyLabel.of([]), 'حرفي');
      expect(SpecialtyLabel.of(['']), 'حرفي');
      expect(SpecialtyLabel.of(['   ']), 'حرفي');
    });

    test('the first trade is never the one dropped', () {
      final label = SpecialtyLabel.of([
        'painting', 'wallpaper', 'tiling_marble', 'electrical', 'plumbing',
      ]);
      expect(label.startsWith(Taxonomy.categoryName('painting')), isTrue);
    });
  });

  group('the count must not be able to lie', () {
    test('two slugs for one trade print once and claim no extra', () {
      // `painting` and `general_painting` resolve to the same trade. Printing
      // both would tell a customer the man works in two things; a `+1` over a
      // one-name list would be a count of nothing.
      final label = SpecialtyLabel.of(['painting', 'general_painting']);
      expect(label, Taxonomy.categoryName('painting'));
      expect(label, isNot(contains('+')));
    });

    test('de-duplication still leaves a true count', () {
      // Three entries, two of which are the same trade: two real trades, so
      // nothing is hidden and nothing is claimed.
      final label =
          SpecialtyLabel.of(['painting', 'general_painting', 'plumbing']);
      expect(label, isNot(contains('+')));
    });

    test('an unknown slug never leaks English into the Arabic UI', () {
      // Taxonomy folds an unknown slug to a single Arabic label, so three of
      // them are one trade and the line must not claim three.
      final label = SpecialtyLabel.of(['nope', 'also_nope', 'still_nope']);
      expect(label.contains('nope'), isFalse);
      expect(label, isNot(contains('+')));
    });
  });
}
