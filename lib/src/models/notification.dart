// The notification model reads the server's JSON instead of casting it, and
// the reason is the same one that moved `chat.dart` off its casts — plus one
// thing this screen adds on top.
//
// `repository._rows` turns a model `TypeError` into an `ApiException` and
// **drops the row**. A chat row that is lost is one message missing from a
// thread; a notification row that is lost is **not shown at all**, so the
// unread badge counts fewer than the server holds. The user is told «لا
// إشعارات جديدة» — "nothing new" — while a quote he is waiting for is sitting
// in the database. That is a quieter and a worse failure than the chat one,
// because nothing on the screen is broken-looking; the screen simply lies.
//
// Four wrong shapes are real here, not invented:
//
//   * **a column as a string.** `_asInt` in `data/repository.dart` says it in
//     its own doc comment — "a null from a LEFT JOIN, a string from SQLite".
//     D1 hands back strings.
//   * **copy that is not copy.** `json['x'] as String?` succeeds on a `String`
//     and on `null` and throws on everything else — an int, a map, a list.
//   * **a body the server wrote as a number.** `review_received` is sent by the
//     Worker as a bare `5/5`; a column that holds a plain score arrives as an
//     int, and `as String?` takes the whole row down over it.
//   * **a `link` that is not a string.** `link` is the routing input — see
//     [notificationTarget] — so a link that cannot be read must become `none`
//     and let the type's fallback place the row, never a crash.
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
        // A count, not a claim: an id the phone cannot read is 0 and the row
        // sorts first, which is visible. `as int` used to throw and take the
        // whole centre with it, and `markNotificationsRead` POSTs these ids
        // back — so a number SQLite sent as `'15'` must arrive as 15 or the
        // write marks nothing.
        id: _int(json['id']),
        // `type` is a **key**: `NotificationLook.of` answers a key it has never
        // heard of with «إشعار» and `notificationTarget` answers one with the
        // type's own destination. So an unreadable type is flattened by its own
        // text — «42» is a key that maps to the fallback look and to `none`,
        // both of which are honest. It must not become '', which would be
        // indistinguishable from a row the server sent without a type.
        type: _wireText(json['type']),
        // The headline the screen does **not** draw: `notification_copy.dart`
        // replaces it with Arabic copy per type, because a developer key or a
        // server-supplied sentence is not the app's voice. It is kept because
        // it is part of the row, and read as text rather than cast so an
        // unreadable one is empty instead of a lost row.
        title: _text(json['title']) ?? '',
        // Copy. `notificationBodyCopy` already has an answer for an absent body
        // — type-aware, «افتح الرسائل للاطلاع عليها» for a new message — so an
        // unreadable body must be *absent* so that answer is reached. A
        // flattened number would print «5» where a sentence should be.
        body: _text(json['body']),
        // A routing key, and blank-is-absent for the same reason `chat.dart`
        // says it is for `image_url`: `notificationTarget` treats a non-null
        // link as the exact destination, so a whitespace-only link must not
        // reach it as a path it will try to parse.
        link: _text(json['link']),
        // A flag the badge is built on, so it is read rather than cast:
        // `'0'`/`'1'` as strings from SQLite are the answer the server meant,
        // and `as num?` used to throw on them and take the whole centre down.
        //
        // **The absent case keeps the old default of 0 on purpose.** It is a
        // real fork — 0 paints the gold «جديد» pip on a row the app cannot
        // prove is unread, 1 hides a genuinely new one — and picking either is
        // a product decision about which lie to tell, not a shape fix. So it
        // stays as it has always behaved, unchanged, and the fork is recorded
        // in IMPROVEMENT_BACKLOG.md for PRODUCT to settle rather than settled
        // by a refactor nobody asked for.
        isRead: _nullableInt(json['is_read']) ?? 0,
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

// ---- reading the payload, not casting it -----------------------------------
//
// The same four readers `chat.dart` keeps, and deliberately the same rules:
// these two files are read together, and a fifth version of "how do we read a
// column" in a codebase is how the two drift apart. What is *not* copied is
// the tolerance: every one of them is private to its file, so this one cannot
// import the other's.

/// An integer column, tolerant of the two shapes D1 really answers with.
///
/// `_asInt` in `data/repository.dart` names them: a number from a JSON body, a
/// string from SQLite. 0 when neither — and 0 on `id` is a row that sorts to
/// the top and is plainly wrong, which beats a crash that shows nothing.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// An integer that stays null when the field is absent or unreadable, so the
/// caller must choose a default instead of inheriting one by accident.
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A wire value as text, for a **key** column: a type name.
///
/// Interpolation prints the literal «null» for an absent key, and «null» is a
/// string the routing rule and the look table have never heard of — the same
/// place an unreadable key lands, so the fallback is what an absent one gets.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Copy, trimmed, or null when absent/empty/not a string.
///
/// No flattening: a number is not a sentence somebody wrote, and every caller
/// here already has the Arabic answer for «there is nothing here».
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
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
