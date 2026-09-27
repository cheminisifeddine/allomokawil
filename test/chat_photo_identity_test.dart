// A picture could never be recognised as delivered, and the check that was
// standing in for one matched every picture with every other picture.
//
// The reconciliation this file pins is the question a lost answer leaves open:
// «the POST may already be stored — is it?». The screen answered it by
// re-reading the thread and comparing `row.content == local.content`.
//
// For a **photo**, `content` is null on both sides, so that test was
// `null == null`: always true. The thread was asked a question it could not
// answer, and replied yes anyway. Two consequences, both silent:
//
//  * a photo the server never stored was reported as delivered, and then
//    `_forget` **deleted the queue record** — the picture was not retried, not
//    redrawn, and no sentence said it had not arrived. The user is left holding
//    a message he believes was sent, with nothing left on the device to send it
//    from. That is not a duplicate; it is the loss the outbox exists to prevent,
//    produced by the mechanism built to prevent it;
//  * the row adopted as «mine» was whichever image came first, so the bubble
//    could end up wearing a stranger's server id.
//
// Text was accidentally correct, which is why 1100+ tests never saw it: two
// non-null strings really can be equal. A photo has no such string on either
// side — the phone holds a local path and the thread holds an R2 URL, and those
// two can never be equal in any build.
//
// The fix gives a picture a name the server can be asked about: the URL its
// upload returned, written to the queue record the moment it exists, and
// compared exactly on every re-read. `data/thread_match.dart` is the predicate;
// these tests hold it to both directions.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/thread_match.dart';
import 'package:allomokawil/src/models/chat.dart';

Message _row({int id = 1, int senderId = 30, String? content, String? imageUrl}) =>
    Message(
      id: id,
      conversationId: 7,
      senderId: senderId,
      content: content,
      imageUrl: imageUrl,
      type: imageUrl != null ? MessageType.image : MessageType.text,
      isRead: 0,
      createdAt: DateTime.utc(2026, 9, 27, 10),
    );

