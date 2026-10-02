// Chat models: the conversation thread and the messages inside it.
//
// Timestamps come from D1 as `YYYY-MM-DD HH:MM:SS` in UTC with no zone marker,
// so they go through `parseServerTime` (the app's single server-clock parser)
// instead of `DateTime.tryParse`, which would read them as local wall-clock and
// print every message an hour off in Algiers — and file the ones sent after
// 23:00 UTC under the wrong day.
//
// The two parsers below **read** the payload instead of casting it, and the
// reason is not politeness. The chat read is the app's highest-traffic screen,
// and it goes through `repository._rows`, which turns a model `TypeError` into
// an `ApiException` and **drops the row**. So the cost of one cast that meets
// an unexpected shape is not a bad field — it is a hole in the conversation,
// and when the server answers every row in that shape the screen shows
// «حدث خطأ غير متوقع» where the user's messages should be.
//
// Two wrong shapes are real here, not hypothetical:
//   * **a column as a string.** `_asInt` in `data/repository.dart` documents it
//     in its own words — "a null from a LEFT JOIN, a string from SQLite".
//   * **copy that is not copy.** `json['x'] as String?` succeeds on a `String`
//     and on `null` and throws on everything else.
import 'notification.dart' show parseServerTime;

/// A conversation thread keyed by (customer, worker, project).
class Conversation {
  final int id;
  final int customerId;
  final int workerUserId;
  final String? projectId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String? lastMessageContent;
  final int unreadCount;

  /// Server `last_message_at` — drives the relative timestamp in the list row.
  final DateTime? lastMessageAt;

  const Conversation({
    required this.id,
    required this.customerId,
    required this.workerUserId,
    this.projectId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.lastMessageContent,
    required this.unreadCount,
    this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: _int(json['id']),
        customerId: _int(json['customer_id']),
        workerUserId: _int(json['worker_user_id']),
        // A project id is a key, not prose: whatever the server sent is
        // flattened by its own text, which is what interpolation did here
        // before — an absent id reads as '' rather than the word «null».
        projectId: _wireText(json['project_id']),
        // The name is the row's title, and an unreadable one is a blank title:
        // `chat_list_screen` already answers an empty name with «محادثة».
        // Flattening a number would put «41» where a person should be.
        otherUserName: _text(json['other_user_name']) ?? '',
        otherUserAvatar: _text(json['other_user_avatar']),
        // A preview is copy. `chatPreviewCopy` already answers null with the
        // standard «لا توجد رسائل بعد», which is the truth; a printed «12» is
        // a claim nobody made.
        lastMessageContent: _text(json['last_message_content']),
        unreadCount: _nullableInt(json['unread_count']) ?? 0,
        lastMessageAt: parseServerTime(json['last_message_at']),
      );
}

/// Message types supported in chat.
enum MessageType { text, image, quote, system }

/// Where one of *my* messages is in its journey to the server.
///
/// A bubble that looks the same whether it reached the server or not is a
/// silent lie: the user closes the app believing the contractor got his address
/// and his phone number. Anything that came back from the API is [sent]; only a
/// bubble this device drew can be [sending] or [failed].
enum SendState {
  /// On screen, still travelling: the request is in flight, or it is queued
  /// because this phone has no connection.
  sending,

  /// Stored by the server — it has a real id and a server timestamp.
  sent,

  /// The request came back with an error and is still on the phone. The bubble
  /// keeps the text and offers one tap to send it again.
  failed,

  /// The request left the phone and no answer ever arrived, so the server may
  /// already hold these words. The bubble keeps the text and offers **no** retry
  /// affordance, and the thread will not re-send it by itself.
  ///
  /// This state exists because [failed] is a claim and this is not one. A
  /// `failed` bubble is told to be pressed, and the thread's own startup flush
  /// presses it for the user: both turn «we do not know» into a second copy of a
  /// message the server may already have. The only honest thing is to hold the
  /// message, say so, and settle it against the next read that actually lands.
  unconfirmed,
}

/// A single chat message (text or image).
class Message {
  /// Server id, or a negative local id for a bubble this device drew that the
  /// server has not stored yet — negative so it can never collide with a row.
  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final String? imageUrl;
  final MessageType type;
  final int isRead;

