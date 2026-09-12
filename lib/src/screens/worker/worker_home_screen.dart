import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/enums.dart';
import '../../models/project.dart';
import '../../models/worker.dart';
import '../../widgets/big_button.dart';
import '../../widgets/project_card.dart';
import '../../widgets/ui.dart';
import '../chat/chat_list_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/projects_screen.dart';
import '../verify/verification_screen.dart';
import 'profile_edit_screen.dart';

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
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.badge_outlined),
                  tooltip: 'التوثيق والملف',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const VerificationScreen())),
                ),
              ],
            )
          : null,
      body: IndexedStack(index: _tab, children: [
        _MarketplaceView(repo: _repo),
        ProjectsScreen(repo: _repo),
        ChatListScreen(repo: _repo),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined), label: 'المنصة'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), label: 'مشاريعي'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'الرسائل'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
        ],
      ),
    );
  }
}

/// The marketplace tab: contractor header + quick stats + the open-project
/// feed with a legible kit-based filter bar.
class _MarketplaceView extends StatefulWidget {
  final Repository repo;
  const _MarketplaceView({required this.repo});

  @override
  State<_MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<_MarketplaceView> {
  String? _category;
  String? _wilaya;
  late Future<List<Project>> _projects;

  /// Signed-in contractor, used by the branded header and the stats row.
  /// Not `final`: the profile editor can change it, and the header must show
  /// the saved values without leaving the tab.
  late Future<WorkerProfile> _me;

  @override
  void initState() {
    super.initState();
    _projects = widget.repo.browseProjects(status: ProjectStatus.open);
    _me = widget.repo.myProfile();
  }

  void _reload() {
    setState(() {
      _projects = widget.repo.browseProjects(
        category: _category,
        wilaya: _wilaya,
        status: ProjectStatus.open,
      );
    });
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
          SliverToBoxAdapter(
              child: _HeaderSection(profile: _me, onEdit: _editProfile)),
          SliverToBoxAdapter(
            child: _FilterBar(
              category: _category,
              wilaya: _wilaya,
              onCategory: _selectCategory,
              onWilaya: () => _pickWilaya(context),
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
            future: _projects,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SliverToBoxAdapter(child: _ProjectsSkeleton());
              }
              if (snap.hasError) {
                return SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.wifi_off_rounded,
                    title: 'تعذّر جلب المشاريع',
                    message: snap.error.toString(),
                    actionLabel: 'إعادة المحاولة',
                    onAction: _reload,
                    danger: true,
                  ),
                );
              }
              final projects = snap.data ?? const <Project>[];
              if (projects.isEmpty) {
                return const SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.inbox_rounded,
                    title: 'لا مشاريع مفتوحة حالياً',
                    message: 'جرّب تغيير الفلتر',
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
                style: AppTheme.label
                    .copyWith(fontSize: 15, color: AppTheme.textPrimary),
              ),
              onTap: () => Navigator.pop(context, w.id),
            ),
        ],
      ),
    );
    if (picked != null) {
      _wilaya = picked;
      _reload();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Branded header — identity, availability and the quick-stats row.
// ─────────────────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  final Future<WorkerProfile> profile;
  final VoidCallback onEdit;
  const _HeaderSection({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: profile,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
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
                              fontSize: 13, color: AppTheme.onNavyMuted),
                        ),
                      ),
                      if (worker != null) _availabilityPill(worker),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    ..._skeletonRows()
                  else if (worker == null)
                    Text(
                      'تعذّر جلب ملفك',
                      style: AppTheme.bodySoft
                          .copyWith(color: AppTheme.onNavyMuted),
                    )
                  else ...[
                    _identity(worker),
                    if (worker.verificationStatus ==
                            VerificationStatus.verified ||
                        (worker.wilaya != null && worker.wilaya!.isNotEmpty)) ...[
                      const SizedBox(height: 14),
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
                          if (worker.wilaya != null && worker.wilaya!.isNotEmpty)
                            StatusPill(
                                label: Taxonomy.wilayaName(worker.wilaya!),
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
            if (!loading && worker != null)
              // A contractor with no history yet cannot have a rating or a job
              // count, so three zeroes say nothing and offer no next step.
              // Show the path to a hireable profile instead.
              (worker.totalCompletedJobs == 0 && worker.totalReviews == 0)
                  ? _GettingStarted(worker: worker, onEdit: onEdit)
                  : _QuickStats(worker: worker),
          ],
        );
      },
    );
  }

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
                    .copyWith(fontSize: 17, color: AppTheme.onNavy),
              ),
              const SizedBox(height: 5),
              Text(
                _specialtyLabel(w),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySoft
                    .copyWith(fontSize: 13, color: AppTheme.onNavyMuted),
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
            SkeletonBox(width: 52, height: 52, radius: 26),
            SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 150, height: 15),
                  SizedBox(height: 10),
                  SkeletonBox(width: 100, height: 11),
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

