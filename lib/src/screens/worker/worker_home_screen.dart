import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/project.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/project_card.dart';
import '../chat/chat_list_screen.dart';
import '../profile_screen.dart';
import '../project/project_detail_screen.dart';
import '../project/projects_screen.dart';
import '../verify/verification_screen.dart';

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
              title: const Text('المنصة'),
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

  @override
  void initState() {
    super.initState();
    _projects = widget.repo.browseProjects(status: ProjectStatus.open);
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('مشاريع مفتوحة للعروض',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          CategoryGrid(onTap: (slug) {
            _category = _category == slug ? null : slug;
            _reload();
          }),
          _filters(),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<List<Project>>(
              future: _projects,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingList(count: 6);
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.wifi_off,
                    title: 'تعذّر جلب المشاريع',
                    subtitle: snap.error.toString(),
                    action: TextButton(
                        onPressed: _reload, child: const Text('إعادة المحاولة')),
                  );
                }
                final projects = snap.data ?? const [];
                if (projects.isEmpty) {
                  return const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'لا مشاريع مفتوحة حالياً',
                      subtitle: 'جرّب تغيير الفلتر');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: projects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => ProjectCard(
                    project: projects[i],
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ProjectDetailScreen(
                                projectId: projects[i].id, repo: widget.repo))),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          FilterChip(
            label: Text(_wilaya == null
                ? 'كل الولايات'
                : Taxonomy.wilayaName(_wilaya!)),
            selected: _wilaya != null,
            onSelected: (_) => _pickWilaya(context),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('الميزانية'),
            selected: false,
            onSelected: (_) {},
          ),
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
              title: Text(w.name),
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