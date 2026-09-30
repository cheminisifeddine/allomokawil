import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/auth_gate.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/project_search.dart';
import '../../data/stale_projects_copy.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/project.dart';
import '../../widgets/feed_search_field.dart';
import '../../widgets/motion.dart';
import '../../widgets/project_card.dart';
import '../../widgets/a11y.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import 'project_detail_screen.dart';
import 'project_new_screen.dart';

/// Status filters for the list. `null` means "الكل" and is passed straight
/// through to `Repository.myProjects(status: null)` (no `status` query param).
const List<({ProjectStatus? status, String label, IconData icon})> _tabs = [
  (status: null, label: 'الكل', icon: Icons.apps_rounded),
  (status: ProjectStatus.open, label: 'مفتوح', icon: Icons.bolt_rounded),
  (
    status: ProjectStatus.inProgress,
    label: 'قيد التنفيذ',
    icon: Icons.play_circle_fill_rounded
  ),
  (
    status: ProjectStatus.completed,
    label: 'منجز',
    icon: Icons.check_circle_rounded
  ),
  (status: ProjectStatus.cancelled, label: 'ملغى', icon: Icons.cancel_rounded),
];

/// "My projects" with status tabs, shared by customers and workers
/// (both have a cap to reach the detail screen of a project they're involved in).
class ProjectsScreen extends StatefulWidget {
  final Repository repo;

  /// Where a worker with no job at all is sent when he taps the empty state.
  ///
  /// Only a client can create a project from here, so a contractor's first
  /// project arrives from the marketplace tab — a different tab of the same
  /// shell, which is why the shell passes the switch in rather than this list
  /// pushing a screen of its own.
  final VoidCallback? onDiscover;

  /// The wall clock the band's age is measured against.
  ///
  /// Injectable for the same reason and with the same contract as
  /// `MarketplaceView.clock`: the band is dated, and a test that cannot move
  /// the clock can only ever see one side of the minute-old threshold. A
  /// widget test that passed a stamp but no clock would render a real time
  /// against a frozen `now`, and one that passed a clock but no stamp would
  /// assert the wrong half of the contract.
  final DateTime Function()? clock;

  const ProjectsScreen(
      {super.key, required this.repo, this.onDiscover, this.clock});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  ProjectStatus? _status = ProjectStatus.open;
  late Future<List<Project>> _future;

  /// The last rows that arrived, kept so a *re-read* that fails can fall back
  /// to them instead of erasing the list.
  ///
  /// This screen never had the field at all, so `_future` was re-assigned by
  /// every pull and by every status tab while the failure branch drew
  /// «تعذّر جلب المشاريع» over the whole list. That made a *pending* re-read
  /// replace the user's own projects with a shimmer and a *failed* one replace
  /// them with an error page. These rows are the only record the user has of
  /// jobs he posted or worked — nothing else in the app lists them — so
  /// throwing them away is not a temporary inconvenience, it is the list
  /// ceasing to exist.
  ///
  /// Deliberately scoped to a *settled* answer. A read still in flight writes
  /// nothing here, so the previous list survives it and the reader is never
  /// shown a shimmer for work he did not ask for. See the builder for where
  /// the doubt is drawn.
  ///
  /// **It carries the tab it was read for, and that is the fix this field
  /// needed.** It used to be a bare `List<Project>?`, which meant the fallback
  /// above answered *any* question with the rows of the last one: tap
  /// «قيد التنفيذ», the read fails, and the «مفتوح» projects are drawn under
  /// the tab that names running jobs. A customer asking whether his renovation
  /// started was shown four open projects as though they were the running one
  /// — and the band above them cannot repair it, because the band says those
  /// rows are *old*, not that they are *from somewhere else*.
  ///
  /// One record rather than three parallel fields, because rows, tab and stamp
  /// are **one fact**: a stamp from a different read than the rows is worse
  /// than no stamp, and three nullable fields can disagree in ways no test
  /// would notice. The tab is written in the same `setState` that writes the
  /// rows, so it cannot drift.
  ProjectsRead? _cache;

  /// The sentence for the last failed read, or null when there is nothing to
  /// doubt — a read that has not failed yet, and a first read that failed
  /// (which has no rows to qualify, so it keeps the full-screen error).
  String? _staleReason;

  /// When the rows currently on screen were read, or null when there is
  /// nothing to date.
  ///
  /// The band already admits «هذه آخر نتيجة قرأناها»; this is the half it could
  /// not say, and for *this* screen it is not a nicety. These rows are the only
  /// record the customer has of the jobs he posted — no other surface lists
  /// them — so «how old is this» is the question a stale band forces on him,
  /// and an unanswerable one is how a list that failed at 09:00 and one that
  /// failed an hour ago print the same confident sentence.
  ///
  /// Set in the same `setState` that installs [_cache], because the two are
  /// one fact: a stamp from a *different* read than the one on screen is worse
  /// than no stamp, because it is now confidently wrong. [Future] cannot carry
  /// a completion time, and `then` would have to race the [FutureBuilder] that
  /// is already listening to the same object.

