import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/project_search.dart';
import 'package:allomokawil/src/models/project.dart';

/// Builds a project the way the API delivers one — the slugs and codes are
/// English/numeric, which is exactly why searching by the Arabic name has to
/// resolve them through the taxonomy.
Project _p({
  String title = '',
  String? description,
  String category = 'painting',
  String wilaya = '16',
  String? commune,
  ProjectStatus status = ProjectStatus.open,
}) =>
    Project(
      id: 'p-$title-$commune',
      customerId: 1,
      title: title,
      description: description,
      category: category,
      images: const [],
      wilaya: wilaya,
      commune: commune,
      urgency: UrgencyLevel.flexible,
      status: status,
    );

void main() {
  group('title and description', () {
    final painting = _p(
      title: 'دهان شقة 3 غرف',
      description: 'أحتاج دهان كامل مع تصليح الجبس',
      commune: 'حسين داي',
    );

    test('a word from the title matches', () {
      expect(projectMatchesQuery(painting, 'دهان'), isTrue);
      expect(projectMatchesQuery(painting, 'شقة'), isTrue);
    });

    test('a word from the description matches', () {
      expect(projectMatchesQuery(painting, 'تصليح'), isTrue);
    });

    test('the commune matches with or without hamza-free spelling', () {
      expect(projectMatchesQuery(painting, 'حسين داي'), isTrue);
    });

    test('tatweel and diacritics in the stored text do not hide it', () {
      final stretched = _p(title: 'دهـــان', description: 'دَهَّان محترف');
      expect(projectMatchesQuery(stretched, 'دهان'), isTrue);
    });

    test('a word from neither field does not match', () {
      expect(projectMatchesQuery(painting, 'سباكة'), isFalse);
      expect(projectMatchesQuery(painting, 'فيلا الرياض'), isFalse);
    });

    test('every typed word has to land, in any order', () {
      expect(projectMatchesQuery(painting, 'دهان حسين'), isTrue);
      expect(projectMatchesQuery(painting, 'حسين دهان'), isTrue);
      expect(projectMatchesQuery(painting, 'دهان وهران'), isFalse);
    });

    test('a project with no description at all still matches its title', () {
      final bare =
          _p(title: 'ترميم واجهة', description: null, category: 'construction');
      expect(projectMatchesQuery(bare, 'ترميم'), isTrue);
      expect(projectMatchesQuery(bare, 'دهان'), isFalse);
    });
  });

  group('category and wilaya are searched by their Arabic name', () {
    final gypsumInBlida = _p(
      title: 'سقف معلق',
      category: 'plaster_drywall',
      wilaya: '09',
      commune: 'بوفاريك',
    );

    test('the category name finds a project stored under an English slug', () {
      expect(projectMatchesQuery(gypsumInBlida, 'جبس'), isTrue);
      expect(projectMatchesQuery(gypsumInBlida, 'ديكور'), isTrue);
    });

    test('the wilaya name finds a project stored under a numeric code', () {
      expect(projectMatchesQuery(gypsumInBlida, 'البليدة'), isTrue);
      // Folded: no hamza, ya for alef maqsura.
      expect(projectMatchesQuery(gypsumInBlida, 'البليده'), isTrue);
    });

    test('a project with no wilaya never matches the wilaya fallback', () {
      final noWilaya = _p(title: 'صباغة', wilaya: '');
      expect(projectMatchesQuery(noWilaya, 'الجزائر'), isFalse);
    });

    test('an unknown category slug falls back to Arabic, never to English', () {
      final unknown = _p(title: 'خدمة', category: 'unknown_trade');
      expect(projectMatchesQuery(unknown, 'عامة'), isTrue);
    });
  });

  group('narrowProjects', () {
    final all = [
      _p(title: 'دهان شقة', category: 'painting', wilaya: '16', commune: 'حسين داي'),
      _p(title: 'جبس بورد', category: 'plaster_drywall', wilaya: '09'),
      _p(title: 'سباكة حمام', category: 'plumbing', wilaya: '16', commune: 'باب الوادي'),
    ];

    test('an empty or punctuation-only query leaves the feed untouched', () {
      expect(narrowProjects(all, ''), hasLength(3));
      expect(narrowProjects(all, '   '), hasLength(3));
      expect(narrowProjects(all, '؟!'), hasLength(3));
    });

    test('a typed word narrows to the matching projects only', () {
      final gypsum = narrowProjects(all, 'جبس');
      expect(gypsum, hasLength(1));
      expect(gypsum.single.title, 'جبس بورد');
    });

    test('the same wilaya spelled two ways returns the same two projects', () {
      expect(narrowProjects(all, 'الجزائر'), hasLength(2));
      expect(narrowProjects(all, 'الجزاير'), hasLength(2));
    });

    test('narrowing keeps the original order', () {
      final algiers = narrowProjects(all, 'الجزاير');
      expect(algiers.map((p) => p.title).toList(),
          ['دهان شقة', 'سباكة حمام']);
    });

    test('a word nobody has returns nothing, not everything', () {
      expect(narrowProjects(all, 'مسبح'), isEmpty);
    });
  });
}
