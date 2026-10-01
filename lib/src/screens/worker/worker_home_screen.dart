import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/l10n/strings.dart';
import '../../core/location/place_state.dart';
import '../../core/auth_gate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/photo_count_copy.dart';
import '../../data/stale_market_copy.dart';
import '../../data/project_search.dart';
import '../../data/repository.dart';
import '../../data/unread_message_trust.dart';
import '../../data/taxonomy.dart';
import '../../data/quote_count_copy.dart';
import '../../data/unread_message_count.dart';
import '../../data/stats_freshness_copy.dart';
import '../../data/star_row_shape.dart';
import '../../data/worker_stats_copy.dart';
import '../../models/enums.dart';
import '../../models/chat.dart';
import '../../models/plan.dart';
import '../../models/project.dart';
import '../../models/worker.dart';
import '../../widgets/app_tab_bar.dart';
import '../../widgets/notifications_bell.dart';
import '../../widgets/big_button.dart';
import '../../widgets/feed_search_field.dart';
import '../../widgets/project_card.dart';
import '../../widgets/a11y.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../chat/chat_list_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/projects_screen.dart';
import '../verify/verification_screen.dart';
import 'my_portfolio_screen.dart';
import 'subscription_screen.dart';
import 'profile_edit_screen.dart';
import '../../core/l10n/error_copy.dart';

