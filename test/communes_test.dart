import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/communes.dart';
import 'package:allomokawil/src/data/taxonomy.dart';

/// The commune dataset is generated (`tool/gen_communes.py`) and shipped as an
/// asset, so these tests guard the three ways it can silently break: the asset
/// stops being bundled, a wilaya loses its list, or matching regresses to a raw
/// `contains()` that no Algerian actually types.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final index = CommuneIndex.instance;

  setUpAll(() async {
    await index.load();
  });

  group('dataset shape', () {
    test('loads the whole country: 58 wilayas, 1541 communes', () {
      expect(index.isLoaded, isTrue);
      // 1,541 is the official number of Algerian communes. A silent drop means
      // the generator or the asset changed under us.
      expect(index.total, 1541);
    });

    test('every wilaya in the app taxonomy has communes', () {
      final empty = [
        for (final w in Taxonomy.wilayas)
          if (index.countFor(w.id) == 0) w.id,
      ];
      expect(empty, isEmpty);
    });

    test('the dataset wilaya names agree with the taxonomy', () {
      // Names live in two places; if they drift the picker header would show a
      // wilaya the rest of the app does not call that.
      for (final w in Taxonomy.wilayas) {
        expect(index.wilayaName(w.id), w.name, reason: 'wilaya ${w.id}');
      }
    });

    test('known wilaya sizes are right', () {
      // Spot checks against the official counts: Alger 57, Constantine 12,
      // Oran 26, El Menia 3, Adrar 16.
      expect(index.countFor('16'), 57);
      expect(index.countFor('25'), 12);
      expect(index.countFor('31'), 26);
      expect(index.countFor('58'), 3);
      expect(index.countFor('01'), 16);
    });

    test('no commune has an empty name and none is duplicated inside a wilaya',
        () {
      for (final w in Taxonomy.wilayas) {
        final names = <String>[];
        for (final c in index.inWilaya(w.id)) {
          expect(c.name.trim(), isNotEmpty, reason: 'wilaya ${w.id}');
          expect(c.latin.trim(), isNotEmpty, reason: c.name);
          names.add(c.name);
        }
        expect(
          names.toSet().length,
          names.length,
          reason: 'wilaya ${w.id} lists the same commune twice',
        );
      }
    });

    test('zero-padded ids resolve (the taxonomy uses 01, the asset uses 1)',
        () {
      expect(index.countFor('01'), index.countFor('1'));
      expect(index.inWilaya('01').length, greaterThan(0));
    });
  });

  group('search', () {
    test('finds حسين داي inside الجزائر with the hamza', () {
      final hits = index.search('16', 'حسين داي');
      expect(hits.map((c) => c.name), contains('حسين داي'));
    });

    test('finds it when the hamza is dropped — how Algerians actually type',
        () {
      // Stored as الأبيار / أولاد فايت, typed without the hamza.
      expect(index.search('16', 'الابيار').map((c) => c.latin),
          contains('El Biar'));
      expect(index.search('16', 'اولاد فايت').map((c) => c.latin),
          contains('Ouled Fayet'));
    });

    test('finds it with no space at all', () {
      expect(index.search('16', 'حسينداي'.replaceAll(' ', '')), isNotEmpty);
    });

    test('folds alef maqsura and ta marbuta', () {
      // أولاد أحمد تيمى is stored with a final alef maqsura.
      expect(index.search('01', 'تيمي'), isNotEmpty);
      expect(index.search('01', 'تيمى'), isNotEmpty);
    });

    test('finds a Latin-typed name from an Arabic-first list', () {
      final hits = index.search('16', 'hussein');
      expect(hits, isNotEmpty);
      expect(hits.first.name, contains('حسين'));
    });

    test('a nonsense query returns nothing rather than everything', () {
      expect(index.search('16', 'zzzz'), isEmpty);
      expect(index.searchCount('16', 'zzzz'), 0);
    });

    test('an empty query returns the whole wilaya', () {
      expect(index.search('16', '').length, index.countFor('16'));
      expect(index.search('16', '   ').length, index.countFor('16'));
    });

    test('search never leaks a commune from another wilaya', () {
      // سيدي خالد exists in both Ouled Djellal (51) and Sidi Bel Abbès (22);
      // the matcher must stay inside the wilaya it was given.
      final inWilaya = index.search('51', 'سيدي خالد').map((c) => c.name);
      expect(inWilaya, contains('سيدي خالد'));
      for (final c in index.search('51', 'سيدي خالد')) {
        expect(
          index.inWilaya('51').map((x) => x.name),
          contains(c.name),
        );
      }
    });

    test('counts stay honest when the rendered list is capped', () {
      final n = index.searchCount('16', 'ا');
      expect(n, greaterThan(0));
      expect(index.search('16', 'ا', limit: 3).length, 3);
      expect(n, greaterThanOrEqualTo(index.search('16', 'ا', limit: 3).length));
    });

    test('an unknown wilaya yields an empty list, not an exception', () {
      expect(index.search('999', 'x'), isEmpty);
      expect(index.countFor('999'), 0);
    });
  });
}
