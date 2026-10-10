import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/snack.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/theme/app_theme.dart';
import '../../data/notification_copy.dart';
import '../../data/notification_body_copy.dart';
import '../../data/notification_count_trust.dart';
import '../../data/notification_read_outcome.dart';
import '../../data/notification_shortfall_copy.dart';
import '../../data/repository.dart';
import '../../data/stale_notifications_copy.dart';
import '../../models/chat.dart';
import '../../models/notification.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/projects_screen.dart';
import '../../widgets/ui.dart';
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

  /// `GET /api/unread` as last read, beside [_items] -- **null means the phone
  /// has no server count at all**, which is not the same as zero.
  ///
  /// Added 10 Oct 2026 to close the defect `tool/notification_read_audit.py`
  /// measured on production: the centre draws at most 100 rows while the server
  /// holds more, so counting the unread out of [_items] made `_unread` reach 0
  /// on a set that was not empty, and `if (_unread > 0)` then removed
  /// «تعليم الكل كمقروء» -- the app claiming nothing was unread about 100 of
  /// 140 rows. See `notification_shortfall_copy.dart` for the measurement.
  ///
  /// Two arms because the count is a second request that can fail on its own,
  /// and its failure must not cost the rows: a centre whose list loaded fine
  /// says so about the list and says nothing about the count.
  int? _serverUnread;

  /// The failure, when one is being shown.
  ///
  /// **Used to be a dead field on a populated list, and that was the defect.**
  /// `_load` assigned it on failure and `_body` read it only inside
  /// `if (_items.isEmpty)`, so a failed *re-read* — by far the most ordinary
  /// failure on this screen — set a value no branch could see and the centre
  /// went on drawing yesterday's rows with nothing said about it. A first read
  /// that fails still gets the full-screen error; this field now carries the
  /// failure to both of those places instead of only one.
  String? _error;

  /// Whether [_items] is being drawn while a newer read has failed to land.
  ///
  /// Separate from [_error] because a *first* read that fails and a *re-read*
  /// that fails are opposite answers — the first has nothing to draw, the
  /// second has a whole list it must not throw away — and one nullable string
  /// cannot carry "the list on screen is stale" on its own. `_error` is set by
  /// both; this says which of them the body is in.
  bool get _stale => _error != null && _items.isNotEmpty;

  /// The tick that ages the rows' timestamps while the centre sits open.
  ///
  /// **[NotificationsScreen.clock] was a seam with nothing behind it.** The
  /// field exists so the golden gate can pin pixels — the `15_notifications`
  /// baseline drifted 171 px on an hour boundary and took the whole
  /// `flutter test` gate red with it — and that is all it was ever used for.
  /// Production leaves it null, `_tile` reads `relativeTimeAr` against the real
  /// wall clock, and the timestamp it prints is therefore whatever was true
  /// when that tile last rebuilt. This screen rebuilds on exactly three things:
  /// the first `_load`, a pull-to-refresh, and a read being marked. None of
  /// them is "a minute passed".
  ///
  /// So the centre showed «قبل 12 دقيقة» to a contractor who sat reading the
  /// list for twenty minutes, next to a message that arrived *during* those
  /// twenty minutes. The newest row and the oldest row on the same screen
  /// disagreed about when it was, and both were stamped from one build. This
  /// is the same fuse as `profile_screen.dart`'s plan row and
  /// `subscription_screen.dart`'s card: a computed answer whose screen never
  /// asks the question again. The seam is here; the timer is what makes it
  /// live.
  Timer? _ageTimer;

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

  /// The *generation* of the list currently on screen, so a read that is
  /// still in flight cannot write over one that has already answered.
  ///
  /// **This screen had no token at all, and it is the reason the notification
  /// centre could quietly lose a row the newest read had listed.** Five call
  /// sites re-issue [_load] — the first read in [didChangeDependencies], the
  /// [RefreshIndicator] pull, [_markRead], [_markAllRead] and the [_settleRead]
  /// re-read — and all of them ask the **same** question, «the whole
  /// notification list». A tab- or id-keyed cache cannot separate them, so
  /// nothing else stopped an older read from answering last:
  ///
  ///     read 1  09:00  issued, parked on a slow connection ─┐
  ///     read 2  09:40  answers: 2 rows                      ─┤
  ///     read 1  09:40  lands LAST: 1 row                    ─┘
  ///
  /// Which is not merely a stale picture. `[_unread]` counts these very rows,
  /// so the late list *is* the number the home header paints — the badge goes
  /// **backwards**, dropping a notification that arrived while the user was
  /// away, with nothing on screen saying so. The failure arm was worse still,
  /// because it reaches another screen: a late `_trust.withdraw()` publishes a
  /// doubt about a list nobody is looking at, and the flag is one-way by
  /// design (only a real `/api/unread` read restores it), so the header goes on
  /// muting a count the app has just freshly read from the server.
  ///
  /// Every arming is a new generation, and the guard is checked on **both**
  /// arms — the success arm installs rows, and the error arm is the one that
  /// speaks to the header.
  int _loadToken = 0;

  Future<void> _load() async {
    final token = ++_loadToken;
    try {
      final list = await _repo.notifications();
      // The guard, on the success arm too. See [_loadToken]: a read the user
      // has already replaced must not install its rows last, because
      // [_unread] — the home header's pip — is counted from them.
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() {
        _items = list;
        _error = null;
      });
      // The server's own count, fetched **after** the rows landed and read only
      // once this read is still the current generation. Two reasons it is not
      // folded into the same future:
      //
      //   * the rows are the screen, the count is a qualifier on them. A joined
      //     read that failed on the count would throw away a list that arrived
      //     perfectly, and a failed re-read is exactly the state this screen
      //     already has a banner for -- it would turn "I could not check the
      //     number" into "your list is stale", which is a different lie.
      //   * the generation guard has to be checked on this arm too. A late
      //     count would otherwise land on a list it was never asked about, and
      //     the band would claim a gap against rows the user has already
      //     replaced.
      unawaited(_readServerUnread(token));
      // Armed where the first stamp lands, not from `initState`: before this
      // runs there are no rows and nothing to age, and `_load` re-arms rather
      // than arms so a pull-to-refresh cannot leave two live timers behind.
      _armAgeTick();
    } catch (e) {
      // Checked here as well, and this is the half that reaches another
      // screen: the doubt below belongs to *this* read, so a failure for a
      // question the reader has already moved off must not paint the amber
      // banner over rows that are perfectly current — nor withdraw the header
      // pip for a list that was read from the server after this one was
      // issued. `withdraw()` cannot be taken back.
      if (!mounted || token != _loadToken) {
        return;
      }
      setState(() => _error = errorCopy(e, fallback: S.errUnexpected));
      // **The half of this bug that was sitting unused.** This screen is the
      // input to the header's unread pip — `_unread` counts these very rows —
      // and `notification_count_trust.dart` exists precisely so the header
      // stops painting a count the app cannot check as a fact. A failed read
      // here means the number behind that pip is the phone's memory, so the
      // same sentence the centre now shows on screen is shown to the header.
      //
      // Withdrawing does not clear the number; it stops claiming to be the
      // server's, which is the whole claim `restore()` is documented against
      // (only a real read of `/api/unread` puts it back). The screen already
      // did this for the one failure it could see — the `_settleRead` re-read
      // that could not run — so a plain pull-to-refresh was the odd one out.
      _trust.withdraw();
    }
  }

  /// Reads `/api/unread` for the band, and never disturbs the rows.
  ///
  /// A failure here leaves [_serverUnread] **null**, which is the honest state:
  /// the app cannot say the centre is short, so the band is not drawn and the
  /// button falls back to what it can prove. Silently keeping the *previous*
  /// count would be worse than null -- that number was true of an older list,
  /// and pairing it with fresh rows states a gap the wire never confirmed.
  ///
  /// On success this is also the only read in the app that restores
  /// [_trust]: `notification_count_trust.dart` is one-directional because a
  /// successful `GET /api/notifications` proves a row is read and says nothing
  /// about the size of the unread set the header pip paints. This endpoint
  /// answers that question directly, so the screen that owns the number is the
  /// one place that can put the pip back to being the server's.
  Future<void> _readServerUnread(int token) async {
    int n;
    try {
      n = await _repo.unreadCount();
    } catch (_) {
      // Not an error the screen reports: the list is fine and the user is not
      // being asked to do anything about a number they never saw. The band is
      // simply not drawn.
      if (!mounted || token != _loadToken) return;
      setState(() => _serverUnread = null);
      return;
    }
    // The same guard the rows get. See [_loadToken].
    if (!mounted || token != _loadToken) {
      return;
    }
    setState(() => _serverUnread = n);
    // **Publish, do not merely restore.** The bell reads the same endpoint on
    // every resume, and publishing the number here lets that read be answered
    // by this one instead of the header asking again — a duplicated round-trip
    // on a box with no swap, and a violation of the invariant
    // `unread_round_trip_test.dart` pins ("the same question is not asked
    // twice"), which this screen's own read used to break with a third
    // request per visit.
    _trust.publish(n);
  }

  /// Starts the once-a-minute tick that re-labels the rows.
  ///
  /// A `setState` with no fields changed is the whole mechanism: `_tile` calls
  /// `relativeTimeAr` with the clock at build time, so re-running `build` is
  /// what re-reads it. Same shape as the tick on `browse_screen.dart`, and for
  /// the same reason it is not written in `build` — a timer made in `build` is
  /// a new timer every frame and the tick multiplies.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Nothing to age: a failed first read draws no rows, so ticking would
      // rebuild an error screen once a minute for nothing.
      if (_items.isEmpty) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    // The bell pushes this route and the route can sit under the project screen
    // it opened, so an uncancelled timer outlives the trip back and fires
    // `setState` on a dead State — which fails the next test in the file with
    // "A Timer is still pending".
    _ageTimer?.cancel();
    super.dispose();
  }

  int get _unread => _items.where((n) => n.isRead == 0).length;

  /// The server's count beside the rows, as of the last read that had both.
  ///
  /// **Two numbers, not one, and conflating them is what made this feature
  /// unable to fire.** [NotificationShortfall.drawn] is the size of the list —
  /// the question *"is there anything on screen for a band to sit on?"* — and
  /// [NotificationShortfall.unreadDrawn] is the subtraction. Passing
  /// `rows: _unread` answered both with the unread count, so a user who read
  /// every visible row (the exact state the server audit walked into) left
  /// `drawn == 0` and `worthReporting` false: **the band was gated off by the
  /// very condition it exists to report.** Both are read from [_items], and
  /// they differ precisely when the user has done their job.
  NotificationShortfall get _shortfall => NotificationShortfall(
        serverUnread: _serverUnread,
        unreadDrawn: _unread,
        drawn: _items.length,
      );

  /// Whether «تعليم الكل كمقروء» is offered.
  ///
  /// **Was `_unread > 0`, and that was a claim about rows the phone had not
  /// read.** The list is capped at 100 server-side while the unread set is not,
  /// so `_unread` reaches 0 on a set that still holds rows -- and the gate then
  /// *removed the button*, which is how a capped read turned into a silent
  /// claim that the user's inbox was empty. Measured end to end on production
  /// by `tool/notification_read_audit.py`: 140 made, 100 drawn, 40 unread on
  /// the server, 0 on screen.
  ///
  /// **The rule is one line: only a server count of zero retires the button.**
  /// Every other state shows it, and that asymmetry is the point rather than an
  /// oversight:
  ///
  ///   * the write behind it is `POST /api/notifications/read` with no ids,
  ///     which clears everything and is **idempotent** -- pressing it when
  ///     there is genuinely nothing unread costs the user one tap and the
  ///     server nothing;
  ///   * *hiding* it when the server still holds unread rows is the defect,
  ///     and it is invisible: no error, no band, a control that was simply not
  ///     there any more.
  ///
  /// So the cost is deliberately pushed onto the harmless branch. A count that
  /// could not be read ([_serverUnread] null) leaves the button in place rather
  /// than falling back to `_unread`, because "the phone cannot rule out more"
  /// and "there is nothing more" are different facts and only one of them is
  /// ever the truth here.
  bool get _canMarkAll {
    final server = _shortfall.serverUnread;
    // The server's answer, and the only fact that removes the control.
    if (server != null && server == 0 && _unread == 0) return false;
    // Nothing drawn and nothing measured: there is no list to clear and no
    // evidence that anything is waiting behind it.
    if (_items.isEmpty && server == null) return false;
    return true;
  }

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
    // Was `if (_unread == 0) return;`, which made the *button's own* gate the
    // authority on whether there is anything to clear -- and that number comes
    // from a capped list. It is now the same [_canMarkAll] the button is drawn
    // from, so the two cannot disagree: there is no state where the control is
    // on screen and pressing it is a silent no-op.
    if (!_canMarkAll) {
      return;
    }
    // The optimistic flip paints the rows the user can see, and **only** those
    // rows -- it never invents a row for the ones the cap is holding back. The
    // band below stays on screen through the write, because the gap is the
    // server's answer and the write has not replaced that answer yet; the
    // `_load` on the far side re-reads both.
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
    _showRechecking();
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
      _showCommitResult(notificationReadOutcomeCopy(outcome));
    }
  }

  /// «نتحقّق من الإشعارات…» — the line that replaces the one sentence it is
  /// about to contradict.
  ///
  /// A recheck line, not an error line, because the failure has not been
  /// classified yet and the user is owed an answer rather than an apology.
  void _showRechecking() {
    showNote(context, recheckNote(notifications: true));
  }

  /// The classified answer, drawn in place of the recheck line.
  ///
  /// `ScaffoldMessenger` **queues** by default: a second `showSnackBar` while
  /// one is visible waits for the first to time out, so the user would read
  /// «نتحقّق من الإشعارات…» for its full four seconds after the check had
  /// already finished, and the verdict — the only sentence that answers «is
  /// this notification still counted as new?» — would arrive last and behind
  /// it.
  ///
  /// The project screen reached the same conclusion for [_accept] and
  /// [_complete] and the bid sheet; this is that discipline, applied here.
  /// Unlike the third `showSnackBar` in [_open] (the «no action» line, which
  /// has nothing above it to replace) this one is the answer to the line it is
  /// hiding, so the queue is removed first and only the answer is left.
  void _showCommitResult(String copy) => showVerdict(context, copy);

  /// Opens whatever the row is about, and never lets a tap die in silence.
  ///
  /// The founder's report, verbatim: «when i get a notification they are not
  /// clickble when i click on them nothing happens fix it». [notificationTarget]
  /// holds the rule; this turns it into a screen.
  Future<void> _open(AppNotification n) async {
    // `unawaited`, not `await`: the row has already flipped to read locally
    // and the thread this opens must not wait on the write landing. The write
    // reports its own failure inside [_markRead] and reloads on a refusal.
    unawaited(_markRead([n.id]));
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
      showNote(context, S.notificationNoAction);
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
          if (_canMarkAll)
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
    // **The banner is a header on the list, not a replacement for it.** That
    // is the whole fix, and it is the same shape the inbox and the project
    // list landed on: the rows are real and a newer read did not land, so they
    // stay, and the doubt is stated above them. A header keeps the pull gesture
    // working too — the rows scroll, so there is always something to pull.
    //
    // Reached only when [_stale]: a first read that failed has no rows and was
    // already answered by the full-screen error above.
    final stale = _stale;
    // The two banners answer two different questions and **can both be true**:
    // `stale` is "the rows in front of you may be older than the server", and
    // `short` is "the server says there are unread rows that are not in front of
    // you". A list that failed to re-read is exactly when the gap is most
    // likely to be misreported, so neither is folded into the other.
    //
    // Ordered stale-first because it is the more urgent half: it qualifies the
    // rows themselves, the second qualifies their completeness.
    final short = _shortfall.worthReporting
        ? notificationShortfallLineAr(_shortfall)
        : '';
    // Plain arithmetic, not a collection-`if`: this is an expression in a
    // statement position and `if` has no value there, so the analyzer read the
    // `(if ...)` as a parenthesised type and then blamed the arithmetic that
    // followed for being `double`. The count is written out once and used for
    // the list length AND the row offset -- deriving it in two places is how
    // the off-by-one below came to exist.
    final headers = (stale ? 1 : 0) + (short.isEmpty ? 0 : 1);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _items.length + headers,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      // Rows fade up on first build (AppMotion.reveal). The list is short, so
      // every row reveals together — no stagger, no row left waiting on a timer.
      itemBuilder: (_, i) {
        // `i` indexes the *header* block first, so the row offset is every
        // header drawn, not just the stale one. It was `stale ? 1 : 0`, which
        // with a shortfall band alone would have drawn the banner and then
        // shifted every row up by one -- the last notification off the list and
        // an off-by-one crash on the tile below it.
        if (i < headers) {
          if (stale && (i == 0 || short.isEmpty)) {
            return _StaleNotificationsBanner(
                line: staleNotificationsLineAr(_error ?? S.errUnexpected));
          }
          return _ShortfallBanner(line: short);
        }
        return Reveal(child: _tile(_items[i - headers]));
      },
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
    // A bare `5/5` is the Worker's own encoding of a review, and it is the
    // only Latin-numeral string in this screen. A body a person typed is
    // left exactly as typed. See [notificationBodyCopy].
    final body = notificationBodyCopy(n.body, type: n.type);
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
              width:
                  unread ? AppTheme.hairlineSelected : AppTheme.hairlineResting,
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
                    // Unconditional: [notificationBodyCopy] never returns an
                    // empty string, so this line is as optional as the headline
                    // above it. Gating it left the card a line short beside its
                    // neighbours — the inbox row had the same hole until this
                    // same day.
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body.copyWith(
                          fontSize: AppTheme.fsMeta,
                          color: AppTheme.textSecondary),
                    ),
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

