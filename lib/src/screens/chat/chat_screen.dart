import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/theme/app_theme.dart';
import '../../data/chat_outbox.dart';
import '../../data/chat_time.dart';
import '../../data/repository.dart';
import '../../models/chat.dart';
import '../../widgets/a11y.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';

/// Thread chat: text + image. A message the server refuses is written to this
/// device's outbox *before* the first attempt, so leaving the thread — or the
/// phone killing the app in the background — cannot lose it. See
/// `lib/src/data/chat_outbox.dart`.
class ChatScreen extends StatefulWidget {
  final int? conversationId;
  final String? projectId;
  final int otherUserId;
  final String otherName;
  final Repository repo;

  /// The queue that keeps an unsent message across a restart. Injectable so a
  /// test can hand in its own store instead of the real preferences file.
  final ChatOutbox? outbox;

  /// How a message's clock is written. Null in the app, which is the point: a
  /// user reads the hour his phone is on, so the thread is drawn in the device's
  /// own zone and never anything else.
  ///
  /// It is a seam, not a feature. [Message.createdAt] arrives already converted
  /// by `parseServerTime`, so the *instant* is right but the *zone* it is
  /// rendered in is whatever machine runs the code — which is why the design
  /// gate could not hold this screen still. `Platform.environment` is an
  /// unmodifiable map, so the zone cannot be repinned from inside a test.
  /// Handing in the formatter makes the rendered hour a property of the test
  /// instead of of the box.
  final String Function(DateTime at)? clockFormat;

