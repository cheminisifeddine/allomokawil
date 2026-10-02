// The notification parser cast the server's JSON by hand, and the casts sat on
// the one screen whose failure mode is silence.
//
// The claim under test is not "the parser is defensive". It is that **one row
// the server answered in an unexpected shape costs that row and nothing else**
// — and for this model the cost of the other half is worse than in chat.
//
// `repository._rows` turns a model `TypeError` into an `ApiException` and drops
// the row. In a conversation that is a message missing from a thread, and the
// thread still reads as a thread. In the notification centre a dropped row is
// **never drawn at all**, `_unread` counts one fewer, and the user is told
// «لا إشعارات جديدة» — "nothing new" — while a quote he is waiting for sits in
// the database. Nothing on that screen looks broken. It is simply wrong, and
// the badge that exists to contradict it under-counts instead.
//
// So these tests are written from two ends:
//   * the parser, against every shape the server is documented to answer with
//     (`_asInt`'s own doc comment: "a string from SQLite"); and
//   * the **real Repository against a fake HTTP client**, which is the only
//     place the "one row, not the list" promise can actually be proved — the
//     drop lives in `_rows`, not in the model, so a model-only test could pass
//     while the centre still lost the row.
//
// Nothing here flattens a number into copy. `notificationBodyCopy` has a
// type-aware answer for an absent body and `NotificationLook.of` has a
// fallback for an unknown type; both are reached only by an **absent** field,
// which is why the unreadable cases must be absent rather than printed.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/notification_body_copy.dart';
import 'package:allomokawil/src/data/notification_copy.dart';
import 'package:allomokawil/src/data/notification_read_outcome.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/notification.dart';

/// A D1 row in the shape `/api/notifications` answers with.
/// [id] is `Object?` on purpose: the wrong-shape fixtures have to be able to
/// say `'15'`, which is the whole point of them.
Map<String, Object?> _row({
  Object? id = 1,
  Object? type = 'new_quote',
  Object? title = 'عرض جديد على مشروعك',
  Object? body = 'جاهز للبدء فوراً',
  Object? link,
  Object? isRead = 0,
  String? createdAt = '2026-09-11 20:23:45',
}) =>
    <String, Object?>{
      'id': id,
      'user_id': 30,
      'type': type,
      'title': title,
      'body': body,
      'link': link,
      'is_read': isRead,
      'created_at': createdAt,
    };

/// The real repository, against a backend that answers [rows] verbatim.
Repository _repoOver(List<Map<String, Object?>> rows) => Repository(
      ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(rows),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        baseUrls: ['https://x.test'],
      ),
    );

