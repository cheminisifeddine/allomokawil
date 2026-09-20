import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/auth_gate.dart';
import '../../core/l10n/strings.dart';
import '../../core/location/place_state.dart';
import '../../core/theme/app_theme.dart';
import '../../data/first_run.dart';
import '../../data/repository.dart';
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
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _tab = 0;
  late final Repository _repo;
  late Future<List<WorkerProfile>> _topWorkers;

  /// Null for a signed-out visitor: there is no «مشاريعي» without an account,
  /// so the strip is not requested and cannot fail. The founder saw exactly
  /// that failure — «تعذّر جلب المشاريع» — on the home of a visitor who had
  /// never signed in.
  Future<List<Project>>? _recentProjects;

  /// The same endpoint the messages tab reads. The client home needs it because
  /// the first-run guide has to disappear as soon as the owner has contacted
  /// somebody. Null for a visitor, for the same reason as the projects above.
  Future<List<Conversation>>? _conversations;

  /// True while nobody is signed in.
  bool _guest = false;

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
    _repo = Repository(AppScope.of(context).api);
    _guest = AuthGate.isGuest(context);
    _place = AppScope.maybeOf(context)?.place;
    _place?.addListener(_onPlaceChanged);
    _topWorkers = _repo.topWorkers(limit: 12, preferWilaya: _place?.wilayaId);
    if (_guest) {
      // Nothing to read without an account, and nothing to decide either: the
      // two session-only strips stay empty and the tab shows the way in.
      _recentProjects = null;
      _conversations = null;
    } else {
      _recentProjects = _repo.myProjects();
      _conversations = _repo.conversations();
      _readFirstRunGuide();
    }
  }

  /// The fix can land after the first paint — the stored one at boot, or a
  /// fresh GPS answer. When it does, the one strip that answers «who is near
  /// me» is re-read once; nothing else on the screen moves.
  void _onPlaceChanged() {
    final id = _place?.wilayaId;
    if (!mounted || id == null) return;
    setState(() => _topWorkers = _repo.topWorkers(limit: 12, preferWilaya: id));
  }

  @override
  void dispose() {
    _place?.removeListener(_onPlaceChanged);
    super.dispose();
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
  void _reloadWorkers() => setState(() =>
      _topWorkers = _repo.topWorkers(limit: 12, preferWilaya: _place?.wilayaId));
  void _reloadProjects() => setState(_reloadStrips);

  /// Re-reads everything the explore tab knows about this client. The guide is
  /// derived from two of those answers, so it is re-evaluated with them. A
  /// visitor has neither, and asking for them would only produce the two error
  /// states this screen must not show him.
  void _reloadStrips() {
    if (_guest) return;
    _recentProjects = _repo.myProjects();
    _conversations = _repo.conversations();
    _readFirstRunGuide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        _ExploreView(
          firstRun: _firstRun,
          topWorkers: _topWorkers,
          recentProjects: _recentProjects,
          guest: _guest,
          onRetryWorkers: _reloadWorkers,
          onRetryProjects: _reloadProjects,
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
        ),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: AppTabBar(
        index: _tab,
        onSelect: (i) => setState(() => _tab = i),
        items: const [
          AppTabItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'استكشف'),
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

  /// Null for a signed-out visitor — the tab then shows the way in instead of
  /// a strip it has nothing to put in.
  final Future<List<Project>>? recentProjects;

  /// True while nobody is signed in.
  final bool guest;
  final VoidCallback onRetryWorkers;
  final VoidCallback onRetryProjects;
  final VoidCallback onPost;
  final VoidCallback onBrowseAll;
  final VoidCallback onSeeAllProjects;
  final void Function(String) onBrowseCategory;
  final void Function(WorkerProfile) onWorker;
  final void Function(Project) onProject;

  const _ExploreView({
    required this.firstRun,
    required this.topWorkers,
    required this.recentProjects,
    required this.guest,
    required this.onRetryWorkers,
    required this.onRetryProjects,
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
    final location = (wilayaId == null || wilayaId.isEmpty)
        ? 'كل الولايات'
        : fromPhone != null
            ? '${Taxonomy.wilayaName(wilayaId)} • موقعك'
            : Taxonomy.wilayaName(wilayaId);

    return CustomScrollView(
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
            if (snap.connectionState != ConnectionState.done) {
              return const SliverToBoxAdapter(
                  child: Shimmer(child: _WorkerStripSkeleton()));
            }
            if (snap.hasError) {
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
            final workers = snap.data ?? const <WorkerProfile>[];
            if (workers.isEmpty) {
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
            return SliverToBoxAdapter(
              child: SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: workers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => WorkerCard(
                    worker: workers[i],
                    variant: WorkerCardVariant.vertical,
                    onTap: () => onWorker(workers[i]),
                  ),
                ),
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
            if (snap.connectionState != ConnectionState.done) {
              return const SliverToBoxAdapter(
                  child: Shimmer(child: _ProjectStripSkeleton(count: 2)));
            }
            if (snap.hasError) {
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
            final projects = snap.data ?? const <Project>[];
            if (projects.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: firstRun
                      ? const _FirstRunProjectsHint()
                      : _NoProjectsCard(onPost: onPost),
                ),
              );
            }
            final recent = projects.take(3).toList();
            return SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
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
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 172,
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
