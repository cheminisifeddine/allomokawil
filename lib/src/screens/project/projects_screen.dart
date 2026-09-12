import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/project_search.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/project.dart';
import '../../widgets/feed_search_field.dart';
import '../../widgets/project_card.dart';
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

  const ProjectsScreen({super.key, required this.repo, this.onDiscover});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  ProjectStatus? _status = ProjectStatus.open;
  late Future<List<Project>> _future;

  final _search = TextEditingController();

  /// Live text from the search box. The narrowing runs in memory over the rows
  /// the visible tab already fetched (this endpoint returns every one of the
  /// user's projects, unpaged), so a keystroke never costs a round trip.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.repo.myProjects(status: _status);
  }

  void _reload(ProjectStatus? s) {
    setState(() {
      _status = s;
      _future = widget.repo.myProjects(status: s);
    });
  }

  /// Pull-to-refresh: re-issues the exact request the visible tab already made.
  Future<void> _refresh() async {
    setState(() => _future = widget.repo.myProjects(status: _status));
    try {
      await _future;
    } catch (_) {
      // The FutureBuilder renders the error state; nothing to do here.
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
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مشاريعي', style: AppTheme.h1.copyWith(fontSize: 18)),
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
                  if (snap.connectionState != ConnectionState.done) {
                    return const Shimmer(child: _ProjectsSkeleton(count: 4));
                  }
                  if (snap.hasError) {
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
                  final loaded = snap.data ?? const <Project>[];
                  if (loaded.isEmpty) {
                    return _emptyList(context);
                  }
                  final projects = narrowProjects(loaded, _query);
                  if (projects.isEmpty) {
                    return _noMatchList();
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    itemCount: projects.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => ProjectCard(
                      project: projects[i],
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                  projectId: projects[i].id,
                                  repo: widget.repo))),
                    ),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.navy : AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
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
                  fontSize: 14,
                  color: selected ? AppTheme.onNavy : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppTheme.line),
        ),
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