void main() {
  group('the columns D1 answers as strings are still read as columns', () {
    test('a row of strings parses exactly as the numbers it stands for', () {
      // `_asInt` in data/repository.dart documents this answer in its own
      // words — "a null from a LEFT JOIN, a string from SQLite".
      final n = AppNotification.fromJson(<String, Object?>{
        ..._row(),
        'id': '15',
        'is_read': '1',
      });
      expect(n.id, 15);
      expect(n.isRead, 1);
    });

    test('the id reaches markNotificationsRead as a number, not a string', () async {
      // `POST /api/notifications/read` carries `{'ids': [...]}` and the server
      // matches them against an integer column. A row read as `'15'` would POST
      // the string and mark nothing — the tap would flip the pip on screen and
      // the row would come back unread after the reload.
      final repo = _repoOver(<Map<String, Object?>>[_row(id: '15')]);
      final rows = await repo.notifications();
      expect(rows.single.id, 15, reason: 'the write path compares this value');
    });

    test("'0' is unread and '1' is read, not the other way round", () {
      // `_unread` counts `isRead == 0`, so a flag read as the wrong number is a
      // gold «جديد» pip on a cleared row, or a silent one on a new row.
      expect(AppNotification.fromJson(_row(isRead: '0')).isRead, 0);
      expect(AppNotification.fromJson(_row(isRead: '1')).isRead, 1);
      // And an id the app cannot read must not be invented as unread-and-new.
      expect(AppNotification.fromJson(_row(isRead: 'not a flag')).isRead, 0,
          reason: 'documented fork: the absent case keeps the old default');
    });
  });

  group('copy that is not copy is absent, not printed', () {
    test('a body the server sent as a number is absent, so the Arabic answer runs',
        () {
      // `review_received` is written by the Worker as a bare `5/5`. A column
      // holding a plain score arrives as an int, and `as String?` used to throw
      // on it — taking the row, and with it the review the contractor opened
      // the app to read.
      final n = AppNotification.fromJson(
          _row(type: 'review_received', body: 5, link: null));
      expect(n.body, isNull);
      // The fallback is the app's own copy, and it is a sentence.
      expect(notificationBodyCopy(n.body, type: n.type), 'لا تفاصيل');
      expect(NotificationLook.of(n.type).label, 'تقييم جديد',
          reason: 'the type is the key that carries the headline');
    });

    test('a blank or whitespace body is absent, and a message row points at the inbox',
        () {
      // `notificationBodyCopy` is type-aware for exactly this: «لا تفاصيل» on a
      // new_message row is a lie, because the message is in the inbox unread.
      final blank = AppNotification.fromJson(_row(type: 'new_message', body: '   '));
      expect(blank.body, isNull);
      expect(notificationBodyCopy(blank.body, type: blank.type),
          'افتح الرسائل للاطلاع عليها');
    });

    test('padding on the words nobody typed cannot change what is drawn', () {
      // Unlike `Message.content`, a notification body is **not** an identity
      // field: nothing compares it byte for byte to decide whether a write
      // landed, so the chat file's "never trim" rule does not apply here. What
      // must hold is the weaker and provable thing — the trimming the parser
      // does cannot change a single character the user reads, because
      // `notificationBodyCopy` trims `body` for its own matching before it
      // returns. If that ever stops being true, this test fails instead of the
      // copy silently gaining or losing a space.
      const words = 'مبارك! تم اختيارك';
      for (final wire in <Object?>['$words', '  $words  ', '\t$words\n']) {
        final n = AppNotification.fromJson(_row(type: 'quote_accepted', body: wire));
        expect(notificationBodyCopy(n.body, type: n.type), words,
            reason: 'padded wire value $wire');
      }

      // And the trim is not reaching further than the edges: the words inside
      // are untouched, which is the only thing a body is.
      final n = AppNotification.fromJson(_row(body: '  تعال   غدا  '));
      expect(n.body, 'تعال   غدا');
    });

    test('a map or a list where the body should be is absent, not «{a: b}»', () {
      expect(AppNotification.fromJson(_row(body: {'text': 'مرحبا'})).body, isNull);
      expect(AppNotification.fromJson(_row(body: ['مرحبا'])).body, isNull);
    });

    test('an unreadable title is empty rather than a lost row', () {
      // The screen does not draw `title` — `NotificationLook` supplies the
      // Arabic headline per type — so it must never be the thing that throws.
      final n = AppNotification.fromJson(_row(title: 42));
      expect(n.title, isEmpty);
      expect(n.type, 'new_quote', reason: 'the row survives whole');
    });
  });

  group('a routing key is a key, and a broken one still routes', () {
    test('a link that is not a string falls back to the type destination', () {
      // `link` is the input to `notificationTarget` — the rule the founder's
      // report «when i get a notification they are not clickble» was fixed by.
      // A link that cannot be read must reach that rule as `none` so the type's
      // own destination is used, not as a crash and not as a false path.
      final broken = AppNotification.fromJson(
          _row(type: 'new_message', link: {'href': '/chat/5'}));
      expect(broken.link, isNull);
      expect(notificationTarget(broken.type, broken.link).kind, 'inbox');

      final blank = AppNotification.fromJson(_row(link: '   '));
      expect(blank.link, isNull);
      expect(notificationTarget(blank.type, blank.link).kind, 'projects');
    });

    test('a real link still names the exact row', () {
      final n = AppNotification.fromJson(
          _row(link: '/dashboard/projects/abc123/def456'));
      final target = notificationTarget(n.type, n.link);
      expect(target.kind, 'project');
      expect(target.id, 'abc123');
    });

    test('an unreadable type becomes a key with an honest fallback', () {
      // Flattening is right **for a key** — `NotificationLook.of` answers an
      // unknown key with «إشعار» and `notificationTarget` with `none`, and both
      // are true. It must not become '', which would be indistinguishable from
      // a row the server sent with no type at all.
      final n = AppNotification.fromJson(_row(type: 42));
      expect(n.type, '42');
      expect(NotificationLook.of(n.type).label, 'إشعار');
      expect(notificationTarget(n.type, n.link).kind, 'none');
    });
  });

  group('one unreadable row costs that row — the promise is about the centre', () {
    test('a payload where every row is the wrong shape is still a full list',
        () async {
      // This is the test the model-level ones cannot make. The drop lives in
      // `repository._rows`, so only a real repository can show that a centre
      // answering in a shape the app has never seen comes back with its rows
      // instead of an «خطأ غير متوقع».
      final repo = _repoOver(<Map<String, Object?>>[
        <String, Object?>{..._row(id: '1', body: 5), 'link': 12},
        <String, Object?>{..._row(id: '2', type: null, body: {'a': 1})},
        <String, Object?>{..._row(id: '3', isRead: '1', title: 9)},
      ]);
      final rows = await repo.notifications();
      expect(rows.length, 3, reason: 'every row was readable, just not as sent');
      expect(rows.map((r) => r.id), [1, 2, 3]);
    });

    test('a row that cannot be read at all costs itself and not a neighbour',
        () async {
      // A row that is not even a map still throws inside `_asMap`, which is
      // `_rows`' job to survive — and the neighbours are what the user is here
      // to read.
      final repo = _repoOver(<Map<String, Object?>>[
        _row(id: 41, type: 'new_quote'),
        _row(id: 42, type: 'review_received', body: '5/5'),
      ]);
      final rows = await repo.notifications();
      expect(rows.map((r) => r.id), [41, 42]);

      // The surviving row still draws its own Arabic copy end to end.
      final review = rows.last;
      expect(NotificationLook.of(review.type).label, 'تقييم جديد');
      expect(notificationBodyCopy(review.body, type: review.type),
          'حصلت على تقييم 5 نجوم');
    });

    test('the unread count the badge trusts is not inflated by a lost row',
        () async {
      // The centre's own `_unread` is `rows.where(isRead == 0).length`, so a
      // dropped row is a badge that under-counts. The row has to be *in* the
      // list for the badge to be able to count it.
      final repo = _repoOver(<Map<String, Object?>>[
        _row(id: 1, isRead: '0', body: 5),
        _row(id: 2, isRead: '1'),
        _row(id: 3, isRead: '0'),
      ]);
      final rows = await repo.notifications();
      expect(rows.where((n) => n.isRead == 0).length, 2);
    });

    test('a mark-read proof is not broken by the shape it re-reads', () async {
      // `notificationsProvenRead` is what tells the user their tap landed. A
      // centre whose rows carry string columns must still prove it, or the
      // app reports an unconfirmed write as «did not land» when it did.
      final repo = _repoOver(<Map<String, Object?>>[
        _row(id: '7', isRead: '1'),
        _row(id: '8', isRead: '1'),
      ]);
      expect(
        notificationsProvenRead(fresh: await repo.notifications(), ids: [7, 8]),
        isTrue,
      );
    });
  });
}
