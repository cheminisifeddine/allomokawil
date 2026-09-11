import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/worker.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/worker_card.dart';
import '../worker/worker_profile_screen.dart';

/// Contractor search. Used by clients (find a pro) and reused for
/// browsing top-rated workers by category/wilaya.
class BrowseScreen extends StatefulWidget {
  final bool customerSide;
  final String? initialCategory;

  const BrowseScreen({super.key, this.customerSide = true, this.initialCategory});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final Repository _repo;
  final _search = TextEditingController();
  String? _category;
  String? _wilaya;
  Future<List<WorkerProfile>>? _future;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _category = widget.initialCategory;
    _future = _repo.searchWorkers(category: _category, wilaya: _wilaya);
  }

  void _reload() {
    setState(() {
      _future = _repo.searchWorkers(category: _category, wilaya: _wilaya);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ابحث عن مقاول')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'اسم الحرفي، التخصص...',
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => setState(() {
                  _future = _repo.searchWorkers(
                      category: _category, wilaya: _wilaya);
                }),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                children: [
                  FilterChip(
                    label: Text(_wilaya == null
                        ? 'كل الولايات'
                        : Taxonomy.wilayaName(_wilaya!)),
                    selected: _wilaya != null,
                    onSelected: (_) => _pickWilaya(context),
                  ),
                  const SizedBox(width: 8),
                  for (final c in Taxonomy.categories.take(8))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text(c.name),
                        selected: _category == c.slug,
                        onSelected: (sel) {
                          _category = sel ? c.slug : null;
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<WorkerProfile>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const LoadingList(count: 5);
                  }
                  if (snap.hasError) {
                    return EmptyState(
                      icon: Icons.wifi_off,
                      title: 'تعذّر جلب المقاولين',
                      action: TextButton(
                          onPressed: _reload,
                          child: const Text('إعادة المحاولة')),
                    );
                  }
                  final workers = snap.data ?? const [];
                  if (workers.isEmpty) {
                    return const EmptyState(
                        icon: Icons.people_outline,
                        title: 'لا نتائج مطابقة',
                        subtitle: 'جرّب تغيير الفلتر أو الولاية');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: workers.length,
                    itemBuilder: (context, i) {
                      final w = workers[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: WorkerCard(
                          worker: w,
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      WorkerProfileScreen(workerId: w.id))),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
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