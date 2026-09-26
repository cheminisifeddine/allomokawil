// The app must never name a wilaya the payload does not state.
//
// Found 26 Sep 2026. `Taxonomy.wilayaName` ended in `return 'الجزائر'`, so the
// one field that decides where a job is answered "I do not know" with the name
// of the capital. Two shapes reach that line, and both are real:
//
//   * `Project.fromJson` reads `wilaya: (json['wilaya'] as String?) ?? ''`, so
//     every project row the server sent without a wilaya became `''` — and
//     `''` is not in the table, so its card, its status row and its detail
//     header all published **«الجزائر»** for a job nobody had placed.
//   * A code this build has not heard of: D1 adding a wilaya, a code
//     reformatted `'9'` instead of `'09'`, or a `user_wilaya` written by any
//     other client.
//
// Neither is cosmetic. A contractor filtering «الجزائر» to find work near him
// is sent to the one wilaya this getter names when it is wrong, and the other
// 57 are right — so nobody notices except the man who cannot find the job that
// is 40 km outside his own gate.
//
// The rule this file pins: **a place is printed only when the code resolves,
// and a place is never invented.** Null is the app's answer to everything else
// it cannot measure (`avgRating`, `serviceRadiusKm`, `renewsInDays`), and a
// wilaya joins them.
import 'package:allomokawil/src/data/project_search.dart';
import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Taxonomy.wilayaNameOrNull — no invented wilaya', () {
    test('every wilaya in the table resolves to its own name', () {
      for (final w in Taxonomy.wilayas) {
        expect(Taxonomy.wilayaNameOrNull(w.id), w.name,
            reason: 'wilaya ${w.id} ${w.name}');
      }
    });

    test('a blank code is no wilaya at all', () {
      // This is the exact value `Project.fromJson` manufactures out of a
      // missing `wilaya` field, so it is not a synthetic edge case: it is on
      // every project row the server answers without a location.
      expect(Taxonomy.wilayaNameOrNull(''), isNull);
      expect(Taxonomy.wilayaNameOrNull('   '), isNull);
      expect(Taxonomy.wilayaNameOrNull(null), isNull);
    });

    test('a code this build has not heard of is null, not Algiers', () {
      // A 59th wilaya in D1, or `'9'` written without the zero pad: both used
      // to land on the fallback and print «الجز».
      expect(Taxonomy.wilayaNameOrNull('59'), isNull);
      expect(Taxonomy.wilayaNameOrNull('9'), isNull);
      expect(Taxonomy.wilayaNameOrNull('16x'), isNull);
      expect(Taxonomy.wilayaNameOrNull('الجزائر'), isNull);
    });

    test('the total form never names a place it does not have', () {
      // `wilayaName` keeps a non-null signature for the pickers and the GPS
      // path, whose codes are ours by construction. Its fallback must be a
      // dash, not the capital: a guard that lies is worse than no guard.
      expect(Taxonomy.wilayaName('16'), 'الجزائر');
      expect(Taxonomy.wilayaName('31'), 'وهران');
      expect(Taxonomy.wilayaName(''), '—');
      expect(Taxonomy.wilayaName('59'), '—');
    });
  });

  group('a project without a wilaya is not published in Algiers', () {
    Project build(Map<String, dynamic> overrides) => Project.fromJson({
          'id': 'p1',
          'customer_id': 1,
          'title': 'دهان غرفة',
          'category': 'painting',
          'images': <String>[],
          'urgency': 'normal',
          'status': 'open',
          ...overrides,
        });

    test('the blank code is what a missing field turns into', () {
      // Pinned so a future change to the parser cannot quietly make this file
      // pass for the wrong reason: the null branch below is only meaningful
      // while a missing field really does become `''`.
      expect(build({}).wilaya, '');
    });

    test('a project in a known wilaya keeps its place', () {
      expect(build({'wilaya': '16'}).wilaya, '16');
      expect(Taxonomy.wilayaNameOrNull(build({'wilaya': '31'}).wilaya), 'وهران');
    });

    test('a project in an unknown wilaya resolves to nothing at all', () {
      expect(Taxonomy.wilayaNameOrNull(build({'wilaya': '59'}).wilaya), isNull);
    });
  });

  group('search cannot match a wilaya the project does not have', () {
    // The other half of the same defect, and the half a user would notice
    // fastest: with the fallback in the haystack, typing «الجزائر» returned
    // **every** project on the platform, because each one claimed the capital
    // in a field it did not have.
    Project project({String? wilaya, String title = 'دهان غرفة'}) => Project.fromJson(
          {
            'id': 'p1',
            'customer_id': 1,
            'title': title,
            'category': 'painting',
            'images': <String>[],
            'urgency': 'normal',
            'status': 'open',
            if (wilaya != null) 'wilaya': wilaya,
          },
        );

    test('a project with no wilaya does not answer a search for Algiers', () {
      expect(projectMatchesQuery(project(), 'الجزائر'), isFalse);
    });

    test('a project in an unknown wilaya does not either', () {
      expect(projectMatchesQuery(project(wilaya: '59'), 'الجزائر'), isFalse);
    });

    test('a project that really is in Algiers still answers', () {
      expect(projectMatchesQuery(project(wilaya: '16'), 'الجزائر'), isTrue);
    });

    test('a real location still searches, and the wilaya name is not required',
        () {
      expect(projectMatchesQuery(project(wilaya: '16'), 'حسين داي'), isFalse,
          reason: 'the commune was never set on this project');
      expect(projectMatchesQuery(project(wilaya: '31'), 'وهران'), isTrue);
    });
  });
}