  /// Server `created_at` — drives the day dividers and the clock under the
  /// bubble. For a queued bubble it is the phone's own time, which is the best
  /// answer available until the server confirms one.
  final DateTime? createdAt;

  /// See [SendState]. Server payloads are always `sent`.
  final SendState sendState;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.imageUrl,
    required this.type,
    required this.isRead,
    this.createdAt,
    this.sendState = SendState.sent,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    // An unreadable `message_type` is a **text** message. The alternatives were
    // dropping the row (the words are perfectly readable) or inventing a
    // type; text is what an absent type means anyway, and a row the user can
    // read beats a correct label on a row nobody sees.
    final t = _wireText(json['message_type']);
    return Message(
      id: _int(json['id']),
      conversationId: _int(json['conversation_id']),
      senderId: _int(json['sender_id']),
      // **Not trimmed, and never flattened.** `threadHolds` compares these
      // words against the ones this phone sent, byte for byte, to decide
      // whether a message whose answer never arrived is on the server. A
      // trimmed read would break delivery detection and re-send a delivered
      // message; a flattened read would let a number claim to be words
      // somebody wrote — the `null == null` lie `thread_match.dart` exists to
      // end. So the server's bytes, or nothing at all.
      content: _verbatimText(json['content']),
      // Blank is absent: `chat_screen` draws the picture branch on
      // `imageUrl != null`, so `''` and `'   '` reached the image widget as a
      // URL to fetch.
      imageUrl: _verbatimText(json['image_url']),
      type: t == 'image'
          ? MessageType.image
          : t == 'quote'
              ? MessageType.quote
              : t == 'system'
                  ? MessageType.system
                  : MessageType.text,
      isRead: _nullableInt(json['is_read']) ?? 0,
      createdAt: parseServerTime(json['created_at']),
    );
  }

  /// A copy with the delivery state — and, when the server row arrives without
  /// a timestamp, the local clock already on screen — swapped in.
  Message copyWith({DateTime? createdAt, SendState? sendState}) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        content: content,
        imageUrl: imageUrl,
        type: type,
        isRead: isRead,
        createdAt: createdAt ?? this.createdAt,
        sendState: sendState ?? this.sendState,
      );
}

// ---- reading the payload, not casting it -----------------------------------
//
// Four readers, one rule: **an unreadable field is a missing field.** Nothing
// here throws, because every caller of `fromJson` is a list of conversations or
// a list of messages, and one row the app cannot read must not become a hole in
// a conversation.

/// An integer column, tolerant of the two shapes D1 really answers with.
///
/// `_asInt` in `data/repository.dart` names them: a number from a JSON body, a
/// string from SQLite. A `sender_id` read as `'30'` used to throw and take the
/// whole row with it. A numeric string parses; anything else is 0 — and 0 on
/// `id`/`conversation_id` is a row nobody should draw, which is visible, rather
/// than a crash that also drew nothing.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// An integer that stays null when the field is absent or unreadable, so a
/// missing count never becomes a printed zero or a drawn «غير مقروء» badge.
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A wire value as text, for a **key** column: an id, a type name.
///
/// `'${json['id']}'` prints the literal «null» for an absent id, and that
/// string is what gets POSTed back and compared against. Flattening keeps the
/// old tolerance — any shape becomes text — minus the null.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Copy, trimmed, or null when absent/empty/not a string.
///
/// Trimming is right for a **label** (a title, a preview): a name that is only
/// spaces is no name, and the screen has a standard answer for «no name»
/// already. Copy that is not copy is not flattened into digits the user would
/// read as a message.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}

/// Copy kept **exactly** as the server sent it, or null when it is not a
/// string or is only whitespace.
///
/// This is the one reader whose discipline is load-bearing. [content] and
/// [imageUrl] take part in an exact comparison in `threadHolds` and in a
/// `!= null` branch in `chat_screen`, so a trimmed read would change a
/// delivery verdict and an empty string would fetch a picture from the URL
/// ''. Everything is preserved; only the unusable is dropped.
String? _verbatimText(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value;
}
