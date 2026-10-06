import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/auth_gate.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';
import '../../core/location/place_state.dart';
import '../../core/theme/app_theme.dart';
import '../../data/first_run.dart';
import '../../data/project_order.dart';
import '../../data/repository.dart';
import '../../data/stale_home_strip_copy.dart';
import '../../data/unread_message_trust.dart';
import '../../data/unread_message_count.dart';
import '../../data/taxonomy.dart';
import '../../models/chat.dart';
import '../../models/project.dart';
import '../../models/worker.dart';
import '../../widgets/app_tab_bar.dart';
import '../../widgets/notifications_bell.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/client_start_card.dart';
import '../../widgets/project_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/ui.dart';
import '../../widgets/worker_card.dart';
import '../browse/browse_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/project_new_screen.dart';
import '../project/projects_screen.dart';
import '../worker/worker_profile_screen.dart';

/// Dual home screen for clients: find contractors, post a project,
/// track existing projects and messages.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key, this.clock});

  /// The wall clock, injectable so a test can age a stale band without
  /// waiting a real hour. Defaults to the system clock in the app.
  ///
  /// The bands under both strips report how old their rows are, so their
  /// wording is a function of the time between the read and the reader — the
  /// one thing a test cannot control by arranging a Future.
  final DateTime Function()? clock;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with WidgetsBindingObserver, UnreadCountOnResume {
  int _tab = 0;
  late final Repository _repo;

  /// The tab badge's confirmation flag. See `worker_home_screen.dart` and
  /// `app_scope.dart` — same flag, same reason it lives in the scope.
  late final UnreadMessageTrust _messages;
  late Future<List<WorkerProfile>> _topWorkers;

  @override
  void initState() {
    super.initState();
    // About the engine, not about this screen's dependencies — see
    // [UnreadCountOnResume].
    registerUnreadOnResume(this);
  }

  /// Android delivers this on every return to the foreground, and iOS too.
  ///
  /// The client is the role this matters most for: he is told all through the
  /// app to message contractors, so the people writing to him are strangers he
  /// chose, and a first message from one is the single event most likely to
  /// arrive while he is looking at something else. Before this read, the badge
  /// was written once by `didChangeDependencies` and then only by the
  /// deliberate gestures — pull, thread, pop — so a message that landed with
  /// the app open left the number frozen at its last navigation.
  ///
  /// Only the conversations are re-read: the guide and the strips are decided
  /// by the same list, so they come along for free, and a resume is not a
  /// reason to re-ask for the top contractors and spend the user's data to
  /// redraw a directory that has not moved.
  @override
  void readUnreadOnResume() {
    if (!_scopeReady || !mounted) return;
    if (_guest) return;
    final future = _repo.conversations();
    _conversations = future;
    _unreadToken++;
    _resolveUnread();
  }

  /// Null for a signed-out visitor: there is no «مشاريعي» without an account,
  /// so the strip is not requested and cannot fail. The founder saw exactly
  /// that failure — «تعذّر جلب المشاريع» — on the home of a visitor who had
  /// never signed in.
  Future<List<Project>>? _recentProjects;

  /// What the two home strips last read successfully, and the sentence for the
  /// last read that failed.
  ///
  /// Deliberately scoped to a *settled* answer. A read still in flight writes
  /// nothing here, so the previous strip survives it and the reader is never
  /// shown a skeleton over rows he did not ask to reload. The doubt is a fact
  /// about the data, so it is recorded as a *sentence* rather than as a flag
  /// and drawn on the strip it belongs to — the two reads behind [_refresh] can
  /// fail independently, and one band about «the screen» would be a claim
  /// about a strip that answered.
  ///
  /// See `stale_home_strip_copy.dart` — the seventh screen in this family, and
  /// the first where the two halves need different words.
  ///
  /// The contractors half is one [ContractorStripRead] **record** rather than
  /// three parallel nullables, and that is the whole fix. `_onPlaceChanged`
  /// re-arms this read with the phone's wilaya, so the strip's answer depends on
  /// a value the screen does not own: a bare `List?` cannot say which wilaya its
  /// rows belong to, so a *failed* switch fell back to the previous fix's
  /// contractors and drew them under a header naming a different city. The
  /// projects half stays three fields on purpose — `myProjects()` asks the same
  /// question every time, so there is nothing to key it with, and one read
  /// without a dimension is not a reason to invent one.
  ContractorStripRead? _workersRead;

  /// Bumped by every [_armWorkers] call, so a read that settles after a later
  /// one was issued is dropped instead of overwriting it.
  ///
  /// See the note on the generation inside that method: the wilaya stamped on
  /// the record catches a read that was *filed* wrongly, and cannot catch one
  /// that was *answered* late.
  int _workersToken = 0;

  List<Project>? _projectsCache;
  String? _projectsStaleReason;

  /// Bumped by every [_armProjects] call, so a read that settles after a later
  /// one was issued is dropped instead of overwriting it.
  ///
  /// The projects half had no token for four months of shipping while the
  /// contractors half beside it did, and the note on [_armWorkers] gave the
  /// reason as *the wilaya changing*. That reason was about the **question**,
  /// and it is correct — `myProjects()` asks the same thing every time, so
  /// there is nothing to key a record by. It is not the reason the token is
  /// load-bearing, and reading it that way is how the gap survived: a constant
  /// question is exactly why **two reads compete to write one slot**. A user
  /// posts a project, `_push` re-arms this read on the way back, the new read
  /// answers, and the read issued a moment *before* the post — parked on a slow
  /// connection — lands afterwards and installs the list that does not contain
  /// the project he just made.
  ///
  /// The rows are the newer ones for as long as the newer read succeeds, because
  /// the `FutureBuilder` draws its own answer. It goes wrong on the next
  /// failure, which is the frame this screen exists for: the strip falls back to
  /// the cache, and the cache is now the older list — on the one screen that
  /// lists his own jobs, and the only place he would look for it.
  int _projectsToken = 0;

  /// When each strip last read cleanly, so the band can say *how* old it is.
  ///
  /// The band already admits «هذه آخر نتيجة قرأناها»; this is the half it
  /// could not say. The two strips get **separate** stamps because they are two
  /// reads that fail independently, and one stamp shared by both is how a
  /// projects list that refreshed a second ago gets dated by a contractors read
  /// that has not landed in an hour.
  ///
  /// Written in the same `setState` that installs the cache, because the two
  /// are one fact: a stamp from a *different* read than the one on screen is
  /// worse than no stamp, because it is then confidently wrong. Null for a
  /// signed-out visitor, who has no strips to read at all.
  DateTime? _projectsReadAt;

  /// Ticks once a minute so an honest band ages without a re-read.
  ///
  /// Same reason and same resolution as the projects screen: the copy reports
  /// at minute granularity, so one tick per reported resolution cannot make
  /// the line stale by more than the words it prints. Without it a client who
  /// leaves the home open keeps reading «قبل 12 دقيقة» on rows that are now an
  /// hour old, which is the same lie in a slower costume. Cancelled in
  /// [dispose]; the shell's `IndexedStack` keeps this tab alive across every
  /// other one, so an uncancelled timer would outlive it and tick a dead state.
  Timer? _ageTimer;

  /// Points one strip at a read, and records what that read settled to.
  ///
  /// The cache is written on every settled success and cleared of doubt by the
  /// next one, so the band cannot outlive the read that answered it.
  ///
  /// `onError` does not `setState` on its own: this is called from inside a
  /// `setState` in [_reloadWorkers], [_reloadStrips] and [_refresh], and the
  /// answer to a future is a microtask later than all three, so the rebuild is
  /// scheduled here and lands after the caller's own.
  ///
  /// The wilaya is a **parameter**, decided by the caller at the instant the
  /// request is issued and travelling out with it. Reading `_place?.wilayaId`
  /// inside the `then` is this app's ninth recurrence of the same defect, in
  /// the one place where it is not a hypothetical: the GPS answer lands late by
  /// construction, so a read issued before it and a read issued after it are
  /// both in flight at once, and the rows get filed under whichever wilaya the
  /// phone happens to be holding when the answer arrives.
  void _armWorkers(Future<List<WorkerProfile>> read, {required String? wilaya}) {
    _topWorkers = read;
    // Every arming is a new **generation**, and a read that settles after a
    // later one was issued is ignored outright. Same rule [_readFirstRunGuide]
    // already applies to the guide, and the same reason it needs one there:
    // two reads for this strip are routinely in flight at once, because the
    // GPS answer lands late by construction and every pull re-arms the read.
    //
    // Without it a **late success overwrites newer state**: read 1 (Oran) is
    // parked on a slow connection, the fix moves back to Algiers, read 2 is
    // issued and fails — and then read 1 lands and replaces the honest record
    // with another question's rows. The wilaya stamped on the record cannot
    // catch that, because read 1's *own* stamp is correct: it was asked for
    // Oran and it answered Oran. What is wrong is that it answered at all.
    final token = ++_workersToken;
    read.then((list) {
      if (!mounted || token != _workersToken) return;
      setState(() {
        _workersRead = ContractorStripRead(
          rows: list,
          rowsAsked: wilaya,
          asked: wilaya,
          reason: null,
          // The clock *now*, not the moment the request was issued, so a read
          // in flight for forty seconds is dated when it actually landed.
          // Stamping at issue time would under-report the age on a slow
          // connection — the exact case where the number matters most.
          readAt: _now(),
        );
      });
      _armAgeTick();
    }, onError: (Object e, StackTrace _) {
      if (!mounted || token != _workersToken) return;
      setState(() {
        // **Kept, not replaced.** This is the half a record can get wrong in
        // the other direction: writing a fresh record with `rows: null` throws
        // away the contractors the last good read returned, so a blink during
        // a pull — the gesture this screen's whole stale-read family exists
        // for — blanks the strip and tells a client on the first screen he
        // opens that the marketplace is empty.
        //
        // The stamp is carried over untouched, because it is the age of *those
        // rows* and nothing that has happened since has made them newer.
        final prev = _workersRead;
        _workersRead = ContractorStripRead(
          rows: prev?.rows,
          // **Carried, never re-derived.** The rows that survive belong to the
          // question `prev` asked, which is not this read's question — that is
          // the whole difference between a pull and a switch, and it is the one
          // thing a single `asked` field cannot hold: a failed read that keeps
          // another question's rows is describing **two** facts at once, and
          // folding them into one field is how the switch half of this fix
          // came back broken when it was first written.
          rowsAsked: prev?.rowsAsked,
          // The failed read answers the question it was **issued** for. A pull
          // inside one fix is the same question and keeps its rows; a switch is
          // a different one and has nothing of its own.
          asked: wilaya,
          reason: errorCopy(e),
          readAt: prev?.readAt,
        );
      });
    });
  }

  /// The projects half of [_armWorkers]. Not null-guarded here, because every
  /// call site already checks [_guest] — a visitor has no projects read at all,
  /// and asking for one would only produce the error state this screen must not
  /// show him.
  void _armProjects(Future<List<Project>> read) {
    _recentProjects = read;
    // The generation, for the same reason [_armWorkers] takes one: every pull
    // and every return from a posted project re-arms this read, so two are
    // routinely in flight at once, and the older one must not write last. The
    // question cannot change here, so there is no stamp that could catch this —
    // the read is filed correctly and simply answers late, which is the half a
    // record stamped with its question cannot see.
    final token = ++_projectsToken;
    read.then((list) {
      if (!mounted || token != _projectsToken) return;
      setState(() {
        _projectsCache = list;
        _projectsStaleReason = null;
        _projectsReadAt = _now();
      });
      _armAgeTick();
    }, onError: (Object e, StackTrace _) {
      if (!mounted || token != _projectsToken) return;
      setState(() => _projectsStaleReason = errorCopy(e));
    });
  }

  /// The same endpoint the messages tab reads. The client home needs it because
  /// the first-run guide has to disappear as soon as the owner has contacted
  /// somebody. Null for a visitor, for the same reason as the projects above.
  Future<List<Conversation>>? _conversations;

  /// True while nobody is signed in.
  bool _guest = false;

  /// Unread messages across the threads, or 0 while nothing is known.
  ///
  /// **A plain int, not the `_conversations` future read inside `build`** — a
  /// future cannot be resolved in a build method, so doing that would hand the
  /// tab a permanent 0 and ship the badge as another feature that is complete
  /// and unreachable. The value is written by `_resolveUnread` below.
  ///
  /// A **failed read leaves the count alone**: the last number the phone
  /// actually read is honest, whereas a 0 would be the app asserting «you are
  /// caught up» from a request that never landed.
  int _unreadMessages = 0;

  /// Sums the conversations the client shell already holds.
  ///
  /// Token-guarded, because `_reloadStrips` re-arms `_conversations` on every
  /// pop-back: without it a slow answer to an abandoned read lands last and
  /// paints a count the user has already moved past.
  void _resolveUnread() {
    final future = _conversations;
    if (future == null) {
      _unreadMessages = 0;
      return;
    }
    final token = _unreadToken;
    future.then((list) {
      if (!mounted || token != _unreadToken) return;
      _messages.restore();
      if (_unreadMessages == unreadMessageTotal(list)) return;
      setState(() => _unreadMessages = unreadMessageTotal(list));
    }).catchError((Object _) {
      // A failed conversations read is the badge's own read, so it is the most
      // direct way for the count to stop being a fact. Mute the pip; do not
      // zero it — see `unread_message_trust.dart`.
      //
      // **Checked against the generation, like the success arm above.** It was
      // not, and that made this the third site of one defect: the shell's
      // resume read and the pull both re-arm [_conversations], so a read that
      // parked on a slow connection and failed *after* a newer one had landed
      // muted the pip for the rest of the session — over a count the server
      // had answered correctly seconds earlier, with nothing left in flight to
      // restore it. The flag is a claim about the number *now* on the tab, and
      // a read the user has already replaced knows nothing about it.
      if (!mounted || token != _unreadToken) return;
      _messages.withdraw();
    });
  }

  /// Bumped per read so a stale answer cannot overwrite a newer one.
  int _unreadToken = 0;

  /// Where the phone is, once the app knows. Decides which contractors come
  /// first and which wilaya the header names.
  PlaceState? _place;

  /// Whether the explore tab shows the first-run guide. `false` until the two
  /// strips answer, so a slow connection never promises a first run it cannot
  /// back up.
  bool _firstRun = false;

  /// Guards the guide against a stale answer: every re-read takes a token and
  /// only the newest one is allowed to write.
  int _guideToken = 0;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    final scope = AppScope.of(context);
    _repo = Repository(scope.api);
    _messages = scope.messages;
    _guest = AuthGate.isGuest(context);
    _place = AppScope.maybeOf(context)?.place;
    _place?.addListener(_onPlaceChanged);
    _armWorkers(_repo.topWorkers(limit: 12, preferWilaya: _place?.wilayaId),
        wilaya: _place?.wilayaId);
    if (_guest) {
      // Nothing to read without an account, and nothing to decide either: the
      // two session-only strips stay empty and the tab shows the way in.
      _recentProjects = null;
      _conversations = null;
      _unreadMessages = 0;
    } else {
      _armProjects(_repo.myProjects());
      _conversations = _repo.conversations();
      _unreadToken++;
      _resolveUnread();
      _readFirstRunGuide();
    }
  }

  /// The fix can land after the first paint — the stored one at boot, or a
  /// fresh GPS answer. When it does, the one strip that answers «who is near
  /// me» is re-read once; nothing else on the screen moves.
  void _onPlaceChanged() {
    final id = _place?.wilayaId;
    if (!mounted || id == null) return;
    // Block body for the reason written on [_reloadWorkers]: an arrow closure
    // here returns the future it assigns, and `setState` throws on a
    // Future-returning callback in debug. A GPS answer landing after boot is an
    // everyday event on this screen, so this was throwing on the main path.
    setState(() {
      _armWorkers(_repo.topWorkers(limit: 12, preferWilaya: id), wilaya: id);
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _place?.removeListener(_onPlaceChanged);
    unregisterUnreadOnResume(this);
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [CustomerHomeScreen.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Starts the once-a-minute tick that ages the bands, once there is a stamp
  /// to age.
  ///
  /// Re-armed from the same place the stamps are written, so a re-read that
  /// puts the old stamp back does not leave two live timers. Called from
  /// [_armWorkers] and [_armProjects] rather than from `build`, because a
  /// timer created in `build` is a new timer on every frame and the tick would
  /// multiply.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Nothing to age yet: a first read that has not landed has no rows, and
      // a band only ever appears over rows that do.
      if (_workersRead?.readAt == null && _projectsReadAt == null) return;
      setState(() {});
    });
  }

  /// Decides whether this account is still on its first run, from the client's
  /// own projects and conversations. Either request failing means "no guide":
  /// a card that keeps telling a client who already posted to post reads as a
  /// broken app, and silence is the cheaper mistake.
  void _readFirstRunGuide() {
    final projects = _recentProjects;
    final conversations = _conversations;
    // A visitor has no history to read, and the guide is about a history.
    if (projects == null || conversations == null) return;
    final token = ++_guideToken;
    _resolveFirstRun(token, projects, conversations);
  }

  Future<void> _resolveFirstRun(
    int token,
    Future<List<Project>> projectsFuture,
    Future<List<Conversation>> conversationsFuture,
  ) async {
    List<Project>? projects;
    List<Conversation>? conversations;
    try {
      projects = await projectsFuture;
    } catch (_) {
      projects = null;
    }
    try {
      conversations = await conversationsFuture;
    } catch (_) {
      conversations = null;
    }
    if (!mounted || token != _guideToken) return;
    final needed = clientNeedsFirstRunGuideFor(
      projects: projects,
      conversations: conversations,
    );
    if (needed != _firstRun) setState(() => _firstRun = needed);
  }

  /// Retry handlers for the two home strips. They call the same repository
  /// methods the screen already used — just a second time, on demand.
  ///
  /// Written with a block body, not `() => _topWorkers = …`. The arrow form made
  /// the closure *return* the future it had just assigned, and
  /// `State.setState` throws the moment a callback returns a `Future`
  /// (framework.dart:1202-1214) — inside an assert, so only in debug, which is
  /// exactly why it stayed invisible in a release build. The read still ran and
  /// the strip still updated, so the button worked; it was throwing underneath
  /// itself on every tap, and the pull gesture drove the same handler.
  void _reloadWorkers() => setState(() {
        _armWorkers(_repo.topWorkers(limit: 12, preferWilaya: _place?.wilayaId),
            wilaya: _place?.wilayaId);
      });
  void _reloadProjects() => setState(_reloadStrips);

  /// Pull-to-refresh on the explore tab.
  ///
  /// The gesture a user reaches for first when a home screen has gone stale,
  /// and this was the last big read in the app with no way to answer it: a
  /// client coming back after an hour — a contractor signed up across town, a
  /// quote landed, his own project moved to «قيد التنفيذ» — got the same
  /// screen and the only way to move it was killing the app.
  ///
  /// Unlike its four siblings this is **three** reads behind one gesture: the
  /// top contractors, his own projects, and the conversations that decide the
  /// first-run guide. So the contract is written down here instead of left to
  /// chance:
  ///
  ///  * **What the indicator waits on** — all of them, through [Future.wait].
  ///    A pull that fired and returned would take the spinner down while the
  ///    home was still loading, which is the one thing the spinner is for.
  ///  * **What it says when one of the three is dead** — nothing new. Every
  ///    read already has its own `FutureBuilder` and its own error state, so a
  ///    failed contractors call is announced in place as «تعذّر جلب المقاولين»
  ///    with its own retry button, exactly as it is without a pull. Letting the
  ///    gesture itself fail would throw away the two reads that did answer and
  ///    trade a message that names the dead thing for a generic one.
  ///  * **A visitor is never asked to read what he has no account for** — the
  ///    two session-only strips stay null, so his pull is the contractor strip
  ///    alone and the «إنشاء حساب» card is untouched.
  Future<void> _refresh() async {
    _reloadWorkers();
    _reloadProjects();
    // The setters above have already installed the new futures, so the wait is
    // on the requests *this* pull issued and not on the ones it replaced.
    final reads = <Future<void>>[
      _topWorkers.then((_) {}, onError: (_, __) {}),
      if (!_guest) _recentProjects!.then((_) {}, onError: (_, __) {}),
      if (!_guest) _conversations!.then((_) {}, onError: (_, __) {}),
    ];
    await Future.wait(reads);
  }

  /// Re-reads everything the explore tab knows about this client. The guide is
  /// derived from two of those answers, so it is re-evaluated with them. A
  /// visitor has neither, and asking for them would only produce the two error
  /// states this screen must not show him.
  void _reloadStrips() {
    if (_guest) return;
    _armProjects(_repo.myProjects());
    _conversations = _repo.conversations();
    // The count is re-summed here because **coming back from a thread is what
    // clears it**: the server marks a conversation read when it is opened, so
    // without this the badge would still show the pre-read number to a user
    // who had just read every one of those messages.
    _unreadToken++;
    _resolveUnread();
    _readFirstRunGuide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        _ExploreView(
          firstRun: _firstRun,
          topWorkers: _topWorkers,
          workersRead: _workersRead,
          workersQuestion: _place?.wilayaId,
          projectsReadAt: _projectsReadAt,
          now: _now(),
          recentProjects: _recentProjects,
          projectsCache: _projectsCache,
          projectsStaleReason: _projectsStaleReason,
          guest: _guest,
          onRetryWorkers: _reloadWorkers,
          onRetryProjects: _reloadProjects,
          onRefresh: _refresh,
          onPost: () => _gatedPost(),
          onBrowseAll: () => _push(const BrowseScreen(customerSide: true)),
          onSeeAllProjects: () => setState(() => _tab = 1),
          onBrowseCategory: (slug) =>
              _push(BrowseScreen(customerSide: true, initialCategory: slug)),
          onWorker: (w) => _push(WorkerProfileScreen(workerId: w.id)),
          onProject: (p) =>
              _push(ProjectDetailScreen(projectId: p.id, repo: _repo)),
        ),
        ProjectsScreen(repo: _repo),
        // A client with no conversation yet is sent to the directory that
        // starts one; the inbox itself can never create the first message.
        ChatListScreen(
          repo: _repo,
          initial: _conversations,
          onDiscover: () => _push(const BrowseScreen(customerSide: true)),
          // The tab's number is the sum of this list, so a list that changed
          // under the shell's back has to change the sum with it. Without this
          // the badge is the shell's last read and the rows are whatever the
          // inbox last drew — two numbers for one thing on one screen.
          onRead: (list) {
            if (!mounted) return;
            // A **landed** conversations read, so the count is the server's
            // again. The same restore the contractor's shell keeps at its
            // `onRead`: without it a single dropped request mutes the pip for
            // the rest of the session, because the withdrawal would have no
            // matching restore on the path a read actually lands.
            _messages.restore();
            setState(() => _unreadMessages = unreadMessageTotal(list));
          },
        ),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: AppTabBar(
        index: _tab,
        onSelect: (i) => setState(() => _tab = i),
        // Not `const`: the messages tab carries a count read from the server,
        // so this list is rebuilt on every repaint. The other three are still
        // `const` and cost nothing.
        items: [
          const AppTabItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'استكشف'),
          const AppTabItem(
              icon: Icons.folder_outlined,
              activeIcon: Icons.folder_rounded,
              label: 'مشاريعي'),
          AppTabItem(
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'الرسائل',
              badge: _unreadMessages,
              // The one destination whose count comes from the conversations
              // table, and so the one that can be unconfirmed. Stated as a
              // flag on the item rather than matched on the label.
              countsMessages: true),
          const AppTabItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'حسابي'),
        ],
        // A client's one repeating action is posting the next project.
        action: AppTabAction(
          icon: Icons.add_rounded,
          label: 'مشروع جديد',
          onTap: () => _gatedPost(),
        ),
      ),
    );
  }

  /// Posting a project is the first thing a visitor cannot do signed out, so
  /// this is where the account form appears — not at the door of the app.
  Future<void> _gatedPost() async {
    if (!await AuthGate.requireAuth(context, what: 'لنشر مشروعك')) return;
    if (!mounted) return;
    _push(const ProjectNewScreen());
  }

  /// Pushes a screen and re-reads the home strips when it pops.
  ///
  /// Posting the first project has to make the first-run guide disappear, and
  /// that decision is made from the very lists this tab loads — so the screen
  /// the user returns to cannot keep the answers it had before he posted.
  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (mounted) setState(_reloadStrips);
    });
  }
}

