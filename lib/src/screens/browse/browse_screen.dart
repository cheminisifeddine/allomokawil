import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/text/arabic_search.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../models/worker.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
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

  /// The submitted search text. Held separately from the controller so a
  /// half-typed word does not refetch on every keystroke.
  String _query = '';

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
    _future = _repo.searchWorkers(
        category: _category, wilaya: _wilaya, query: _query);
  }

  void _reload() {
    setState(() {
      _future = _repo.searchWorkers(
          category: _category, wilaya: _wilaya, query: _query);
    });
  }

  /// Runs the search for what is currently in the box.
  void _submitSearch(String raw) {
    final next = raw.trim();
    if (next == _query) return; // nothing new to ask the API for
    _query = next;
    _reload();
  }

  /// Drops filters and the search text, then re-runs the query.
  void _clearFilters() {
    setState(() {
      _category = null;
      _wilaya = null;
      _query = '';
      _search.clear();
    });
    _reload();
  }

  /// Does this contractor match the typed text? Applied on top of the server
  /// filter so search still works against a backend that does not know `q`
  /// yet, and so the match rules (hamza, ta marbuta, digits) are identical to
  /// the ones the rest of the app uses.
  ///
  /// `wilaya` is stored as a numeric code, so the Arabic name is resolved
  /// through the taxonomy — otherwise typing a wilaya name finds nobody.
  bool _matchesQuery(WorkerProfile w) {
    if (_query.isEmpty) return true;
    return ArabicSearch.matches(_query, [
      w.fullName,
      w.bio,
      w.commune,
      w.wilaya == null ? null : Taxonomy.wilayaName(w.wilaya!),
      w.specialties.map(Taxonomy.categoryName).join(' '),
    ]);
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
            _searchField(context),
            _filterBar(context),
            Expanded(
              child: FutureBuilder<List<WorkerProfile>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Shimmer(child: LoadingList(count: 5));
                  }
                  if (snap.hasError) {
                    return EmptyView(
                      icon: Icons.wifi_off_rounded,
                      title: 'تعذّر جلب المقاولين',
                      message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                      actionLabel: 'إعادة المحاولة',
                      onAction: _reload,
                    );
                  }
                  final workers =
                      (snap.data ?? const <WorkerProfile>[])
                          .where(_matchesQuery)
                          .toList();
                  if (workers.isEmpty) {
                    final hasFilter = _category != null ||
                        _wilaya != null ||
                        _query.isNotEmpty;
                    return EmptyView(
                      icon: Icons.search_off_rounded,
                      title: 'لا نتائج مطابقة',
                      message: _query.isEmpty
                          ? 'جرّب تغيير التخصص أو الولاية'
                          : 'لا يوجد مقاول يطابق «$_query».\nجرّب كلمة أقصر أو امسح البحث',
                      actionLabel: hasFilter ? 'مسح البحث والفلاتر' : null,
                      onAction: hasFilter ? _clearFilters : null,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                    itemCount: workers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final w = workers[i];
                      return WorkerCard(
                        worker: w,
                        variant: WorkerCardVariant.row,
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    WorkerProfileScreen(workerId: w.id))),
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

  // ── Search field ────────────────────────────────────────────────────────
  Widget _searchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _search,
        builder: (context, value, _) {
          final empty = value.text.isEmpty;
          return TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            style: AppTheme.body,
            decoration: InputDecoration(
              hintText: 'اسم الحرفي، التخصص...',
              hintStyle: AppTheme.bodySoft.copyWith(color: AppTheme.textMuted),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppTheme.navy),
              suffixIcon: empty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: () {
                        _search.clear();
                        FocusScope.of(context).unfocus();
                        _query = '';
                        _reload();
                      },
                    ),
            ),
            // Submitting asks the API for the typed text. Deleting it back to
            // empty restores the unfiltered list without a second tap, so the
            // control never looks stuck.
            onChanged: (v) {
              if (v.trim().isEmpty && _query.isNotEmpty) {
                _query = '';
                _reload();
              }
            },
            onSubmitted: _submitSearch,
          );
        },
      ),
    );
  }

  // ── Filter bar ──────────────────────────────────────────────────────────
  Widget _filterBar(BuildContext context) {
    final hasFilter = _wilaya != null || _category != null;
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        children: [
          _FilterPill(
            icon: Icons.location_on_rounded,
            label: _wilaya == null
                ? 'كل الولايات'
                : Taxonomy.wilayaName(_wilaya!),
            selected: _wilaya != null,
            tint: AppTheme.info,
            wash: AppTheme.infoWash,
            onTap: () => _pickWilaya(context),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 8),
            _FilterPill(
              icon: Icons.close_rounded,
              label: 'مسح الفلاتر',
              selected: false,
              tint: AppTheme.danger,
              wash: AppTheme.dangerWash,
              onTap: _clearFilters,
            ),
          ],
          for (final c in Taxonomy.categories.take(8)) ...[
            const SizedBox(width: 8),
            _FilterPill(
              icon: c.icon,
              label: c.name,
              selected: _category == c.slug,
              tint: c.tint,
              wash: c.wash,
              onTap: () {
                // Same toggle semantics as the previous chip (tap again =
                // deselect) and the same reload call.
                setState(() {
                  _category = _category == c.slug ? null : c.slug;
                });
                _reload();
              },
            ),
          ],
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
              title: Text(w.name, style: AppTheme.label),
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

/// Rounded, fully-coloured filter chip. Deliberately NOT a Material
/// `ChoiceChip`/`FilterChip`: those inherit colours and rendered illegible
/// white-on-white labels before. Selected = navy fill with white label.
class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color tint;
  final Color wash;
  final VoidCallback onTap;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.tint,
    required this.wash,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.navy : wash,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: Border.all(
                color: selected ? AppTheme.navy : AppTheme.line, width: 1.2),
          ),
          // Keeps long category names from stretching a single pill across
          // the whole 360px viewport.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? AppTheme.onNavy : tint),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label.copyWith(
                      fontSize: 13.5,
                      color: selected
                          ? AppTheme.onNavy
                          : AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