  /// Ticks once a minute so an honest band does not need a re-read to become an
  /// honest band.
  ///
  /// Without it the age is frozen at whatever it said when the failure landed:
  /// a customer who leaves the tab open over a coffee break keeps reading
  /// «قبل 12 دقيقة» on a list that is now an hour old, which is the same lie
  /// in a slower costume. A minute is the resolution the copy reports at, so a
  /// tick per resolution cannot make the line stale by more than the words it
  /// prints. Cancelled in [dispose]; the shell's `IndexedStack` keeps this tab
  /// alive across every other one, so an uncancelled timer would outlive it.
  Timer? _ageTimer;

  final _search = TextEditingController();

  /// Live text from the search box. The narrowing runs in memory over the rows
  /// the visible tab already fetched (this endpoint returns every one of the
  /// user's projects, unpaged), so a keystroke never costs a round trip.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _arm(widget.repo.myProjects(status: _status), _status);
  }

  /// Points the list at a read, and records what that read settled to.
  ///
  /// The cache is written **on every settled success**, and the failure is
  /// recorded as a *sentence* rather than as a boolean, so the band can name
  /// the failure instead of asserting that something is wrong. Both are
  /// cleared by the next success, so the doubt cannot outlive the read that
  /// answered.
  ///
  /// `onError` does not `setState` on its own: this is called from inside a
  /// `setState` in [_reload] and [_refresh], and the answer to a future is a
  /// microtask later than both, so the rebuild is scheduled here and lands
  /// after the caller's own.
  ///
  /// **The tab is a parameter, not a read of `_status` after the `then`.**
  /// That is the whole write-vs-form rule this app has shipped eight times
  /// elsewhere, and the naive fix for this bug is to write
  /// `status: _status` inside the callback — which reintroduces it here: tap
  /// «مفتوح», tap «قيد التنفيذ» before the first read lands, and the first
  /// read's rows are filed under the *second* tab, which is the same
  /// cross-tab mislabelling this change exists to remove, one layer down. The
  /// tab is decided at the moment the request is issued and travels out with
  /// it, so the read and its label cannot come apart.
  void _arm(Future<List<Project>> read, ProjectStatus? status) {
    _future = read;
    read.then((list) {
      if (!mounted) return;
      setState(() {
        // The clock *now*, not the moment the request was issued, so a read
        // that was in flight for forty seconds is dated when it actually
        // landed. Stamping at issue time would under-report the age on a slow
        // connection — the exact case where the number matters most.
        _cache = ProjectsRead(rows: list, status: status, readAt: _now());
        _staleReason = null;
      });
      _armAgeTick();
    }, onError: (Object e, StackTrace _) {
      if (!mounted) return;
      setState(() => _staleReason = errorCopy(e));
    });
  }

  void _reload(ProjectStatus? s) {
    setState(() {
      _status = s;
      _arm(widget.repo.myProjects(status: s), s);
    });
  }

  /// Pull-to-refresh: re-issues the exact request the visible tab already made.
  ///
  /// Awaitable on purpose. [RefreshIndicator] holds the spinner until the
  /// future it was handed resolves, so a pull that returned before the request
  /// answered would snap the indicator away and leave a list that *looks*
  /// freshly loaded while still holding the rows the user was trying to
  /// replace.
  Future<void> _refresh() async {
    final read = widget.repo.myProjects(status: _status);
    setState(() => _arm(read, _status));
    try {
      await read;
    } catch (_) {
      // The builder renders the doubt; nothing to do here.
    }
  }

  /// Empties the box from the outside — the empty state's own action.
  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    // The shell keeps this tab alive across every other one, so an uncancelled
    // timer keeps firing — and calling `setState` after dispose — for as long
    // as the app is open.
    _ageTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [ProjectsScreen.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Starts the once-a-minute tick that ages the band, once there is a stamp to
  /// age.
  ///
  /// Re-armed from the same place the stamp is written, so a re-read that puts
  /// the old stamp back does not end up with two live timers. Called from
  /// [_arm] rather than from `build`, because a timer created in `build` is a
  /// new timer on every frame and the tick would multiply.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Nothing to age yet: a first read that has not landed has no rows, and
      // a band only ever appears over rows that do.
      if (_cache == null) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Signed out, this tab holds nothing that is his — and it is where a
    // visitor's own material would be. It keeps the same app bar and the same
    // shape, and offers the one action the tab is for.
    if (AuthGate.isGuest(context)) {
      final worker = AuthGate.guestRole(context) == UserRole.worker;
      return Scaffold(
        appBar: AppBar(title: Text('مشاريعي', style: AppTheme.bar)),
        body: SignInWall(
          title: worker ? 'طلباتك تظهر هنا' : 'مشاريعك تظهر هنا',
          body: worker
              ? 'أرسل عرضاً على مشروع مفتوح، وسيظهر هنا بعد أن يقبله صاحب المشروع، مع المحادثة والتفاصيل.'
              : 'انشر مشروعك واشرح ما تحتاجه، وسيصلك عروض المقاولين القريبين منك لتقارنها وتختار.',
          role: worker ? UserRole.worker : UserRole.customer,
          note: worker
              ? 'التصفّح مجاني — لا تحتاج حساباً لتقرأ المشاريع المفتوحة.'
              : 'البحث عن المقاولين مجاني وبدون حساب.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('مشاريعي', style: AppTheme.bar),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _tabStrip(),
          const SizedBox(height: 6),
          FeedSearchField(
            controller: _search,
            hint: 'ابحث في مشاريعك: العنوان، الحي، التخصص...',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.navy,
              backgroundColor: AppTheme.surface,
              child: FutureBuilder<List<Project>>(
                future: _future,
                builder: (context, snap) {
                  // One branch decides what the reader is looking at, so a
                  // re-read cannot take a different path from a first read.
                  //
                  // **A failed re-read falls back to the cache, and that is the
                  // whole fix.** It used to answer the full-screen error for
                  // *every* failure, and this screen's primary interaction is a
                  // status tab — five pills, each a full re-read. A customer
                  // choosing between contractors spends the decision flipping
                  // them on one bar of signal, and every flip that failed
                  // erased the list he was comparing offers on. A *first* read
                  // has nothing to fall back on and keeps the error, which is
                  // the only state where the error is the truth. See
                  // `stale_projects_copy.dart`.
                  final waiting = snap.connectionState != ConnectionState.done;
                  final failed = snap.hasError && !waiting;
                  // `null` means "there is nothing to draw", and it has to mean
                  // that for a **waiting** read too, not only a failed one.
                  // Collapsing "no cache" and "no rows" into the same empty
                  // list is what sends an unanswered feed to `_emptyList` —
                  // which is how a customer on a slow connection is told he
                  // has no projects, before the request has even answered.
                  // The fallback is answered **only for the tab it was read
                  // for.** Rows from another tab are not a stale version of
                  // this one, they are a different list, and drawing them under
                  // this tab's name is the app answering a question nobody
                  // asked. A failed tab switch therefore has nothing to fall
                  // back on and says so — which is the truth, and the retry
                  // button is already wired to *this* tab.
                  //
                  // A pull-to-refresh inside one tab is untouched: that is the
                  // same question asked twice, and keeping the rows there is
                  // the entire point of the field.
                  final fallback = _cache != null && _cache!.status == _status
                      ? _cache!.rows
                      : null;
                  final shown = fallback != null && (waiting || failed)
                      ? fallback
                      : (waiting || failed
                          ? null
                          : (snap.data ?? const <Project>[]));
                  if (shown == null) {
                    if (waiting) {
                      return const Shimmer(child: _ProjectsSkeleton(count: 4));
                    }
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      children: [
                        EmptyView(
                          icon: Icons.wifi_off_rounded,
                          title: 'تعذّر جلب المشاريع',
                          message:
                              'تحقق من اتصالك بالإنترنت ثم أعد المحاولة',
                          actionLabel: 'إعادة المحاولة',
                          onAction: () => _reload(_status),
                        ),
                      ],
                    );
                  }
                  if (shown.isEmpty) {
                    return _emptyList(context);
                  }
                  final projects = narrowProjects(shown, _query);
                  if (projects.isEmpty) {
                    return _noMatchList();
                  }
                  // The doubt is an annotation *on* the list, so the band
                  // scrolls with it as a header rather than sitting above a
                  // list that is pretending nothing happened.
                  final stale = failed && _staleReason != null;
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    // +1 for the band. `estimatedChildCount` is the estimate
                    // the scroll view is allowed to use, NOT the item count,
                    // so the band is asserted on in the tests as a descendant
                    // of the list rather than as a count.
                    itemCount: projects.length + (stale ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (stale && i == 0) {
                        return _StaleProjectsBanner(
                            line: staleProjectsLineWithAgeAr(
                                _staleReason!, _cache!.readAt,
                                now: _now()));
                      }
                      final p = projects[stale ? i - 1 : i];
                      return Reveal(
                        child: ProjectCard(
                          project: p,
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => ProjectDetailScreen(
                                      projectId: p.id,
                                      repo: widget.repo))),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontally scrolling pill tabs. A pill strip never squeezes the Arabic
  /// labels the way a fixed segmented control does on a 360dp phone.
  Widget _tabStrip() {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final tab = _tabs[i];
          return _TabPill(
            label: tab.label,
            icon: tab.icon,
            selected: _status == tab.status,
            onTap: () => _reload(tab.status),
          );
        },
      ),
    );
  }

  /// The typed word matched nothing in this tab. Deliberately not the same
  /// state as [_emptyList]: the projects exist, only the word missed, so the
  /// action offered is to clear the search rather than to create anything.
  Widget _noMatchList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        EmptyView(
          icon: Icons.search_off_rounded,
          title: 'لا نتائج مطابقة',
          message: 'لا يوجد مشروع في هذه الحالة يطابق «$_query».\n'
              'جرّب كلمة أقصر، أو امسح البحث لعرض الكل',
          actionLabel: 'مسح البحث',
          actionIcon: Icons.close_rounded,
          onAction: _clearSearch,
        ),
      ],
    );
  }

  /// Empty state per tab, with a call to action that fits the signed-in role.
  ///
  /// Both roles get a real next step: a client posts a project, a contractor
  /// goes to the open projects. "ستظهر هنا المشاريع التي تعمل عليها" alone was
  /// a sentence with nothing behind it.
  Widget _emptyList(BuildContext context) {
    final isCustomer = AppScope.of(context).auth.role == UserRole.customer;
    final workerAction =
        isCustomer || widget.onDiscover == null ? null : widget.onDiscover;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        EmptyView(
          icon: Icons.folder_off_outlined,
          title: 'لا مشاريع في هذه الحالة',
          message: isCustomer
              ? 'انشر مشروعك الأول واستقبل عروض المقاولين الموثوقين'
              : 'ستظهر هنا المشاريع التي تعمل عليها.\n'
                  'تصفّح المشاريع المفتوحة وقدّم عرضك الأول لتصل إليك هنا.',
          actionLabel: workerAction == null ? null : 'تصفّح المشاريع المفتوحة',
          actionIcon: Icons.storefront_rounded,
          onAction: workerAction,
        ),
        if (isCustomer)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: PrimaryButton(
              label: 'انشر مشروعك',
              icon: Icons.add_rounded,
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProjectNewScreen())),
            ),
          ),
      ],
    );
  }
}

