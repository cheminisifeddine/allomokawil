/// Tolerant timestamp parsing for the API's `yyyy-MM-dd HH:mm:ss` strings.
/// Returns null when the field is absent so older payloads keep working.
DateTime? _parseTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

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
        lastMessageAt: _parseTime(json['last_message_at']),
      );
}

/// Message types supported in chat.
enum MessageType { text, image, quote, system }

/// A single chat message (text or image).
class Message {
  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final String? imageUrl;
  final MessageType type;
  final int isRead;

  /// Server `created_at` — drives the date dividers in the thread.
  /// Null for messages queued offline (they carry no server timestamp).
  final DateTime? createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    this.imageUrl,
    required this.type,
    required this.isRead,
    this.createdAt,
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
      createdAt: _parseTime(json['created_at']),
    );
  }
}