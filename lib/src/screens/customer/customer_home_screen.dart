import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../data/repository.dart';
import '../../models/worker.dart';
import '../../widgets/category_grid.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/worker_card.dart';
import '../browse/browse_screen.dart';
import '../chat/chat_list_screen.dart';
import '../profile_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _repo = Repository(AppScope.of(context).api);
    _topWorkers = _repo.topWorkers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        _ExploreView(
          repo: _repo,
          topWorkers: _topWorkers,
          onPost: () => _push(const ProjectNewScreen()),
          onBrowseCategory: (slug) => _push(
              BrowseScreen(customerSide: true, initialCategory: slug)),
          onWorker: (w) => _push(WorkerProfileScreen(workerId: w.id)),
        ),
        ProjectsScreen(repo: _repo),
        ChatListScreen(repo: _repo),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'استكشف'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: 'مشاريعي'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'الرسائل'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'حسابي'),
        ],
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _ExploreView extends StatelessWidget {
  final Repository repo;
  final Future<List<WorkerProfile>> topWorkers;
  final VoidCallback onPost;
  final void Function(String) onBrowseCategory;
  final void Function(WorkerProfile) onWorker;

  const _ExploreView({
    required this.repo,
    required this.topWorkers,
    required this.onPost,
    required this.onBrowseCategory,
    required this.onWorker,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    S.appName,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16213E)),
                  ),
                  const SizedBox(height: 6),
                  const Text('ماذا تريد أن تنجز في منزلك؟',
                      style: TextStyle(color: Color(0xFF6E6E73))),
                  const SizedBox(height: 14),
                  // Search entry — big, obvious tap target
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            const BrowseScreen(customerSide: true))),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.search, color: Color(0xFF6E6E73)),
                          SizedBox(width: 10),
                          Text('ابحث عن حرفي أو تخصص...',
                              style: TextStyle(
                                  color: Color(0xFF6E6E73), fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text('التخصصات',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
            ),
          ),
          SliverToBoxAdapter(
            child: CategoryGrid(onTap: onBrowseCategory),
          ),
          // Post-project hero banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: onPost,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child:
                              const Icon(Icons.add_home_work, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('انشر مشروعك مجاناً',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 4),
                              Text('استقبل عروض مقاولين موثوقين خلال أيام',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('أفضل المقاولين',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
            ),
          ),
          FutureBuilder<List<WorkerProfile>>(
            future: topWorkers,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SliverToBoxAdapter(child: LoadingList(count: 3));
              }
              if (snap.hasError) {
                return const SliverToBoxAdapter(
                    child: EmptyState(
                        icon: Icons.wifi_off, title: 'تعذّر جلب المقاولين'));
              }
              final workers = snap.data ?? const [];
              if (workers.isEmpty) {
                return const SliverToBoxAdapter(
                    child: EmptyState(
                        icon: Icons.people_outline,
                        title: 'لا يوجد مقاولون بعد'));
              }
              return SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: workers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) =>
                        WorkerCard(worker: workers[i], onTap: () => onWorker(workers[i])),
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
}