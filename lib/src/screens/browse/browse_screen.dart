import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/text/arabic_search.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/repository.dart';
import '../../data/stale_directory_copy.dart';
import '../../data/taxonomy.dart';
import '../../models/worker.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/a11y.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/worker_card.dart';
import '../worker/worker_profile_screen.dart';

/// Contractor search. Used by clients (find a pro) and reused for
/// browsing top-rated workers by category/wilaya.
class BrowseScreen extends StatefulWidget {
  final bool customerSide;
  final String? initialCategory;

  /// The wall clock the band's age is measured against.
  ///
  /// Injectable for the same reason and with the same contract as
  /// `ProjectsScreen.clock` and `MarketplaceView.clock`: the band is dated, and
  /// a test that cannot move the clock can only ever see one side of the
  /// minute-old threshold. A widget test that passed a stamp but no clock
  /// would render a real time against a frozen `now`, and one that passed a
  /// clock but no stamp would assert the wrong half of the contract.
  final DateTime Function()? clock;

  const BrowseScreen(
      {super.key,
      this.customerSide = true,
      this.initialCategory,
      this.clock});

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

  /// The last list that landed, kept so a re-read does not blank the directory.
  ///
  /// **This screen had no cache at all until 29 Sep 2026**, which made it the
  /// worst member of the family `worker_profile_screen` and `chat_list_screen`
  /// already belong to. Every re-read — a pull, a submitted search, clearing
  /// the box, a filter chip — re-assigned `_future`, and the builder's failure
  /// branch painted «تعذّر جلب المقاولين» over the whole feed. So a *pending*
  /// re-read put a shimmer where a warm list of contractors was, and a
  /// *failed* one put an error page there. Neither state had anything to hold
  /// on to, because nothing was ever kept.
  ///
  /// The directory is the worst surface in the app to lose that on. It is the
  /// first screen a client opens, and the only read a customer makes who is not
  /// here to chat: the other screens in this family hold the user's own
  /// history, this one holds the *supply*. Supply he cannot see does not
  /// exist — and he is most likely to be reading it on one bar of signal, in
  /// the shop, pricing the job he is standing in.
  ///
  /// Deliberately scoped to a *settled* answer. A read that is still in flight
  /// writes nothing here, so the previous list survives it and the reader is
  /// never shown a shimmer for work he did not ask for. See the builder for
  /// where the doubt is drawn.
  List<WorkerProfile>? _cache;

  /// The sentence for the last failed read, or null when there is nothing to
  /// doubt — a read that has not failed yet, and a first read that failed
  /// (which has no rows to qualify, so it keeps the full-screen error).
  String? _staleReason;

  /// The wall clock [_cache] was true at, so the band can say *how* old the
  /// contractors on screen are.
  ///
  /// The band already admits «هذه آخر نتيجة قرأناها»; this is the half it could
  /// not say, and on **this** screen it is not a nicety. The other members of
  /// the family hold the reader's own history; this one holds the *supply* —
  /// and a contractor's availability, price band and number change with no push
  /// the app can send. So a client reading a list that failed to refresh is
  /// asking whether the man in front of him is still free today, and «failed to
  /// refresh» does not answer it.
  ///
  /// Set in the same `setState` that installs [_cache], because the two are one
  /// fact: a stamp from a *different* read than the one on screen is worse
  /// than no stamp, because it is now confidently wrong. [Future] cannot carry
  /// a completion time, and `then` would have to race the [FutureBuilder]
  /// already listening to the same object.
  DateTime? _cacheReadAt;

