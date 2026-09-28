import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/theme/app_theme.dart';
import '../../data/notification_copy.dart';
import '../../data/notification_count_trust.dart';
import '../../data/notification_read_outcome.dart';
import '../../data/repository.dart';
import '../../models/chat.dart';
import '../../models/notification.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/projects_screen.dart';
import '../../widgets/motion.dart';

/// Notification centre: every quote, acceptance, message and review the user
/// has received, newest first, with the unread ones marked.
///
/// This screen is why the app can be closed and reopened without losing what
/// happened while it was away: each row says what happened, when, and opens
/// the thing it is about.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.repo,
    this.clock,
    this.trust,
  });

  /// Injected by tests and by callers that already hold a repository.
  final Repository? repo;

  /// Shared with the header behind this screen.
  ///
  /// **This is what stops the app contradicting itself one gesture after it
  /// admits it cannot know.** [S.notifReadUnconfirmedUnknown] tells the user the
  /// phone could not check the server, and the optimistic rows on this screen
  /// are therefore a guess. The header's pip is the same number for the same
  /// unread set — so if it comes back painting that count in red, the app has
  /// withdrawn a sentence and re-issued the answer in the loudest colour it
  /// owns, one tap later.
  ///
  /// Null means **fall back to the flag [AppScope] owns.** That is the answer
  /// to the gap the bell left open: this screen is also reachable by routes
  /// that do not go through the header — the in-app route, a future deep link
  /// — and a caller that pushed it with no flag withdrew nothing, so the pip
  /// behind it went on red. Reading the scope means *every* way in withdraws
  /// the same object the header is watching, and no caller has to remember to
  /// pass anything. Left null only where there is no scope at all: a widget
  /// test or design shot pumping the screen on its own, with no header behind
  /// it to contradict.
  final NotificationCountTrust? trust;

  /// The wall clock the relative timestamps are measured against.
  ///
  /// `relativeTimeAr` renders «قبل ساعة» from the *difference* to now, so a
  /// screen that always reads `DateTime.now()` labels the same row differently
  /// as the hours pass. That is right for a person and fatal for the golden
  /// gate, which pins pixels: the notifications baseline drifted 171 px on an
  /// hour boundary and failed ~50 minutes after it was captured, taking the
  /// whole `flutter test` gate red with it. Tests hand in a fixed clock;
  /// production leaves this null and reads the real time.
  final DateTime Function()? clock;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Repository _repo;
  bool _wired = false;

  /// The flag this screen withdraws.
  ///
  /// Never null in the app, for the reason on [trust] — and holding it as a
  /// field rather than re-reading `widget.trust` at the call site is what
  /// makes `withdraw()` unconditional below.
  late final NotificationCountTrust _trust;

  List<AppNotification> _items = const [];
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) {
      return;
    }
    _wired = true;
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _trust = widget.trust ?? AppScope.of(context).trust;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.notifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = S.errUnexpected);
    }
  }

  int get _unread => _items.where((n) => n.isRead == 0).length;

  /// Marks [ids] read. The rows flip immediately so the tap feels answered,
  /// then the list is reloaded from the server — so a write that fails cannot
  /// leave the screen claiming something the database does not agree with.
  ///
  /// **That guarantee had a hole, and it was the one case that mattered.** The
  /// comment above was true of the code until the reload *also* failed: `_load`
  /// sets `_error`, and `_body` only reads `_error` when `_items.isEmpty`, so a
  /// failed reload on a populated list is unreachable state. The optimistic
  /// flip stood, nothing was drawn, and the user was told — by the absence of a
  /// gold pip — that a notification was cleared which the database still held
  /// as unread. The write is ambiguous exactly when the network is worst, and
  /// the one screen whose entire job is the unread pip was the one that went
  /// quiet.
  ///
  /// So an **unconfirmed** write is now answered instead of shrugged at: the
  /// app re-reads the centre with a GET and says which of the three true things
  /// it is. Every other failure still falls through to the plain reload, which
  /// is correct for them — a 403 or a 404 is not in doubt, the list comes back
  /// and the row comes back with it.
  Future<void> _markRead(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    setState(() {
      _items = [
        for (final n in _items) ids.contains(n.id) ? n.asRead() : n,
      ];
    });
    try {
      await _repo.markNotificationsRead(ids: ids);
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        await _settleRead(ids);
        return;
      }
      // A refusal the server stated. The reload below puts the row back.
    }
    await _load();
  }

  Future<void> _markAllRead() async {
    if (_unread == 0) {
      return;
    }
    setState(() {
      _items = [for (final n in _items) n.asRead()];
    });
    try {
      await _repo.markNotificationsRead();
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // The no-ids form clears everything, so the proof is that nothing is
        // unread in the fresh list.
        await _settleRead(const []);
        return;
      }
      // As above: the reload is the source of truth.
    }
    await _load();
  }

  /// Answers a mark-read the server never confirmed, by re-reading the centre.
  ///
  /// The re-read is a **GET**, so it is safe to run and cannot itself change a
  /// row. Whatever it returns, the list on screen is replaced by the server's
  /// answer before the verdict is shown — including when the re-read failed,
  /// where the previous rows are left in place and the user is told that
  /// proves nothing rather than left staring at an optimistic flip.
  Future<void> _settleRead(List<int> ids) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text(S.notifReadUnconfirmedRecheck)),
    );
    final outcome = await resolveNotificationReadOutcome(
      recheck: () => _repo.notifications(),
      ids: ids,
    );
    // Whenever the re-read ran, the list is refreshed from it rather than left
    // on the optimistic flip — that is the whole point of asking. Only
    // [NotificationReadOutcome.unknown] has no fresh list to draw, and there
    // the rows on screen are a guess, so the sentence has to say so.
    if (outcome != NotificationReadOutcome.unknown) {
      await _load();
    } else {
      // The one outcome that leaves a guess on screen. Both halves of it are
      // the phone's memory rather than the server's: the rows below are still
      // the optimistic flip (only a real re-read replaces them), and the header
      // pip is about to re-read a count it cannot check either. So the header
      // is told, and stops drawing the number as a fact.
      //
      // **Not called for [NotificationReadOutcome.missing] on purpose.** That
      // verdict *is* the server's answer — it read the list and found the row
      // still unread — so the pip below is a fact and has no business being
      // muted. Only «I could not read the server at all» withdraws anything.
      _trust.withdraw();
    }
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(notificationReadOutcomeCopy(outcome))),
      );
    }
  }

  /// Opens whatever the row is about, and never lets a tap die in silence.
  ///
  /// The founder's report, verbatim: «when i get a notification they are not
  /// clickble when i click on them nothing happens fix it». [notificationTarget]
  /// holds the rule; this turns it into a screen.
  Future<void> _open(AppNotification n) async {
    _markRead([n.id]);
    final target = notificationTarget(n.type, n.link);
    if (target.kind == 'chat') {
      await _openThread(target.id);
      return;
    }
    final screen = _screenFor(target);
    if (!mounted) {
      return;
    }
    if (screen == null) {
      // An informational row with nothing behind it. Saying so beats a tap that
      // does nothing at all — the reason this screen was reported broken.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.notificationNoAction)),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Opens the thread a message notification came from, falling back to the
  /// inbox when the conversation is gone.
  Future<void> _openThread(String? conversationId) async {
    final id = int.tryParse(conversationId ?? '');
    final me = AppScope.of(context).auth.user?.id;
    Conversation? conv;
    if (id != null) {
      try {
        conv = (await _repo.conversations()).firstWhere((c) => c.id == id);
      } catch (_) {
        conv = null;
      }
    }
    if (!mounted) {
      return;
    }
    final peer = conv == null
        ? null
        : (conv.customerId == me ? conv.workerUserId : conv.customerId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => (conv == null || peer == null)
            ? ChatListScreen(repo: _repo)
            : ChatScreen(
                conversationId: conv.id,
                otherUserId: peer,
                otherName: conv.otherUserName,
                repo: _repo,
              ),
      ),
    );
  }

  /// The screen behind a target, or null when there is none.
  Widget? _screenFor(NotificationTarget t) {
    switch (t.kind) {
      case 'project':
        return ProjectDetailScreen(projectId: t.id!, repo: _repo);
      case 'inbox':
      case 'chat':
        return ChatListScreen(repo: _repo);
      case 'projects':
        return ProjectsScreen(repo: _repo);
      case 'profile':
        return const ProfileScreen();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text(S.notifications, style: AppTheme.bar),
        actions: [
          if (_unread > 0)
            TextButton(
              key: const Key('notifications-mark-all'),
              onPressed: _markAllRead,
              child: Text(
                S.markAllRead,
                style: AppTheme.label.copyWith(color: AppTheme.accentDeep),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accentDeep,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      final failed = _error != null;
      return _message(
        icon:
            failed ? Icons.cloud_off_rounded : Icons.notifications_none_rounded,
        title: failed ? _error! : S.noNotifications,
        hint: failed ? S.noNotificationsErrorHint : S.noNotificationsHint,
        actionLabel: failed ? S.retry : S.back,
        onAction: failed ? _load : () => Navigator.of(context).maybePop(),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      // Rows fade up on first build (AppMotion.reveal). The list is short, so
      // every row reveals together — no stagger, no row left waiting on a timer.
      itemBuilder: (_, i) => Reveal(child: _tile(_items[i])),
    );
  }

  /// Scrollable on purpose: a pull-to-refresh gesture needs something to pull.
  Widget _message({
    required IconData icon,
    required String title,
    required String hint,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    // Centred in the space that is actually there, but kept a scroll view so
    // pull-to-refresh still has something to pull: a short screen scrolls
    // instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 54, color: AppTheme.textMuted),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTheme.h2.copyWith(
                      fontSize: AppTheme.fsH2, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: AppTheme.body.copyWith(
                      fontSize: AppTheme.fsMeta, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 22),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: AppTheme.tapMin,
                    child: OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        style: AppTheme.button.copyWith(
                            fontSize: AppTheme.fsSmall,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppNotification n) {
    final look = NotificationLook.of(n.type);
    final unread = n.isRead == 0;
    final body = n.body ?? '';
    final when = relativeTimeAr(n.createdAt, now: widget.clock?.call());
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        key: Key('notification-${n.id}'),
        onTap: () => _open(n),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: unread ? AppTheme.accent : AppTheme.line,
              width: unread ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: look.wash,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Icon(look.icon, size: 22, color: look.tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            look.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.h2.copyWith(
                                fontSize: AppTheme.fsLead,
                                color: AppTheme.textPrimary),
                          ),
                        ),
                        if (unread) const _NewTag(),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                            fontSize: AppTheme.fsMeta,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        when,
                        style: AppTheme.caption.copyWith(
                            fontSize: AppTheme.fsCaption,
                            color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold «جديد» pip for a row the user has not opened yet.
class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accentWash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Text(
        S.newTag,
        style: AppTheme.caption
            .copyWith(fontSize: AppTheme.fsBadge, color: AppTheme.accentDeep),
      ),
    );
  }
}
