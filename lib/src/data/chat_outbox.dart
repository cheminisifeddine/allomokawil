// The phone's own queue of chat messages the server has not stored yet.
//
// Why this exists: a failed send used to live only inside the open ChatScreen —
// a list in memory, gone the moment the user tapped back or Android killed the
// app in the background. The client who typed «العنوان: حسين داي» on a dead
// connection lost the message with no trace: it never reached the contractor,
// and nothing in the app ever said so again. On an Algerian 3G connection that
// is the difference between "the app works" and "the app ate my message".
//
// So a message is written down *before* its first network attempt: the queue is
// one JSON string in `SharedPreferences` (the store the session and the
// onboarding flag already use), it survives leaving the thread and a cold
// start, and the record is removed the moment the server confirms a row.
// Nothing here is a second copy of the thread — only what this device owes.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat.dart';

/// The one preferences key the outbox owns.
const String chatOutboxKey = 'chat.outbox';

/// How many unanswered messages one device holds. Past this the oldest record
/// is dropped: sixty sends the server has refused for days is an account
/// problem, not a queue problem, and a preferences blob must stay bounded.
const int chatOutboxMax = 60;

/// One message this device took responsibility for and the server has not
/// stored yet.
class PendingMessage {
  /// Device-local id, `conversationId.micros.seq`. It is a string precisely so
  /// it can never be confused with a server id (an int, positive) or with the
  /// negative id of the bubble drawn on screen.
  final String id;

  final int conversationId;

  /// What the user typed, or null for a photo.
  final String? text;

  /// Absolute path of a photo that has not been uploaded yet, or null.
  final String? imagePath;

  final DateTime createdAt;

  /// Why this record is still here. `null` — the default and the only value an
  /// old stored row can have — means «the server refused it», which is a fact:
  /// the thread is free to re-send it whenever the network is back.
  ///
  /// [SendState.unconfirmed] is the other case, and it is the one this field was
  /// added for. A request that left the phone with no answer back may already be
  /// stored, so re-sending it on the next thread open is not a retry — it is a
  /// second copy of the same message. Persisting the reason is what stops the
  /// cold start from doing exactly what the network layer refused to do.
  final SendState? uncertain;

  const PendingMessage({
    required this.id,
    required this.conversationId,
    this.text,
    this.imagePath,
    required this.createdAt,
    this.uncertain,
  });

  bool get isImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasText => text != null && text!.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'conversation_id': conversationId,
        if (text != null) 'text': text,
        if (imagePath != null) 'image_path': imagePath,
        // Epoch millis, UTC: a stored queue must not drift if the phone's
        // timezone changes between two opens.
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        if (uncertain != null) 'uncertain': uncertain!.name,
      };

  /// Reads one stored row, or `null` when it cannot describe a message.
  ///
  /// A queue must never throw on a corrupt byte: a malformed row is dropped and
  /// the rest of the queue still loads. Same defence as the session restore in
  /// `core/security/auth_state.dart` — the app opens with what it can trust.
  static PendingMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final conv = raw['conversation_id'];
    final stamp = raw['created_at'];
    if (id is! String || id.isEmpty) return null;
    if (conv is! num || stamp is! num) return null;
    final text = raw['text'] is String ? raw['text'] as String : null;
    final image =
        raw['image_path'] is String ? raw['image_path'] as String : null;
    final hasText = text != null && text.isNotEmpty;
    final hasImage = image != null && image.isNotEmpty;
    // A bubble with neither words nor a picture is not a message.
    if (!hasText && !hasImage) return null;
    // Only `unconfirmed` is stored, and only when it is that exact name: a
    // value this build does not recognise must read as «not certain», which
    // keeps the record and stops the auto-send. Guessing the other way would
    // put a possibly-delivered message back on the wire.
    final rawUncertain = raw['uncertain'];
    final uncertain = rawUncertain is String &&
            rawUncertain == SendState.unconfirmed.name
        ? SendState.unconfirmed
        : null;
    return PendingMessage(
      id: id,
      conversationId: conv.toInt(),
      text: hasText ? text : null,
      imagePath: hasImage ? image : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(stamp.toInt(), isUtc: true)
              .toLocal(),
      uncertain: uncertain,
    );
  }
}

/// Reads a stored queue. Accepts the raw preferences value (a JSON string) or an
/// already-decoded list, and answers an empty queue for anything else — never
/// throws, because a queue that cannot be read must not stop a thread opening.
List<PendingMessage> decodeOutbox(Object? raw) {
  Object? decoded = raw;
  if (raw is String) {
    if (raw.isEmpty) return <PendingMessage>[];
    try {
      decoded = jsonDecode(raw);
    } catch (error) {
      debugPrint('outbox: stored queue is not JSON, dropped ($error)');
      return <PendingMessage>[];
    }
  }
  if (decoded is! List) return <PendingMessage>[];
  final items = <PendingMessage>[];
  for (final row in decoded) {
    final message = PendingMessage.fromJson(row);
    if (message != null) items.add(message);
  }
  return items;
}