/// The "explore" tab: branded header, search, categories, top contractors and
/// the client's own most recent projects.
class _ExploreView extends StatelessWidget {
  /// True while this client has neither posted a project nor contacted anybody.
  final bool firstRun;
  final Future<List<WorkerProfile>> topWorkers;

  /// The last settled answer for each strip, and the sentence for the last read
  /// that failed. Held by the parent so the doubt survives the strip's own
  /// re-read; see the state fields on `_CustomerHomeScreenState`.
  /// The last contractors read this screen settled, and the doubt attached to
  /// it. One record rather than three arguments — see
  /// [_CustomerHomeScreenState._workersRead].
  final ContractorStripRead? workersRead;

  /// The wilaya the strip is currently asking about.
  ///
  /// Read at **build** time, not captured with the read: this is the question
  /// *now*, and the cache records the question it answered. The fallback is
  /// gated on the two being the same question, which is what makes a failed
  /// *switch* answer with an honest «تعذّر جلب المقاولين» instead of the previous
  /// city's contractors under a header naming a different one.
  final String? workersQuestion;
  final List<Project>? projectsCache;
  final String? projectsStaleReason;

  /// When the projects strip last read cleanly, so its band can say how old the
  /// rows under it are. The contractors half carries its own stamp inside
  /// [workersRead] — one read, one record.
  final DateTime? projectsReadAt;