/// Dual home screen for contractors: browse open projects, filter by
/// specialty, enter their professional profile & verification.
class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen>
    with WidgetsBindingObserver, UnreadCountOnResume {
  int _tab = 0;
  late final Repository _repo;

  /// The tab badge's confirmation flag, read from the scope in
  /// [didChangeDependencies] — see `app_scope.dart` on why a flag has to
  /// outlive the route that withdrew it.
  late final UnreadMessageTrust _messages;

  bool _scopeReady = false;

  /// Captured with the repository, so the flag and the client that feeds it
  /// come from the same read of the scope.
  late final AppScope _scope;

  @override
  void initState() {
    super.initState();
    // Registered here and not in `didChangeDependencies` because the observer
    // is about the engine, not about this screen's dependencies. Paired with
    // the removal in `dispose` — see [UnreadCountOnResume].
    registerUnreadOnResume(this);
  }

  /// Android delivers this on every return to the foreground, and iOS too.
  ///
  /// **This is the read that was missing**, and it is the whole reason a
  /// message could land on a contractor's phone and the number on his tab
  /// never move. Before it, the badge was written exactly once — by
  /// `didChangeDependencies` — so the count the user trusted was the count
  /// from whenever the shell was built. Lock the phone, read a quote in
  /// another app, come back: the badge still said what it said at unlock, with
  /// nothing to tell him that was minutes or hours ago.
  ///
  /// The `_scopeReady` guard is the same one the bell keeps for the same
  /// reason: the engine can deliver a lifecycle message before
  /// `didChangeDependencies` has assigned `_repo`, and reading the `late final`
  /// then throws inside a framework callback.
  @override
  void readUnreadOnResume() {
    if (!_scopeReady || !mounted) return;
    _readConversations();
  }

  /// The conversations the messages tab reads, held so the unread count can
  /// be drawn on the tab itself.
  ///
  /// The contractor's header bell is mounted **only on tab 0**
  /// (`appBar: _tab == 0 ? … : null`), so before this the unread number left
  /// the app the moment he opened «الرسائل» — the one tab whose whole purpose
  /// is unread messages. He was standing in the inbox with nothing on screen
  /// saying anything was waiting.
  Future<List<Conversation>>? _conversations;

  /// Bumped per read so a slow answer from an abandoned read cannot land
  /// after a newer one and paint a count the user has already dismissed.
  int _conversationToken = 0;

  /// Unread messages across the threads, or 0 while nothing is known.
  ///
  /// **A plain int, not a `Future` read during `build`** — a future cannot be
  /// awaited in a build method, so resolving it inline would hand every tab a
  /// permanent 0 and ship the badge as another dead feature. The value is
  /// written by the `.then` below and read here as a plain field.
  int _unreadMessages = 0;

  /// Re-reads the conversations and repaints the tab count.
  ///
  /// A **failed read is a no badge**, not a zero: zero is «you are caught up»,
  /// which is a claim, and a dropped request supports no claim at all. The
  /// count only ever comes from a read that landed.
  void _readConversations() {
    if (AuthGate.isGuest(context)) {
      _conversations = null;
      _unreadMessages = 0;
      return;
    }
    final token = ++_conversationToken;
    final future = _repo.conversations();
    _conversations = future;
    future.then((list) {
      if (!mounted || token != _conversationToken) return;
      _messages.restore();
      setState(() => _unreadMessages = unreadMessageTotal(list));
    }).catchError((Object _) {
      // Leave the count alone: the last number we actually read is better
      // than a zero that claims he has nothing, and better than a stale
      // number presented as fresh — but say out loud that it is the latter.
      // Muting the pip is what stops "better than a stale number presented as
      // fresh" from quietly meaning "presented as fresh".
      // **The generation is checked here too, and that is the fix.** This arm
      // used to withdraw the pip unconditionally, while the success arm above
      // checks its token — so the one arm that could not be argued away from
      // the count's state was the one that had no guard. A read that parked on
      // a slow connection and failed *after* the next unlock's read had landed
      // muted the pip for the rest of the session, over a count the server had
      // answered correctly seconds earlier, with nothing left in flight able to
      // restore it. The withdrawal is a claim about the current count, so it is
      // only true for a read that is still the current one.
      if (!mounted || token != _conversationToken) return;
      _messages.withdraw();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _scope = AppScope.of(context);
    _repo = Repository(_scope.api);
    _messages = _scope.messages;
    _readConversations();
  }

  @override
  void dispose() {
    // The `IndexedStack` in `build` keeps this shell alive for as long as it
    // is on the stack, so an observer left registered outlives the state and
    // keeps re-reading — and calling `setState` on — a widget the framework
    // has already thrown away.
    unregisterUnreadOnResume(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _tab == 0
          ? AppBar(
              title: const Text(
                'المنصة',
                style: AppTheme.bar,
              ),
              actions: [
                const NotificationsBell(),
                IconButton(
                  icon: const Icon(Icons.badge_outlined),
                  tooltip: 'التوثيق والملف',
                  onPressed: () async {
                    // Signed out, the badge is the door to the account form:
                    // nothing here is readable without a session.
                    if (!await AuthGate.requireAuth(context,
                        what: 'لتوثيق حسابك',
                        as: UserRole.worker)) {
                      return;
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const VerificationScreen()));
                  },
                ),
              ],
            )
          : null,
      body: IndexedStack(index: _tab, children: [
        MarketplaceView(
        repo: _repo,
        // A visitor browsing the market must not hit the contractor endpoints:
        // without this flag the header asked for a profile it cannot have and
        // answered with «تعذّر جلب ملفك» on the dashboard the founder saw.
        guest: AuthGate.isGuest(context),
      ),
        // Both tabs below are dead ends without a job or a conversation: the
        // only thing that creates either one is the market on tab 0, so each
        // empty state can send the contractor back there.
        ProjectsScreen(repo: _repo, onDiscover: () => setState(() => _tab = 0)),
        ChatListScreen(
          repo: _repo,
          initial: _conversations,
          onDiscover: () => setState(() => _tab = 0),
          // The badge is drawn from the shell's copy of this list, so a
          // pull-to-refresh or a pop out of a thread that re-reads the inbox
          // has to re-sum here too — otherwise the tab keeps the old number
          // over a list the user just emptied, which is the disagreement this
          // badge exists to make impossible.
          onRead: (list) {
            if (!mounted) return;
            // A **landed** conversations read, so the count is the server's
            // again. Without this the pip would stay muted for ever after the
            // first dropped request: the withdrawal would have no matching
            // restore, because the resume path and this callback are the two
            // places a read actually lands.
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
        // so this list is built on every repaint. The other three entries are
        // still `AppTabItem(...)` with no badge and cost nothing extra.
        items: [
          const AppTabItem(
              icon: Icons.storefront_outlined,
              activeIcon: Icons.storefront_rounded,
              label: 'المنصة'),
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
        // A contractor's one repeating action is adding the work he has done.
        action: AppTabAction(
          icon: Icons.add_a_photo_outlined,
          label: 'أضف عملاً',
          onTap: () async {
            if (!await AuthGate.requireAuth(context,
                what: 'لإضافة صور أعمالك', as: UserRole.worker)) {
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MyPortfolioScreen()));
          },
        ),
      ),
    );
  }
}

/// The marketplace tab: contractor header + quick stats + the open-project
/// feed with a legible kit-based filter bar.
class MarketplaceView extends StatefulWidget {
  final Repository repo;

  /// True when nobody is signed in. The feed itself is public; only the
  /// branded "my stats" header needs an account.
  final bool guest;

  /// The wall clock the header's freshness line is measured against.
  ///
  /// Injected so the test can pin it: a header that renders «قبل 3 ساعات» only
  /// on the one run where the mock's clock happened to advance is a test that
  /// is green whenever it is green and worth nothing the day it is not. Null
  /// in production, which is [DateTime.now].
  final DateTime Function()? clock;

  const MarketplaceView(
      {super.key, required this.repo, this.guest = false, this.clock});

  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView> {
  /// How many pages of open projects a search pulls in at once. The endpoint
  /// pages 20 rows at a time with no server-side text search, so widening to
  /// 100 rows is what makes searching the market meaningful instead of a scan
  /// of the newest twenty postings.
  static const int _searchPages = 5;

  String? _category;
  String? _wilaya;

  /// The open market, read once and re-read on every filter change.
  ///
  /// Nullable on purpose: `didChangeDependencies` seeds the wilaya from the
  /// phone *before* the first build asks for anything, so the first request the
  /// app makes is already the filtered one. Fetching in `initState` would ask
  /// for the whole country and throw the answer away one frame later.
  Future<List<Project>>? _projects;

  /// The feed to draw, fetched on first use.
  ///
  /// Routed through [_arm] rather than assigned, and that is load-bearing: the
  /// lazy `??=` meant the *first* read of a session never wrote the cache, so
  /// the very first pull-to-refresh a contractor made had nothing to fall back
  /// on and the fallback this whole item adds would have been dead on arrival
  /// — the defect would have survived its own fix. [_arm] also stamps
  /// [_cacheKey], which the `??=` knew nothing about.
  Future<List<Project>> get _feed => _projects ??= _arm(widget.repo
          .browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
      ));

  final _search = TextEditingController();

  /// Live text from the search box.
  String _query = '';

  /// Rows from the widened (multi-page) fetch, once a search has started.
  /// Kept beside the single-page future instead of replacing it, so the list
  /// never blinks back to a skeleton on the first keystroke.
  List<Project>? _wideRows;

  /// The last rows that actually landed, so a *re-read* that is slow or that
  /// failed can be annotated instead of replacing the market.
  ///
  /// Deliberately scoped to a **settled** answer, and this is what makes the
  /// pull honest. A read still in flight writes nothing here, so the twenty
  /// projects the contractor was reading survive both a filter tap and a
  /// pull-to-refresh rather than blinking to a skeleton. See the builder for
  /// where the doubt is drawn.
  List<Project>? _cache;

  /// The filter set [_cache] answers, and the reason a bare cache is not safe
  /// on this screen the way it is on its siblings.
  ///
  /// `browse_screen` and `projects_screen` both keep one list and re-read it
  /// with a changed query, and falling back to the previous answer there is at
  /// worst a stale list of *contractors* or of *the user's own* jobs. Here the
  /// changed query is usually a **wilaya**: the same feed re-read for
  /// `16 = Boumerdès` and then for `09 = Blida` does not have a subset
  /// relationship, and showing the first answer under the second filter is
  /// not a stale list — it is a set of jobs in the **wrong city**, under a
  /// filter chip that says otherwise. A contractor bids from that row, so this
  /// is the one place in the family where the fallback has to be scoped to the
  /// question it answers, and it is why [_arm] records the key with the rows
  /// instead of trusting a bare `_cache != null`.
  ///
  /// Keyed on the pair the request is built from, so it cannot drift from it.
  (String?, String?)? _cacheKey;

  /// The generation [_arm] is on, and the guard that makes [_cacheKey] mean
  /// anything at all.
  ///
  /// [_cacheKey] was supposed to stop one wilaya's rows being drawn under
  /// another's filter, and it does — but it is checked against the **live**
  /// filter pair, so it only describes the read that installed the cache *if
  /// that read is the latest one*. `_arm` issued before a filter change can
  /// still be in flight when the filter moves, and if it is, it installs
  /// itself and stamps [_cacheKey] with the pair it **captured at issue** —
  /// the wilaya the user has already moved off. The comparison then refuses,
  /// and the refusal is worse than the bug the key was added for: the cache
  /// is not stale, it is dead. Nothing can draw it, so the next pull that fails
  /// finds no fallback and answers «تعذّر جلب المشاريع» — the exact loss of
  /// screen this whole family exists to prevent, caused by a read that
  /// *succeeded*.
  ///
  /// Six controls re-issue this read ([_reload]) and the user is expected to
  /// tap through filters on a phone connection that is not answering in order,
  /// so the two reads racing here is ordinary use, not a corner case.
  int _feedToken = 0;

  /// When the rows in [_cache] were read, so the band can say how old they
  /// are rather than only that they are old.
  ///
  /// Stamped in the **same** `setState` that installs the rows, for the reason
  /// [_meReadAt] gives: a stamp from a different read than the one on screen is
  /// worse than no stamp, because it is then confidently wrong. It is `null`
  /// whenever there is no cache to date, which is every state the band is not
  /// drawn in — a first read, and a re-read whose filter has moved (see
  /// [_fallback]), because rows from another wilaya are not drawn at all.
  DateTime? _cacheReadAt;

  /// The sentence for the last failed read, or null when there is nothing to
  /// doubt — a read that has not failed yet, and a first read that failed
  /// (which has no rows to qualify, so it keeps the full-screen error).
  ///
  /// A *sentence* rather than a boolean, for the reason every sibling in this
  /// family uses one: the band can then name the failure instead of asserting
  /// that something is wrong, and `errorCopy` has already chosen the wording
  /// for the kind of failure it was.
  String? _staleReason;

  /// True while the widened fetch is in flight, so the feed can say "still
  /// looking" instead of declaring "no results" too early.
  bool _widening = false;

  /// One widen per filter set. Reset whenever the filters change.
  bool _widened = false;

  /// How many times the contractor has come back from his own gallery.
  ///
  /// A count, not a bool, because two visits to the gallery are two different
  /// questions and a single flag would drop the second.
  int _galleryRuns = 0;

  /// The gallery was closed — the photo count on the tile may have moved.
  void _onGalleryClosed() {
    if (!mounted) return;
    setState(() => _galleryRuns++);
  }

  /// Bumped on every reload so a stale widen cannot write into a newer feed.
  int _searchToken = 0;

  /// Signed-in contractor, used by the branded header and the stats row.
  /// Not `final`: the profile editor can change it, and the header must show
  /// the saved values without leaving the tab. Null for a signed-out visitor —
  /// the feed is public, his stats are not.
  Future<WorkerProfile>? _me;

  /// When the profile read currently in [\_me] actually returned, not when it
  /// was issued. Paired with that future so the header can say how old its own
  /// numbers are.
  ///
  /// Set in the same `setState` that installs the future, because the two are
  /// one fact: a timestamp from a *different* read than the one on screen is
  /// worse than no timestamp, because it is now confidently wrong. The future
  /// itself cannot carry this — [Future] has no completion time, and
  /// `Future.then` would have to race the `FutureBuilder` that is already
  /// listening to the same object.
  DateTime? _meReadAt;

  /// Ticks once a minute so an honest header does not need a re-read to become
  /// an honest header.
  ///
  /// Without it the freshness line is frozen at whatever it said when the
  /// profile was read: it would read «الآن» for a contractor who left the app
  /// open over lunch, which is the same lie in a slower costume. A minute is
  /// the resolution [statsFreshnessAr] reports at, so a tick per resolution
  /// cannot make the line stale by more than the copy it prints.
  ///
  /// Paired with `dispose` through `mounted`, and it is the only timer in this
  /// screen — the shell is an `IndexedStack` that keeps all three tabs alive,
  /// so a timer that is not cancelled here would outlive the tab by hours.
  Timer? _freshnessTimer;

  /// Where the phone is, once the app knows. Its wilaya opens the market on the
  /// projects a contractor standing in that wilaya can actually take, which is
  /// the founder's «show related offers» brief. It stays a seed: the first
  /// manual filter choice owns the filter from then on, and the chip always
  /// says which wilaya is applied, so nothing is hidden behind the app's back.
  PlaceState? _place;

  /// True once the user picked a wilaya (or cleared the filters) himself.
  bool _wilayaChosen = false;

  /// One look-up of the shared location state per screen.
  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scopeReady) return;
    _scopeReady = true;
    _place = AppScope.maybeOf(context)?.place;
    _place?.addListener(_onPlaceChanged);
    _seedFromPlace();
  }

  void _onPlaceChanged() {
    if (mounted) _seedFromPlace();
  }

  /// Opens the feed on the visitor's own wilaya, and re-opens it there when the
  /// fix lands after the first paint — but never over a filter he set himself.
  void _seedFromPlace() {
    final id = _place?.wilayaId;
    if (id == null || _wilayaChosen || _wilaya == id) return;
    _wilaya = id;
    // Drop the read: the next build asks for the wilaya instead, once.
    _projects = null;
    _wideRows = null;
    _widened = false;
    // **The cache stays** — that is the whole point of the family: a late
    // location fix must not take the market away on a slow connection. So its
    // age must keep running. Nothing to change: the stamp belongs to the rows,
    // and the rows are still the ones on screen until the next read answers.
    // What must not happen is the stamp being *credited* to rows it did not
    // time, so it is left alone here and cleared only by [_arm]'s success arm,
    // which is the only thing that installs new rows.
    _searchToken++;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!widget.guest) _readMe();
  }

  /// Re-issues the profile read after a failure.
  ///
  /// Without this the header's «تعذّر جلب ملفك» was a dead end with no control
  /// attached: the only way back was to leave the tab and come back, which
  /// nothing on screen said was possible. A read that failed once on a dropped
  /// connection must be retryable in place, exactly like the market feed below
  /// it.
  ///
  /// `_me` is replaced inside the same [setState] that triggers the rebuild, so
  /// the `FutureBuilder` drawing the header is already listening to the new
  /// read by the end of this call. There is no frame in which the request is in
  /// flight with nothing attached to it, which is why this read needs no error
  /// listener of its own (the quote read on the project screen does: its
  /// builder is not constructed until the project read answers).
  ///
  /// The block body is load-bearing, not a style choice. Written as
  /// `=> setState(() => _me = ...)`, the callback's value *is* the assigned
  /// `Future`, and Flutter asserts on a `setState` callback that returns one —
  /// "setState() callback argument returned a Future". The read was issued and
  /// the tap appeared to work, while the rebuild never happened and the failure
  /// state stayed on screen: a retry that did nothing. Measured, not assumed:
  /// the log showed the second `GET /api/mobile/my/profile` and the failure
  /// state on screen at the same time.
  void _retryProfile() {
    _readMe();
  }

  /// Issues the header read and stamps it, keeping the two in one `setState`.
  ///
  /// Every path that puts a profile on screen goes through here, which is the
  /// point: there are four of them (first build, the retry button, a pull, and
  /// a save in the editor) and any one of them that stamped a time separately
  /// would be free to stamp it at the wrong moment. The stamp is the clock
  /// *now*, not the request's start, so a read held open by a slow connection
  /// is not credited with being fresh the moment it was issued.
  void _readMe() {
    setState(() {
      _me = widget.repo.myProfile();
      _meReadAt = _now();
    });
    _armFreshnessTick();
  }

  /// Points the market at a read, and records what that read settled to.
  ///
  /// The cache is written **on every settled success**, and the failure is
  /// recorded as a *sentence* rather than as a boolean, so the band can name
  /// the failure instead of asserting that something is wrong. Both are
  /// cleared by the next success, so the doubt cannot outlive the read that
  /// answered.
  ///
  /// `onError` does not `setState` on its own: this is called from inside a
  /// `setState` in [_reload] and [_seedFromPlace]'s caller, and the answer to
  /// a future is a microtask later than both, so the rebuild is scheduled here
  /// and lands after the caller's own.
  ///
  /// Returns [read] itself, so the lazy `_feed` getter can install the first
  /// read through here without a second assignment. The returned future still
  /// carries the failure — the `onError` arm records it, and the `FutureBuilder`
  /// is the thing that reports it to the reader.
  Future<List<Project>> _arm(Future<List<Project>> read) {
    final key = (_category, _wilaya);
    // The generation, for the reason [_feedToken] gives. Checked on **both**
    // arms: a success arm that ran would overwrite the cache and its key with
    // the pair it captured, and an error arm that ran would put a band on
    // screen claiming the rows underneath it are the last ones read — for a
    // read the user has already replaced. Neither is a colour problem, so
    // neither is what the guard is for.
    final token = ++_feedToken;
    _projects = read;
    read.then((list) {
      if (!mounted || token != _feedToken) return;
      setState(() {
        _cache = list;
        _cacheKey = key;
        // The clock *now*, not the moment the request was issued, so a read
        // held open by a slow connection is not credited with being fresh the
        // moment it was asked for. Same rule as [_readMe].
        _cacheReadAt = _now();
        _staleReason = null;
      });
      // The market's age is aged by the same minute tick as the header's, and
      // the tick has to be armed from **here** as well. `_readMe` never runs for
      // a visitor, so arming only there left the one read in this screen a
      // signed-out contractor can have with a stamp that never moved: the band
      // would say «قبل 12 دقيقة» for as long as the app stayed open. Re-armed
      // rather than started, so two live timers cannot survive a filter change.
      _armFreshnessTick();
    }, onError: (Object e, StackTrace _) {
      if (!mounted || token != _feedToken) return;
      setState(() => _staleReason = errorCopy(e));
    });
    return read;
  }

  /// The doubt, as a sliver above whatever the builder is about to draw.
  ///
  /// Shared by **both** exits — the rows and the empty state — because the
  /// empty one is a hole this family has sprung before and it opens again
  /// here for the same reason. A failed re-read that the active search then
  /// narrows to nothing reached «لا يوجد مشروع مفتوح يطابق «…»» with no
  /// mention of the failure, and that is the family's original sin in a new
  /// costume: a confident claim about the market, built on rows the server has
  /// already contradicted. The sentence is the same one either way, so the two
  /// paths cannot drift into saying different things about one read.
  List<Widget> _staleMarketSlivers(String? reason) {
    if (reason == null) return const <Widget>[];
    // **The freshness half.** The line already admitted that these rows are the
    // last ones read; what it could not say is how long ago that was, and a
    // contractor about to bid on one of them is asking exactly that question. A
    // list four seconds old and a list forty minutes old printed the same
    // sentence, and only the second is one where a project somebody else has
    // already taken is a bid he loses. `null` here — a first read, or one whose
    // filter has moved, since neither is annotated — leaves the line exactly as
    // it was, which is the whole contract of
    // `staleMarketLineWithAgeAr`.
    final line = staleMarketLineWithAgeAr(reason, _cacheReadAt, now: _now());
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter, 0, AppTheme.gutter, AppTheme.s12),
          child: _StaleMarketBand(
            key: const Key('stale-market'),
            line: line,
          ),
        ),
      ),
    ];
  }

  /// The rows a waiting or failed read may honestly keep on screen.
  ///
  /// `null` is the honest answer for a *first* read, and for a read whose
  /// filter has moved since the rows were fetched — see [_cacheKey]. Every
  /// other state has something real to show.
  List<Project>? get _fallback {
    final cached = _cache;
    if (cached == null) return null;
    return _cacheKey == (_category, _wilaya) ? cached : null;
  }

  void _reload() {
    setState(() {
      _arm(widget.repo.browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
      ));
      // A different filter means a different market: drop the widened rows and
      // let the next keystroke widen again.
      _wideRows = null;
      _widened = false;
      // **A reload has to stand the widen down, and this is the line that does
      // it.** `_searchToken` is bumped above, so the in-flight `_widenForSearch`
      // will throw its answer away when it lands — but only *after* it has
      // already returned early on both of its guards, and neither guard clears
      // this flag. So the flag was left `true` with nothing in the air to clear
      // it, permanently: the hairline `_widening` progress bar at the top of the
      // feed never went away, and worse, the empty branch below reads
      // `if (_widening) return skeleton`, so a market with no matching project
      // showed an **eternal shimmer** instead of «لا مشاريع مفتوحة حالياً» and
      // the retry button under it. The user had no way out of a screen that
      // looked like it was still loading, with no results actually coming.
      //
      // Reachable from five controls that all call `_reload`: a filter change, a
      // clear, the retry button, the profile-save path, and — from 27 Sep — the
      // pull-to-refresh, which is the fastest of them. Type a word into the
      // search box, then change the trade before the widened read answers, and
      // the screen is stuck loading for good.
      _widening = false;
      _searchToken++;
    });
  }

  /// Pull-to-refresh on the market tab.
  ///
  /// The contractor's home is the busiest surface in the product and the last
  /// `CustomScrollView` in the app with no way to answer the gesture every user
  /// tries first on a screen that has gone stale. It was not a low-value
  /// screen: a project posted across town, a quote that landed, a competitor
  /// who registered an hour ago, his own completed-jobs count and his remaining
  /// monthly quotes — all of it changes while the tab is open, and none of it
  /// moved when he pulled. The only recovery was leaving the tab and coming
  /// back, which nothing on screen offered him.
  ///
  /// Two reads sit behind this gesture, they fail independently, and the
  /// contract is written down here rather than left to chance:
  ///
  ///  * **What the indicator waits on** — both, through [Future.wait]. A pull
  ///    that fired and returned would take the spinner down while the market was
  ///    still loading, which is the one thing the spinner is for.
  ///  * **A failed market read says nothing here.** The feed's own
  ///    `FutureBuilder` has its own `EmptyView` with its own retry button, and
  ///    letting the gesture fail would throw that away in favour of a generic
  ///    message that names nothing.
  ///  * **A failed profile read must not cost him the header.** This is the one
  ///    place the pull differs from its siblings, and the reason is in
  ///    [_readProfileForRefresh]: re-reading `myProfile` replaces the branded
  ///    header, and on a *failed* read that replacement is the «تعذّر جلب ملفك»
  ///    state, which removes his name, his stats, his three tool tiles and his
  ///    plan row. A flaky network on a pull would take away a header that was
  ///    working, in exchange for a sentence that is not what he asked for. So a
  ///    failed profile read puts the previous one back and the pull still
  ///    refreshes the market.
  ///  * **A search that is still typed is re-widened**, not silently demoted
  ///    back to the newest 20 rows. `_reload` drops `_wideRows` because the
  ///    filter may have changed; when a query is live that would leave the
  ///    results looking complete while quietly covering a smaller slice of the
  ///    market, and the user has no way to see that it happened.
  ///  * **A visitor is never asked to read what he has no account for.** The
  ///    feed is public, the header is not, so his pull is the market alone.
  Future<void> _refresh() async {
    final hadQuery = _query.trim().isNotEmpty;
    _reload();
    // The setters above already installed the new futures, so this waits on the
    // requests *this* pull issued and not on the ones it replaced.
    final reads = <Future<void>>[
      _projects!.then((_) {}, onError: (_, __) {}),
      _readProfileForRefresh(),
    ];
    await Future.wait(reads);
    if (hadQuery) await _widenForSearch();
  }

  /// Re-reads the contractor's own profile for [\_refresh] and keeps the
  /// header on screen if the read fails.
  ///
  /// Returns a future that **never throws**: a failure here is reported by the
  /// header's own `FutureBuilder` state, and the gesture has nothing to add.
  Future<void> _readProfileForRefresh() async {
    if (widget.guest) return;
    // Kept so a failed read can be undone. The block body is load-bearing for
    // the same reason `_retryProfile`'s is: an arrow here would make the
    // `setState` callback *return* the assigned `Future`, which Flutter asserts
    // against in debug (framework.dart:1202-1214) — the read would run and the
    // rebuild would never happen.
    final previous = _me;
    final previousReadAt = _meReadAt;
    final next = widget.repo.myProfile();
    // The block body is load-bearing, and the test above proves it: an arrow
    // here makes the `setState` callback *return* the assigned `Future`, and
    // Flutter asserts against exactly that (framework.dart:1204). It is an
    // assert, so debug-only — meaning in a release build the read would run and
    // the header would simply never rebuild, which is the same silent half-fix
    // `_retryProfile` was written to avoid. This is the third time this file
    // has been bitten by it.
    setState(() {
      _me = next;
      _meReadAt = _now();
    });
    _armFreshnessTick();
    try {
      await next;
    } catch (_) {
      // Not a generic «تعذّر التحميل» banner: the contractor's header is working
      // and his market is changing. The one thing that went wrong is a refresh
      // he did not ask for by name, so it is the one thing that must not cost
      // him the screen.
      if (mounted) {
        // Block body again: the arrow form returns the assigned `Future` and
        // throws the same assert, *on the failure path*, which is the worst
        // place for it to surface — the header would stay broken and the
        // restore would be the thing that throws.
        setState(() {
          _me = previous;
          // The previous profile's own age goes back with it. Leaving the
          // failed read's stamp behind would date numbers the contractor has
          // been looking at for an hour as though they had just arrived — the
          // one case where the freshness line would be a lie *because* the
          // repair worked.
          _meReadAt = previousReadAt;
        });
      }
    }
  }

  /// Live feed search. Filtering is in memory; the first typed character also
  /// widens the request once, because the visible page is only the newest 20
  /// open projects on the platform.
  void _onSearchChanged(String v) {
    setState(() => _query = v);
    if (v.trim().isNotEmpty) _widenForSearch();
  }

  /// Empties the box from the outside — the empty state's own action.
  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _widenForSearch() async {
    if (_widened || _widening) return;
    setState(() => _widening = true);
    final token = _searchToken;
    final List<Project> wide;
    try {
      wide = await widget.repo.browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
        pages: _searchPages,
      );
    } catch (_) {
      // Network down or the API refused: keep the page already on screen, which
      // the in-memory filter still narrows. `_widened` stays set so a dead
      // connection is not hammered on every keystroke; the retry button (or a
      // filter change) calls _reload and resets it.
      if (!mounted || token != _searchToken) return;
      setState(() {
        _widening = false;
        _widened = true;
      });
      return;
    }
    if (!mounted || token != _searchToken) return;
    setState(() {
      _widening = false;
      _widened = true;
      if (wide.isNotEmpty) _wideRows = wide;
    });
  }

  @override
  void dispose() {
    _place?.removeListener(_onPlaceChanged);
    _search.dispose();
    // The `IndexedStack` in the shell keeps this tab alive across every other
    // one, so an uncancelled timer keeps firing — and calling `setState` after
    // dispose — for as long as the app is open.
    _freshnessTimer?.cancel();
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [MarketplaceView.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Starts the once-a-minute tick that ages the header, once there is a
  /// header to age.
  ///
  /// Guarded on [mounted] and re-armed from the same place each time the stamp
  /// changes, so a failed read — which puts the old stamp back — does not end
  /// up with two live timers. Called from [_readMe] and the refresh install
  /// rather than from `build`, because a timer created in `build` is a new
  /// timer on every frame and the tick would multiply.
  void _armFreshnessTick() {
    if (!mounted) return;
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // **Both** ages on this screen, and the second one is new. The header's
      // stats line is gated on [_meReadAt] because it only exists for a
      // signed-in contractor. The market band is not: the market is served to a
      // visitor with no account at all, so a contractor whose profile read has
      // not landed — or who has none — was reading a band whose age froze at
      // whatever it said when the failure happened, which is the same
      // confidently-wrong claim this file was opened for, in slower motion.
      if (_meReadAt == null && _cacheReadAt == null) return;
      setState(() {});
    });
  }

  /// Opens the profile editor and, on save, refreshes without a round trip to
  /// the server for the header — the editor already returns the saved profile.
  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<WorkerProfile>(
      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _me = Future<WorkerProfile>.value(updated);
      // The editor read is as current as this screen's newest data is, and
      // the numbers it just wrote are the ones now on screen.
      _meReadAt = _now();
    });
    // Specialties may have changed, so re-run the feed against the new trades.
    _reload();
  }

  /// The empty market's own action. `_selectCategory(null)` only clears the
  /// trade; a wilaya filter can empty the page on its own, so both go.
  void _clearFilters() {
    _wilayaChosen = true;
    if (_category == null && _wilaya == null) return;
    _category = null;
    _wilaya = null;
    _reload();
  }

  /// Tapping a category twice clears the filter (same as the old strip).
  void _selectCategory(String? slug) {
    _category = _category == slug ? null : slug;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // `AlwaysScrollableScrollPhysics` is what keeps the gesture reachable on
      // the states where the page is short enough not to overflow — the empty
      // market and the failed market both render a single `EmptyView` inside a
      // `Center`, which is exactly the "nothing to scroll" case where a pull
      // would otherwise be swallowed. `ScrollView` already defaults a vertical,
      // controllerless scroll view to exactly this physics
      // (scroll_view.dart:141-148), so the line is belt-and-braces here too; it
      // is written out because the test asserts the contract on the widget, and
      // a contract nobody wrote down is one nobody can check.
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.navy,
        backgroundColor: AppTheme.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_me != null || widget.guest)
              SliverToBoxAdapter(
                  child: _HeaderSection(
                profile: _me,
                guest: widget.guest,
                onEdit: _editProfile,
                galleryRuns: _galleryRuns,
                onGalleryClosed: _onGalleryClosed,
                onRetryProfile: _retryProfile,
                readAt: _meReadAt,
                now: _now,
              )),
            SliverToBoxAdapter(
              child: _FilterBar(
                category: _category,
                wilaya: _wilaya,
                onCategory: _selectCategory,
                onWilaya: () => _pickWilaya(context),
              ),
            ),
            SliverToBoxAdapter(
              child: FeedSearchField(
                controller: _search,
                hint: 'ابحث في المشاريع: العنوان، الحي، التخصص...',
                onChanged: _onSearchChanged,
              ),
            ),
            if (_widening)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, 2, 18, 2),
                  child:
                      LinearProgressIndicator(minHeight: 3, color: AppTheme.navy),
                ),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SectionTitle('مشاريع مفتوحة للعروض',
                    icon: Icons.storefront_rounded),
              ),
            ),
            FutureBuilder<List<Project>>(
              future: _feed,
              builder: (context, snap) {
                // One branch decides what the reader is looking at, so a
                // re-read cannot take a different path from a first read.
                //
                // **A failed re-read keeps the rows and a waiting one keeps
                // them too, and that is the whole fix.** It used to answer the
                // skeleton for anything unsettled and the full-screen
                // `EmptyView` for anything that errored, over a feed that
                // [_reload] re-issues from six controls — pull-to-refresh, two
                // filter chips, the location fix, the empty state's own
                // «تحديث», and the profile-save path. So a network that blinked
                // during any of them replaced the open projects a contractor
                // was reading with an error page, and a *slow* one replaced
                // them with a shimmer that stayed for as long as the request
                // took. This is the busiest surface in the product and the one
                // read that a **visitor** can lose, because the market is
                // served with no account at all.
                //
                // A **first** read has nothing to fall back on and keeps the
                // error, which is the only state where the error is the truth.
                // See `stale_market_copy.dart`.
                final waiting = snap.connectionState != ConnectionState.done;
                final failed = snap.hasError && !waiting;
                // `null` while a read is still in flight or a first one failed
                // — neither can be annotated, because neither has rows the
                // reader could be mistaking for the server's.
                final stale = failed && _staleReason != null;
                final fallback = waiting || failed ? _fallback : null;
                if (fallback == null && waiting) {
                  return const SliverToBoxAdapter(
                      child: Shimmer(child: _ProjectsSkeleton()));
                }
                if (snap.hasError && fallback == null) {
                  return SliverToBoxAdapter(
                    child: EmptyView(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذّر جلب المشاريع',
                      message: errorCopy(snap.error),
                      actionLabel: 'إعادة المحاولة',
                      onAction: _reload,
                      danger: true,
                    ),
                  );
                }
                // Prefer the widened rows when a search has already pulled them.
                final loaded = _wideRows ??
                    fallback ??
                    (waiting ? null : snap.data) ??
                    const <Project>[];
                final projects = narrowProjects(loaded, _query);
                if (projects.isEmpty) {
                  // The multi-page fetch is still in flight — that is not yet a
                  // verdict, so show the loading shape rather than "no results".
                  if (_widening) {
                    return const SliverToBoxAdapter(
                        child: Shimmer(child: _ProjectsSkeleton()));
                  }
                  if (_query.trim().isNotEmpty) {
                    return SliverMainAxisGroup(
                      slivers: [
                        ..._staleMarketSlivers(stale ? _staleReason : null),
                        SliverToBoxAdapter(
                          child: EmptyView(
                            icon: Icons.search_off_rounded,
                            title: 'لا نتائج مطابقة',
                            message:
                                'لا يوجد مشروع مفتوح يطابق «$_query».\nجرّب كلمة أقصر، أو امسح البحث',
                            actionLabel: 'مسح البحث',
                            actionIcon: Icons.close_rounded,
                            onAction: _clearSearch,
                          ),
                        ),
                      ],
                    );
                  }
                  // "جرّب تغيير الفلتر" was advice with no button under it. A
                  // filtered-out market is cleared in one tap; a genuinely empty
                  // one is re-fetched, because that is the only honest action a
                  // contractor has when the platform has nothing published.
                  final filtered = _category != null || _wilaya != null;
                  return SliverMainAxisGroup(
                    slivers: [
                      ..._staleMarketSlivers(stale ? _staleReason : null),
                      SliverToBoxAdapter(
                        child: EmptyView(
                          icon: Icons.inbox_rounded,
                          title: 'لا مشاريع مفتوحة حالياً',
                          message: filtered
                              ? 'لا يوجد مشروع منشور يطابق الفلتر.\n'
                                  'اعرض كل التخصصات لترى باقي المشاريع.'
                              : 'لم يُنشر أي مشروع في تخصصك بعد.\n'
                                  'حدّث الصفحة أو عد لاحقاً.',
                          actionLabel: filtered ? 'اعرض كل المشاريع' : 'تحديث',
                          actionIcon: filtered
                              ? Icons.apps_rounded
                              : Icons.refresh_rounded,
                          onAction: filtered ? _clearFilters : _reload,
                        ),
                      ),
                    ],
                  );
                }
                // The doubt is an annotation *on* the market, so it is a
                // sliver above the rows rather than a page in their place — and
                // it is above them, not beside them, so the rows keep the
                // scroll position they were at when the pull failed.
                return SliverMainAxisGroup(
                  slivers: [
                    ..._staleMarketSlivers(stale ? _staleReason : null),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                      sliver: SliverList.separated(
                        itemCount: projects.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => ProjectCard(
                          project: projects[i],
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(
                                  builder: (_) => ProjectDetailScreen(
                                      projectId: projects[i].id,
                                      repo: widget.repo))),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickWilaya(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final w in Taxonomy.wilayas)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(
                w.name,
                style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsBody, color: AppTheme.textPrimary),
              ),
              onTap: () => Navigator.pop(context, w.id),
            ),
        ],
      ),
    );
    // The sheet is the app's own surface, so this is a real window: the phone
    // is rotated mid-selection, or the activity is reclaimed and the sheet's
    // route is gone while the answer is still delivered.
    //
    // The guard is here and **before** the two assignments, not just before
    // `_reload()`, because they are not the same defect. A lost guard on the
    // `setState` is a red frame; a lost guard on `_wilayaChosen` is a
    // *silently wrong screen* — that flag is what stops `_seedFromPlace` from
    // re-detecting the GPS wilaya over the man's own choice, so he picks
    // وهران and gets his location back instead. The sibling `_editProfile` in
    // this same file already reads `updated == null || !mounted`.
    if (!mounted) return;
    if (picked != null) {
      _wilayaChosen = true;
      _wilaya = picked;
      _reload();
    }
  }
}