  const ChatScreen({
    super.key,
    this.conversationId,
    this.projectId,
    required this.otherUserId,
    this.otherName = '',
    required this.repo,
    this.outbox,
    this.clockFormat,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// True while one send is in flight, so a second tap cannot start a second.
  ///
  /// The composer is emptied only *after* the queue write has taken the words,
  /// because a draft held for the length of a disk write is a draft the app can
  /// still lose to Android killing it. That leaves a window in which the field
  /// still holds the message and the send button is still live, and without
  /// this flag a second tap in it reads the same text and sends it again — the
  /// duplicate this app has an entire phase for killing. The flag closes the
  /// window without giving the durability back.
  bool _sending = false;

  int get _me => AppScope.of(context).auth.user?.id ?? 0;

  int? _convId;
  List<Message> _messages = [];
  bool _loading = true;
  bool _error = false;

  /// Local bubble ids count *down* from -1: a bubble this device drew before the
  /// server answered can never be mistaken for a stored row (real ids are
  /// positive).
  int _nextLocalId = -1;

  /// Bubbles the server refused. They stay in the thread with their text, so
  /// the composer's «إرسال» button can send them again instead of the message
  /// disappearing behind a toast.
  /// The bubbles the app will send again on its own or on a tap.
  ///
  /// [SendState.unconfirmed] is deliberately excluded. It is not a failure the
  /// user can retry — the server may already hold these words — and both callers
  /// of this list would re-send it: the startup flush on every thread open, and
  /// the banner's own «إرسال» button. Excluding it here is what stops a possible
  /// duplicate; [_unresolved] is the list that keeps the user informed instead.
  List<Message> get _unsent =>
      _messages.where((m) => m.sendState == SendState.failed).toList();

  /// Everything the thread still owes an answer about, retryable or not.
  ///
  /// The banner counts these, so a message whose outcome is unknown stays
  /// visible on every screen the user can reach. What the banner must not do is
  /// offer to re-send *that* one, so the wording and the button are driven by
  /// whether anything here is actually retryable.
  /// What the banner is allowed to offer: a real retry, or nothing.
  List<Message> get _retryable => _unsent;

  List<Message> get _unresolved => _messages
      .where((m) =>
          m.sendState == SendState.failed || m.sendState == SendState.unconfirmed)
      .toList();

  /// The queue of messages this device still owes the server. Survives leaving
  /// the thread and a cold start; see `data/chat_outbox.dart`.
  late final ChatOutbox _outbox = widget.outbox ?? ChatOutbox();

  /// Local bubble id -> the queue record behind it, so a confirmed send knows
  /// exactly which record to forget.
  final Map<int, String> _queuedIds = <int, String>{};

  /// Local bubble id -> whether that bubble's record is really on the disk.
  ///
  /// Almost always true, and false only when the device refused the queue
  /// write. It is tracked per bubble rather than per screen because durability
  /// is a property of *that message*: a phone that refused one write can still
  /// have stored an earlier one, so a single screen-wide flag would either lie
  /// about the first message or about the second. Every failure sentence for
  /// this bubble is chosen from it, so no path can promise a copy the phone
  /// does not have.
  final Map<int, bool> _persisted = <int, bool>{};

  /// Whether [bubble]'s words are on the disk. Unknown bubbles — ones restored
  /// from the queue itself — are durable by construction: the record being read
  /// is the proof.
  bool _isPersisted(Message bubble) => _persisted[bubble.id] ?? true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Opens the thread, then redraws and flushes whatever this phone still owes
  /// it.
  ///
  /// The queue is restored whether or not the server answered: a message the
  /// user already wrote has to appear on a dead connection, with its retry line,
  /// instead of being replaced by an error page that hides it.
  Future<void> _bootstrap() async {
    var refused = false;
    try {
      var convId = widget.conversationId;
      convId ??= await widget.repo.openConversation(
        projectId: widget.projectId,
        otherUserId: widget.otherUserId,
      );
      _convId = convId;
      await _load();
    } catch (_) {
      refused = true;
    }
    await _restoreQueued();
    if (!mounted) return;
    setState(() {
      if (refused) _error = true;
      _loading = false;
    });
    _jumpToBottom();
    await _flushQueued();
  }

  /// Puts the stored queue back in the thread, oldest first, each one drawn as a
  /// bubble the server does not have yet — the same shape the user saw when the
  /// send failed, so nothing looks as if it evaporated overnight.
  ///
  /// A queued record the server turns out to already hold is **not** redrawn.
  /// That case is the whole reason [SendState.unconfirmed] exists: the earlier
  /// POST landed and never said so, so the fresh thread already contains those
  /// words, and appending the local bubble would show the user his own message
  /// twice the moment he opens the thread. Such a record is settled against the
  /// read that just happened — adopted as the server's own row, or kept, but in
  /// one copy only.
  Future<void> _restoreQueued() async {
    final convId = _convId;
    if (convId == null) return;
    final pending = await _outbox.pendingFor(convId);
    if (pending.isEmpty || !mounted) return;
    final me = _me;
    setState(() {
      for (final p in pending) {
        // A record whose answer never came may already be stored. If the thread
        // we just read holds the same words from the same person, the server
        // has it: forget the record and draw nothing.
        if (p.uncertain != null) {
          final stored = _messages.any((m) =>
              m.content == p.text && (me <= 0 || m.senderId == me));
          if (stored) {
            _forgetQuietly(p.id);
            continue;
          }
        }
        final bubble = Message(
          id: _nextLocalId--,
          conversationId: convId,
          senderId: _me,
          content: p.text,
          imageUrl: p.imagePath,
          type: p.isImage ? MessageType.image : MessageType.text,
          isRead: 0,
          createdAt: p.createdAt,
          // Not `failed`: a failed record is re-sent the moment this thread
          // opens, and this one may already be on the server. The distinction
          // is the whole point of persisting it.
          sendState: p.uncertain ?? SendState.failed,
        );
        _queuedIds[bubble.id] = p.id;
        _messages = [..._messages, bubble];
      }
    });
  }

  /// One attempt per queued message when the thread opens, without a snackbar
  /// each: an automatic retry is not news, and the bubble's own line already
  /// says what happened to it.
  Future<void> _flushQueued() async {
    for (final m in _unsent) {
      // A message whose answer never came is not a retry candidate. Re-sending
      // it here is the duplicate the network layer refused to create: the
      // server may already hold these words, and this loop would put a second
      // copy of them in the thread with no user action at all.
      if (m.sendState == SendState.unconfirmed) continue;
      await _deliver(m, announce: false);
    }
  }

  /// Writes one bubble into the queue and remembers which record owns it.
  /// Called *before* the first network attempt, which is the whole point.
  ///
  /// Answers whether the record is on the disk. False means the device refused
  /// the write, and it is the one fact the send path needs to be honest about:
  /// [ChatOutbox] deliberately never throws on a refused store so that a storage
  /// failure cannot become a lost message or a red screen, which leaves the
  /// screen as the only place that can still tell the user the truth.
  Future<bool> _enqueue(Message bubble,
      {String? text, String? imagePath}) async {
    final convId = _convId;
    if (convId == null) return false; // no thread yet: nowhere to attach it
    final record = await _outbox.add(
      conversationId: convId,
      text: text,
      imagePath: imagePath,
    );
    _queuedIds[bubble.id] = record.id;
    final landed = _outbox.lastPersisted;
    _persisted[bubble.id] = landed;

    // The queue did not take the write. The record exists only in this State,
    // so the line the failed bubble carries cannot claim the words are safe on
    // the phone, and the retry affordance is the only thing that still works.
    // The screen survives the app being closed; the record does not.
    if (!landed) {
      if (mounted) _toast(S.chatNotSaved);
      return false;
    }

    // The queue is bounded, so at some point it has to forget something. When it
    // does, the user is told *which* message is gone: a dropped line is his own
    // address and his own words, and the bubble he is looking at cannot be the
    // proof, because the record behind it is already deleted.
    final dropped = _outbox.lastDropped;
    if (dropped != null && mounted) {
      _toast(droppedMessageCopy(dropped));
    }
    return true;
  }

  Future<void> _load() async {
    if (_convId == null) return;
    final msgs = await widget.repo.messages(_convId!);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
      _error = false;
    });
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendText() async {
    // Set before the first `await`, which is the whole point: the tap that has
    // to be refused arrives while the queue write is still on the disk, and a
    // flag set after that write would already be too late. A second tap is
    // dropped rather than queued, and the words stay in the composer for the
    // send that is already running to deliver — nothing is lost by refusing it.
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty && _unsent.isEmpty) return;
    _sending = true;
    try {
      await _sendClaimed(text);
    } finally {
      // Released even when the body throws, so one failed send cannot wedge the
      // composer: a bubble the server refused must stay re-sendable.
      _sending = false;
    }
  }