/// One status filter. Explicit colours on both states — never inherited.
class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: A11y.button(
        selected: selected,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.navy : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 17,
                  color: selected ? AppTheme.accent : AppTheme.textSecondary),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTheme.label.copyWith(
                  fontSize: AppTheme.fsSmall,
                  color: selected ? AppTheme.onNavy : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// The amber band a failed re-read leaves above the list it did not replace.
///
/// Same tone and same shape as `_StaleDirectoryBanner` in `browse_screen` and
/// the inbox band: the doubt is a fact about the data, not an alarm, so it is
/// drawn in the same `accentDeep`-on-`accentWash` the stale catalogue uses
/// rather than in the red of the full-screen error it replaces.
class _StaleProjectsBanner extends StatelessWidget {
  const _StaleProjectsBanner({required this.line});

  /// The composed sentence from [staleProjectsLineWithAgeAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-projects'),
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
              key: const Key('stale-projects-line'),
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

/// Skeleton rows while a tab loads — calm grey blocks, not a spinner.
class _ProjectsSkeleton extends StatelessWidget {
  final int count;

  const _ProjectsSkeleton({this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: count,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: AppTheme.cardPad,
        decoration: AppTheme.cardDecoration,
        child: Row(
          children: const [
            SkeletonBox(height: 76, width: 76, radius: AppTheme.rSm, color: SkeletonTone.base),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14, width: 150, color: SkeletonTone.base),
                  SizedBox(height: 10),
                  SkeletonBox(height: 12, width: 110, color: SkeletonTone.base),
                  SizedBox(height: 10),
                  SkeletonBox(height: 12, width: 78, color: SkeletonTone.base),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// One settled read of «مشاريعي», and the tab it was asked for.
///
/// The three fields are written together and are meaningless apart: [rows]
/// without [status] cannot be told from the rows of another tab, and [readAt]
/// without [rows] dates nothing. See `_ProjectsScreenState._cache`.
class ProjectsRead {
  const ProjectsRead({
    required this.rows,
    required this.status,
    required this.readAt,
  });

  /// What the server answered, already narrowed to the tab that asked.
  final List<Project> rows;

  /// The status pill the read was issued from — `null` is «الكل».
  ///
  /// Carried out of the tab as it stood when the **request was issued**, so a
  /// second tap while the first is in flight cannot file the first read's rows
  /// under the second tab. See [_ProjectsScreenState._arm].
  final ProjectStatus? status;

  /// When these rows landed.
  final DateTime readAt;
}