  /// The instant the age is measured against, taken **once per build** so both
  /// bands on a screen cannot disagree about "now" by the microseconds between
  /// two calls.
  final DateTime now;

  /// Null for a signed-out visitor — the tab then shows the way in instead of
  /// a strip it has nothing to put in.
  final Future<List<Project>>? recentProjects;

  /// True while nobody is signed in.
  final bool guest;
  final VoidCallback onRetryWorkers;
  final VoidCallback onRetryProjects;

  /// The pull gesture. A `Future<void>` rather than a `VoidCallback` so the
  /// indicator can hold itself on screen until every read behind it answers.
  final Future<void> Function() onRefresh;

  final VoidCallback onPost;
  final VoidCallback onBrowseAll;
  final VoidCallback onSeeAllProjects;
  final void Function(String) onBrowseCategory;
  final void Function(WorkerProfile) onWorker;
  final void Function(Project) onProject;

  const _ExploreView({
    required this.firstRun,
    required this.topWorkers,
    required this.workersRead,
    required this.workersQuestion,
    required this.recentProjects,
    required this.projectsCache,
    required this.projectsStaleReason,
    required this.projectsReadAt,
    required this.now,
    required this.guest,
    required this.onRetryWorkers,
    required this.onRetryProjects,
    required this.onRefresh,
    required this.onPost,
    required this.onBrowseAll,
    required this.onSeeAllProjects,
    required this.onBrowseCategory,
    required this.onWorker,
    required this.onProject,
  });

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).auth.user;
    final rawName = user?.fullName.trim() ?? '';
    // The profile wilaya comes first — it is what the owner said about himself.
    // Failing that, the phone's own answer, named as such so the header never
    // claims a location the visitor did not give.
    final profileWilaya = user?.wilaya;
    final place = AppScope.maybeOf(context)?.place;
    final fromPhone = (profileWilaya == null || profileWilaya.isEmpty)
        ? place?.wilayaId
        : null;
    final wilayaId = (profileWilaya == null || profileWilaya.isEmpty)
        ? fromPhone
        : profileWilaya;
    // Resolved before the branch, not after: the old code only asked whether the
    // id was *non-empty*, so a code this build does not know passed the test and
    // then printed the fallback — the customer's home header greeted him with
    // «الجزائر» for a wilaya nobody had named. An id that resolves to nothing
    // is the same as no id at all, and the header says «كل الولايات».
    final resolvedWilaya = Taxonomy.wilayaNameOrNull(wilayaId);
    final location = resolvedWilaya == null
        ? 'كل الولايات'
        : fromPhone != null
            ? '$resolvedWilaya • موقعك'
            : resolvedWilaya;

    // `AlwaysScrollableScrollPhysics` is what keeps the gesture reachable when
    // the page is short enough that the content does not overflow. `ScrollView`
    // already defaults a vertical, controllerless scroll view to exactly that
    // physics (scroll_view.dart:141-148), so on this screen the line is
    // belt-and-braces — unlike the result list the sibling screen had to
    // defend. It is written out because the test asserts the contract on the
    // widget, and a contract nobody wrote down is one nobody can check.
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.navy,
      backgroundColor: AppTheme.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Branded header (greeting + location + search) ────────────────
          SliverToBoxAdapter(
            child: _HomeHeader(
              name: rawName.isEmpty ? null : rawName,
              location: location,
              onSearch: onBrowseAll,
            ),
          ),

          // ── First-run guide ──────────────────────────────────────────────
          // A project owner opening the app for the first time used to get the
          // marketplace with no explanation of what to do first. He gets the
          // three steps and one obvious action instead — right under the header,
          // where he cannot miss them.
          if (firstRun)
            SliverToBoxAdapter(
              child: ClientStartCard(
                onPost: onPost,
                onBrowseWorkers: onBrowseAll,
              ),
            )
          // ── The action this screen exists for ────────────────────────────
          // Publishing a project is the only thing on this screen that gets work
          // done; everything else here is browsing, and the categories and the
          // contractor strip look the same to every visitor. So the one action
          // leads. While the first-run guide is up it already carries this
          // action twice, and the banner stands down.
          else
            SliverToBoxAdapter(child: _PostProjectBanner(onTap: onPost)),

          // ── Categories ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionTitle(
                'التخصصات',
                icon: Icons.grid_view_rounded,
                actionText: 'عرض الكل',
                onAction: onBrowseAll,
              ),
            ),
          ),
          SliverToBoxAdapter(child: CategoryGrid(onTap: onBrowseCategory)),

          // ── Top-rated contractors ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionTitle(
                'أفضل المقاولين',
                icon: Icons.workspace_premium_rounded,
                actionText: 'عرض الكل',
                onAction: onBrowseAll,
              ),
            ),
          ),
          FutureBuilder<List<WorkerProfile>>(
            future: topWorkers,
            builder: (context, snap) {
              // The family's split, unchanged: a failed *first* read has
              // nothing to draw and keeps the error; a failed *re-read* keeps
              // the rows and states the doubt. `null` has to mean "nothing to
              // draw" for a **waiting** read too, or an unanswered request
              // falls out of the skeleton into the empty strip below and tells
              // a client on a slow connection that there are no contractors
              // before the phone has even asked.
              final waiting = snap.connectionState != ConnectionState.done;
              final failed = snap.hasError && !waiting;
              // **The gate.** A read that settled for a *different* wilaya is
              // not a fallback for this one — it is another question's answer,
              // and drawing it here is how «مقاولو وهران» ends up under a
              // header that says «موقعك: الجزائر». Same fix the directory and the
              // projects list shipped, one layer down: the rows are real and they
              // are not the answer.
              //
              // A **pull** inside one fix is the same question asked twice, so
              // it keeps its rows; only a *switch* has nothing of its own and
              // says so.
              // **Two** gates, and they answer different questions, which is
              // the half a single `asked` comparison gets wrong.
              //
              // `mine` — did the read that just settled ask what the screen is
              // asking? It decides whether there is a *doubt* about this
              // question: a failure for Oran is not a doubt about Algiers.
              //
              // `rowsMine` — do the rows on hand answer this question? It
              // decides whether they may be *drawn*. A failed read inside one
              // fix keeps its rows and both are true; a failed **switch** keeps
              // the previous fix's rows and only the first is true, so those
              // rows are not an answer to anything on screen and the honest
              // screen is the error, not another city's contractors.
              final mine = workersRead?.asked == workersQuestion;
              final rowsMine = workersRead?.rowsAsked == workersQuestion;
              final stale = failed && mine && workersRead?.reason != null;
              final shown = (waiting || failed)
                  ? (rowsMine ? workersRead?.rows : null)
                  : (snap.data ?? const <WorkerProfile>[]);
              if (shown == null) {
                if (waiting) {
                  return const SliverToBoxAdapter(
                      child: Shimmer(child: _WorkerStripSkeleton()));
                }
                return SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.wifi_off_rounded,
                    title: 'تعذّر جلب المقاولين',
                    message: 'تحقق من اتصالك بالإنترنت ثم أعد المحاولة',
                    actionLabel: 'إعادة المحاولة',
                    onAction: onRetryWorkers,
                  ),
                );
              }
              if (shown.isEmpty) {
                // "سيظهر أفضل المقاولين هنا" left the client with nothing to do.
                // The one action that makes contractors appear for him is the one
                // he can take himself: publish the project so it reaches them.
                return SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.people_outline_rounded,
                    title: 'لا يوجد مقاولون بعد',
                    message: 'لم يسجّل أي مقاول في منطقتك حتى الآن.\n'
                        'انشر مشروعك وسيصل إليه أول المقاولين المسجّلين.',
                    actionLabel: 'انشر مشروعاً ليصلك مقاول',
                    actionIcon: Icons.add_rounded,
                    onAction: onPost,
                  ),
                );
              }
              // The doubt is an annotation *on* the strip, so it sits above
              // the cards rather than replacing them — a client who has pulled
              // twice and failed twice still has the contractors he was
              // looking at, and the band is what says so.
              return SliverToBoxAdapter(
                child: Column(
                  children: [
                    if (stale)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppTheme.gutter, 0, AppTheme.gutter, AppTheme.s12),
                        child: _StaleHomeStripBand(
                          key: const Key('stale-workers'),
                          line: staleHomeStripLineWithAgeAr(
                              workersRead!.reason!,
                              workersRead!.readAt,
                              StaleHomeStrip.contractors,
                              now: now),
                        ),
                      ),
                    SizedBox(
                      height: AppTheme.stripH,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, i) => WorkerCard(
                          worker: shown[i],
                          variant: WorkerCardVariant.vertical,
                          onTap: () => onWorker(shown[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── The client's own recent projects ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SectionTitle(
                'مشاريعي الأخيرة',
                icon: Icons.folder_outlined,
                actionText: 'عرض الكل',
                onAction: onSeeAllProjects,
              ),
            ),
          ),
          if (recentProjects == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SignInForProjects(onPost: onPost),
              ),
            )
          else
            FutureBuilder<List<Project>>(
              future: recentProjects,
              builder: (context, snap) {
                // Same split as the contractors strip above, and for the same
                // reason, but the stakes are higher: nothing else in the app
                // lists *his own* jobs, so erasing these three rows is not an
                // inconvenience — it is the home screen forgetting what he
                // posted. A `null` here has to mean "nothing to draw" for a
                // waiting read too, or the first run is told he has no projects
                // before the request answers.
                final waiting = snap.connectionState != ConnectionState.done;
                final failed = snap.hasError && !waiting;
                final stale = failed && projectsStaleReason != null;
                final shown = (waiting || failed)
                    ? projectsCache
                    : (snap.data ?? const <Project>[]);
                if (shown == null) {
                  if (waiting) {
                    return const SliverToBoxAdapter(
                        child: Shimmer(child: _ProjectStripSkeleton(count: 2)));
                  }
                  return SliverToBoxAdapter(
                    child: EmptyView(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذّر جلب المشاريع',
                      message: 'تحقق من اتصالك بالإنترنت ثم أعد المحاولة',
                      actionLabel: 'إعادة المحاولة',
                      onAction: onRetryProjects,
                    ),
                  );
                }
                if (shown.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: firstRun
                          ? const _FirstRunProjectsHint()
                          : _NoProjectsCard(onPost: onPost),
                    ),
                  );
                }
                // Newest first, and the sort happens BEFORE the take — the
                // three drawn here have to be the three most recent, which
                // `take(3)` on server order cannot promise. The heading above
                // says «مشاريعي الأخيرة» and this is the line that has to make
                // it true. See `project_order.dart`.
                final recent = newestProjectFirst(shown).take(3).toList();
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      children: [
                        if (stale)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppTheme.s12),
                            child: _StaleHomeStripBand(
                              key: const Key('stale-projects-strip'),
                              line: staleHomeStripLineWithAgeAr(
                                  projectsStaleReason!,
                                  projectsReadAt,
                                  StaleHomeStrip.projects,
                                  now: now),
                            ),
                          ),
                        for (var i = 0; i < recent.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          ProjectCard(
                            project: recent[i],
                            onTap: () => onProject(recent[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

/// The band that states a strip failed to re-read, without erasing it.
///
/// The **same widget for both strips on purpose** — the projects list, the
/// inbox and the directory each drew their own, and four near-identical
/// private classes is how one of them ends up in the error red instead of the
/// wash. The doubt is a fact about the data, not an alarm, so it is drawn in
/// the same `accentDeep`-on-`accentWash` as its siblings rather than in the red
/// of the full-screen error it replaces.
class _StaleHomeStripBand extends StatelessWidget {
  const _StaleHomeStripBand({super.key, required this.line});

  /// The composed sentence from `staleHomeStripLineAr`.
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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

/// ── Branded header ───────────────────────────────────────────────────────
/// Navy gradient block that owns the status-bar inset (so the colour reaches
/// the top of the screen), carrying the brand mark, the greeting, the user's
/// wilaya and the search entry point.
class _HomeHeader extends StatelessWidget {
  final String? name;
  final String location;
  final VoidCallback onSearch;

  const _HomeHeader({
    required this.name,
    required this.location,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.navyDeep, AppTheme.navySoft],
        ),
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppTheme.rXl)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.home_work_rounded,
                        color: AppTheme.navy, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مرحباً بك',
                          style: AppTheme.caption.copyWith(
                              fontSize: AppTheme.fsCaption,
                              color: AppTheme.onNavyMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name ?? S.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.h1.copyWith(
                              fontSize: AppTheme.fsBar, color: AppTheme.onNavy),
                        ),
                      ],
                    ),
                  ),
                  const NotificationsBell(onNavy: true),
                ],
              ),
              const SizedBox(height: 14),
              // Location pill — wilaya the user registered with.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.onNavy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 15, color: AppTheme.accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.label.copyWith(
                            fontSize: AppTheme.fsCaption,
                            color: AppTheme.onNavy),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ماذا تريد أن تنجز في منزلك؟',
                style: AppTheme.body.copyWith(
                    fontSize: AppTheme.fsSmall, color: AppTheme.onNavyMuted),
              ),
              const SizedBox(height: 14),
              _SearchBar(onTap: onSearch),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search entry point. It is a button, not an input: tapping it opens the