  /// [text] is the composer's content captured on entry, and the composer still
  /// holds it. Everything from here can await, and everything that touches
  /// `context` is still read before the first of those awaits.
  Future<void> _sendClaimed(String text) async {
    // Everything that reads `context` is read **before the first await**.
    // `_localBubble` asks the session who the user is, and that is a `context`
    // lookup — so building the bubble after any await means building it on a
    // State he may have already left, which throws
    // "This widget has been unmounted, so the State no longer has a context".
    // Tapping back is the most ordinary way to end a conversation and the one
    // gesture he makes right after sending, so the window is not theoretical.
    final local = text.isEmpty ? null : _localBubble(text: text);

    // Written down before the first attempt, and before the retries below: if
    // the phone loses the network, the user taps back, or Android kills the app
    // mid-request, the message is still on the device with a way to send it.
    // It has to be first for a second reason. Anything below is a network round
    // trip he can walk away from, and a throw on any of them unwound this whole
    // method — so a message that was only *about to be* written was simply
    // never written. The queue write cannot throw for the same reason it never
    // throws anywhere else: it is the last thing that happens, on data already
    // read, with no `context` involved.
    if (local != null) await _enqueue(local, text: text);

    // Anything the server refused goes next, so the thread keeps its order: the
    // older words reach the server before his new ones, and the bubble for this
    // one is only drawn once they are settled.
    if (_unsent.isNotEmpty) await _retryUnsent();
    if (local == null) return;

    // The write has landed, so his words are safe either way — on disk, or in
    // the record the draw below was about to put on screen. There is nothing
    // left to say to a State that is gone, and no composer to clear: it was
    // disposed with the route. Only the draw needs the guard, and without it
    // this is a red screen over the message he just sent.
    //
    // Clearing here rather than before the write is what makes the composer
    // durable, and it is the reason [_sending] exists: the field is full for
    // exactly as long as the write takes, and the flag is what stops that window
    // from becoming a second send. Do not move the clear back up to the top of
    // the method — that is the loss the outbox was built to prevent.
    if (!mounted) return;
    _input.clear();
    setState(() => _messages = [..._messages, local]);
    _jumpToBottom();
    await _deliver(local);
  }

  /// A bubble drawn from this device, already in the thread: the user sees his
  /// own words the instant he sends them, marked as still travelling.
  Message _localBubble({String? text, String? imagePath}) => Message(
        id: _nextLocalId--,
        conversationId: _convId ?? 0,
        senderId: _me,
        content: text,
        imageUrl: imagePath,
        type: imagePath == null ? MessageType.text : MessageType.image,
        isRead: 0,
        createdAt: DateTime.now(),
        sendState: SendState.sending,
      );