/// The amber band above a notification list that failed to re-read.
///
/// The tone is the one `stale_catalogue_copy.dart`, `chat_list_screen` and
/// `worker_home_screen` already use (`accentDeep` over `accentWash`), so a
/// screen that is quietly out of date looks the same wherever it is found. The
/// unread pip it protects is also amber, and that is deliberate rather than a
/// clash: both mean the same thing here — something on this screen is not yet
/// the server's.
class _StaleNotificationsBanner extends StatelessWidget {
  const _StaleNotificationsBanner({required this.line});

  /// The composed sentence from [staleNotificationsLineAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-notifications'),
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
              key: const Key('stale-notifications-line'),
              style: AppTheme.body.copyWith(
                color: AppTheme.accentDeep,
                height: AppTheme.lhProse,
                fontWeight: AppTheme.wControl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The band above a centre that is not showing the whole unread set.
///
/// A **sibling** of [_StaleNotificationsBanner], and deliberately not a reuse
/// of it: that one is `AppTheme.accentDeep` over `accentWash` because what it
/// protects is the *same* doubt the unread pip already wears. This one is the
/// neutral `infoWash`/`info` pair, because nothing here is in doubt — the
/// server stated a count and the app is reporting it. Two bands in the same
/// colour would read as one doubled warning and teach the user that amber
/// means «something is broken», which is exactly what the stale band's tone is
/// already carrying on seven other screens.
class _ShortfallBanner extends StatelessWidget {
  const _ShortfallBanner({required this.line});

  /// The composed sentence from [notificationShortfallLineAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('short-notifications'),
      color: AppTheme.infoWash,
      borderColor: AppTheme.info,
      padding: AppTheme.cardPadRail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_outlined,
              size: AppTheme.s20, color: AppTheme.info),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              line,
              key: const Key('short-notifications-line'),
              style: AppTheme.body.copyWith(
                color: AppTheme.info,
                height: AppTheme.lhProse,
                fontWeight: AppTheme.wControl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