/// The amber band above the open-project feed that failed to re-read.
///
/// The same tone `stale_directory_copy.dart` and `stale_catalogue_copy.dart`
/// already age a stale list into (`AppTheme.accentDeep` on `accentWash`), so a
/// screen that is quietly out of date looks the same wherever it is found. The
/// doubt is a fact about the data and not an alarm, so it is not drawn in the
/// red of the full-screen error it stands in for — on a screen that pulls with
/// one finger in a basement, red here would read as "the market is gone".
class _StaleMarketBand extends StatelessWidget {
  const _StaleMarketBand({super.key, required this.line});

  /// The composed sentence from [staleMarketLineAr].
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
              key: const Key('stale-market-line'),
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


// ─────────────────────────────────────────────────────────────────────────
//  Branded header — identity, availability, and one line of numbers.
// ─────────────────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  /// The signed-in contractor's profile, or null for a signed-out visitor —
  /// there is no profile to fetch without an account.
  final Future<WorkerProfile>? profile;
  final bool guest;
  final VoidCallback onEdit;

  /// Gallery visit count and its callback, forwarded to the photo tile.
  ///
  /// This widget is stateless and cannot own the counter: the read it feeds
  /// lives in a child [State], and the increment has to survive the header
  /// being rebuilt by every keystroke in the search box below it.
  final int galleryRuns;
  final VoidCallback onGalleryClosed;

