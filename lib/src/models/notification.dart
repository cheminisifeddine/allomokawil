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

/// Where a notification tap should land — the rule on its own, with no widget
/// attached, so it can be tested without pumping a screen.
class NotificationTarget {
  /// One of `project`, `chat`, `inbox`, `projects`, `profile`, `none`.
  final String kind;

  /// The project id or conversation id when the target names one.
  final String? id;

  const NotificationTarget(this.kind, [this.id]);

  bool get isNone => kind == 'none';

  @override
  String toString() => id == null ? kind : '$kind:$id';
}

/// The destination for one notification row.
///
/// The founder's report, verbatim — «when i get a notification they are not
/// clickble when i click on them nothing happens fix it» — was a routing hole,
/// not a rendering bug: the server sends `link: null` for a new message, for a
/// published project and for a fresh review, and the screen dropped every link
/// it did not recognise. Most rows were therefore dead on tap. This reads the
/// link first (it names an exact row) and falls back to the notification's own
/// type, so every row the server can send has somewhere to go.
NotificationTarget notificationTarget(String? type, String? link) {
  final l = link ?? '';
  final project = RegExp(r'projects/([A-Za-z0-9_-]+)').firstMatch(l)?.group(1);
  if (project != null) {
    return NotificationTarget('project', project);
  }
  final chat = RegExp(r'chat/(\d+)').firstMatch(l)?.group(1);
  if (chat != null) {
    return NotificationTarget('chat', chat);
  }
  if (l.contains('profile')) {
    return const NotificationTarget('profile');
  }
  switch (type) {
    case 'new_message':
      return const NotificationTarget('inbox');
    case 'project_update':
    case 'new_quote':
    case 'quote_received':
    case 'quote_accepted':
      return const NotificationTarget('projects');
    case 'review_received':
      return const NotificationTarget('profile');
  }
  return const NotificationTarget('none');
}
