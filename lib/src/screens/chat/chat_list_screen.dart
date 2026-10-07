import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/auth_gate.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/chat_outbox.dart';
import '../../data/chat_preview_copy.dart';
import '../../data/notification_copy.dart';
import '../../data/stale_inbox_copy.dart';
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

  /// The wall clock, injectable so a test can age the stale band without
  /// waiting a real hour. Defaults to the system clock in the app.
  ///
  /// The band has to say how old its rows are, and a widget test that could
  /// only photograph the silent case — a read inside the minute — would pass
  /// against a screen that never dated anything at all.
  final DateTime Function()? clock;

  const ChatListScreen({
    super.key,
    required this.repo,
    this.initial,
    this.onDiscover,
    this.outbox,
    this.onRead,
    this.clock,
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

  /// When the list on screen was last read successfully.
  ///
  /// Written where the read **settles**, not where it is issued, and refreshed
  /// on **every** success — the second half is the one that is easy to get
  /// wrong. A screen that stamps only its first successful read answers the
  /// second outage with the age of the first one, and tells a user their
  /// conversation list is «قبل ساعتين» when it was fetched this very second.
  DateTime? _cacheReadAt;

  /// Bumped per read so a slow answer from an abandoned read cannot land after
  /// a newer one. See [_arm] — this screen is the third member of the
  /// generation-token family and the only one that shipped without one.
  int _armToken = 0;

  /// Ages the band once a minute, so «قبل 12 دقيقة» is a live claim rather
  /// than whatever the clock said on the frame the failure landed.
  ///
  /// Cancelled in [dispose] and re-armed from the same place the stamp is
  /// written, so a re-read that puts the stamp back does not leave two live
  /// timers.
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _outbox = widget.outbox ?? ChatOutbox();
    _arm(widget.initial ?? widget.repo.conversations());
    _loadQueued();
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [ChatListScreen.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Starts the once-a-minute tick that ages the band, once there is a stamp
  /// to age.
  ///
  /// Called from [_arm] rather than from `build`, because a timer created in
  /// `build` is a new timer on every frame and the tick would multiply. The
  /// guard is the reason this is not just a blind `setState`: a first read that
  /// has not landed has no rows to date, and a band only ever appears over rows
  /// that do.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_cacheReadAt == null) return;
      setState(() {});
    });
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
  ///
  /// **The cache is written whether or not a shell is listening, and that used
  /// not to be true.** `setState(() => _cache = list)` sat *after* an
  /// `if (onRead == null) return;`, so the field this class documents as the
  /// reason a re-read does not blank the screen was only ever written on the
  /// two home shells, which are the only callers that pass `onRead`. The
  /// notification centre opens this same screen with no callback
  /// (`notifications_screen.dart:272`), and there the cache was never set, ever
  /// — so the fallback the code claims to make could not be made at all and a
  /// failed refresh there wiped the list exactly as it always did. Caching is
  /// not the badge's business; only [UnreadMessageTrust] and [onRead] are.
  void _arm(Future<List<Conversation>> read) {
    _future = read;
    final onRead = widget.onRead;
    // The generation, for the reason [_feedToken] gives in the market tab. This
    // is the **third** screen of the family, and the only one of the three
    // that had no token at all — so it is the one where a late answer writes
    // unconditionally, where nothing anywhere had to be right for the read to
    // be the wrong one to believe.
    //
    // Both arms were reachable from one gesture. The pull and the pop out of a
    // thread both call [_reload], which arms a second read while the first is
    // still on the wire, and [didUpdateWidget] arms a third from the shell's
    // own re-read. So:
    //
    //   * a late **success** installs `_cache` and `_cacheReadAt` for a read
    //     the user replaced, then calls `onRead` — which is the *tab badge's*
    //     only source, so the pip goes back to gold over a count from a read
    //     that is no longer on screen, and the count is drawn for the list the
    //     screen is no longer showing; and
    //   * a late **failure** calls `withdraw()` for a read already replaced by
    //     a live one, so the pip goes muted for ever with nothing in flight
    //     that can ever restore it. That is the worse half, and it is the
    //     exact shape this family keeps producing: an answer nobody asked for
    //     again decides a visible state forever.
    //
    // Both are worse for being quiet. The inbox is the one screen whose whole
    // job is unread mail; the badge it feeds is drawn one tap away.
    final token = ++_armToken;
    read.then((list) {
      if (!mounted || token != _armToken) return;
      _messages?.restore();
      setState(() {
        _cache = list;
        // The clock *now*, not the moment the request was issued, so a read in
        // flight for forty seconds is dated when it actually landed.
        _cacheReadAt = _now();
      });
      _armAgeTick();
      onRead?.call(list);
    }, onError: (_, __) {
      // **This is the most direct of the three failure paths**, and the
      // backlog filed it as the one that was easiest to forget: the inbox's own
      // read *is* the read the tab badge is summed from, so a failure here is
      // the badge losing its source rather than something adjacent to it. The
      // inbox already tells the truth on screen («تعذّر جلب الرسائل»); this
      // makes the tab stop contradicting it one tap earlier.
      if (!mounted || token != _armToken) return;
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
            //
            // **A failed re-read falls back to the cache too, and that is the
            // whole fix.** It used to answer `null` for `snap.hasError`, so
            // the one state [_cache] was written for — rows on screen, server
            // unreachable — was the only one that threw the rows away and
            // replaced the inbox with the full-screen error. On the surface
            // that admits unsent messages (the per-row queued pill, this app's
            // last honest signal that a message never left), that meant the bad
            // connection which stopped a message sending was also the one that
            // hid the proof it never sent, and an empty inbox in this app is a
            // true statement with a real meaning. See `stale_inbox_copy.dart`.
            final waiting = snap.connectionState != ConnectionState.done;
            final failed = snap.hasError && !waiting;
            final convs = waiting || (failed && _cache != null)
                ? _cache
                : (failed ? null : (snap.data ?? const <Conversation>[]));
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
              // **A failed read that landed on an empty cache is not an empty
              // inbox, and this branch used to say it was.** `_cache` is
              // written on success whatever the list contains, so «the last
              // read landed and it was empty» and «the read failed and we have
              // never had a list» are the *same two values* by the time they
              // reach this line — `_cache == []` — and the code cannot tell them
              // apart. It answered the empty-inbox CTA either way, so a refresh
              // that failed on a user who genuinely has no conversations yet
              // told them «لا محادثات بعد» and offered a button to go browse
              // the directory. That is a confident false statement built out of
              // a read that never returned, and it is the one this inbox
              // exists to prevent: an empty inbox here is a *true* statement
              // with a real meaning, so it is the last thing that should ever be
              // printed without a read behind it. Worse, the empty view's only
              // action is `onDiscover` — there is no retry on it at all, so a
              // user on a dead network was handed a browse button and no way to
              // re-read.
              if (failed) {
                return EmptyView(
                  icon: Icons.wifi_off_rounded,
                  title: 'تعذّر جلب الرسائل',
                  message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                  actionLabel: 'إعادة المحاولة',
                  onAction: _reload,
                );
              }
              return _emptyInbox(context);
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              // The banner is a list header, not a replacement for the list, so
              // it scrolls with the rows and the pull gesture still has
              // something to pull. A failure is stated, not acted on: the rows
              // are real and a newer read did not land.
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                itemCount: convs.length + (failed ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  if (failed && i == 0) {
                    return _StaleInboxBanner(
                        line: staleInboxLineWithAgeAr(
                            snap.error == null
                                ? S.errUnexpected
                                : errorCopy(snap.error!),
                            _cacheReadAt,
                            now: _now()));
                  }
                  final conv = convs[i - (failed ? 1 : 0)];
                  return _ConversationTile(
                    conv: conv,
                    queued: _queued[conv.id] ?? 0,
                    onTap: () => _openThread(conv),
                    // The tile prints an age on the trailing edge, and this is
                    // the clock the screen itself was handed. Passing it down
                    // is what makes the number the same number as the band
                    // above it.
                    now: _now(),
                  );
                },
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

/// The amber band above a list that failed to re-read.
///
/// The staleness tone is deliberately the one `stale_catalogue_copy.dart` and
/// `worker_home_screen` already use (`AppTheme.accentDeep` over `accentWash`),
/// so a screen that is quietly out of date looks the same wherever it is found.
/// The queued pill on a row below it is also amber, and that is intentional
/// rather than a clash: both mean the same thing here — something on this
/// screen is not yet the server's.
class _StaleInboxBanner extends StatelessWidget {
  const _StaleInboxBanner({required this.line});

  /// The composed sentence from [staleInboxLineAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-inbox'),
      color: AppTheme.accentWash,
      borderColor: AppTheme.accent,
      padding: AppTheme.cardPadRail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_toggle_off_rounded,
              size: AppTheme.s20, color: AppTheme.accentDeep),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              line,
              key: const Key('stale-inbox-line'),
              style: AppTheme.body.copyWith(
                color: AppTheme.accentDeep,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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

  /// The clock the screen dates its stale band against. See
  /// [ChatListScreen.clock].
  ///
  /// **Why the tile takes it rather than calling `DateTime.now()` itself.**
  /// This widget is the third user of the screen's clock and the only one
  /// that was reading the *system* clock instead: the band above it passed
  /// `now: _now()`, and the row beside it passed nothing, so on a screen
  /// handed a clock the two answers were minutes apart and no test could say
  /// which was right. The failure was invisible in the app — `clock` is null
  /// there and the two readings agree — and unasserted by every existing
  /// test, because the only assertion anyone could write about the age was
  /// unreachable: this row's age could not be aged.
  ///
  /// The system clock is still the default, so nothing changes for the app;
  /// the seam now exists for the same reason it exists on the screen.
  final DateTime now;

  const _ConversationTile({
    required this.conv,
    required this.onTap,
    this.queued = 0,
    required this.now,
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
                  relativeTimeAr(conv.lastMessageAt, now: now),
                  style: AppTheme.caption.copyWith(
                      fontSize: AppTheme.fsBadge, color: AppTheme.textMuted),
                ),
              if (queued > 0) ...[
                if (hasUnread || conv.lastMessageAt != null)
                  const SizedBox(height: 7),
                Tooltip(
                  message: queuedCountLabel(queued),
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: AppTheme.pipMinW),
                    padding: AppTheme.pipPad,
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
                          // Was already [AppTheme.fsBadge], and now it is the
                          // token by name: the pip below it in this column was
                          // the writer that drifted, and a token is what stops
                          // the *next* one from arriving with its own idea of
                          // how large a count is drawn.
                          style: AppTheme.label.copyWith(
                              fontSize: AppTheme.pipNumeral,
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
                  constraints:
                      const BoxConstraints(minWidth: AppTheme.pipMinW),
                  padding: AppTheme.pipPad,
                  decoration: BoxDecoration(
                    // Accent is the app's single highlight colour.
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: Text(
                    conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                    textAlign: TextAlign.center,
                    // **This was the outlier.** The pip above it, in this same
                    // column, is the same box at [AppTheme.fsBadge] — and so
                    // are the tab bar's pip and the bell's. This one number was
                    // [AppTheme.fsCaption], 1.5 dp larger, which made the
                    // capsule 2 dp taller than the one stacked directly above
                    // it: two pills of two sizes on the one row that carries
                    // both, which is the row a user reaches when a message
                    // failed to send. Same shape, same padding, same radius,
                    // one glyph too big — and R4 counted none of it, because a
                    // `fontSize` is not an `EdgeInsets` and the two literals it
                    // *did* read (the padding) were already identical.
                    // See `test/chat_list_pip_test.dart`.
                    style: AppTheme.label.copyWith(
                        fontSize: AppTheme.pipNumeral,
                        height: 1.2,
                        color: AppTheme.navy),
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