  /// Re-issues the profile read after it failed. The state that owns the read
  /// owns the repair too; this widget only renders the failure and the button.
  final VoidCallback onRetryProfile;

  /// When the profile on screen was read, so the stats line can date itself.
  final DateTime? readAt;

  /// The clock the freshness line is measured against. See
  /// `MarketplaceView.clock`.
  final DateTime Function()? now;

  const _HeaderSection({
    required this.profile,
    required this.guest,
    required this.onEdit,
    required this.galleryRuns,
    required this.onGalleryClosed,
    required this.onRetryProfile,
    required this.readAt,
    required this.now,
  });

  /// What a visitor gets where the contractor's own card would be: the same
  /// navy card, a line saying what the market is, and the one way in. It never
  /// reads «تعذّر جلب ملفك» — nothing failed, he simply has no account yet.
  List<Widget> _guestBody(BuildContext context) => [
        Text(
          'سوق المقاولين',
          style: AppTheme.h2.copyWith(color: AppTheme.onNavy),
        ),
        const SizedBox(height: 6),
        Text(
          'تصفّح المشاريع المفتوحة في ولايتك، وقدّم عروضك بعد إنشاء حساب مقاول. مجاناً.',
          style: AppTheme.bodySoft.copyWith(color: AppTheme.onNavyMuted),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('header-create-account'),
          onPressed: () => AuthGate.requireAuth(
            context,
            what: 'لتقدّم عروضك على المشاريع',
            as: UserRole.worker,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.navy,
            minimumSize: const Size.fromHeight(AppTheme.tapMin),
          ),
          child: const Text('أنشئ حساب مقاول'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: profile,
      builder: (context, snap) {
        final loading =
            profile != null && snap.connectionState != ConnectionState.done;
        final worker = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.navy,
                borderRadius: BorderRadius.circular(AppTheme.rXl),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.construction_rounded,
                          size: 18, color: AppTheme.onNavy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.label.copyWith(
                              fontSize: AppTheme.fsMeta,
                              color: AppTheme.onNavyMuted),
                        ),
                      ),
                      if (worker != null) _availabilityPill(worker),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    ..._skeletonRows()
                  else if (worker == null && guest)
                    ..._guestBody(context)
                  else if (worker == null)
                    // **A failed read is not an empty profile.**
                    //
                    // `snap.data` is null on an error exactly as it is on a read
                    // that has not answered, and this builder asked which of the
                    // two it was holding only implicitly, through `loading` —
                    // which is keyed on the *future*, not on the snapshot. One
                    // 500 on `GET /api/mobile/my/profile` and every row gated on
                    // `worker != null` below it disappeared at once: the
                    // identity row, the stats line, the three tool tiles and
                    // the subscription row.
                    //
                    // So a signed-in contractor who could not load his own
                    // profile lost the gallery he uploads work to, the state of
                    // his verification papers, his commercial profile and his
                    // plan — the whole contractor half of the product — and the
                    // only thing left on screen was a sentence with no button
                    // under it, on a scroll view with no pull-to-refresh. The
                    // only recovery the UI offered was leaving the tab and
                    // coming back, and nothing said that was possible.
                    ..._headerFailed(context, snap.error)
                  else ...[
                    _identity(worker),
                    if (worker.hasHistory) ...[
                      const SizedBox(height: 8),
                      _StatsLine(worker: worker, readAt: readAt, now: now),
                    ],
                    if (worker.verificationStatus ==
                            VerificationStatus.verified ||
                        worker.dossierUnderReview ||
                        worker.verificationStatus ==
                            VerificationStatus.rejected ||
                        (worker.wilaya != null &&
                            worker.wilaya!.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (worker.verificationStatus ==
                              VerificationStatus.verified)
                            const StatusPill(
                                label: 'مقاول موثّق',
                                color: AppTheme.success,
                                wash: AppTheme.successWash,
                                icon: Icons.verified_rounded),
                          // The header used to fall silent here, so a man who had
                          // just uploaded his papers saw nothing at all and
                          // started over. Say where the dossier stands.
                          if (worker.dossierUnderReview)
                            const StatusPill(
                                label: 'قيد المراجعة',
                                color: AppTheme.info,
                                wash: AppTheme.infoWash,
                                icon: Icons.hourglass_top_rounded),
                          if (worker.verificationStatus ==
                              VerificationStatus.rejected)
                            const StatusPill(
                                label: 'مستنداتك مرفوضة',
                                color: AppTheme.danger,
                                wash: AppTheme.dangerWash,
                                icon: Icons.report_gmailerrorred_rounded),
                          // Resolved name, not a non-empty string: an
                          // unknown code is no chip at all rather than a chip
                          // reading «الجزائر» (see `wilayaNameOrNull`).
                          if (Taxonomy.wilayaNameOrNull(worker.wilaya) case
                              final name?)
                            StatusPill(
                                label: name,
                                color: AppTheme.info,
                                wash: AppTheme.infoWash,
                                icon: Icons.location_on_rounded),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            // A contractor who has never been hired cannot have a rating or a
            // job count, so three zeroes say nothing and offer no next step: he
            // gets the path to a hireable profile instead.
            if (!loading && worker != null && !worker.hasHistory)
              _GettingStarted(worker: worker, onEdit: onEdit),
            // His three doors, one row instead of three full-width tiles.
            if (!loading && worker != null)
              _ToolStrip(
                worker: worker,
                onEdit: onEdit,
                galleryRuns: galleryRuns,
                onGalleryClosed: onGalleryClosed,
              ),
            // The subscription row sits directly under his tools. The app now
            // earns from the contractor, so his plan, its remaining quota and
            // the way to pay must be one tap from home — not buried in a menu.
            // The plan row gets the same clock the stats line uses, for the
            // same reason: two ages measured against two different "now"s on
            // one screen is a second defect wearing the first one's clothes.
            if (!loading && worker != null) ...[
              const SizedBox(height: AppTheme.s12),
              _PlanEntry(worker: worker, now: now ?? DateTime.now),
            ],
          ],
        );
      },
    );
  }

