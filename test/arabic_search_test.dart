import 'package:allomokawil/src/core/text/arabic_search.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:flutter_test/flutter_test.dart';

/// The point of these tests is that each one is a spelling a real Algerian user
/// types. If a case here regresses, search silently stops finding people —
/// which is the bug this file exists to prevent.
void main() {
  group('normalize folds orthographic variants', () {
    test('hamza forms collapse to bare alef', () {
      expect(ArabicSearch.normalize('أحمد'), ArabicSearch.normalize('احمد'));
      expect(ArabicSearch.normalize('إبراهيم'), ArabicSearch.normalize('ابراهيم'));
      expect(ArabicSearch.normalize('آمنة'), ArabicSearch.normalize('امنة'));
    });

    test('alef maqsura folds to ya', () {
      expect(ArabicSearch.normalize('مصطفى'), ArabicSearch.normalize('مصطفي'));
    });

    test('ta marbuta folds to ha', () {
      expect(ArabicSearch.normalize('مقاولة'), ArabicSearch.normalize('مقاوله'));
    });

    test('hamza on waw and ya folds away', () {
      expect(ArabicSearch.normalize('مسؤول'), ArabicSearch.normalize('مسوول'));
      expect(ArabicSearch.normalize('قائم'), ArabicSearch.normalize('قايم'));
    });

    test('tatweel is decoration and is dropped', () {
      expect(ArabicSearch.normalize('دهـــان'), 'دهان');
    });

    test('diacritics are dropped', () {
      expect(ArabicSearch.normalize('دَهَّان'), 'دهان');
    });

    test('arabic-indic digits fold to ascii', () {
      expect(ArabicSearch.normalize('٠٧٧١٢٣٤٥٦٧'), '0771234567');
    });

    test('punctuation becomes a separator, not a blocker', () {
      // Note the fold applies to the expected side too: ئ -> ي, ة -> ه.
      expect(ArabicSearch.normalize('حسين داي، الجزائر'), 'حسين داي الجزاير');
      expect(ArabicSearch.normalize('سباكة (عاجل)'), 'سباكه عاجل');
    });

    test('whitespace is collapsed and trimmed', () {
      expect(ArabicSearch.normalize('  دهان    شقة  '), 'دهان شقه');
    });

    test('normalising twice changes nothing', () {
      const raw = 'أحــمَد  دهّان';
      final once = ArabicSearch.normalize(raw);
      expect(ArabicSearch.normalize(once), once);
    });

    test('latin text still matches case-insensitively', () {
      expect(ArabicSearch.normalize('Plombier'), 'plombier');
    });

    test('empty and punctuation-only input normalise to empty', () {
      expect(ArabicSearch.normalize(''), '');
      expect(ArabicSearch.normalize('   '), '');
      expect(ArabicSearch.normalize('؟!!'), '');
    });
  });

  group('matches finds what a user would expect', () {
    test('searching without the hamza finds a name stored with it', () {
      expect(ArabicSearch.matches('احمد', ['أحمد المقاول']), isTrue);
    });

    test('searching with the hamza finds a name stored without it', () {
      expect(ArabicSearch.matches('أحمد', ['احمد المقاول']), isTrue);
    });

    test('a bare word finds it behind the definite article', () {
      expect(ArabicSearch.matches('بحث', ['قسم البحث']), isTrue);
    });

    test('ta marbuta and ha are interchangeable in a query', () {
      expect(ArabicSearch.matches('مقاوله', ['مقاولة عامة']), isTrue);
      expect(ArabicSearch.matches('مقاولة', ['مقاوله عامة']), isTrue);
    });

    test('alef maqsura in the stored value is found by ya', () {
      expect(ArabicSearch.matches('مصطفي', ['مصطفى للدهان']), isTrue);
    });

    test('multi-word queries require every word', () {
      final fields = ['دهان شقة 3 غرف', 'حسين داي'];
      expect(ArabicSearch.matches('دهان شقة', fields), isTrue);
      // Word order must not matter.
      expect(ArabicSearch.matches('شقة دهان', fields), isTrue);
      // A word that is not there must fail.
      expect(ArabicSearch.matches('دهان قصر', fields), isFalse);
    });

    test('a query can span several fields', () {
      expect(ArabicSearch.matches('دهان حسين', ['دهان شقة', 'حسين داي']), isTrue);
    });

    test('an empty query matches everything', () {
      expect(ArabicSearch.matches('', ['anything']), isTrue);
      expect(ArabicSearch.matches('   ', ['anything']), isTrue);
    });

    test('a query against blank fields finds nothing', () {
      expect(ArabicSearch.matches('دهان', ['', null]), isFalse);
    });

    test('a phone number typed either way is found', () {
      expect(ArabicSearch.matches('0771234567', ['٠٧٧١٢٣٤٥٦٧']), isTrue);
    });

    test('trades match across diacritics and tatweel', () {
      // A plasterer writes جبّاس; the client types جباس.
      expect(ArabicSearch.matches('جباس', ['جبّــاس']), isTrue);
    });

    test('equals ignores spelling variants', () {
      expect(ArabicSearch.equals('الجزائر', 'الجزائر'), isTrue);
      expect(ArabicSearch.equals('البليدة', 'بليدة'), isFalse);
    });

    group('the 58-entry wilaya picker', () {
      // The picker filters on the name and the numeric code together, which is
      // how a user either spells it or remembers it.
      List<String> forQuery(String q) => Taxonomy.wilayas
          .where((w) => ArabicSearch.matches(q, [w.name, w.id]))
          .map((w) => w.name)
          .toList();

      test('finds a wilaya when the spelling is not the official one', () {
        expect(forQuery('الجزاير'), contains('الجزائر'));
      });

      test('finds a wilaya from its code', () {
        expect(forQuery('16'), contains('الجزائر'));
      });

      test('an empty box still lists every wilaya', () {
        expect(forQuery('').length, Taxonomy.wilayas.length);
      });

      test('a wrong query narrows rather than empties', () {
        expect(forQuery('البليدة'), contains('البليدة'));
        expect(forQuery('البليدة').length, lessThan(Taxonomy.wilayas.length));
      });
    });
  });
}
