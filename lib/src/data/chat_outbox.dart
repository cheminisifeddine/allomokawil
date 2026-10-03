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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/arabic_agreement.dart';
import '../core/text/clip.dart';
import '../models/chat.dart';

/// The one preferences key the outbox owns.
const String chatOutboxKey = 'chat.outbox';

/// How many unanswered messages one device holds. Past this the oldest record
/// is dropped: sixty sends the server has refused for days is an account
/// problem, not a queue problem, and a preferences blob must stay bounded.
///
/// The bound is real, but dropping a message is **not** a free bookkeeping
/// decision: the record holds the user's own words — most often the one line
/// that matters, «العنوان: حسين داي». So [ChatOutbox.add] reports the record it
/// had to drop instead of losing it in silence, and the caller shows it. A queue
/// that eats a message quietly is the very failure this file exists to prevent
/// (see the header), reproduced at a larger scale.
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

  /// The R2 URL this picture's upload returned, once it has — or null if the
  /// upload has not answered, or never did.
  ///
  /// This is the *only* thing that can identify a photo in a re-read of the
  /// thread, because that read returns the server's URL while [imagePath] is a
  /// path on this phone. The two are different namespaces and can never be
  /// equal, and the comparison that used to stand in for them (`null == null`
  /// on `content`) matched every picture with every other picture. Persisting
  /// the URL is what makes «did my photo arrive?» answerable on the **next**
  /// launch, which is the launch that matters: the cold start is the one with no
  /// upload in flight and therefore no chance to learn the URL again.
  ///
  /// Null is a real answer, not a gap: it means the upload's own request never
  /// came back, so there is no row this device can claim to have sent.
  final String? uploadedUrl;

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
    this.uploadedUrl,
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
        if (uploadedUrl != null) 'uploaded_url': uploadedUrl,
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
    // An absent or empty `uploaded_url` is the same answer as an absent
    // `image_path`: this picture has no server-side identity, so it must not be
    // claimed as delivered. Reading it as anything else would re-open the exact
    // hole this field closes.
    final uploaded = raw['uploaded_url'] is String
        ? raw['uploaded_url'] as String
        : null;
    final hasUploaded = uploaded != null && uploaded.isNotEmpty;
    return PendingMessage(
      id: id,
      conversationId: conv.toInt(),
      text: hasText ? text : null,
      imagePath: hasImage ? image : null,
      uploadedUrl: hasUploaded ? uploaded : null,
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
    // `setString` answers whether the platform actually stored the value, and
    // this method used to throw that answer away. The plugin's own docs call
    // the result a bool for a reason: a full disk, a revoked storage grant or a
    // rejected commit comes back as **false**, not as a throw — so a write that
    // never reached the disk used to look exactly like one that did, and the
    // caller had no way to tell the two apart.
    final stored = await prefs.setString(chatOutboxKey, raw);
    if (!stored) {
      throw StateError('preferences refused to store the queue');
    }
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
  ///
  /// [lastDropped] carries the record the bound pushed out, if any. It is a
  /// field rather than a return value because the caller already needs the
  /// record it just wrote; a caller that ignores it keeps the old behaviour, so
  /// no existing caller breaks and nothing is lost on the way in.
  Future<PendingMessage> add({
    required int conversationId,
    String? text,
    String? imagePath,
    SendState? uncertain,
  }) async {
    // Inside the lock, and the lock covers the *read* as well as the write.
    // The whole read-modify-write has to be one step, or the fix is theatre:
    // a lock that only wrapped `_write` would still let two callers read the
    // same old blob and each hand `_write` a queue missing the other's row.
    return _serialised(() async {
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
      PendingMessage? dropped;
      while (items.length > chatOutboxMax) {
        dropped = items.removeAt(0);
      }
      final landed = await _write(items);
      // Reported only when the write landed, and both fields together, because
      // the same fact decides them. If the store refused, the queue on the disk
      // is still the *old* one: the record that was evicted never left, and
      // this one never arrived. Reporting the eviction anyway told the user a
      // message was deleted when nothing was — and returning the record anyway
      // let the screen promise the opposite, «محفوظة في الهاتف», for a record
      // the phone does not have.
      lastDropped = landed ? dropped : null;
      lastPersisted = landed;
      return record;
    });
  }

  /// The record the bound pushed off the queue during the last [add], or null.
  PendingMessage? lastDropped;

  /// Whether the queue the last [add] built actually reached the disk.
  ///
  /// True in every ordinary case, and false in exactly one: the device would
  /// not take the write. The outbox is a *promise of durability* — the whole
  /// file exists so a user who typed an address into a dead connection can
  /// close the app and find it still there — so a caller that draws a
  /// "your words are safe on this phone" line off an unconfirmed write is
  /// stating the one thing the phone does not know. Read it immediately after
  /// [add]; it is a field rather than a return value for the same reason
  /// [lastDropped] is, and it is reset by every [add], so a stale `true` from
  /// an earlier send cannot be mistaken for this one.
  bool lastPersisted = true;

  /// Records *why* a message is still queued, so a cold start does not re-send
  /// a request the server may already have stored.
  ///
  /// Pass [uncertain] to mark the record as «the answer never came»; pass null
  /// to clear it, which is what a re-read that came back empty does — at that
  /// point the message is known to be absent and re-sending it is a normal
  /// retry again.
  ///
  /// **Answers whether the mark is now on the disk**, because this one field is
  /// the only thing standing between a cold start and a duplicate. The whole
  /// duplicate-protection design is a single persisted word: [add] writes a
  /// record the server refused, and *this* method writes «do not send me
  /// again» onto it the moment a write's answer is lost. Both directions were
  /// decided by throwing [ChatOutbox._write]'s answer away, and both were
  /// silent:
  ///
  ///  * **the mark is refused** — the record on the disk still reads «safe to
  ///    re-send», the screen's own bubble says otherwise only until the app
  ///    dies, and the next thread open hands the words to [_flushQueued]'s
  ///    auto-send with no user action at all. The server may already hold that
  ///    row: the mark exists *because* nobody knows. The user gets a second
  ///    copy of his own address.
  ///  * **the clear is refused** — the record still says «unconfirmed» for a
  ///    message a re-read just proved is absent, so it comes back after a
  ///    restart with no retry affordance and the startup flush skips it. The
  ///    message is stranded: not on the server, not resendable, and the user
  ///    has to retype his own words.
  ///
  /// So this answers, and the caller is expected to act on a false. The two
  /// paths that find nothing to do are both true, and deliberately so, because
  /// in each the disk already holds the state that protects the user: an id
  /// that is not in the queue cannot be re-sent by anything (it is not on the
  /// disk to be read back), and a record that already carries the requested
  /// mark needs no write. A store is not consulted in either case, so a
  /// declining device costs nothing here.
  ///
  /// Never throws, like every other write in this file: a refused mark is a
  /// duplicate *or* a stranded message, and neither is worth a red screen over
  /// a conversation the user can still read.
  Future<bool> markUncertain(String id, {SendState? uncertain}) async {
    // The lookup is *inside* the lock, for the reason [remove] states: a mark
    // computed from a queue read before the lock is a decision about a queue
    // that may no longer be the one on the disk, and it writes that stale view
    // back over the newer one.
    return _serialised(() async {
      final items = await all();
      final at = items.indexWhere((m) => m.id == id);
      // Nothing in the queue carries this id, so nothing on the disk can be
      // re-sent on the user's behalf: the invariant this method protects holds
      // without a write, and there is nothing to tell the user about.
      if (at < 0) return true;
      // Already the state being asked for — the reason this record is still
      // here has not changed, so the disk is correct and untouched.
      if (items[at].uncertain == uncertain) return true;
      final next = List<PendingMessage>.of(items);
      next[at] = PendingMessage(
        id: items[at].id,
        conversationId: items[at].conversationId,
        text: items[at].text,
        imagePath: items[at].imagePath,
        // Carried forward, never re-derived: a record rebuilt without it would
        // quietly drop the picture's only server-side identity, and the next
        // re-read would conclude the picture never arrived — after the very send
        // that this mark was written to protect.
        uploadedUrl: items[at].uploadedUrl,
        createdAt: items[at].createdAt,
        uncertain: uncertain,
      );
      return _write(next);
    });
  }

  /// Records the R2 URL [url] for the picture in [id], so a later re-read of
  /// the thread can tell this device's picture from every other one.
  ///
  /// Written the moment the upload answers and before the message row is
  /// posted, because that is the only window in which the URL exists anywhere on
  /// the phone and the app could not survive losing it: a re-read after a cold
  /// start has no upload in flight to ask. Answers whether it reached the disk
  /// for the same reason [markUncertain] does — a store that refuses this write
  /// leaves the picture unidentifiable, and the caller decides what to say.
  ///
  /// Never throws, like every other write here.
  Future<bool> noteUploadedUrl(String id, String url) async {
    if (url.isEmpty) return true; // nothing learned: the disk is already right
    return _serialised(() async {
      final items = await all();
      final at = items.indexWhere((m) => m.id == id);
      // Not in the queue. The record is gone, so nothing on the disk can be
      // re-sent or re-checked against this write, and the bubble that owned it
      // is about to be replaced by the server's own row.
      if (at < 0) return true;
      if (items[at].uploadedUrl == url) return true;
      final next = List<PendingMessage>.of(items);
      next[at] = PendingMessage(
        id: items[at].id,
        conversationId: items[at].conversationId,
        text: items[at].text,
        imagePath: items[at].imagePath,
        uploadedUrl: url,
        createdAt: items[at].createdAt,
        uncertain: items[at].uncertain,
      );
      return _write(next);
    });
  }

  /// Forgets one message: called the moment the server stores it, and when a
  /// queued photo's file is gone and it can never be sent.
  Future<void> remove(String id) async {
    // Locked for the same reason [add] is: a forget that interleaves with a
    // send would write back a queue the send never saw, and the record for the
    // message the user is *right now* typing would be the one that disappears.
    return _serialised(() async {
      final items = await all();
      final kept = <PendingMessage>[
        for (final m in items)
          if (m.id != id) m,
      ];
      if (kept.length == items.length) return;
      await _write(kept);
    });
  }

  /// Drops the whole queue. Signing out of a device must not leave someone
  /// else's unsent messages sitting on it.
  Future<void> clear() async =>
      _serialised(() async => _write(<PendingMessage>[]));

  /// Runs [body] with exclusive access to the queue, and hands the previous
  /// one's slot straight to it.
  ///
  /// **The lock is per-key and static, not per-object, and that is the whole
  /// point.** The app builds more than one [ChatOutbox] over the same
  /// `SharedPreferences` key: `AuthState` owns one for sign-out,
  /// `ChatListScreen` builds another for the inbox badges
  /// (`chat_list_screen.dart:64`) and passes it down, and `ChatScreen` uses
  /// whichever it is handed. An instance lock would have serialised one object
  /// against itself and let two objects interleave exactly as before — the
  /// race survives a per-instance fix untouched, which is why the lock is
  /// keyed by [chatOutboxKey] instead.
  ///
  /// A single slot rather than a queue of futures, because the only thing that
  /// must not interleave is the read-modify-write; there is no fairness to
  /// promise and no starvation to fear at this rate of traffic.
  static final Map<String, Future<void>> _locks = <String, Future<void>>{};

  Future<T> _serialised<T>(Future<T> Function() body) {
    final previous = _locks[chatOutboxKey] ?? Future<void>.value();
    final completer = Completer<void>();
    _locks[chatOutboxKey] = completer.future;
    return () async {
      // Awaited for its completion, not its value: if the previous holder
      // threw, `previous` is a failed future and awaiting its *result* would
      // throw here too — in a method that has not even started yet, in a
      // queue that would then be wedged shut for every later send.
      try {
        await previous;
      } catch (_) {
        // The previous holder already reported its own failure; the queue is
        // still on disk and this one is a normal read-modify-write.
      }
      try {
        return await body();
      } finally {
        // Released even when the body throws: one failed send must not wedge
        // every later one behind a lock nobody will ever take off.
        if (identical(_locks[chatOutboxKey], completer.future)) {
          // `Map<String, Future<void>>.remove` *returns* the entry it dropped,
          // which is the discarded future `unawaited_futures` fires on here.
          // The value is deliberately dropped -- the entry is being retired,
          // not waited on -- and the guard stays exactly as it was: only the
          // holder that owns the lock releases it.
          unawaited(_locks.remove(chatOutboxKey));
        }
        completer.complete();
      }
    }();
  }

  /// Stores [items], and answers whether they are now on the disk.
  ///
  /// A refusal is still not a failed *send* — the bubble keeps its text and its
  /// retry line, which is why this has always been swallowed here. What it used
  /// to do as well is swallow the distinction between "written" and "not
  /// written", and that distinction is the one the user needs. The write is the
  /// last statement on the send path, so a store that refuses it cannot unwind
  /// anything the user can see — but it can absolutely make a promise on their
  /// behalf, and the screen is told which one to make.
  Future<bool> _write(List<PendingMessage> items) async {
    try {
      await _store.write(encodeOutbox(items));
      return true;
    } catch (error) {
      debugPrint('outbox: cannot persist the queue ($error)');
      return false;
    }
  }
}