  /// The failure state, drawn in the navy card's own colours.
  ///
  /// [EmptyView] is deliberately not reused here: it paints its title and body
  /// in `textPrimary` and `bodySoft`, which are near-black, and would put black
  /// text on the navy header. The control is the same accent pill «أنشئ حساب
  /// مقاول» uses two widgets up, so the one button on this card looks like the
  /// other button on this card.
  List<Widget> _headerFailed(BuildContext context, Object? error) => [
        IconBubble(
          icon: Icons.cloud_off_rounded,
          tint: AppTheme.onNavyMuted,
          wash: AppTheme.navySoft,
          size: 42,
        ),
        const SizedBox(height: 14),
        Text(
          'تعذّر جلب ملفك',
          textAlign: TextAlign.center,
          style: AppTheme.h2
              .copyWith(fontSize: AppTheme.fsH2, color: AppTheme.onNavy),
        ),
        const SizedBox(height: 6),
        Text(
          // The same sentence every other failed read in the app renders, so
          // this one reports a fact about the connection instead of a line
          // written for the card.
          errorCopy(error),
          textAlign: TextAlign.center,
          style: AppTheme.bodySoft.copyWith(color: AppTheme.onNavyMuted),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(
            key: const Key('worker-header-retry'),
            onPressed: onRetryProfile,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.navy,
              minimumSize: const Size.fromHeight(AppTheme.tapMin),
            ),
            child: const Text('إعادة المحاولة'),
          ),
        ),
      ];

  static Widget _availabilityPill(WorkerProfile w) => StatusPill(
        label: w.isAvailable ? 'متاح الآن' : 'غير متاح',
        color: w.isAvailable ? AppTheme.success : AppTheme.textSecondary,
        wash: w.isAvailable ? AppTheme.successWash : AppTheme.lineSoft,
        icon: w.isAvailable
            ? Icons.bolt_rounded
            : Icons.pause_circle_filled_rounded,
      );

  Widget _identity(WorkerProfile w) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // White ring so the navy avatar separates from the navy header.
        Container(
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            shape: BoxShape.circle,
          ),
          child: InitialAvatar(name: w.fullName, size: 52),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                w.fullName.isEmpty ? 'حرفي' : w.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.h2
                    .copyWith(fontSize: AppTheme.fsH2, color: AppTheme.onNavy),
              ),
              const SizedBox(height: 5),
              Text(
                _specialtyLabel(w),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySoft.copyWith(
                    fontSize: AppTheme.fsMeta, color: AppTheme.onNavyMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _skeletonRows() => const [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
                width: 52, height: 52, radius: 26, color: SkeletonTone.base),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150, height: 15, color: SkeletonTone.base),
                  SizedBox(height: 10),
                  SkeletonBox(width: 100, height: 11, color: SkeletonTone.base),
                ],
              ),
            ),
          ],
        ),
      ];

  static String _specialtyLabel(WorkerProfile w) {
    if (w.specialties.isEmpty) return 'حرفي';
    return w.specialties
        .map((s) => Taxonomy.categoryName(s))
        .take(2)
        .join(' · ');
  }
}

