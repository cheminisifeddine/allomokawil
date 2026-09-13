// Chat models: the conversation thread and the messages inside it.
//
// Timestamps come from D1 as `YYYY-MM-DD HH:MM:SS` in UTC with no zone marker,
// so they go through `parseServerTime` (the app's single server-clock parser)
// instead of `DateTime.tryParse`, which would read them as local wall-clock and
// print every message an hour off in Algiers — and file the ones sent after
// 23:00 UTC under the wrong day.
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
        id: json['id'] as int,
        customerId: json['customer_id'] as int,
        workerUserId: json['worker_user_id'] as int,
        projectId: json['project_id']?.toString(),
        otherUserName: (json['other_user_name'] ?? '') as String,
        otherUserAvatar: json['other_user_avatar'] as String?,
        lastMessageContent: json['last_message_content'] as String?,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
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
    final t = (json['message_type'] as String?) ?? 'text';
    return Message(
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int,
      senderId: json['sender_id'] as int,
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      type: t == 'image'
          ? MessageType.image
          : t == 'quote'
              ? MessageType.quote
              : t == 'system'
                  ? MessageType.system
                  : MessageType.text,
      isRead: (json['is_read'] as num?)?.toInt() ?? 0,
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