  /// Sends one bubble and swaps the local copy for the server row **by local
  /// id** — the old code appended the server row and left the optimistic bubble
  /// in place, so every retry showed the user his message twice.
  Future<void> _deliver(Message local, {bool announce = true}) async {
    final convId = _convId;
    if (convId == null) {
      // No thread to send into (opening it failed): say so and keep the text.
      if (mounted) {
        setState(() => _replace(
            local.id, local.copyWith(sendState: SendState.failed)));
      }
      if (announce) {
        _toast(_failureCopy(persisted: _isPersisted(local)));
      }
      return;
    }
    // A queued photo whose file the system cleaned up can never be sent: forget
    // the record instead of retrying a missing file on every open, and say the
    // one useful thing — pick it again.
    final path = local.imageUrl;
    if (local.type == MessageType.image &&
        path != null &&
        !File(path).existsSync()) {
      await _forget(local);
      if (!mounted) return;
      setState(
          () => _replace(local.id, local.copyWith(sendState: SendState.failed)));
      if (announce) {
        _toast('لم تعد الصورة موجودة على الجهاز — اختر الصورة من جديد وأرسلها');
      }
      return;
    }
    try {
      final sent = local.type == MessageType.image
          ? await widget.repo.sendImage(convId, File(local.imageUrl!))
          : await widget.repo.sendText(convId, local.content ?? '');
      // The server has the row: the phone no longer owes it. Order matters —
      // forgetting first would lose the message if the app died right here.
      await _forget(local);
      if (!mounted) return;
      setState(
          () => _replace(local.id, sent.copyWith(sendState: SendState.sent)));
    } catch (e) {
      if (!mounted) return;
      if (isWriteUnconfirmed(e)) {
        // The message may already be on the server. Re-read the thread instead
        // of telling the user to press a bubble that is not really unsent —
        // that is how one message becomes two.
        await _markUnconfirmed(local);
        // Read before the closure runs, not inside it: `_me` is a `context`
        // lookup, and this closure executes after two awaits by which time the
        // user is free to have left the thread. Reading it there threw
        // "This widget has been unmounted" from inside a *recovery* path — the
        // one path that exists to turn a lost message into a saved one.
        final me = _me;
        final outcome = await resolveWriteOutcome(
          recheck: () async {
            final fresh = await widget.repo.messages(convId);
            return fresh.any((m) =>
                m.content == local.content && (me <= 0 || m.senderId == me));
          },
        );
        if (!mounted) return;
        await _settleUnconfirmed(local, outcome);
        return;
      }
      setState(
          () => _replace(local.id, local.copyWith(sendState: SendState.failed)));
      if (announce) {
        _toast(_failureCopy(persisted: _isPersisted(local)));
      }
    }
    _jumpToBottom();
  }

  /// «تعذّر الإرسال» alone used to hide the one fact that matters — the words
  /// are still on the phone.
  ///
  /// **Only say that when they are.** This sentence is the app's promise that
  /// the queue will outlive the screen, and the outbox can decline to keep it:
  /// a device that refused the write leaves the message in memory only. Printed
  /// there, the user closes the app believing his address is safe, and the
  /// words are gone — the exact loss the outbox was built to prevent, announced
  /// by the very line that claims to prevent it. [S.chatNotSaved] is the true
  /// sentence for that case, and it is told at enqueue time.
  static const String _retryCopy =
      'تعذّر الإرسال — الرسالة محفوظة في الهاتف، اضغط عليها لإعادة المحاولة';

  /// What a failed send may say, given whether the record really landed.
  ///
  /// A queue that refused the write has already told the user it did, and
  /// repeating that louder over the bubble would bury the one instruction that
  /// still works. So this returns the honest sentence and the screen stops
  /// guessing: durability is a fact carried by the write, not an assumption
  /// every failure path is allowed to make.
  String _failureCopy({required bool persisted}) =>
      persisted ? _retryCopy : S.chatNotSaved;

  /// Forgets a queue record by id from inside a `setState` callback, where
  /// [forget] would re-enter the build. The write is fire-and-forget on
  /// purpose: the record is settled either way, and a storage failure must not
  /// stop the thread from drawing.
  void _forgetQuietly(String id) {
    _outbox.remove(id).catchError((Object _) {});
  }

  /// Drops [local]'s queue record, if it has one.
  Future<void> _forget(Message local) async {
    final id = _queuedIds.remove(local.id);
    if (id != null) await _outbox.remove(id);
  }

  /// Stops the bubble from looking retryable while the app is deciding, and
  /// writes the reason onto the stored record before the re-read runs.
  ///
  /// A `failed` bubble draws a retry affordance, and the user is explicitly told
  /// to press it. Pressing it is exactly the wrong move while the row may
  /// already be on the server, so the bubble is held at `sending` until
  /// [_settleUnconfirmed] knows the answer.
  ///
  /// The stored record is marked in the same breath, and that ordering is the
  /// point: if the phone dies during the re-read — which is exactly the moment
  /// this whole path exists for — the next cold start must find a record that
  /// says «do not send this again». Marking it afterwards would lose the reason
  /// in precisely the window where it matters.
  Future<void> _markUnconfirmed(Message local) async {
    final recordId = _queuedIds[local.id];
    if (recordId != null) {
      await _outbox.markUncertain(recordId, uncertain: SendState.unconfirmed);
    }
    if (!mounted) return;
    setState(
        () => _replace(local.id, local.copyWith(sendState: SendState.sending)));
  }