/// browse screen, keeping one search experience for the whole app.
class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.tapMin),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppTheme.navy, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ابحث عن حرفي أو تخصص...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(
                      fontSize: AppTheme.fsBody, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The single most prominent action on the home screen.
///
/// It is filled with the accent and lettered in navy — the same pair
/// [PrimaryButton] uses, so the biggest thing on the page is unambiguously the
/// one to press. It used to be navy and sat below the categories, which made it
/// both the same colour as the header above it and the third block down.
class _PostProjectBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _PostProjectBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Material(
        key: const Key('client-post-cta'),
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppTheme.navy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_home_work_rounded,
                      color: AppTheme.accent, size: 27),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'انشر مشروعك مجاناً',
                        style: AppTheme.h2.copyWith(
                            fontSize: AppTheme.fsLead, color: AppTheme.navy),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'استقبل عروض مقاولين موثوقين خلال أيام',
                        style: AppTheme.bodySoft.copyWith(
                            fontSize: AppTheme.fsCaption, color: AppTheme.navy),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_left_rounded,
                    color: AppTheme.navy, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Friendly card shown when the client has not posted anything yet. The call
/// to action goes straight to the post-project form.
class _NoProjectsCard extends StatelessWidget {
  final VoidCallback onPost;

  const _NoProjectsCard({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppTheme.cardPad,
      child: Column(
        children: [
          const IconBubble(
            icon: Icons.folder_open_rounded,
            tint: AppTheme.accentDeep,
            wash: AppTheme.accentWash,
            size: 64,
          ),
          const SizedBox(height: 14),
          Text(
            'لا مشاريع بعد',
            textAlign: TextAlign.center,
            style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'انشر مشروعك الأول واستقبل عروض المقاولين الموثوقين',
            textAlign: TextAlign.center,
            style: AppTheme.bodySoft,
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'انشر مشروعك',
            icon: Icons.add_rounded,
            onPressed: onPost,
          ),
        ],
      ),
    );
  }
}

/// What a visitor sees where his own projects would be.
///
/// The founder, verbatim: «remove ... تعذر جلب المشاريع تحقق من اتصالك بالإنترنت
/// ثم أعد المحاولة». Nothing failed — there is simply no account to read from —
/// so the strip invites him in instead of reporting a fault that never happened.
class _SignInForProjects extends StatelessWidget {
  final VoidCallback onPost;

  const _SignInForProjects({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('guest-projects-invite'),
      padding: AppTheme.cardPad,
      child: Column(
        children: [
          const IconBubble(
            icon: Icons.folder_open_rounded,
            tint: AppTheme.accentDeep,
            wash: AppTheme.accentWash,
            size: 64,
          ),
          const SizedBox(height: 14),
          Text(
            'مشاريعك تظهر هنا',
            textAlign: TextAlign.center,
            style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'أنشئ حساباً مجانياً لنشر مشروعك واستقبال عروض المقاولين، ومتابعة كل '
            'مشاريعك من هذه الصفحة.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySoft,
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            key: const Key('home-create-account'),
            label: 'إنشاء حساب',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: onPost,
          ),
        ],
      ),
    );
  }
}

/// Shown in the "recent projects" strip while the first-run guide owns the
/// publish action. The guide already offers it twice, so this only says what
/// will appear here.
class _FirstRunProjectsHint extends StatelessWidget {
  const _FirstRunProjectsHint();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppTheme.cardPad,
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded,
              size: 20, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ستظهر هنا مشاريعك بعد نشر أول مشروع',
              style: AppTheme.bodySoft.copyWith(
                  fontSize: AppTheme.fsMeta, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the horizontal contractor strip — grey placeholders that read
/// as "loading" instead of a bare spinner.
class _WorkerStripSkeleton extends StatelessWidget {
  const _WorkerStripSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.stripH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: AppTheme.stripCardW,
          padding: AppTheme.cardPadRail,
          decoration: AppTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  SkeletonBox(
                      height: 46,
                      width: 46,
                      radius: 23,
                      color: SkeletonTone.base),
                  Spacer(),
                  SkeletonBox(
                      height: 18,
                      width: 18,
                      radius: 9,
                      color: SkeletonTone.base),
                ],
              ),
              SizedBox(height: 14),
              SkeletonBox(height: 13, width: 118, color: SkeletonTone.base),
              SizedBox(height: 9),
              SkeletonBox(height: 11, width: 92, color: SkeletonTone.base),
              SizedBox(height: 11),
              SkeletonBox(height: 12, width: 70, color: SkeletonTone.base),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton rows mirroring [ProjectCard] while the client's projects load.
class _ProjectStripSkeleton extends StatelessWidget {
  final int count;

  const _ProjectStripSkeleton({this.count = 2});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: EdgeInsets.only(bottom: i == count - 1 ? 0 : 12),
              padding: AppTheme.cardPad,
              decoration: AppTheme.cardDecoration,
              child: Row(
                children: const [
                  SkeletonBox(
                      height: 76,
                      width: 76,
                      radius: AppTheme.rSm,
                      color: SkeletonTone.base),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                            height: 14, width: 150, color: SkeletonTone.base),
                        SizedBox(height: 10),
                        SkeletonBox(
                            height: 12, width: 110, color: SkeletonTone.base),
                        SizedBox(height: 10),
                        SkeletonBox(
                            height: 12, width: 78, color: SkeletonTone.base),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the contractors strip last settled to, and the doubt attached to it.
///
/// One record — rows, the wilaya they answer, why the last read failed and
/// when — because those four are **one fact** about one read. Split across
/// parallel fields they can disagree: a stamp from a different read than the
/// rows is worse than no stamp, because it is then confidently wrong, and that
/// is not hypothetical here, it is what the split permitted.
///
/// See `_CustomerHomeScreenState._workersRead` for the defect this replaces.
class ContractorStripRead {
  const ContractorStripRead({
    required this.rows,
    required this.rowsAsked,
    required this.asked,
    required this.reason,
    required this.readAt,
  });

  /// What the server answered, or null when the read failed and there is
  /// nothing of its own to draw.
  final List<WorkerProfile>? rows;

  /// The wilaya the read was **issued** for, or null when the strip is
  /// unfiltered («كل الولايات»).
  ///
  /// Carried out rather than read back out of the state inside the `then`
  /// callback, which is the load-bearing half. The GPS answer lands late by
  /// construction — `PlaceState` fires its listener once the fix resolves, which
  /// is after the screen has already armed a read with no wilaya — so a read
  /// issued before the fix and one issued after it are both in flight at once.
  /// Tagging the rows with the *current* wilaya files the unfiltered answer
  /// under a filter chip that says otherwise, which is the identical defect one
  /// layer down, and the app has now shipped against it nine times.
  final String? asked;

  /// The question [rows] actually answer.
  ///
  /// **Separate from [asked] on purpose.** A failed read keeps the rows the
  /// last good read returned, and those rows answer *that* read's question —
  /// so a record that has only one of the two fields has to either lie about
  /// which city the rows are from, or throw them away. The second is what
  /// happened: the switch half of this fix shipped with a single `asked` and
  /// kept the previous fix's contractors under the new header, and the fix's
  /// own pull half shipped with `rows: null` and blanked the strip instead.
  /// One field could not tell those two failures apart, and both were live.
  final String? rowsAsked;

  /// The already-curated Arabic sentence for a failure, or null on success.
  ///
  /// A *sentence* rather than a flag, because the two strips behind one gesture
  /// can fail independently and a band about «the screen» would be a claim
  /// about a strip that answered.
  final String? reason;

  /// When these rows landed. Null on a failure, because nothing landed.
  final DateTime? readAt;
}
