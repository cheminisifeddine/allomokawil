/// Push-style notification delivered to a user.
class AppNotification {
  final int id;
  final String type;
  final String title;
  final String? body;
  final String? link;
  final int isRead;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.link,
    required this.isRead,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        link: json['link'] as String?,
        isRead: (json['is_read'] as num?)?.toInt() ?? 0,
      );
}