void main() {
  group('the predicate itself', () {
    test('a picture is matched by the URL its upload returned', () {
      const mine = LocalIdentity(
          imagePath: '/storage/emulated/0/DCIM/shot.jpg',
          uploadedUrl: 'https://r2.test/uploads/a1.jpg');
      expect(
        threadHolds(
            _row(imageUrl: 'https://r2.test/uploads/a1.jpg'), mine,
            me: 30),
        isTrue,
      );
    });

    test('another picture from the same person is NOT this picture', () {
      // The exact case the old predicate called a match: both sides null.
      const mine = LocalIdentity(
          imagePath: '/storage/emulated/0/DCIM/shot.jpg',
          uploadedUrl: 'https://r2.test/uploads/a1.jpg');
      expect(
        threadHolds(
            _row(id: 99, imageUrl: 'https://r2.test/uploads/other.jpg'), mine,
            me: 30),
        isFalse,
      );
    });

    test('a picture whose upload never answered cannot be claimed', () {
      // No URL is a fact, not a gap: the row is written *after* the upload, so
      // with no URL there is no row this device can point at.
      const mine = LocalIdentity(imagePath: '/storage/emulated/0/DCIM/shot.jpg');
      expect(threadHolds(_row(imageUrl: 'https://r2.test/x.jpg'), mine, me: 30),
          isFalse);
      expect(threadHolds(_row(), mine, me: 30), isFalse);
    });

    test('words are still matched on the words', () {
      expect(
        threadHolds(_row(content: 'العنوان: حسين داي'),
            const LocalIdentity(text: 'العنوان: حسين داي'),
            me: 30),
        isTrue,
      );
      expect(
        threadHolds(_row(content: 'تمام'), const LocalIdentity(text: 'تمام'),
            me: 30),
        isTrue,
      );
      expect(
        threadHolds(_row(content: 'تمام'), const LocalIdentity(text: 'لا'),
            me: 30),
        isFalse,
      );
    });

    test('an empty string is not a message and never matches', () {
      // `null == null` and `'' == ''` are the same defect wearing two hats.
      expect(
          threadHolds(_row(content: ''), const LocalIdentity(text: ''), me: 30),
          isFalse);
    });

    test("someone else's row is never mine", () {
      expect(
        threadHolds(
            _row(senderId: 31, imageUrl: 'https://r2.test/uploads/a1.jpg'),
            const LocalIdentity(uploadedUrl: 'https://r2.test/uploads/a1.jpg'),
            me: 30),
        isFalse,
      );
    });

    test('an unknown sender cannot filter, so the shape decides', () {
      // me == 0 means the app does not know who it is. The caller has already
      // decided that, so the id is not checked — but a photo still is.
      expect(
        threadHolds(
            _row(senderId: 31, imageUrl: 'https://r2.test/uploads/a1.jpg'),
            const LocalIdentity(uploadedUrl: 'https://r2.test/uploads/a1.jpg'),
            me: 0),
        isTrue,
      );
      expect(
        threadHolds(
            _row(imageUrl: 'https://r2.test/uploads/other.jpg'),
            const LocalIdentity(uploadedUrl: 'https://r2.test/uploads/a1.jpg'),
            me: 0),
        isFalse,
      );
    });
  });

  group('the URL survives the disk', () {
    test('a stored record keeps the URL its upload returned', () async {
      final outbox = ChatOutbox(
          store: MemoryOutboxStore(), clock: () => DateTime(2026, 9, 27));
      final record =
          await outbox.add(conversationId: 7, imagePath: '/tmp/shot.jpg');
      expect(
          await outbox.noteUploadedUrl(
              record.id, 'https://r2.test/uploads/a1.jpg'),
          isTrue);
      final stored = (await outbox.all()).single;
      expect(stored.uploadedUrl, 'https://r2.test/uploads/a1.jpg');
    });

    test('marking a record unconfirmed does not drop the URL', () async {
      // The rebuild in markUncertain is where a field can be silently lost, and
      // losing it here would re-open the exact hole this file closes: the mark
      // is written *because* the send is in doubt, so that is precisely when the
      // URL must survive.
      final outbox = ChatOutbox(
          store: MemoryOutboxStore(), clock: () => DateTime(2026, 9, 27));
      final record =
          await outbox.add(conversationId: 7, imagePath: '/tmp/shot.jpg');
      await outbox.noteUploadedUrl(record.id, 'https://r2.test/uploads/a1.jpg');
      await outbox.markUncertain(record.id, uncertain: SendState.unconfirmed);
      final stored = (await outbox.all()).single;
      expect(stored.uploadedUrl, 'https://r2.test/uploads/a1.jpg');
      expect(stored.uncertain, SendState.unconfirmed);
    });

    test('a refused URL write answers false and changes nothing', () async {
      final store = _DecliningStore();
      final outbox =
          ChatOutbox(store: store, clock: () => DateTime(2026, 9, 27));
      final record =
          await outbox.add(conversationId: 7, imagePath: '/tmp/shot.jpg');
      // The disk is full *now*: the record is there, the URL is not.
      store.decline = true;
      expect(await outbox.noteUploadedUrl(record.id, 'https://r2.test/a.jpg'),
          isFalse);
      store.decline = false;
      final stored = (await outbox.all()).single;
      expect(stored.uploadedUrl, isNull,
          reason: 'a refused write must not leave a half-written record');
    });

    test('an old stored row with no URL reads as unidentifiable, not as landed',
        () {
      final decoded = decodeOutbox(jsonEncode(<Map<String, Object?>>[
        {
          'id': '7.1.0',
          'conversation_id': 7,
          'image_path': '/tmp/shot.jpg',
          'created_at': DateTime(2026, 9, 27)
              .toUtc()
              .millisecondsSinceEpoch,
        }
      ]));
      expect(decoded.single.uploadedUrl, isNull);
      expect(
        threadHolds(
            _row(imageUrl: 'https://r2.test/anything.jpg'),
            LocalIdentity(
                imagePath: decoded.single.imagePath,
                uploadedUrl: decoded.single.uploadedUrl),
            me: 30),
        isFalse,
      );
    });
  });
}

/// A store that accepts the queue and then refuses the next write, which is the
/// shape a full disk takes. `PrefsOutboxStore` answers a refused commit by
/// throwing, so the refusal is modelled here at the seam the outbox sees.
class _DecliningStore implements OutboxStore {
  Object? raw;
  bool decline = false;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    if (decline) throw StateError('preferences refused to store the queue');
    raw = value;
  }
}
