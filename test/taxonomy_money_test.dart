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

  group('Money — readable amounts for low-digital-literacy users', () {
    test('round thousands use Arabic unit words', () {
      expect(Money.amountOnly(60000), '60 ألف');
      expect(Money.amountOnly(600000), '600 ألف');
      expect(Money.amountOnly(7000), '7 آلاف');
      expect(Money.amountOnly(40000), '40 ألف');
    });

    test('one and two thousands are special-cased', () {
      expect(Money.amountOnly(1000), 'ألف');
      expect(Money.amountOnly(2000), 'ألفان');
    });

    test('millions', () {
      expect(Money.amountOnly(1000000), 'مليون');
      expect(Money.amountOnly(1500000), '1.5 مليون');
      expect(Money.amountOnly(12000000), '12 مليون');
    });

    test('non-round amounts are grouped, never ellipsised mid-digits', () {
      expect(Money.amountOnly(7500), '7\u00A0500');
      expect(Money.amountOnly(950), '950');
    });

    test('currency suffix', () {
      expect(Money.dzd(60000), '60 ألف دج');
      expect(Money.dzd(1000), 'ألف دج');
    });

    test('never renders a raw long digit run', () {
      for (final v in [60000, 600000, 7500, 1500000, 12000000, 40000]) {
        expect(Money.dzd(v).contains('000'), isFalse,
            reason: '$v rendered as ${Money.dzd(v)}');
      }
    });
  });
}
