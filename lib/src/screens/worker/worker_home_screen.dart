import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/l10n/strings.dart';
import '../../core/location/place_state.dart';
import '../../core/auth_gate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/photo_count_copy.dart';
import '../../data/project_search.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../data/quote_count_copy.dart';
import '../../data/worker_stats_copy.dart';
import '../../models/enums.dart';
import '../../models/plan.dart';
import '../../models/project.dart';
import '../../models/worker.dart';
import '../../widgets/app_tab_bar.dart';
import '../../widgets/notifications_bell.dart';
import '../../widgets/big_button.dart';
import '../../widgets/feed_search_field.dart';
import '../../widgets/project_card.dart';
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

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  int _tab = 0;
  late final Repository _repo;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
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
        ChatListScreen(repo: _repo, onDiscover: () => setState(() => _tab = 0)),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: AppTabBar(
        index: _tab,
        onSelect: (i) => setState(() => _tab = i),
        items: const [
          AppTabItem(
              icon: Icons.storefront_outlined,
              activeIcon: Icons.storefront_rounded,
              label: 'المنصة'),
          AppTabItem(
              icon: Icons.folder_outlined,
              activeIcon: Icons.folder_rounded,
              label: 'مشاريعي'),
          AppTabItem(
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'الرسائل'),
          AppTabItem(
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

  const MarketplaceView({super.key, required this.repo, this.guest = false});

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
  Future<List<Project>> get _feed => _projects ??= widget.repo.browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
      );

  final _search = TextEditingController();

  /// Live text from the search box.
  String _query = '';

  /// Rows from the widened (multi-page) fetch, once a search has started.
  /// Kept beside the single-page future instead of replacing it, so the list
  /// never blinks back to a skeleton on the first keystroke.
  List<Project>? _wideRows;

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
    _searchToken++;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!widget.guest) _me = widget.repo.myProfile();
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
    setState(() {
      _me = widget.repo.myProfile();
    });
  }

  void _reload() {
    setState(() {
      _projects = widget.repo.browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
      );
      // A different filter means a different market: drop the widened rows and
      // let the next keystroke widen again.
      _wideRows = null;
      _widened = false;
      _searchToken++;
    });
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
    super.dispose();
  }

  /// Opens the profile editor and, on save, refreshes without a round trip to
  /// the server for the header — the editor already returns the saved profile.
  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<WorkerProfile>(
      MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
    );
    if (updated == null || !mounted) return;
    setState(() => _me = Future<WorkerProfile>.value(updated));
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
      child: CustomScrollView(
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
              if (snap.connectionState != ConnectionState.done) {
                return const SliverToBoxAdapter(
                    child: Shimmer(child: _ProjectsSkeleton()));
              }
              if (snap.hasError) {
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
              final loaded = _wideRows ?? snap.data ?? const <Project>[];
              final projects = narrowProjects(loaded, _query);
              if (projects.isEmpty) {
                // The multi-page fetch is still in flight — that is not yet a
                // verdict, so show the loading shape rather than "no results".
                if (_widening) {
                  return const SliverToBoxAdapter(
                      child: Shimmer(child: _ProjectsSkeleton()));
                }
                if (_query.trim().isNotEmpty) {
                  return SliverToBoxAdapter(
                    child: EmptyView(
                      icon: Icons.search_off_rounded,
                      title: 'لا نتائج مطابقة',
                      message:
                          'لا يوجد مشروع مفتوح يطابق «$_query».\nجرّب كلمة أقصر، أو امسح البحث',
                      actionLabel: 'مسح البحث',
                      actionIcon: Icons.close_rounded,
                      onAction: _clearSearch,
                    ),
                  );
                }
                // "جرّب تغيير الفلتر" was advice with no button under it. A
                // filtered-out market is cleared in one tap; a genuinely empty
                // one is re-fetched, because that is the only honest action a
                // contractor has when the platform has nothing published.
                final filtered = _category != null || _wilaya != null;
                return SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.inbox_rounded,
                    title: 'لا مشاريع مفتوحة حالياً',
                    message: filtered
                        ? 'لا يوجد مشروع منشور يطابق الفلتر.\n'
                            'اعرض كل التخصصات لترى باقي المشاريع.'
                        : 'لم يُنشر أي مشروع في تخصصك بعد.\n'
                            'حدّث الصفحة أو عد لاحقاً.',
                    actionLabel: filtered ? 'اعرض كل المشاريع' : 'تحديث',
                    actionIcon:
                        filtered ? Icons.apps_rounded : Icons.refresh_rounded,
                    onAction: filtered ? _clearFilters : _reload,
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                sliver: SliverList.separated(
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => ProjectCard(
                    project: projects[i],
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProjectDetailScreen(
                            projectId: projects[i].id, repo: widget.repo))),
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
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
    if (picked != null) {
      _wilayaChosen = true;
      _wilaya = picked;
      _reload();
    }
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

  const _HeaderSection({
    required this.profile,
    required this.guest,
    required this.onEdit,
    required this.galleryRuns,
    required this.onGalleryClosed,
    required this.onRetryProfile,
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
                      _StatsLine(worker: worker),
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
            if (!loading && worker != null) ...[
              const SizedBox(height: AppTheme.s12),
              _PlanEntry(worker: worker),
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

  const _StatsLine({required this.worker});

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

    return Row(
      children: [
        // A score of 0 is the server's "never rated", not a rating. This line
        // only renders under [WorkerProfile.hasHistory], so a contractor with
        // jobs but no reviews used to be shown «0.0» next to his own job count
        // — the app rating him, on the screen where he judges himself.
        if (worker.hasRating) ...[
          const Icon(Icons.star_rounded, size: 15, color: AppTheme.accent),
          const SizedBox(width: 4),
          Text(
            worker.avgRating!.toStringAsFixed(1),
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
          Expanded(
            child: Text(
              '· $tail',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.label.copyWith(
                  fontSize: AppTheme.fsMeta, color: AppTheme.onNavyMuted),
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
class _PlanEntry extends StatelessWidget {
  const _PlanEntry({required this.worker});

  final WorkerProfile worker;

  @override
  Widget build(BuildContext context) {
    final repo = Repository(AppScope.of(context).api);
    return FutureBuilder<BillingCatalogue>(
      future: repo.subscription(),
      builder: (context, snap) {
        final current = snap.data?.current;
        String line;
        Color tone = AppTheme.textSecondary;
        if (snap.connectionState != ConnectionState.done) {
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
                    Text(line,
                        style: AppTheme.caption.copyWith(color: tone)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: AppTheme.textSecondary),
            ],
          ),
        );
      },
    );
  }
}