/// A working contractor's numbers, said in one line instead of three cards.
///
/// The home screen used to open with three 112 dp stat cards, so the first
/// thing a contractor saw was his own scoreboard and the market he earns from
/// began below the fold. The same numbers now sit under his name, where they
/// answer "how am I doing" without standing in the way of "what can I quote".
class _StatsLine extends StatelessWidget {
  final WorkerProfile worker;

  /// When this profile was read, and the clock to measure it against.
  ///
  /// Both are about the *same* line of copy, so they are one unit: a caller
  /// that passed a stamp but no clock would render a real time against the
  /// test's frozen now, and a caller that passed a clock but no stamp would
  /// render a correctly-aged nothing.
  final DateTime? readAt;
  final DateTime Function()? now;

  const _StatsLine({required this.worker, required this.readAt, this.now});

  @override
  Widget build(BuildContext context) {
    // A job count outranks a review count the way it always did, but a
    // contractor with neither still gets his experience line. Each of the three
    // is null at zero rather than a printed «0» — see [completedJobsAr].
    final jobs = completedJobsAr(worker.totalCompletedJobs);
    final reviews =
        jobs == null ? reviewCountAr(worker.totalReviews) : null;
    final years = experienceYearsAr(worker.experienceYears);
    final tail = <String>[
      if (jobs != null) jobs,
      if (reviews != null) reviews,
      if (years != null) years,
    ].join(' · ');

    // The one clause this line was missing. Every other number here is a fact
    // about the contractor and none of them is a fact about *this screen* —
    // which is the problem: «4 مشاريع منجزة · 5 سنوات خبرة» reads as the state
    // of his business and is in fact the state of his business as of whenever
    // the tab was built. The pull-to-refresh on this tab is what made the gap
    // unavoidable rather than merely unfortunate: the app now offers the
    // contractor a way to make these numbers current, so a stale one is a
    // choice he was given the means to avoid and nothing says he has not made
    // it.
    //
    // Suppressed entirely under a minute (see [statsFreshnessAr]), because
    // «الآن» under three clauses of numbers is a fourth clause of noise.
    final clock = now?.call();
    final freshness = statsFreshnessAr(readAt, now: clock);
    final stale = statsAreStale(readAt, now: clock);

    return Row(
      children: [
        // A score of 0 is the server's "never rated", not a rating. This line
        // only renders under [WorkerProfile.hasHistory], so a contractor with
        // jobs but no reviews used to be shown «0.0» next to his own job count
        // — the app rating him, on the screen where he judges himself.
        if (worker.hasRating) ...[
          const Icon(Icons.star_rounded, size: 15, color: AppTheme.accent),
          const SizedBox(width: 4),
          // The fourth print site, and the only one of the four that never
          // went through [RatingStars]. That is why the 1 Oct clamp missed it:
          // the rule was lifted into the widget's own digits, and this line
          // draws its own single star and its own text, so it kept the raw
          // `avgRating!.toStringAsFixed(1)` and printed **7.5** beside a star
          // that means «out of five» — on the one screen where a contractor
          // reads his own score.
          //
          // Same rule, same reason as the other three: the text beside the
          // shape has to be describing the shape. [WorkerProfile._rating] only
          // folds a score to null when it is not **positive** — `v > 0` is the
          // whole test — so 7.5, and any other oversized mean the server ever
          // computes, arrives here intact and used to be printed intact.
          Text(
            clampRating(worker.avgRating!, count: A11y.scale).toStringAsFixed(1),
            style: AppTheme.label.copyWith(
                fontSize: AppTheme.fsMeta, color: AppTheme.onNavy),
          ),
        ] else ...[
          const Icon(Icons.star_outline_rounded,
              size: 15, color: AppTheme.onNavyMuted),
          const SizedBox(width: 4),
          Text(
            noRatingAr(),
            style: AppTheme.label.copyWith(
                fontSize: AppTheme.fsMeta, color: AppTheme.onNavyMuted),
          ),
        ],
        if (tail.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '· $tail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.label.copyWith(
                  fontSize: AppTheme.fsMeta, color: AppTheme.onNavyMuted),
            ),
          ),
        ],
        if (freshness.isNotEmpty) ...[
          const SizedBox(width: 6),
          // Not `Expanded`. The tail is the part that can be long and
          // ellipsised; the freshness clause is three or four glyphs and
          // shrinking it is how a «قبل 3 ساعات» quietly becomes «قبل…». It
          // keeps its own room, and the tail is what gives way when the row is
          // too narrow for both — the numbers stay readable even when the age
          // is the thing that gets cut.
          Text(
            freshness,
            key: const Key('stats-read-at'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.label.copyWith(
              fontSize: AppTheme.fsMeta,
              // A quarter-old header is a different kind of statement from a
              // fresh one, and the colour is what says so before the words are
              // read. Same accent the rating star already uses on this line,
              // so it reads as part of the header rather than as an alert.
              color: stale ? AppTheme.accent : AppTheme.onNavyMuted,
              fontWeight: stale ? FontWeight.w800 : null,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Filter bar — kit pills, never Material ChoiceChip/FilterChip.
// ─────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String? category;
  final String? wilaya;
  final void Function(String?) onCategory;
  final VoidCallback onWilaya;

  const _FilterBar({
    required this.category,
    required this.wilaya,
    required this.onCategory,
    required this.onWilaya,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTheme.tapMin,
      // Fade the trailing edge so the half-visible chip reads as "there is
      // more here, swipe" rather than as a clipped widget.
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0.0, 0.88, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            _ChipShell(
              selected: category == null,
              onTap: () => onCategory(null),
              child: const StatusPill(
                label: 'الكل',
                color: AppTheme.navy,
                wash: AppTheme.lineSoft,
                icon: Icons.apps_rounded,
              ),
            ),
            const SizedBox(width: 8),
            _ChipShell(
              selected: wilaya != null,
              onTap: onWilaya,
              child: StatusPill(
                label: wilaya == null
                    ? 'كل الولايات'
                    : Taxonomy.wilayaName(wilaya!),
                color: AppTheme.info,
                wash: AppTheme.infoWash,
                icon: Icons.location_on_rounded,
              ),
            ),
            for (final c in Taxonomy.categories) ...[
              const SizedBox(width: 8),
              _ChipShell(
                selected: category == c.slug,
                onTap: () => onCategory(c.slug),
                child: CategoryBadge(slug: c.slug),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Selection ring around a kit pill. The pill itself always carries explicit
/// tint/wash colours, so the label can never render invisible.
class _ChipShell extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  const _ChipShell({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        onTap: onTap,
        child: Center(
          // Full-height (56px) tap target, the pill keeps its natural size.
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accentWash : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
              border: Border.all(
                color: selected ? AppTheme.navy : AppTheme.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Skeleton rows that mirror [ProjectCard]'s layout while the feed loads.
class _ProjectsSkeleton extends StatelessWidget {
  const _ProjectsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                padding: AppTheme.cardPad,
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                        width: 76,
                        height: 76,
                        radius: AppTheme.rSm,
                        color: SkeletonTone.base),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                              width: 160, height: 15, color: SkeletonTone.base),
                          SizedBox(height: 10),
                          SkeletonBox(
                              width: 96,
                              height: 26,
                              radius: 999,
                              color: SkeletonTone.base),
                          SizedBox(height: 12),
                          SkeletonBox(
                              width: 120, height: 11, color: SkeletonTone.base),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of the contractor setup checklist.
class _SetupStep {
  final String label;
  final IconData icon;
  final bool done;
  const _SetupStep(this.label, this.icon, this.done);
}

/// Replaces the all-zeroes stats row for a contractor with no history yet.
///
/// A brand-new contractor used to see `0.0 / 0 / 0` — a rating they cannot
/// have, a job count that only says "nobody has hired you", and no next step.
/// This shows the four things that make a profile hireable, ticks them off as
/// they are done, and links straight to the editor. Verification is included
/// because the marketplace only lists verified contractors.
class _GettingStarted extends StatelessWidget {
  final WorkerProfile worker;
  final VoidCallback onEdit;
  const _GettingStarted({required this.worker, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final steps = <_SetupStep>[
      _SetupStep(
          'أضف تخصصاتك', Icons.handyman_rounded, worker.specialties.isNotEmpty),
      _SetupStep('اكتب نبذة تعريفية عنك', Icons.notes_rounded,
          (worker.bio ?? '').trim().isNotEmpty),
      _SetupStep('حدّد أسعارك ونطاق خدمتك', Icons.payments_rounded,
          worker.priceRangeMin != null && worker.priceRangeMax != null),
      // A submitted dossier is the contractor's part DONE — the rest is on us.
      // Leaving this step unticked while the papers were already in the queue
      // is what made the whole screen read as "you have not uploaded anything".
      _SetupStep(
          worker.dossierUnderReview
              ? 'مستنداتك قيد المراجعة'
              : 'وثّق حسابك بالبطاقة والهوية',
          Icons.verified_user_rounded,
          worker.verificationStatus == VerificationStatus.verified ||
              worker.dossierUnderReview),
    ];
    final done = steps.where((s) => s.done).length;
    final total = steps.length;
    final ratio = total == 0 ? 0.0 : done / total;
    final complete = done == total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: AppCard(
        padding: AppTheme.cardPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color:
                        complete ? AppTheme.successWash : AppTheme.accentWash,
                    borderRadius: BorderRadius.circular(AppTheme.rSm),
                  ),
                  child: Icon(
                    complete
                        ? Icons.emoji_events_rounded
                        : Icons.rocket_launch_rounded,
                    color: complete ? AppTheme.success : AppTheme.accentDeep,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        complete
                            ? 'ملفك مكتمل — بالتوفيق!'
                            : 'ابدأ باستقبال طلبات العمل',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTheme.fsBody,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        complete
                            ? 'ملفك جاهز. تصفّح المشاريع المفتوحة وأرسل عرضك'
                            : 'أكمل ملفك ليظهر اسمك أمام أصحاب المشاريع',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: AppTheme.fsCaption,
                          height: 1.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 8,
                      backgroundColor: AppTheme.line,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        complete ? AppTheme.success : AppTheme.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$done من $total',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTheme.fsCaption,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final s in steps) _SetupRow(step: s),
            if (!complete) ...[
              const SizedBox(height: 12),
              BigButton(
                label: 'أكمل ملفي الآن',
                icon: Icons.edit_rounded,
                onPressed: onEdit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  final _SetupStep step;
  const _SetupRow({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            step.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 19,
            color: step.done ? AppTheme.success : AppTheme.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: AppTheme.fsMeta,
                height: 1.4,
                color: step.done ? AppTheme.textSecondary : AppTheme.navy,
                fontWeight: step.done ? FontWeight.w600 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  The contractor's own workshop — work photos, documents, profile, one row.
// ─────────────────────────────────────────────────────────────────────────

/// The three doors a contractor needs: his work photos, his papers, his file.
///
/// They were three full-width tiles stacked above the market — about 250 dp of
/// the one screen that earns him money. Same three doors, now one row: still a
/// single tap each, and the first open project fits on the first screen.
class _ToolStrip extends StatelessWidget {
  final WorkerProfile worker;
  final VoidCallback onEdit;

  /// How many times the gallery has been opened. Passed to the badge so it
  /// re-reads when the contractor comes back from uploading.
  final int galleryRuns;
  final VoidCallback onGalleryClosed;

  const _ToolStrip({
    required this.worker,
    required this.onEdit,
    required this.galleryRuns,
    required this.onGalleryClosed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      // One row, three equal heights: the tallest badge sets the row.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ToolTile(
                key: const Key('worker-tools-portfolio'),
                icon: Icons.photo_library_rounded,
                tint: AppTheme.accentDeep,
                wash: AppTheme.accentWash,
                label: 'معرض أعمالي',
                badge: _PortfolioBadge(
                    workerId: worker.id, galleryRuns: galleryRuns),
                // The badge lives *under* this card, so the retry line is the
                // only control on the tile that is not the card — see
                // `_ToolBadge`, which gives the line its own touch floor.
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MyPortfolioScreen()),
                  );
                  // Whatever happened in there — three uploads, a delete, a
                  // failure — the count on this tile is now a question the
                  // server has a fresh answer to.
                  onGalleryClosed();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ToolTile(
                key: const Key('worker-tools-documents'),
                icon: Icons.verified_user_rounded,
                tint: AppTheme.info,
                wash: AppTheme.infoWash,
                label: 'المستندات',
                badge: _VerificationBadge(worker: worker),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VerificationScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ToolTile(
                key: const Key('worker-tools-edit'),
                icon: Icons.tune_rounded,
                tint: AppTheme.navy,
                wash: AppTheme.lineSoft,
                label: 'ملفي المهني',
                badge: const _ToolBadge(
                    label: 'تعديل', color: AppTheme.textMuted),
                onTap: onEdit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One third of the strip: mark, name, and one line of state under it.
class _ToolTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color wash;
  final String label;
  final Widget badge;
  final VoidCallback onTap;

  const _ToolTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.wash,
    required this.label,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: AppTheme.cardPadRail,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBubble(icon: icon, tint: tint, wash: wash, size: 40),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.label.copyWith(
                fontSize: AppTheme.fsMeta, color: AppTheme.navy),
          ),
          const SizedBox(height: 6),
          badge,
        ],
      ),
    );
  }
}

/// Reads the gallery size so the tile can say «3 صور» instead of being silent.
///
/// **A failed read is not an empty gallery.** The line this widget used to end
/// on was `final n = snap.data?.length ?? 0;` — and `snap.data` is null on an
/// error exactly as it is on an empty list. One 500, one dropped connection,
/// one host not answering, and a contractor with twelve photos was told
/// «أضف صوراً» — in the gold that means "you should do this". The public
/// profile makes a false claim about his gallery; this tile issues a directive
/// to upload work he has already uploaded, and the contractor who obeys it
/// pushes duplicates to R2 on a mobile connection and concludes his work is
/// not showing up. Same class of lie as `«نصف قطر الخدمة: 0 كم»` and the
/// `«لم يضف صوراً بعد»` row, on the one screen he opens first.
///
/// **The read is issued once, not on every rebuild.** The fetch used to be
/// written inside `build`, so it re-ran on every rebuild of the strip. The
/// search box calls `setState` on every keystroke, which means typing «دهان»
/// fired one `GET /portfolio` per character (measured: 1 request on open, 5
/// after three keystrokes) and flashed the tile back to «...» each time. The
/// future is a field, so a rebuild redraws the answer instead of re-asking for
/// it, and only [_retry] puts a new one in its place.
///
/// The retry lives on the badge rather than behind a second navigation: the
/// whole tile already opens the gallery, and the gallery's own load is the
/// request that just failed, so tapping through is the same 500 one screen
/// later rather than an action.
class _PortfolioBadge extends StatefulWidget {
  final int workerId;

  /// Bumped by the screen after the gallery is closed.
  ///
  /// A read held in a field is a read that is *not* re-issued, which is the
  /// whole point — but the gallery is where the count changes, and a
  /// contractor who uploads four photos, goes back, and still reads «3 صور»
  /// under his own work has been told a number the app itself just proved
  /// wrong. The tile cannot watch the route (there is no [RouteObserver] in
  /// this app), so the screen that pushed it says when it came back.
  final int galleryRuns;

  const _PortfolioBadge(
      {required this.workerId, required this.galleryRuns});

  @override
  State<_PortfolioBadge> createState() => _PortfolioBadgeState();
}

class _PortfolioBadgeState extends State<_PortfolioBadge> {
  /// The one read this badge holds. Deliberately a field and not a
  /// `build`-local future, so a parent rebuild does not re-issue it.
  Future<List<String>>? _images;

  ApiClient? _api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState — and
    // a *different* client means a different session and a different gallery.
    // Keyed on the client rather than guarded by a bool, so signing in or out
    // under this badge re-reads instead of keeping another account's count.
    final api = AppScope.of(context).api;
    if (identical(api, _api)) return;
    _api = api;
    _read();
  }

  @override
  void didUpdateWidget(_PortfolioBadge old) {
    super.didUpdateWidget(old);
    // Exactly the two things that make the held answer wrong: another
    // contractor's id, and a gallery that was visited since it was read.
    if (old.workerId != widget.workerId ||
        old.galleryRuns != widget.galleryRuns) {
      _read();
    }
  }

  /// Issues the one read this badge holds.
  ///
  /// `void` on purpose, and never handed straight to `setState`: an
  /// expression body would return the assigned `Future`, and `setState`
  /// rejects a callback that returns one (it is then treated as an async
  /// `setState`, which is the error it is trying to prevent).
  void _read() {
    _images = Repository(_api!).portfolioImages(widget.workerId);
  }

  /// Re-reads, once, on the user's own say-so.
  void _retry() => setState(_read);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _images,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ToolBadge(label: '...', color: AppTheme.textMuted);
        }
        if (snap.hasError) {
          return _ToolBadge(
            key: const Key('worker-portfolio-badge-error'),
            label: 'تعذّر العرض',
            color: AppTheme.danger,
            icon: Icons.refresh_rounded,
            onTap: _retry,
            onRetryKey: const Key('worker-portfolio-badge-retry'),
          );
        }
        // This line used to read `'\$n صور'` — an escaped dollar, so every
        // contractor with photos saw the literal "\$n صور" and not a count.
        //
        // It then became a two-way branch, `'صورة واحدة'` vs `'$n صور'`, which
        // had no arm for the two ranges Arabic makes mandatory: 2 is the dual
        // «صورتان» and takes no number, and 11+ is counted singular «11 صورة».
        // Both are delegated to [photosAr] now — the same noun the portfolio
        // header uses — so this tile cannot drift from it a second time.
        //
        // The `?? 0` that came with it is gone: an unanswered read is not a
        // zero, and a contractor with no photos is told so by the line below
        // and nobody else.
        final n = snap.data!.length;
        if (n == 0) {
          return const _ToolBadge(label: 'أضف صوراً', color: AppTheme.accentDeep);
        }
        return _ToolBadge(
          label: photosAr(n),
          color: AppTheme.success,
        );
      },
    );
  }
}

/// One line of state under a tool tile — deliberately not a [StatusPill], which
/// is taller than a third of a row can afford.
///
/// [onTap] makes the line itself the control. A tile that only says "I don't
/// know" strands the contractor, and a 56 dp control does not fit a 113 dp
/// third of a row, so the line carries the action and takes the app's own
/// touch floor as its height.
class _ToolBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;
  final Key? onRetryKey;

  const _ToolBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.onTap,
    this.onRetryKey,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.caption.copyWith(
        fontSize: AppTheme.fsBadge,
        fontWeight: FontWeight.w700,
        color: color);
    if (onTap == null) {
      return Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Semantics(
      button: true,
      // What it does, for a screen reader: the icon alone is not a label and
      // the two words on the line do not say that the tile re-reads.
      label: 'تعذّر عرض عدد الصور، اضغط لإعادة المحاولة',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: onRetryKey,
          height: AppTheme.tapMin,
          alignment: Alignment.center,
          // The tile is ~113 dp wide and the text is one line of `fsBadge`;
          // the icon goes ahead of the words rather than behind them, so the
          // line can never clip the way a trailing icon would on a long label.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the contractor's dossier stands, in the same one-line shape.
class _VerificationBadge extends StatelessWidget {
  final WorkerProfile worker;

  const _VerificationBadge({required this.worker});

  @override
  Widget build(BuildContext context) {
    if (worker.verificationStatus == VerificationStatus.verified) {
      return const _ToolBadge(label: 'موثّق', color: AppTheme.success);
    }
    // A contractor whose papers are already in the queue is not "غير موثّق",
    // and telling him he was read as one is what made a good upload look like
    // nothing had been sent.
    if (worker.dossierUnderReview) {
      return const _ToolBadge(label: 'قيد المراجعة', color: AppTheme.info);
    }
    if (worker.verificationStatus == VerificationStatus.rejected) {
      return const _ToolBadge(label: 'مرفوضة', color: AppTheme.danger);
    }
    return const _ToolBadge(label: 'غير موثّق', color: AppTheme.accentDeep);
  }
}

/// The subscription row on the contractor's home.
///
/// A full-width row rather than a fourth tool tile: this is the one line in the
/// app that asks him for money, so it has to say something specific — which plan
/// is live and how many quotes are left this month — instead of showing an icon
/// and hoping he taps. It reads the same endpoint the subscription screen writes
/// to, so the two can never disagree.
/// The contractor's plan card: his name, what he is owed this month, and the
/// door to paying.
///
/// **This row is the second read on the header, and it was the only one that
/// lied.** Three defects, all in the same nine lines, all shipped together.
///
/// 1. **It re-read on every frame.** `future: repo.subscription()` is
///    evaluated inside `build`, so *every* rebuild of the header issued a new
///    `GET /api/mobile/subscription`. The once-a-minute freshness tick added on
///    27 Sep turns that from "once per visit" into "once a minute, forever, for
///    as long as the tab is alive" — and the tab is alive for the whole session
///    because the shell is an `IndexedStack`. A contractor who left the app open
///    on his home overnight woke up to a phone that had asked the server about
///    his money sixty times an hour. The future is cached in state now, which is
///    what [_PlanEntryState] is for.
/// 2. **A failed read published «اختر خطتك»** — the free-plan sentence, on
///    the one card whose whole job is to get him to the renewal screen. The
///    same lie the account tab had, fixed there in `b8508de`-era work and left
///    running here. A contractor whose *paid* plan failed to load is told, in
///    the app's own voice, that he has no plan.
/// 3. **It never said when it was read**, while the stats line eight
///    centimetres above it does. So the screen carried two numbers read at two
///    different moments, and neither said which. The quota left on this card is
///    the number he acts on when deciding whether to renew; an hour-old "2
///    quotes left" and a fresh one are the same sentence, and only one of them
///    is true.
///
/// The read is also the *second* one on this screen, and it fails
/// independently of the header's. It keeps its own age so the two lines can be
/// honestly different ages rather than pretending to be one number.
class _PlanEntry extends StatefulWidget {
  const _PlanEntry({required this.worker, required this.now});

  final WorkerProfile worker;

  /// The same clock the stats line is measured against, so the two ages on one
  /// screen cannot be measured against two different "now"s. See
  /// `MarketplaceView.clock`.
  final DateTime Function() now;

  @override
  State<_PlanEntry> createState() => _PlanEntryState();
}

class _PlanEntryState extends State<_PlanEntry> {
  /// The cached read. Null until `didChangeDependencies` installs it, which is
  /// the first time the row is built with an `AppScope` in context.
  Future<BillingCatalogue>? _plan;

  /// When the read now on screen actually returned — the same two facts about
  /// one read, stamped in one place, for the same reason the header's are.
  DateTime? _readAt;

  /// True while a *retry* is in flight, so the one control this card owns
  /// cannot be pressed twice into two requests.
  bool _retrying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `??=` so a rebuild never re-issues it. Read through `AppScope` here
    // rather than caching the client, for the reason `_PlanAccountRow._retry`
    // gives: this widget can outlive a rebuild that swapped the scope.
    //
    // **The stamp belongs inside the guard, and that is the whole fix.** It
    // used to sit on its own line after it, which re-dated the read every time
    // *any* inherited dependency changed — so the age was not the age of the
    // read, it was the age of the last rebuild, and a read an hour old kept
    // printing as fresh for as long as the user touched the screen. The clause
    // this card was opened for would have been decorative in production and
    // only true in the test, which advanced a clock without changing a
    // dependency. The age of a read is a fact about the read.
    if (_plan == null) {
      _plan = Repository(AppScope.of(context).api).subscription();
      _stamp();
    }
  }

  /// Pairs the pending read with the moment it answers.
  ///
  /// Deliberately stamps `DateTime.now` at *issue* time, not completion. The
  /// alternative — `future.then((_) => _readAt = ...)` — credits a read held
  /// open for nine seconds by a bad connection with being fresh, which is the
  /// exact lie this row was opened for. A read issued at T is at best as fresh
  /// as T.
  void _stamp() {
    _readAt = widget.now();
  }

  /// Re-issues the read after a failure, keeping the block body: an arrow-form
  /// `setState(() => _plan = ...)` returns the assigned `Future` and Flutter
  /// asserts against exactly that.
  void _retry() {
    if (_retrying) return;
    final api = AppScope.of(context).api;
    setState(() {
      _retrying = true;
      _plan = Repository(api).subscription().whenComplete(() {
        if (mounted) setState(() => _retrying = false);
      });
      // A retry is a new read and gets a new age. Leaving the failed read's
      // stamp behind would date the answer as though it had arrived the moment
      // the failure did.
      _stamp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BillingCatalogue>(
      future: _plan,
      builder: (context, snap) {
        final current = snap.data?.current;
        // The age of the read this line is printing. `null` before the first
        // frame and after a failure that has not been retried; both are states
        // where there is nothing to date, and [statsFreshnessAr] answers the
        // empty string for both on purpose.
        final freshness = statsFreshnessAr(_readAt, now: widget.now());

        String line;
        Color tone = AppTheme.textSecondary;
        if (snap.hasError) {
          // Defect 2. A failed read is not a free trial. The account tab
          // (`_PlanAccountRow`) already says this in Arabic and already proved
          // the shape; this card is the same sentence about the same money, and
          // it was still printing the upsell.
          line = 'تعذّر جلب خطتك';
          tone = AppTheme.danger;
        } else if (snap.connectionState != ConnectionState.done) {
          line = 'جارٍ التحميل...';
        } else if (current == null) {
          line = 'خطتك وحدود العروض وتفعيل الاشتراك';
        } else if (current.hasUnlimitedQuotes) {
          line = '${current.nameAr} مفعّل — عروض غير محدودة';
          tone = AppTheme.success;
        } else {
          final left = current.quotesLeft ?? 0;
          line = left == 0
              ? '${current.nameAr} — استنفدت عروض هذا الشهر'
              : quotesLeftLineAr(current.nameAr, left, current.quoteLimit);
          tone = current.isQuotaSpent ? AppTheme.danger : AppTheme.accentDeep;
        }

        return AppCard(
          key: const Key('worker-plan-entry'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          ),
          child: Row(
            children: [
              const IconBubble(
                icon: Icons.workspace_premium_rounded,
                tint: AppTheme.navy,
                wash: AppTheme.accentWash,
              ),
              const SizedBox(width: AppTheme.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.planTitle, style: AppTheme.h2),
                    const SizedBox(height: AppTheme.s4),
                    // The line and its age on one row, so the age cannot be
                    // read as belonging to the stats line above it. Under a
                    // minute the age is empty and the row is unchanged — the
                    // same contract as the header, and for the same reason: a
                    // clause that is never absent is a clause a reader learns to
                    // skip.
                    Text(line,
                        style: AppTheme.caption.copyWith(color: tone)),
                    if (freshness.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        freshness,
                        key: const Key('plan-read-at'),
                        style: AppTheme.label.copyWith(
                          fontSize: AppTheme.fsMeta,
                          // Same rule as the header: an hour-old quota is a
                          // different kind of statement from a fresh one, and
                          // the weight says so before the words are read.
                          color: statsAreStale(_readAt, now: widget.now())
                              ? AppTheme.accentDeep
                              : AppTheme.textSecondary,
                          fontWeight: statsAreStale(_readAt, now: widget.now())
                              ? FontWeight.w800
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (snap.hasError)
                _PlanRetry(onTap: _retry, busy: _retrying)
              else
                const Icon(Icons.chevron_left_rounded,
                    color: AppTheme.textSecondary),
            ],
          ),
        );
      },
    );
  }
}

/// The card's way back from a failed read.
///
/// The card itself stays tappable — it is the door to the plan screen, and a
/// contractor who cannot see his plan can still go and look for it — so the
/// retry sits in the trailing slot where the chevron was, and the chevron does
/// not come back with it. An "open your plan" affordance sitting on a card that
/// has no plan to read is the same lie in a different font; that exact argument
/// is already pinned for the account row in
/// `test/plan_account_read_failure_test.dart`, and it applies here unchanged.
class _PlanRetry extends StatelessWidget {
  const _PlanRetry({required this.onTap, required this.busy});

  final VoidCallback onTap;
  final bool busy;

  /// Kept as a field so the busy branch is a real callback and not a closure
  /// rebuilt on every frame.
  static void _swallow() {}

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'تعذّر جلب خطتك، اضغط لإعادة المحاولة',
      child: A11y.tap(
        label: 'إعادة المحاولة',
        enabled: !busy,
        child: InkWell(
          key: const Key('worker-plan-retry'),
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          // A busy retry must still *win* the gesture arena, so this is a
          // no-op callback and never `null` — the control sits inside the
          // card's own `onTap`, and a null callback drops the recogniser out
          // of the arena entirely, so the second tap would be caught by the
          // card and the man pressing "retry" would be sent to the plan screen
          // with the retry still running behind him.
          onTap: busy ? _swallow : onTap,
          child: Container(
            constraints: const BoxConstraints(
                minWidth: AppTheme.tapMin, minHeight: AppTheme.tapMin),
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
            alignment: Alignment.center,
            child: Icon(
              busy ? Icons.hourglass_empty_rounded : Icons.refresh_rounded,
              size: 20,
              color: AppTheme.danger,
            ),
          ),
        ),
      ),
    );
  }
}
