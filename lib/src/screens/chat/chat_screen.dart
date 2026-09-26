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

  const ChatScreen({
    super.key,
    this.conversationId,
    this.projectId,
    required this.otherUserId,
    this.otherName = '',
    required this.repo,
    this.outbox,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

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
  List<Message> get _unsent =>
      _messages.where((m) => m.sendState == SendState.failed).toList();

  /// The queue of messages this device still owes the server. Survives leaving
  /// the thread and a cold start; see `data/chat_outbox.dart`.
  late final ChatOutbox _outbox = widget.outbox ?? ChatOutbox();

  /// Local bubble id -> the queue record behind it, so a confirmed send knows
  /// exactly which record to forget.
  final Map<int, String> _queuedIds = <int, String>{};

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
  Future<void> _restoreQueued() async {
    final convId = _convId;
    if (convId == null) return;
    final pending = await _outbox.pendingFor(convId);
    if (pending.isEmpty || !mounted) return;
    setState(() {
      for (final p in pending) {
        final bubble = Message(
          id: _nextLocalId--,
          conversationId: convId,
          senderId: _me,
          content: p.text,
          imageUrl: p.imagePath,
          type: p.isImage ? MessageType.image : MessageType.text,
          isRead: 0,
          createdAt: p.createdAt,
          sendState: SendState.failed,
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
      await _deliver(m, announce: false);
    }
  }

  /// Writes one bubble into the queue and remembers which record owns it.
  /// Called *before* the first network attempt, which is the whole point.
  Future<void> _enqueue(Message bubble, {String? text, String? imagePath}) async {
    final convId = _convId;
    if (convId == null) return; // no thread yet: nowhere to attach it
    final record = await _outbox.add(
      conversationId: convId,
      text: text,
      imagePath: imagePath,
    );
    _queuedIds[bubble.id] = record.id;
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
    final text = _input.text.trim();
    if (text.isEmpty && _unsent.isEmpty) return;
    // Anything the server refused goes first, so the thread keeps its order.
    if (_unsent.isNotEmpty) await _retryUnsent();
    if (text.isEmpty) return;
    _input.clear();
    final local = _localBubble(text: text);
    // Written down before the first attempt: if the phone loses the network,
    // the user taps back, or Android kills the app mid-request, the message is
    // still on the device with a way to send it.
    await _enqueue(local, text: text);
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
      if (announce) _toast(_retryCopy);
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
        _markUnconfirmed(local);
        final outcome = await resolveWriteOutcome(
          recheck: () async {
            final fresh = await widget.repo.messages(convId);
            final me = _me;
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
      if (announce) _toast(_retryCopy);
    }
    _jumpToBottom();
  }

  /// «تعذّر الإرسال» alone used to hide the one fact that matters — the words
  /// are still on the phone.
  static const String _retryCopy =
      'تعذّر الإرسال — الرسالة محفوظة في الهاتف، اضغط عليها لإعادة المحاولة';

  /// Drops [local]'s queue record, if it has one.
  Future<void> _forget(Message local) async {
    final id = _queuedIds.remove(local.id);
    if (id != null) await _outbox.remove(id);
  }

  /// Stops the bubble from looking retryable while the app is deciding.
  ///
  /// A `failed` bubble draws a retry affordance, and the user is explicitly told
  /// to press it. Pressing it is exactly the wrong move while the row may
  /// already be on the server, so the state is held at `sending` until
  /// [_settleUnconfirmed] knows the answer.
  void _markUnconfirmed(Message local) {
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
    setState(
        () => _replace(local.id, local.copyWith(sendState: SendState.failed)));
    if (outcome == WriteOutcome.missing) {
      _toast(S.writeUnconfirmedMissing);
    } else {
      _toast(S.writeUnconfirmedUnknown);
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
  Future<void> _retryUnsent() async {
    for (final m in _unsent) {
      await _retryOne(m);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final local = _localBubble(imagePath: file.path);
    await _enqueue(local, imagePath: file.path);
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
          : (_error && _unsent.isEmpty)
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
                    if (_unsent.isNotEmpty) _pendingBanner(),
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
                  onRetry:
                      m.sendState == SendState.failed ? () => _retryOne(m) : null,
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
          if (_unsent.length > 1) ...<Widget>[
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(AppTheme.rPill),
              ),
              child: Text(
                '${_unsent.length}',
                textAlign: TextAlign.center,
                style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsCaption, height: 1.2, color: AppTheme.navy),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              'رسائل غير مرسلة — اضغط لإعادة المحاولة',
              style: AppTheme.label
                  .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.accentDeep),
            ),
          ),
          TextButton(
            onPressed: _sendText,
            style: TextButton.styleFrom(
              minimumSize: const Size(64, AppTheme.tapMin),
              foregroundColor: AppTheme.navy,
            ),
            child: Text('إرسال',
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

  const _BubbleMeta({required this.message, required this.mine, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final at = message.createdAt;
    final clock = at == null ? '' : chatClock(at);

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
        ? Image.network(
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