/// What the user is told when the bound pushed an old message off the queue.
///
/// Silence is not an option here: the record is gone, and it was his own words.
/// A photo is named by its own fact (a file the phone no longer has is easy to
/// explain); a text message quotes itself, so he can see *which* line was lost
/// and retype it. Kept short, because it arrives as a toast over a thread he is
/// trying to read.
String droppedMessageCopy(PendingMessage dropped) => dropped.isImage
    ? 'امتلأت قائمة الانتظار — حُذفت أقدم صورة لم تُرسل. أعد إرسالها.'
    : 'امتلأت قائمة الانتظار — حُذفت أقدم رسالة: «${_clip(dropped.text ?? '')}»';

/// Keeps a quoted line readable in a toast. The queue holds a whole sentence —
/// sometimes a paragraph of address and directions — and a toast that runs the
/// height of the thread is its own kind of noise.
///
/// **Rune-safe, and this is the one place a user is guaranteed to see it.** The
/// cut used to be `flat.substring(0, max)`, which counts UTF-16 code units, so
/// an emoji sitting on the boundary was sliced in half and the toast quoted the
/// user back an orphaned half rendered as U+FFFD («�») — in the exact sentence
/// telling them which message was just lost. Measured on 3 Oct: an emoji whose
/// first code unit lands at index 59 is enough.
///
/// Both halves are counted in **runes**: the `runes.length` test decides whether
/// anything is cut at all, and `TextClip.chars` does the cutting. Counting the
/// test in code units would clip a 30-emoji line that fits in 60 characters.
String _clip(String text, [int max = 60]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.runes.length <= max) return flat;
  return '${TextClip.chars(flat, max)}…';
}

/// How many messages are still only on this phone, in the form Arabic counts
/// with: the singular for one, the dual for two, the plural for three to ten,
/// and the counted singular again from eleven up.
///
/// The agreement is [arabicCounted]'s. The one case written out here rather
/// than handed to it is 1: the count is not part of that sentence at all —
/// «لم تُرسل بعد» names the state, and «رسالة واحدة لم تُرسل» would name a
/// number the sentence never used.
String queuedCountLabel(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'لم تُرسل بعد';
  if (n == 2) return 'رسالتان لم تُرسلا';
  return '${arabicCounted(n, 'رسالة', two: 'رسالتان', few: 'رسائل')} لم تُرسل';
}