  /// Puts the thread back to the truth, whichever way the re-read went.
  ///
  /// Landed: the server row is adopted, the outbox record is dropped, the
  /// bubble becomes an ordinary sent one. Missing: the message really is still
  /// only on the phone, so the failed state and the retry line come back —
  /// now as a true statement rather than a guess. Unknown: the bubble stays
  /// where it is and the user is told to check, because the app cannot claim
  /// either answer.
  Future<void> _settleUnconfirmed(Message local, WriteOutcome outcome) async {
    if (!mounted) return;
    if (outcome == WriteOutcome.landed) {
      // Re-read once more to adopt the server's own row (its id and timestamp)
      // instead of keeping the optimistic bubble, which still has the negative
      // local id the outbox is keyed by.
      final conv = _convId;
      Message? row;
      if (conv != null) {
        final me = _me;
        for (final m in await widget.repo.messages(conv)) {
          if (m.content == local.content && (me <= 0 || m.senderId == me)) {
            row = m;
            break;
          }
        }
      }
      await _forget(local);
      if (!mounted) return;
      setState(() => _replace(local.id,
          (row ?? local).copyWith(sendState: SendState.sent)));
      _jumpToBottom();
      _toast(S.writeUnconfirmedLanded);
      return;
    }
    if (outcome == WriteOutcome.missing) {
      // The list came back and the words are not in it, so re-sending is safe
      // and useful: this is a real failure again, with its real retry line.
      final recordId = _queuedIds[local.id];
      if (recordId != null) await _outbox.markUncertain(recordId, uncertain: null);
      if (!mounted) return;
      setState(
          () => _replace(local.id, local.copyWith(sendState: SendState.failed)));
      _toast(S.writeUnconfirmedMissing);
      return;
    }
    // Unknown: the app still does not know. The record keeps its «do not send
    // again» mark and the bubble is drawn without a retry affordance, so the
    // only ways forward are the ones that are true — the next read, or the user
    // deciding the message is not worth resending.
    if (!mounted) return;
    setState(
        () => _replace(local.id, local.copyWith(sendState: SendState.unconfirmed)));
    _toast(S.writeUnconfirmedUnknown);
  }

  /// Re-reads the thread for a message the app could not confirm, and adopts
  /// the server's row if it turns out to be there.
  ///
  /// This is what the banner's «تحقّق» button does. It is a read, never a
  /// re-send: the whole reason the bubble has no retry line is that sending it
  /// again may be the duplicate, and a button marked «تحقّق» must not do that.
  Future<void> _recheckUnconfirmed() async {
    final convId = _convId;
    if (convId == null) return;
    // Read once, before any await: `_me` is a `context` lookup, and this
    // closure runs after a network round trip during which he may have left the
    // thread — which threw "This widget has been unmounted" from the button
    // that exists to tell him whether his message arrived.
    final me = _me;
    for (final m in _messages
        .where((m) => m.sendState == SendState.unconfirmed)) {
      final fresh = await resolveWriteOutcome(recheck: () async {
        final rows = await widget.repo.messages(convId);
        return rows.any((r) =>
            r.content == m.content && (me <= 0 || r.senderId == me));
      });
      if (!mounted) return;
      if (fresh == WriteOutcome.landed) {
        await _forget(m);
        if (!mounted) return;
        setState(
            () => _replace(m.id, m.copyWith(sendState: SendState.sent)));
        _toast(S.writeUnconfirmedLanded);
      } else {
        _toast(writeOutcomeCopy(fresh));
      }
    }
  }

  /// Puts [next] where the bubble with [localId] was, keeping the clock already
  /// on screen when the server row arrives without a timestamp.
  void _replace(int localId, Message next) {
    _messages = [
      for (final m in _messages)
        if (m.id != localId)
          m
        else
          next.copyWith(createdAt: next.createdAt ?? m.createdAt),
    ];
  }

  /// One bubble's «أعد المحاولة» tap.
  Future<void> _retryOne(Message m) async {
    setState(() => _replace(m.id, m.copyWith(sendState: SendState.sending)));
    await _deliver(m);
  }

