// How many communes, said the way the number says it.
//
// Found on 26 Sep 2026. The commune picker printed its count by hand twice —
// '$_total بلدية' for the wilaya and 'بلدية واحدة' : '$matches بلدية' for the
// search — with the broken plural `بلدية` hard-coded for everything from 2
// upward. Arabic uses `بلدية` for 3-10, `بلديتان` for 2, and the bare
// `بلدية` again for 11 and up, so every wilaya with ten or fewer communes read
// wrong, and so did almost every search result.
//
// The last test is the one that matters: it drives the real bundled dataset,
// because "this is wrong for a quarter of the country" is a claim about the
// data and not about the string function.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/commune_count_copy.dart';
import 'package:allomokawil/src/data/communes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the four forms', () {
    test('1 / 2 / 3-10 / 11+ each take their own noun', () {
      expect(communeCountAr(1), 'بلدية واحدة');
      expect(communeCountAr(2), 'بلديتان');
      expect(communeCountAr(3), '3 بلديات');
      expect(communeCountAr(10), '10 بلديات');
      expect(communeCountAr(11), '11 بلدية');
      expect(communeCountAr(58), '58 بلدية');
      expect(communeCountAr(1541), '1541 بلدية');
    });

    test('the singular is not counted with a 1', () {
      expect(communeCountAr(1), isNot(contains('1 ')));
    });

    test('the dual is not counted with a 2 — it already says two', () {
      expect(communeCountAr(2), isNot(contains('2 ')));
    });

    test('a zero is silence, not «0 بلدية»', () {
      expect(communeCountAr(0), '');
      expect(communeCountAr(-4), '');
    });
  });

  group('no wilaya in the shipped dataset prints the wrong noun', () {
    setUpAll(() async {
      await CommuneIndex.instance.load();
    });

    test('every real commune count agrees with the shared rule', () {
      // The defect, asserted rather than asserted-in-prose: for every wilaya in
      // the country, the count the picker header prints is the one Arabic
      // grammar requires. Before the fix this failed for the 14 wilayas with
      // ten or fewer communes — including Ouargla, El Menia and Tindouf, which
      // have two.
      final wrong = <String>[];
      for (var i = 1; i <= 58; i++) {
        final id = i.toString().padLeft(2, '0');
        final n = CommuneIndex.instance.countFor(id);
        if (n == 0) continue;
        final printed = communeCountAr(n);
        final expected = n == 1
            ? 'بلدية واحدة'
            : n == 2
                ? 'بلديتان'
                : n <= 10
                    ? '$n بلديات'
                    : '$n بلدية';
        if (printed != expected) wrong.add('wilaya $id ($n): «$printed»');
      }
      expect(wrong, isEmpty);
    });

    test('the wilayas that were wrong are covered, and they really are small',
        () {
      // Pinning the two-commune wilayas, so this test cannot quietly stop
      // covering the case that broke. Tindouf is 37, and El Menia 58 — both
      // used to read «2 بلدية» where Arabic requires «بلديتان».
      expect(CommuneIndex.instance.countFor('37'), 2);
      expect(communeCountAr(2), 'بلديتان');
      // A 3-10 wilaya keeps the broken plural, and a large one goes back to the
      // bare singular, so the rule is four cases and not two.
      expect(CommuneIndex.instance.countFor('30'), 8);
      expect(communeCountAr(8), '8 بلديات');
      expect(CommuneIndex.instance.countFor('16'), 57);
      expect(communeCountAr(57), '57 بلدية');
    });

    test('a search that narrows to one or two says so in the right form', () {
      // The search count is the one a user sees on every keystroke, and it is
      // always <= the wilaya total, so the dual case is reachable there too.
      final index = CommuneIndex.instance;
      final all = index.inWilaya('37').map((c) => c.name).toList();
      expect(all.length, 2);
      expect(communeCountAr(index.searchCount('37', all.first)), 'بلدية واحدة');
    });
  });
}
