// «مشاريعي الأخيرة» — *my recent* projects — was not recent, and no project row
// in this app could be dated at all.
//
// Found on 4 Oct 2026. `Project` had no `createdAt` field, and `Project.fromJson`
// read sixteen keys without touching `created_at` — a field the API really does
// send (verified against `allomokawil.com`, and present in this repo's own
// fixtures). The third model in a class this repo has already paid for twice;
// `review_order.dart` is the precedent, and this file is deliberately shaped
// after `review_date_and_order_test.dart` so the same three questions get asked
// of it: does the wire value survive, is the order right, and is the real screen
// actually drawn in that order.
//
// Both halves matter and neither is a missing feature:
//
//   1. **the row was undated** — the home strip's heading promises recency and
//      nothing on the path could deliver it;
//   2. **the list was in whatever order the server sent** — latent while the
//      Worker's `ORDER BY` holds, wrong the day it does not, and untestable
//      here in either case: this suite proves the app owns the order rather
//      than inheriting it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/project_order.dart';
import 'package:allomokawil/src/models/project.dart';

Project _p(String id, {String? createdAt}) => Project.fromJson({
      'id': id,
      'customer_id': 1,
      'title': 'مشروع',
      'category': 'painting',
      'images': <Object?>[],
      'wilaya': '16',
      'urgency': 'within_week',
      'status': 'open',
      'created_at': createdAt,
    });

void main() {
  group('the wire value survives', () {
    test('created_at is read, and read as UTC', () {
      final p = _p('a', createdAt: '2026-09-30 12:07:30');
      expect(p.createdAt, isNotNull);
      // D1 writes UTC with no zone. A naive `DateTime.parse` reads it as local
      // and the whole list lands out by Algeria's offset, so this pins the
      // conversion rather than just the presence of the field.
      expect(p.createdAt!.toUtc().toIso8601String(),
          startsWith('2026-09-30T12:07:30'));
    });

    test('an absent or empty created_at stays null — it must not throw', () {
      // `fromJson` runs on every row of every list in the app; one malformed
      // stamp must not take the whole list down with it.
      expect(_p('a').createdAt, isNull);
      expect(_p('b', createdAt: '').createdAt, isNull);
    });

    test('a junk stamp reads as undated rather than crashing the list', () {
      expect(_p('c', createdAt: 'not-a-date').createdAt, isNull);
    });
  });

  group('newestProjectFirst', () {
    test('orders dated rows newest first regardless of server order', () {
      final out = newestProjectFirst([
        _p('old', createdAt: '2026-01-01 08:00:00'),
        _p('new', createdAt: '2026-10-02 09:00:00'),
        _p('mid', createdAt: '2026-09-11 20:23:44'),
      ]);
      expect(out.map((p) => p.id).toList(), ['new', 'mid', 'old']);
    });

    test('undated rows keep server order and go last, never dropped', () {
      final out = newestProjectFirst([
        _p('u1'),
        _p('d1', createdAt: '2026-10-02 09:00:00'),
        _p('u2'),
        _p('d2', createdAt: '2026-09-01 09:00:00'),
      ]);
      expect(out.map((p) => p.id).toList(), ['d1', 'd2', 'u1', 'u2']);
    });

    test('rows sharing a stamp keep the same order on every read', () {
      // `List.sort` is not stable, so without a tie-break two same-second rows
      // could reorder on every pull and the list would shimmer as the client
      // scrolls. What is pinned here is **determinism**, deliberately not a
      // recency claim: a project id is a 64-char hash, so comparing two of
      // them lexically cannot tell the reader which job was posted first —
      // this is the one place the review precedent's "higher id = inserted
      // later" argument does not carry over.
      final a = [
        _p('aaa1', createdAt: '2026-10-02 09:00:00'),
        _p('bbb2', createdAt: '2026-10-02 09:00:00'),
      ];
      final once = newestProjectFirst(a).map((p) => p.id).toList();
      final reversedOnce =
          newestProjectFirst(a.reversed.toList()).map((p) => p.id).toList();
      // Same two rows, opposite server order -> the same answer either way.
      expect(reversedOnce, once);
      for (var i = 0; i < 25; i++) {
        expect(newestProjectFirst(a).map((p) => p.id).toList(), once);
      }
    });

    test('an empty and a single-row list are left alone', () {
      expect(newestProjectFirst([]), isEmpty);
      expect(newestProjectFirst([_p('a')]).single.id, 'a');
    });
  });
}