  /// Sends every bubble the server refused, oldest first.
  ///
  /// Quiet on purpose, and for the reason [_flushQueued] gives: a retry the app
  /// started on its own is not news. It used to toast once per bubble, so a
  /// thread holding sixty refused messages produced sixty identical SnackBars
  /// in a row — four minutes of screen the user could not read or use, and every
  /// other word the thread had to say (a message the bound deleted, a retyped
  /// address) was buried behind the pile. The banner above the composer already
  /// says it, and keeps saying it while the retry runs.
  Future<void> _retryUnsent() async {
    for (final m in _unsent) {
      // Every attempt is a network round trip, and he can leave the thread in
      // the middle of one. `_sendText` calls this loop *before* it does anything
      // of its own, so the first thing "tap send, tap back" ever runs is this
      // code — which made the one `setState` in the file with no `mounted`
      // check the one most likely to land on a dead State. The throw it raised
      // also aborted `_sendText` outright, so the message he was sending never
      // reached the queue at all: a crash that ate a second unsent message on
      // top of the red screen.
      if (!mounted) return;
      setState(() => _replace(m.id, m.copyWith(sendState: SendState.sending)));
      await _deliver(m, announce: false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final local = _localBubble(imagePath: file.path);
    await _enqueue(local, imagePath: file.path);
    // Same window as [_sendText]: the gallery takes long enough for the user to
    // back out of the thread while the record is still being written.
    if (!mounted) return;
    setState(() => _messages = [..._messages, local]);
    _jumpToBottom();
    await _deliver(local);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Tap-to-view fullscreen preview for an image message.
  void _openImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewer(url: url),
    ));
  }

