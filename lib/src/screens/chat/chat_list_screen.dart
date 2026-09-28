import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/auth_gate.dart';
import '../../core/theme/app_theme.dart';
import '../../data/chat_outbox.dart';
import '../../data/chat_preview_copy.dart';
import '../../data/notification_copy.dart';
import '../../data/repository.dart';
import '../../data/unread_message_trust.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final Repository repo;

  /// A conversations future the caller already holds.
  ///
  /// The client home needs the same list to decide whether its first-run guide
  /// is still needed, so it hands its future over instead of making every
  /// app-open pay for this endpoint twice.
  final Future<List<Conversation>>? initial;

  /// What an empty inbox does next.
  ///
  /// A conversation is never created *here* — it starts in the marketplace,
  /// either by messaging a contractor or by quoting a project. The inbox lives
  /// in a tab inside two different shells, so the shell hands in the switch
  /// instead of this screen guessing where the marketplace is.
  final VoidCallback? onDiscover;

  /// The queue shared with the threads this inbox opens. Injectable so a test
  /// can drive both screens from one store.
  final ChatOutbox? outbox;

  /// Called with every list this screen lands, including the one it is handed.
  ///
  /// **The badge on the tab this inbox sits in is drawn from the shell's own
  /// copy of this list**, so without this callback a pull-to-refresh here would
  /// re-read the inbox while the number on the tab kept the value the shell
  /// last read — two different numbers for the same thing on one screen,
  /// which is the exact failure the badge was written to make impossible. See
  /// `unread_message_count.dart`.
  ///
  /// The shell is told what it is already showing rather than asked to read
  /// again: this screen has just answered the question, so a second request
  /// would be a second chance for the two to disagree.
  final void Function(List<Conversation> conversations)? onRead;

  const ChatListScreen({
    super.key,
    required this.repo,
    this.initial,
    this.onDiscover,
    this.outbox,
    this.onRead,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Conversation>> _future;
  late final ChatOutbox _outbox;

  /// The «الرسائل» tab's confirmation flag, or null when this list is pumped
  /// with no scope above it.
  ///
  /// **Nullable and resolved in [didChangeDependencies], not [initState]**,
  /// because [_arm] runs in `initState` and an `InheritedWidget` cannot be
  /// read there. The handlers use `?.`, so a read that fails before the first
  /// dependency pass simply has nowhere to withdraw — which is honest: a list
  /// with no shell above it has no tab badge to mute.
  UnreadMessageTrust? _messages;

  /// Conversation id -> messages that are still only on this phone. The inbox is
  /// the last place a user can notice that a message never left: without this,
  /// an unsent message is invisible from every screen except the thread it was
  /// written in.
  Map<int, int> _queued = const <int, int>{};

  /// The last list that landed, kept so a re-read does not blank the screen.
  ///
  /// The tab the inbox sits in re-reads this list on the way back from the
  /// background (`didChangeAppLifecycleState` in the two home shells), and
  /// without a cache each of those reads would flash the skeleton at a user
  /// who did nothing at all — a heimlich-looking lurch on every unlock. The
  /// rows stay; only a first read, which has nothing to keep, shows the
  /// shimmer.
  List<Conversation>? _cache;

  @override
  void initState() {
    super.initState();
    _outbox = widget.outbox ?? ChatOutbox();
    _arm(widget.initial ?? widget.repo.conversations());
    _loadQueued();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messages = AppScope.maybeOf(context)?.messages;
  }

  /// Points the list at a read, and tells the shell what that read came back
  /// with.
  ///
  /// The callback fires **off the future**, so it is guarded on [mounted]: the
  /// shell that owns this tab lives in an `IndexedStack` and can be disposed
  /// while a request is still open.
  void _arm(Future<List<Conversation>> read) {
    _future = read;
    final onRead = widget.onRead;
    if (onRead == null) return;
    read.then((list) {
      if (!mounted) return;
      _messages?.restore();
      setState(() => _cache = list);
      onRead(list);
    }, onError: (_, __) {
      // **This is the most direct of the three failure paths**, and the
      // backlog filed it as the one that was easiest to forget: the inbox's own
      // read *is* the read the tab badge is summed from, so a failure here is
      // the badge losing its source rather than something adjacent to it. The
      // inbox already tells the truth on screen («تعذّر جلب الرسائل»); this
      // makes the tab stop contradicting it one tap earlier.
      _messages?.withdraw();
    });
  }

  @override
  void didUpdateWidget(covariant ChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initial;
    // Identity, not equality: the shell hands over a **new future** each time
    // it re-reads, and only a genuinely new read is worth re-arming for. A
    // rebuild for any other reason — the tab index moving, the guide
    // re-evaluating — must not throw away rows the user is reading.
    if (next != null && !identical(next, oldWidget.initial)) _arm(next);
  }

  /// Reads the outbox; a store that will not open leaves the badges empty.
  Future<void> _loadQueued() async {
    final counts = await _outbox.countsByConversation();
    if (!mounted) return;
    setState(() => _queued = counts);
  }

  void _reload() {
    // One read, not two. `_arm` installs the future, so asking the repository
    // here as well would leave the screen listening to the first answer while
    // the shell was told about the second — the two can differ, and the badge
    // would be drawn from whichever landed, not from the list on screen.
    setState(() => _arm(widget.repo.conversations()));
    _loadQueued();
  }

  /// Leaving a thread can change what is still owed, so the badges are re-read
  /// on the way back.
  Future<void> _openThread(Conversation conv) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
              conversationId: conv.id,
              otherUserId: 0,
              otherName: conv.otherUserName,
              repo: widget.repo,
              outbox: _outbox,
            )));
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    // A conversation needs a session on both sides, so signed out the inbox is
    // a shape with an explanation in it rather than a failed request.
    if (AuthGate.isGuest(context)) {
      return Scaffold(
        appBar: AppBar(title: const Text('الرسائل')),
        body: SignInWall(
          title: 'لا رسائل بعد',
          body: 'أول محادثة تبدأ من صفحة مقاول أو حرفي. سجّل الدخول لتتواصل معه مباشرة داخل التطبيق.',
          role: AppScope.of(context).auth.guestRole ?? UserRole.customer,
          onBrowse: widget.onDiscover,
        ),
      );
    }
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('الرسائل')),
        body: FutureBuilder<List<Conversation>>(
          future: _future,
          builder: (context, snap) {
            // One branch decides what the user is looking at, so a re-read
            // cannot take a different path from a first read: waiting falls
            // back to the last list that landed, and only a first read —
            // which has no cache to fall back on — shows the skeleton.
            final waiting = snap.connectionState != ConnectionState.done;
            final convs = waiting
                ? _cache
                : (snap.hasError ? null : (snap.data ?? const <Conversation>[]));
            if (convs == null) {
              if (waiting) {
                return const Shimmer(child: LoadingList(count: 4));
              }
              return EmptyView(
                icon: Icons.wifi_off_rounded,
                title: 'تعذّر جلب الرسائل',
                message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                actionLabel: 'إعادة المحاولة',
                onAction: _reload,
              );
            }
            if (convs.isEmpty) {
              return _emptyInbox(context);
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                itemCount: convs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ConversationTile(
                  conv: convs[i],
                  queued: _queued[convs[i].id] ?? 0,
                  onTap: () => _openThread(convs[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The dead end the second tab used to be: an explanation a user cannot act
  /// on. Both roles now get the sentence that says what creates a conversation
  /// and the button that starts one — a client browses contractors, a
  /// contractor browses the open projects.
  Widget _emptyInbox(BuildContext context) {
    final isCustomer = AppScope.of(context).auth.role == UserRole.customer;
    final canDiscover = widget.onDiscover != null;
    return EmptyView(
      icon: Icons.forum_outlined,
      title: 'لا محادثات بعد',
      message: isCustomer
          ? 'اختر مقاولاً من دليل المقاولين وراسله، أو انشر مشروعك ليصلك عرضه هنا.'
          : 'تصفّح المشاريع المفتوحة وقدّم عرضك؛ تُفتح المحادثة مع صاحب المشروع هنا.',
      actionLabel: !canDiscover
          ? null
          : (isCustomer ? 'تصفّح المقاولين' : 'تصفّح المشاريع المفتوحة'),
      actionIcon: Icons.search_rounded,
      onAction: widget.onDiscover,
    );
  }
}

/// One conversation row: avatar, name, one-line preview, relative time and
/// the unread badge on the trailing edge (left in RTL).
class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;

  /// Messages of this conversation the server has not stored yet.
  final int queued;

  const _ConversationTile({
    required this.conv,
    required this.onTap,
    this.queued = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = conv.unreadCount > 0;
    // The preview is never optional. A photo is stored with no `content` at
    // all — `sendImage` sends no such field — so the newest thread on the
    // platform is the one whose preview line used to vanish entirely. See
    // [chatPreviewCopy].
    final preview = chatPreviewCopy(conv.lastMessageContent) ??
        chatFallbackPreview(hasMessage: conv.lastMessageAt != null);
    return AppCard(
      onTap: onTap,
      padding: AppTheme.cardPad,
      child: Row(
        children: [
          _Avatar(conv: conv),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  conv.otherUserName.isEmpty ? 'محادثة' : conv.otherUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h2.copyWith(fontSize: AppTheme.fsBody),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySoft.copyWith(fontSize: AppTheme.fsMeta),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conv.lastMessageAt != null)
                Text(
                  relativeTimeAr(conv.lastMessageAt),
                  style: AppTheme.caption.copyWith(
                      fontSize: AppTheme.fsBadge, color: AppTheme.textMuted),
                ),
              if (queued > 0) ...[
                if (hasUnread || conv.lastMessageAt != null)
                  const SizedBox(height: 7),
                Tooltip(
                  message: queuedCountLabel(queued),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.accentWash,
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 12, color: AppTheme.accentDeep),
                        const SizedBox(width: 4),
                        Text(
                          '$queued',
                          textAlign: TextAlign.center,
                          style: AppTheme.label.copyWith(
                              fontSize: AppTheme.fsBadge,
                              height: 1.2,
                              color: AppTheme.accentDeep),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (hasUnread) ...[
                if (conv.lastMessageAt != null) const SizedBox(height: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    // Accent is the app's single highlight colour.
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                    textAlign: TextAlign.center,
                    style: AppTheme.label.copyWith(
                        fontSize: AppTheme.fsCaption, height: 1.2, color: AppTheme.navy),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Conversation conv;
  const _Avatar({required this.conv});

  @override
  Widget build(BuildContext context) {
    final url = conv.otherUserAvatar;
    if (url == null || url.isEmpty) {
      return InitialAvatar(name: conv.otherUserName, size: 52);
    }
    return ClipOval(
      // Name and time are already on the row — the avatar is decoration.
      child: NetImage(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            InitialAvatar(name: conv.otherUserName, size: 52),
      ),
    );
  }
}