  /// Ticks once a minute so an honest band does not need a re-read to become an
  /// honest band.
  ///
  /// Without it the age is frozen at whatever it said when the failure landed:
  /// a client who leaves the directory open while he prices a job keeps reading
  /// «قبل 12 دقيقة» on a list that is now an hour old, which is the same lie
  /// in a slower costume. A minute is the resolution the copy reports at, so a
  /// tick per resolution cannot make the line stale by more than the words it
  /// prints. Cancelled in [dispose].
  Timer? _ageTimer;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _category = widget.initialCategory;
    _arm(_repo.searchWorkers(
        category: _category, wilaya: _wilaya, query: _query));
  }

  /// Points the directory at a read, and records what that read settled to.
  ///
  /// The cache is written **on every settled success**, and the failure is
  /// recorded as a *sentence* rather than as a boolean, so the banner can
  /// name the failure instead of asserting that something is wrong. Both are
  /// cleared by the next success, so the doubt cannot outlive the read that
  /// answered.
  ///
  /// `onError` does not `setState` on its own: this is called from inside a
  /// `setState` in [_reload] and from `didChangeDependencies`, and the answer
  /// to a future is a microtask later than both, so the rebuild is scheduled
  /// here and lands after the caller's own.
  void _arm(Future<List<WorkerProfile>> read) {
    _future = read;
    read.then((list) {
      if (!mounted) return;
      setState(() {
        _cache = list;
        _staleReason = null;
        // The clock *now*, not the moment the request was issued, so a read
        // that was in flight for forty seconds is dated when it actually
        // landed. Stamping at issue time would under-report the age on a slow
        // connection — the exact case where the number matters most.
        _cacheReadAt = _now();
      });
      _armAgeTick();
    }, onError: (Object e, StackTrace _) {
      if (!mounted) return;
      setState(() => _staleReason = errorCopy(e));
    });
  }

  void _reload() {
    setState(() => _arm(_repo.searchWorkers(
        category: _category, wilaya: _wilaya, query: _query)));
  }

  /// Pull-to-refresh. The gesture a user reaches for first on a feed that has
  /// gone stale or come back from the background, and on this screen — the one
  /// a client opens to find a contractor — it was the only refresh the feed did
  /// not offer at all: the shimmer, the error state and the populated list were
  /// all static, so a contractor who registered an hour ago never appeared
  /// until the app was killed and reopened.
  ///
  /// Awaitable on purpose. [RefreshIndicator] holds the spinner until the
  /// future it was handed resolves, so a pull that returned before the request
  /// answered would snap the indicator away and leave a list that *looks*
  /// freshly loaded while still holding the rows the user was trying to
  /// replace.
  Future<void> _refresh() async {
    _reload();
    try {
      await _future;
    } catch (_) {
      // The FutureBuilder renders the error state; nothing to do here.
    }
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
      // Null for a blank or unknown code, so the old «الجزائر» fallback could
      // not make every contractor answer a search for Algiers.
      Taxonomy.wilayaNameOrNull(w.wilaya),
      w.specialties.map(Taxonomy.categoryName).join(' '),
    ]);
  }

  @override
  void dispose() {
    // The shell keeps the directory alive across tab switches and while a
    // profile screen is pushed on top of it, so an uncancelled timer keeps
    // firing — and calling `setState` after dispose — for as long as the app
    // is open.
    _ageTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [BrowseScreen.clock].
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
      if (_cacheReadAt == null) return;
      setState(() {});
    });
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
                  // One branch decides what the reader is looking at, so a
                  // re-read cannot take a different path from a first read.
                  //
                  // **A failed re-read falls back to the cache, and that is the
                  // whole fix.** It used to answer the full-screen error for
                  // *every* failure, so on the surface that holds the supply
                  // rather than the user's own history, a network that blinked
                  // mid-pull replaced a warm list of contractors with a page
                  // claiming it could not load them — at the moment the user is
                  // most likely to be on one bar, standing in the shop. A
                  // *first* read has nothing to fall back on and keeps the
                  // error, which is the only state where the error is the
                  // truth. See `stale_directory_copy.dart`.
                  final waiting = snap.connectionState != ConnectionState.done;
                  final failed = snap.hasError && !waiting;
                  // `null` means "there is nothing to draw", and it has to mean
                  // that for a **waiting** read too, not only a failed one.
                  // Collapsing "no cache" and "no rows" into the same empty
                  // list is what sends an unanswered directory to the
                  // «لا يوجد مقاول حالياً» state — telling a client who is
                  // mid-request, on one bar, that the marketplace is empty.
                  // Found 29 Sep while fixing the sibling in `projects_screen`,
                  // which had the same expression and the same latent bug.
                  final shown = _cache != null && (waiting || failed)
                      ? _cache!
                      : (waiting || failed
                          ? null
                          : (snap.data ?? const <WorkerProfile>[]));
                  if (shown == null) {
                    if (waiting) {
                      return const Shimmer(child: LoadingList(count: 5));
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppTheme.navy,
                      backgroundColor: AppTheme.surface,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            AppTheme.s16, AppTheme.s16, AppTheme.s16, AppTheme.s28),
                        children: [
                          EmptyView(
                            icon: Icons.wifi_off_rounded,
                            title: 'تعذّر جلب المقاولين',
                            message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                            actionLabel: 'إعادة المحاولة',
                            onAction: _refresh,
                          ),
                        ],
                      ),
                    );
                  }
                  final workers = shown.where(_matchesQuery).toList();
                  if (workers.isEmpty) {
                    final hasFilter = _category != null ||
                        _wilaya != null ||
                        _query.isNotEmpty;
                    // Two different situations were sharing one state, and only
                    // one of them had a button.
                    //
                    // With a filter or a word set, the user is holding
                    // something of their own and can undo it in a tap. With
                    // nothing set — a young marketplace, two contractors on the
                    // whole platform — the reader has nothing to undo, so the
                    // state rendered **no action at all** and told him to
                    // «جرّب تغيير التخصص أو الولاية»: advice about two controls
                    // he never touched, with nothing under it to press. The
                    // honest action is a re-fetch, which is what the sibling
                    // market already does in the same situation
                    // (`worker_home_screen`), and the heading «لا نتائج
                    // مطابقة» was simply false — nothing was matched, because
                    // nothing was searched.
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppTheme.navy,
                      backgroundColor: AppTheme.surface,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            AppTheme.s16, AppTheme.s16, AppTheme.s16, AppTheme.s28),
                        children: [
                          EmptyView(
                            icon: hasFilter
                                ? Icons.search_off_rounded
                                : Icons.inbox_rounded,
                            title: hasFilter
                                ? 'لا نتائج مطابقة'
                                : 'لا يوجد مقاول حالياً',
                            message: !hasFilter
                                ? 'لم يسجّل أي مقاول في الدليل بعد.\n'
                                    'حدّث الصفحة، أو عد لاحقاً.'
                                : _query.isEmpty
                                    ? 'جرّب تغيير التخصص أو الولاية'
                                    : 'لا يوجد مقاول يطابق «$_query».\nجرّب كلمة أقصر أو امسح البحث',
                            actionLabel: hasFilter
                                ? 'مسح البحث والفلاتر'
                                : 'تحديث',
                            // The default icon is a refresh arrow, which on the
                            // "clear" branch would be the one button in the app
                            // promising to refetch what it is about to throw
                            // away. Same rule as `EmptyView.actionIcon`.
                            actionIcon: hasFilter
                                ? Icons.close_rounded
                                : Icons.refresh_rounded,
                            onAction: hasFilter ? _clearFilters : _refresh,
                          ),
                        ],
                      ),
                    );
                  }
                  // The doubt is an annotation *on* the list, so the band
                  // scrolls with it as a header rather than sitting above a
                  // list that is pretending nothing happened.
                  final stale = failed && _staleReason != null;
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: AppTheme.navy,
                    backgroundColor: AppTheme.surface,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                      // Without this a list that fits the viewport refuses
                      // the pull, so a feed of four contractors would be the
                      // one feed in the app that could not be refreshed.
                      physics: const AlwaysScrollableScrollPhysics(),
                      // +1 for the band. `estimatedChildCount` is the estimate
                      // the scroll view is allowed to use, NOT the item count,
                      // so the band is asserted on in the tests as a descendant
                      // of the list rather than as a count.
                      itemCount: workers.length + (stale ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (stale && i == 0) {
                          return _StaleDirectoryBanner(
                              line: staleDirectoryLineWithAgeAr(
                                  _staleReason!, _cacheReadAt,
                                  now: _now()));
                        }
                        final w = workers[stale ? i - 1 : i];
                        return WorkerCard(
                          worker: w,
                          variant: WorkerCardVariant.row,
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      WorkerProfileScreen(workerId: w.id))),
                        );
                      },
                    ),
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
    // The sheet is the app's own surface, so this is a real window: the phone
    // is rotated mid-selection, or the activity is reclaimed and the sheet's
    // route is gone while the answer is still delivered. Without this the draw
    // lands on a dead `State` — and `_reload` would also have issued a search
    // read that nobody is waiting for. The third `_pickWilaya` in the app
    // (`project_new_screen.dart`) already guards this; these two copies did not.
    if (!mounted) return;
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
      child: A11y.button(
        selected: selected,
        child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
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
                      fontSize: AppTheme.fsMeta,
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
      )),
    );
  }
}

/// The amber band above a contractor list that failed to re-read.
///
/// The same tone `stale_catalogue_copy.dart` and `stale_inbox_copy.dart` already
/// age a stale list into (`AppTheme.accentDeep` on `accentWash`), so a screen
/// that is quietly out of date looks the same wherever it is found — and here
/// it shares a page with the amber queued pill of the inbox and the amber
/// subscription band, which is deliberate rather than a clash: all three mean
/// "this is not yet the server's".
class _StaleDirectoryBanner extends StatelessWidget {
  const _StaleDirectoryBanner({required this.line});

  /// The composed sentence from [staleDirectoryLineAr].
  final String line;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-directory'),
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
              key: const Key('stale-directory-line'),
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