  /// True when a day separator should be printed above message [index]. The
  /// ruling itself lives in `chat_time.dart`, where it is unit-tested without a
  /// widget tree — it used to compare raw UTC fields here, which filed a
  /// message sent after 23:00 UTC under the wrong day.
  bool _needsDateDivider(int index) => needsDayDivider(
        index == 0 ? null : _messages[index - 1].createdAt,
        _messages[index].createdAt,
      );

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(widget.otherName.isEmpty ? 'الرسائل' : widget.otherName)),
      // With a dead connection the error page is only honest when there is
      // nothing of the user's own to show. A queued message fills the thread and
      // the composer stays open, so he can keep writing — it all goes out when
      // the network returns.
      body: _loading
          ? const SkeletonChatThread()
          : (_error && _unresolved.isEmpty)
              ? EmptyView(
                  icon: Icons.wifi_off_rounded,
                  title: 'تعذّر جلب الرسائل',
                  message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                  actionLabel: 'إعادة المحاولة',
                  onAction: _bootstrap,
                )
              : Column(
                  children: [
                    if (_error) _offlineStrip(),
                    Expanded(child: _thread()),
                    if (_unresolved.isNotEmpty) _pendingBanner(),
                    _composer(),
                  ],
                ),
    );
  }

  // ── Thread ──────────────────────────────────────────────────────────────
  Widget _thread() {
    // A conversation nobody has written in yet used to be a blank page above
    // the composer — no explanation, so a user who just tapped "راسل" could
    // believe the app had lost the message. The action is the composer, so the
    // copy points at it instead of inventing a second button.
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined,
                  size: 42, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                'لا رسائل بعد',
                textAlign: TextAlign.center,
                style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'اكتب رسالتك الأولى في الخانة أسفله وستصل مباشرة.',
                textAlign: TextAlign.center,
                style: AppTheme.bodySoft,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final url = m.imageUrl;
        final mine = m.senderId == _me;
        final at = m.createdAt;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_needsDateDivider(i)) _DateDivider(label: chatDayLabel(at!)),
            _Bubble(
              message: m,
              mine: mine,
              onImageTap: url == null ? null : () => _openImage(url),
            ),
            // The clock under every bubble, and the delivery state on my own:
            // a spinner while it travels, a tick once the server has it, and a
            // red line that sends it again when it never arrived. A user who
            // cannot tell a delivered message from a lost one re-sends it — or
            // worse, assumes the contractor read the address.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                child: _BubbleMeta(
                  message: m,
                  mine: mine,
                  clockFormat: widget.clockFormat,
                  onRetry:
                      m.sendState == SendState.failed ? () => _retryOne(m) : null,
                  uncertain: m.sendState == SendState.unconfirmed,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Offline banner ──────────────────────────────────────────────────────
  /// Shown above a thread that could not be fetched, so the queued bubbles below
  /// it are never mistaken for the whole conversation.
  Widget _offlineStrip() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceAlt,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'لا يوجد اتصال — ستُرسل رسائلك المحفوظة عند عودة الشبكة',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingBanner() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.accentWash,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: AppTheme.accentDeep),
          const SizedBox(width: 8),
          // The count, only when it is worth counting: one message is already
          // described by the sentence beside it.
          if (_unresolved.length > 1) ...<Widget>[
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Text(
                '${_unresolved.length}',
                textAlign: TextAlign.center,
                style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsCaption, height: 1.2, color: AppTheme.navy),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              // The promise «اضغط لإعادة المحاولة» is a lie when the only
              // outstanding message is the one the app could not confirm: the
              // retry would be a second copy of words the server may already
              // have. So the banner says what it can promise, which is the
              // re-read — that read is what actually settles the question.
              _retryable.isEmpty
                  ? S.chatUnconfirmed
                  : 'رسائل غير مرسلة — اضغط لإعادة المحاولة',
              style: AppTheme.label
                  .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.accentDeep),
            ),
          ),
          TextButton(
            onPressed: _retryable.isEmpty ? _recheckUnconfirmed : _sendText,
            style: TextButton.styleFrom(
              minimumSize: const Size(64, AppTheme.tapMin),
              foregroundColor: AppTheme.navy,
            ),
            child: Text(_retryable.isEmpty ? 'تحقّق' : 'إرسال',
                style: AppTheme.label.copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.navy)),
          ),
        ],
      ),
    );
  }

  // ── Composer ────────────────────────────────────────────────────────────
  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _CircleAction(
                icon: Icons.add_photo_alternate_outlined,
                background: AppTheme.lineSoft,
                foreground: AppTheme.navy,
                tooltip: 'إرسال صورة',
                onTap: _pickImage,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendText(),
                  minLines: 1,
                  maxLines: 4,
                  style: AppTheme.body,
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة...',
                    hintStyle:
                        AppTheme.bodySoft.copyWith(color: AppTheme.textMuted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.send_rounded,
                background: AppTheme.accent,
                foreground: AppTheme.navy,
                tooltip: 'إرسال',
                onTap: _sendText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56x56 round action — the app's minimum tap target.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleAction({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppTheme.tapMin,
            height: AppTheme.tapMin,
            child: Icon(icon, size: 24, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Pill date separator between days.
class _DateDivider extends StatelessWidget {
  /// «اليوم» / «أمس» / `dd/MM/yyyy`, already ruled by [chatDayLabel].
  final String label;

  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.lineSoft,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
          ),
          child: Text(
            label,
            style: AppTheme.label
                .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// The line under one bubble: the clock, plus the delivery state on my own
/// messages — a spinner while it travels, a tick once the server stored it, and
/// a 56 dp tappable line («لم تُرسل — أعد المحاولة») when it never arrived.
class _BubbleMeta extends StatelessWidget {
  final Message message;
  final bool mine;
  final VoidCallback? onRetry;

  /// Draw the neutral «not confirmed» line instead of the red retry line. Same
  /// slot under the bubble, no tap target, because there is no action that is
  /// true here: re-sending is the duplicate, and pretending otherwise with a
  /// tappable line is how the user creates one.
  final bool uncertain;

  /// See [ChatScreen.clockFormat]. Null in the app: the phone's own hour.
  final String Function(DateTime at)? clockFormat;

  const _BubbleMeta({
    required this.message,
    required this.mine,
    this.onRetry,
    this.uncertain = false,
    this.clockFormat,
  });

  @override
  Widget build(BuildContext context) {
    final at = message.createdAt;
    final clock = at == null
        ? ''
        : (clockFormat ?? chatClock)(at);

    if (onRetry != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          // No `alignment:` on this Container on purpose: a Container with an
          // alignment expands to the widest constraint it is given, which
          // centred this line in the middle of the thread instead of under the
          // bubble it is about. The Row's own cross-axis centring keeps it
          // vertically centred inside the 56 dp tap target.
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTheme.tapMin),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: AppTheme.danger),
                const SizedBox(width: 6),
                // Flexible, because this line is the last thing between a lost
                // message and the user: it may ellipsise on a narrow screen,
                // it must never paint a striped overflow box.
                Flexible(
                  child: Text(
                    'لم تُرسل — أعد المحاولة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label.copyWith(
                        fontSize: AppTheme.fsCaption, color: AppTheme.danger),
                  ),
                ),
                if (clock.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(clock, style: AppTheme.caption.copyWith(
                      fontSize: AppTheme.fsBadge, color: AppTheme.textMuted)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final sending = mine && message.sendState == SendState.sending;
    if (uncertain) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          S.chatUnconfirmed,
          style: AppTheme.caption.copyWith(
              fontSize: AppTheme.fsBadge, color: AppTheme.textMuted),
        ),
      );
    }

    if (clock.isEmpty && !sending) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (clock.isNotEmpty)
            Text(clock,
                style: AppTheme.caption.copyWith(
                    fontSize: AppTheme.fsBadge, color: AppTheme.textMuted)),
          if (sending) ...[
            if (clock.isNotEmpty) const SizedBox(width: 5),
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: AppTheme.textMuted),
            ),
          ] else if (mine && clock.isNotEmpty) ...[
            const SizedBox(width: 4),
            // A sent mark, not a read receipt: this app has no read receipts,
            // so a green «read» tick would be a claim the product cannot keep.
            const Icon(Icons.check_rounded, size: 14, color: AppTheme.textMuted),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final VoidCallback? onImageTap;

  const _Bubble({required this.message, required this.mine, this.onImageTap});

  @override
  Widget build(BuildContext context) {
    // Existing alignment logic kept as-is: in this RTL app own messages sit
    // on the left (start-mirrored) and the other party on the right.
    final align = mine ? Alignment.centerLeft : Alignment.centerRight;
    // Asymmetric corners: outer bottom corner is the tighter one.
    final radius = mine
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rLg),
            topRight: Radius.circular(AppTheme.rLg),
            bottomLeft: Radius.circular(AppTheme.rSm),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rLg),
            topRight: Radius.circular(AppTheme.rLg),
            bottomRight: Radius.circular(AppTheme.rSm),
          );

    final Widget body = message.imageUrl != null
        ? _ImageBubble(
            url: message.imageUrl!,
            radius: BorderRadius.circular(AppTheme.rLg),
            onTap: onImageTap,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? AppTheme.navy : AppTheme.surface,
              borderRadius: radius,
              border: mine ? null : Border.all(color: AppTheme.line),
            ),
            child: Text(
              message.content ?? '',
              style: AppTheme.body.copyWith(
                fontSize: AppTheme.fsBody,
                color: mine ? AppTheme.onNavy : AppTheme.textPrimary,
              ),
            ),
          );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: body,
        ),
      ),
    );
  }
}

