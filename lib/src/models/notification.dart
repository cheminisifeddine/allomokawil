/// Push-style notification delivered to a user.
class AppNotification {
  final int id;
  final String type;
  final String title;
  final String? body;
  final String? link;
  final int isRead;

  /// When the event happened. Null when the server sent no timestamp — the
  /// screen then renders no time rather than a wrong one.
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.link,
    required this.isRead,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        link: json['link'] as String?,
        isRead: (json['is_read'] as num?)?.toInt() ?? 0,
        createdAt: parseServerTime(json['created_at']),
      );

  /// Same notification, marked read — lets the list answer a tap before the
  /// server round-trip finishes.
  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        link: link,
        isRead: 1,
        createdAt: createdAt,
      );
}

/// Parses a server timestamp.
///
/// D1 writes `created_at` in UTC as `YYYY-MM-DD HH:MM:SS`. Dart would read
/// that string as local time, so the offset is pinned to UTC before the value
/// is converted for display — otherwise every time is off by the timezone.
DateTime? parseServerTime(Object? raw) {
  if (raw is! String || raw.isEmpty) {
    return null;
  }
  final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final zoned = (iso.endsWith('Z') || iso.contains('+')) ? iso : '${iso}Z';
  return DateTime.tryParse(zoned)?.toLocal();
}
