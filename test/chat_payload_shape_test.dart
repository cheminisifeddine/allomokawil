// The chat parsers cast the server's JSON by hand, and the casts sat on the
// thread itself — the app's highest-traffic screen.
//
// The claim under test is not "the parsers are defensive". It is that **one
// row the server answered in an unexpected shape costs that row and nothing
// else**. That distinction is the whole item, because the chat read goes
// through `repository._rows`, which turns a model `TypeError` into an
// `ApiException` and *drops the row* — so a payload where every row disagrees
// with the app is not a degraded thread, it is a dead one: the screen answers
// «حدث خطأ غير متوقع» and the user is shown no messages at all, in a screen
// whose entire job is showing messages.
//
// Two families of wrong shape are covered, both taken from what this codebase
// has already recorded as true rather than invented:
//
//  * **a column as a string.** `_asInt` in `data/repository.dart` says it in
//    its own doc comment — "a null from a LEFT JOIN, a string from SQLite".
//    D1 hands back strings. So `json['sender_id'] as int` is not a paranoid
//    guess; it is a cast that fails on a real server answer.
//  * **copy that is not copy.** `content`, `image_url`, `other_user_name` and
//    `message_type` are read with `as String?`, which succeeds on a `String`
//    and on `null` and **throws on everything else** — an int, a map, a list.
//
// The second group has one rule that must not be relaxed, and it is the reason
// this file exists: **`content` is an identity field, not a label.**
// `threadHolds` compares a row's `content` against the words this phone sent,
// word for word, to decide whether a message whose send answer never arrived
// is on the server. Reading it by *flattening* (`'$value'`) would manufacture
// matches that are not there — the same `null == null` class of lie
// `data/thread_match.dart` was written to end. So a `content` that is not a
// string must be **absent**, and the guard below proves it cannot match a
// local message.
//
// And one thing must not change: **the words are not trimmed.** A trimmed read
// would be "tidier" and would break delivery detection, because the row comes
// back with the server's bytes and the phone holds the ones it sent.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/thread_match.dart';
import 'package:allomokawil/src/models/chat.dart';

void main() {
  group('the conversation list survives the shapes the server answers', () {
    test('the id columns as strings SQLite hands back are still numbers', () {
      // `_asInt` in repository.dart documents this answer as real.
      final c = Conversation.fromJson({
        'id': '5',
        'customer_id': '30',
        'worker_user_id': '31',
        'other_user_name': 'مقاول تجربة',
        'unread_count': '2',
        'last_message_at': '2026-09-11 20:23:47',
      });
      expect(c.id, 5);
      expect(c.customerId, 30);
      expect(c.workerUserId, 31);
      expect(c.unreadCount, 2,
          reason: 'a count read as a string is still a count, not zero');
    });

    test('a name that is not a string leaves an empty title, not a crash', () {
      final c = Conversation.fromJson({
        'id': 5,
        'customer_id': 30,
        'worker_user_id': 31,
        'other_user_name': 41,
        'other_user_avatar': {'url': 'x'},
      });
      expect(c.otherUserName, isEmpty,
          reason: 'no name is blank; a number is not a person');
      expect(c.otherUserAvatar, isNull);
    });

    test('the preview is absent rather than a printed number', () {
      // A preview row in the list said «12» — the user reads a number as a
      // message. Absent lets the row fall back; «12» is a claim nobody made.
      final c = Conversation.fromJson({
        'id': 5,
        'customer_id': 30,
        'worker_user_id': 31,
        'other_user_name': 'مقاول',
        'last_message_content': 12,
      });
      expect(c.lastMessageContent, isNull);
    });
  });

  group('a message row survives the shapes the server answers', () {
    test('its id columns as strings are still numbers', () {
      final m = Message.fromJson({
        'id': '11',
        'conversation_id': '5',
        'sender_id': '30',
        'content': 'مرحبا',
        'message_type': 'text',
        'is_read': '1',
      });
      expect(m.id, 11);
      expect(m.conversationId, 5);
      expect(m.senderId, 30);
      expect(m.isRead, 1);
    });

    test('the words as an int are absent, and cannot claim to be mine', () {
      final m = Message.fromJson({
        'id': 11,
        'conversation_id': 5,
        'sender_id': 30,
        'content': 1234,
        'message_type': 'text',
      });
      expect(m.content, isNull,
          reason: 'flattening a number would invent words nobody wrote');

      // The half that matters. `mine` is my own unconfirmed send; this row is
      // claimed to be its copy. If an unreadable `content` matched, the outbox
      // would delete a message the server never received — and delete the
      // user's only copy with it.
      expect(
        threadHolds(m, const LocalIdentity(text: 'مرحبا'), me: 30),
        isFalse,
        reason: 'a row whose words could not be read is not proof of delivery',
      );
      // And the same for the picture path, which matches on the URL.
      final photo = Message.fromJson({
        'id': 12,
        'conversation_id': 5,
        'sender_id': 30,
        'content': null,
        'image_url': 77,
        'message_type': 'image',
      });
      expect(
        threadHolds(photo,
            const LocalIdentity(uploadedUrl: 'https://r2/photo.jpg'), me: 30),
        isFalse,
      );
    });

    test('an unreadable type is a text message, not a dropped row', () {
      final m = Message.fromJson({
        'id': 13,
        'conversation_id': 5,
        'sender_id': 30,
        'content': 'تمام',
        'message_type': 9,
      });
      expect(m.type, MessageType.text);
      expect(m.content, 'تمام',
          reason: 'the words survive even when the label does not');
    });

    test('a blank image URL is absent, so no bubble loads an empty string', () {
      // `chat_screen` draws the picture branch on `imageUrl != null`. `''` is
      // not null, so an empty string reached the image widget as a URL.
      final m = Message.fromJson({
        'id': 14,
        'conversation_id': 5,
        'sender_id': 30,
        'content': null,
        'image_url': '   ',
        'message_type': 'image',
      });
      expect(m.imageUrl, isNull);
    });

    test('the words keep the server bytes — no trimming', () {
      // The guard against a "tidy" parser. `threadHolds` is an exact
      // comparison by design (see thread_match.dart), so trimming here would
      // make a delivered message read as undelivered and the outbox would send
      // it a second time.
      final m = Message.fromJson({
        'id': 15,
        'conversation_id': 5,
        'sender_id': 30,
        'content': ' مرحبا ',
        'message_type': 'text',
      });
      expect(m.content, ' مرحبا ');
      expect(
        threadHolds(m, const LocalIdentity(text: ' مرحبا '), me: 30),
        isTrue,
        reason: 'what was sent is what comes back, byte for byte',
      );
      expect(
        threadHolds(m, const LocalIdentity(text: 'مرحبا'), me: 30),
        isFalse,
        reason: 'so trimming one side would silently break the match',
      );
    });

    test('a timestamp the server sent as an epoch is not a crash', () {
      // `parseServerTime` already reads only strings — so this one is a
      // regression guard on a parser that was fixed first, not a new fix.
      final m = Message.fromJson({
        'id': 16,
        'conversation_id': 5,
        'sender_id': 30,
        'content': 'x',
        'created_at': 1757625827,
      });
      expect(m.createdAt, isNull);
    });
  });
}