/// Serialises a queue. Kept beside [decodeOutbox] so the two are tested as one
/// round trip.
String encodeOutbox(List<PendingMessage> items) =>
    jsonEncode(<Map<String, dynamic>>[
      for (final m in items) m.toJson(),
    ]);

/// Where the queue lives. An interface so a test — or any future caller that
/// must not touch the disk — can hold it in memory.
abstract class OutboxStore {
  Future<Object?> read();
  Future<void> write(String raw);
}

/// The real store: one string key in `SharedPreferences`.
class PrefsOutboxStore implements OutboxStore {
  const PrefsOutboxStore();

  @override
  Future<Object?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.get(chatOutboxKey);
    } catch (error) {
      // A store that will not open means "nothing queued", not a crash.
      debugPrint('outbox: cannot read the queue ($error)');
      return null;
    }
  }

  @override
  Future<void> write(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(chatOutboxKey, raw);
  }
}

/// In-memory store: used by tests, and by any caller that must not persist.
class MemoryOutboxStore implements OutboxStore {
  MemoryOutboxStore([this.raw]);

  Object? raw;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async => raw = value;
}

/// The device-local send queue.
class ChatOutbox {
  ChatOutbox({OutboxStore? store, DateTime Function()? clock})
      : _store = store ?? const PrefsOutboxStore(),
        _clock = clock ?? DateTime.now;

  final OutboxStore _store;
  final DateTime Function() _clock;

  /// Microsecond ticks can repeat; this counter keeps two messages typed in the
  /// same tick apart.
  static int _seq = 0;

  Future<List<PendingMessage>> all() async => decodeOutbox(await _store.read());

  /// Everything still owed to thread [conversationId], oldest first, so the
  /// thread can be redrawn in the order it was written.
  Future<List<PendingMessage>> pendingFor(int conversationId) async => [
        for (final m in await all())
          if (m.conversationId == conversationId) m,
      ];

  /// How many messages each conversation is still owed — this is what the inbox
  /// badge counts, so a user who leaves the thread can still see that his words
  /// are on the phone.
  Future<Map<int, int>> countsByConversation() async {
    final counts = <int, int>{};
    for (final m in await all()) {
      counts[m.conversationId] = (counts[m.conversationId] ?? 0) + 1;
    }
    return counts;
  }

  /// Writes one message down and returns the record that now owns it.
  Future<PendingMessage> add({
    required int conversationId,
    String? text,
    String? imagePath,
    SendState? uncertain,
  }) async {
    final at = _clock();
    final record = PendingMessage(
      id: '$conversationId.${at.toUtc().microsecondsSinceEpoch}.${_seq++}',
      conversationId: conversationId,
      text: text,
      imagePath: imagePath,
      createdAt: at,
      uncertain: uncertain,
    );
    final items = await all();
    items.add(record);
    while (items.length > chatOutboxMax) {
      items.removeAt(0);
    }
    await _write(items);
    return record;
  }

  /// Records *why* a message is still queued, so a cold start does not re-send
  /// a request the server may already have stored.
  ///
  /// Pass [uncertain] to mark the record as «the answer never came»; pass null
  /// to clear it, which is what a re-read that came back empty does — at that
  /// point the message is known to be absent and re-sending it is a normal
  /// retry again. An unknown id is not an error: the record may already have
  /// been forgotten, and the state that matters is then already correct.
  Future<void> markUncertain(String id, {SendState? uncertain}) async {
    final items = await all();
    final at = items.indexWhere((m) => m.id == id);
    if (at < 0) return;
    if (items[at].uncertain == uncertain) return;
    final next = List<PendingMessage>.of(items);
    next[at] = PendingMessage(
      id: items[at].id,
      conversationId: items[at].conversationId,
      text: items[at].text,
      imagePath: items[at].imagePath,
      createdAt: items[at].createdAt,
      uncertain: uncertain,
    );
    await _write(next);
  }

  /// Forgets one message: called the moment the server stores it, and when a
  /// queued photo's file is gone and it can never be sent.
  Future<void> remove(String id) async {
    final items = await all();
    final kept = <PendingMessage>[
      for (final m in items)
        if (m.id != id) m,
    ];
    if (kept.length == items.length) return;
    await _write(kept);
  }

  /// Drops the whole queue. Signing out of a device must not leave someone
  /// else's unsent messages sitting on it.
  Future<void> clear() async => _write(<PendingMessage>[]);

  /// A store that refuses the write leaves a degraded queue — a message that is
  /// only on the screen — but never a failed send: the bubble keeps its text and
  /// its retry line.
  Future<void> _write(List<PendingMessage> items) async {
    try {
      await _store.write(encodeOutbox(items));
    } catch (error) {
      debugPrint('outbox: cannot persist the queue ($error)');
    }
  }
}

/// How many messages are still only on this phone, in the form Arabic counts
/// with: the singular for one, the dual for two, the plural for three to ten,
/// and the counted singular again from eleven up.
String queuedCountLabel(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'لم تُرسل بعد';
  if (n == 2) return 'رسالتان لم تُرسلا';
  if (n <= 10) return '$n رسائل لم تُرسل';
  return '$n رسالة لم تُرسل';
}
