import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/format/money.dart';
import 'package:allomokawil/src/data/taxonomy.dart';

/// Every slug dialect ever written into `projects.category` by any client.
/// The web v1 app (`app/lib/constants.ts`), older mobile builds and manual
/// rows all used different vocabularies against one column.
const _liveDbSlugs = <String>[
  // canonical (Flutter app)
  'construction', 'renovation', 'general_finishing', 'painting',
  'plaster_drywall', 'plumbing', 'electrical', 'tiling_marble',
  'carpentry_aluminum', 'ironwork_welding', 'waterproofing_insulation',
  'hvac_heating', 'epoxy_flooring', 'landscaping_exterior',
  'venetian_plaster', 'wallpaper',
  // web v1 specialty vocabulary
  'decorative_paint', 'general_painting', 'texture_coating', 'metallic_paint',
  'wood_effect', 'marble_effect', 'tadelakt', 'stucco', 'microcement', 'epoxy',
  // hyphenated leftovers actually present in D1
  'exterior-paint', 'marble-effect', 'micro-cement', 'plaster-decor',
  'venetian-plaster', 'plaster_decor',
];

void main() {
  final arabic = RegExp(r'[\u0600-\u06FF]');

  group('Taxonomy.canonical — no raw English slug reaches an Arabic screen', () {
    for (final slug in _liveDbSlugs) {
      test('"$slug" resolves to an Arabic category name', () {
        final name = Taxonomy.categoryName(slug);
        expect(arabic.hasMatch(name), isTrue,
            reason: '"$slug" rendered as "$name" — leaked into the Arabic UI');
        expect(name, isNot(slug));
      });
    }

    test('unknown slug degrades to a generic Arabic label, never English', () {
      expect(Taxonomy.categoryName('some_future_trade'), 'خدمات عامة');
    });

    test('hyphen and underscore dialects hit the same category', () {
      expect(Taxonomy.canonical('venetian-plaster'), 'venetian_plaster');
      expect(Taxonomy.canonical('venetian_plaster'), 'venetian_plaster');
      expect(Taxonomy.canonical('micro-cement'), 'epoxy_flooring');
      expect(Taxonomy.canonical('marble-effect'), 'tiling_marble');
    });

    test('aliases do not collide with real slugs', () {
      for (final canonical in Taxonomy.categories.map((c) => c.slug)) {
        expect(Taxonomy.canonical(canonical), canonical);
      }
    });
  });

  group('Money — plain dinar amounts', () {
    // The founder's call, verbatim: «use dinar format like 6000 دج instead of 6
    // الاف دينار». The Arabic unit words are gone: an amount is digits, then دج,
    // so two prices can be compared without translating either one first.
    test('thousands stay digits', () {
      expect(Money.amountOnly(60000), '60000');
      expect(Money.amountOnly(7000), '7000');
      expect(Money.amountOnly(1000), '1000');
    });

    test('millions stay digits too', () {
      expect(Money.amountOnly(1000000), '1000000');
      expect(Money.amountOnly(1500000), '1500000');
    });

    test('no grouping separators, no unit words', () {
      expect(Money.amountOnly(7500), '7500');
      expect(Money.amountOnly(950), '950');
    });

    test('currency suffix', () {
      expect(Money.dzd(6000), '6000 دج');
      expect(Money.dzd(1000), '1000 دج');
    });

    test('a negative amount clamps to zero instead of printing a minus', () {
      expect(Money.amountOnly(-5), '0');
    });
  });
}