/// Rounded frame around an image message; tapping opens the fullscreen view.
class _ImageBubble extends StatelessWidget {
  final String url;
  final BorderRadius radius;
  final VoidCallback? onTap;

  const _ImageBubble({
    required this.url,
    required this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Local (queued) files are not remote URLs — same split as before.
    final isRemote = url.startsWith('http');
    final Widget image = isRemote
        ? NetImage(
            url,
            width: 220,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const SkeletonBox(height: 170, width: 220, radius: 0),
            errorBuilder: (_, __, ___) => const _ImageFallback(),
          )
        : Image.file(
            File(url),
            width: 220,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => const _ImageFallback(),
          );

    return Material(
      color: AppTheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: A11y.tap(
        label: 'صورة في المحادثة، اضغط لعرضها بالحجم الكامل',
        child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppTheme.line),
          ),
          child: ClipRRect(borderRadius: radius, child: image),
        ),
      )),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 150,
      alignment: Alignment.center,
      color: AppTheme.lineSoft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 32, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Text('تعذّر عرض الصورة',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// Fullscreen image preview (pinch to zoom, tap the app bar back to close).
class _ImageViewer extends StatelessWidget {
  final String url;

  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    final isRemote = url.startsWith('http');
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.navyDeep,
        foregroundColor: AppTheme.onNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.onNavy),
        title: const Text(
          'الصورة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: AppTheme.fsH2,
            fontWeight: FontWeight.w700,
            color: AppTheme.onNavy,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: isRemote
              // Deliberately NOT a NetImage: the user asked for this one at
              // full size and can pinch to 4x, so downscaling the decode to
              // the screen would trade the only thing this screen is for.
              ? Image.network(url,
                  semanticLabel: 'الصورة بالحجم الكامل',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _ViewerFallback())
              : Image.file(File(url),
                  semanticLabel: 'الصورة بالحجم الكامل',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _ViewerFallback()),
        ),
      ),
    );
  }
}

class _ViewerFallback extends StatelessWidget {
  const _ViewerFallback();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 44, color: AppTheme.onNavyMuted),
          const SizedBox(height: 12),
          Text('تعذّر عرض الصورة',
              textAlign: TextAlign.center,
              style: AppTheme.bodySoft.copyWith(color: AppTheme.onNavyMuted)),
        ],
      ),
    );
  }
}