class _QuickStats extends StatelessWidget {
  final WorkerProfile worker;
  const _QuickStats({required this.worker});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 112,
              child: _StatCard(
                icon: Icons.star_rounded,
                tint: AppTheme.star,
                wash: AppTheme.accentWash,
                value: worker.avgRating.toStringAsFixed(1),
                label: 'التقييم',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 112,
              child: _StatCard(
                icon: Icons.task_alt_rounded,
                tint: AppTheme.success,
                wash: AppTheme.successWash,
                value: '${worker.totalCompletedJobs}',
                label: 'مشروع منجز',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 112,
              child: _StatCard(
                icon: Icons.workspace_premium_rounded,
                tint: AppTheme.info,
                wash: AppTheme.infoWash,
                value: '${worker.experienceYears}',
                label: 'سنوات خبرة',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One quick-stat: [AppCard] + [IconBubble], every colour explicit.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color wash;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.tint,
    required this.wash,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBubble(icon: icon, tint: tint, wash: wash, size: 36),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.h2.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style:
                AppTheme.caption.copyWith(fontSize: 10.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
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
                label:
                    wilaya == null ? 'كل الولايات' : Taxonomy.wilayaName(wilaya!),
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
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Center(
          // Full-height (56px) tap target, the pill keeps its natural size.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: selected ? AppTheme.accentWash : AppTheme.surface,
              borderRadius: BorderRadius.circular(999),
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
                padding: const EdgeInsets.all(13),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 76, height: 76, radius: AppTheme.rSm),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 160, height: 15),
                          SizedBox(height: 10),
                          SkeletonBox(width: 96, height: 26, radius: 999),
                          SizedBox(height: 12),
                          SkeletonBox(width: 120, height: 11),
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
      _SetupStep('أضف تخصصاتك', Icons.handyman_rounded,
          worker.specialties.isNotEmpty),
      _SetupStep('اكتب نبذة تعريفية عنك', Icons.notes_rounded,
          (worker.bio ?? '').trim().isNotEmpty),
      _SetupStep('حدّد أسعارك ونطاق خدمتك', Icons.payments_rounded,
          worker.priceRangeMin != null && worker.priceRangeMax != null),
      _SetupStep('وثّق حسابك بالبطاقة والهوية', Icons.verified_user_rounded,
          worker.verificationStatus == VerificationStatus.verified),
    ];
    final done = steps.where((s) => s.done).length;
    final total = steps.length;
    final ratio = total == 0 ? 0.0 : done / total;
    final complete = done == total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: complete ? AppTheme.successWash : AppTheme.accentWash,
                    borderRadius: BorderRadius.circular(12),
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
                          fontSize: 15.5,
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
                          fontSize: 12.5,
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
                    borderRadius: BorderRadius.circular(99),
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
                    fontSize: 12.5,
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
                fontSize: 13.5,
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
