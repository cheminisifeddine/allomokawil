import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/motion.dart';
import '../data/taxonomy.dart';
import 'a11y.dart';

/// The trade/wilaya filter strip above the contractor directory.
///
/// **This bar used to throw half the marketplace away, silently.** It read
/// `Taxonomy.categories.take(8)` — a literal 8 against a 16-trade taxonomy —
/// so the eight trades below the fold of a *horizontally* scrolling strip were
/// never built, not merely off-screen. A contractor whose only trade is
/// «سباكة وترصيص صحي» or «ورق جدران» could not be filtered for by anyone, ever:
/// on this screen the supply half of the marketplace was searchable in sixteen
/// ways on the customer home grid and in eight ways here, and a customer
/// landing here first had no way to tell which eight he was missing.
///
/// The truncation has been in place since the 12 Sep design overhaul, which is
/// how a number typed into a `take()` can outlast the reason it was typed for.
/// The identical strip in `worker_home_screen.dart` iterates the full list, so
/// the two halves of the product disagreed about how many trades exist.
///
/// Two rules, because restoring the list is only half the fix:
///
///   * **All of them are built.** [Taxonomy.categories] in full. The strip is
///     horizontal and scrollable, so a long list is not a layout problem — it
///     is what the strip is *for*. `worker_home_screen` has proven the shape at
///     16 already.
///   * **The active trade is scrolled into view.** A customer who arrives from
///     the home grid having tapped «سباكة وترصيص صحي» — a perfectly ordinary
///     path, `BrowseScreen(initialCategory:)` — used to land on a bar with that
///     filter applied, its results below, and **no chip lit**: the strip was cut
///     before the trade being filtered on. A filter the user cannot see is a
///     filter he cannot clear, and one he cannot tell he applied. A trailing
///     «» affordance that opens the full list would have been the alternative;
///     showing the chip is the cheaper one and matches what every other screen
///     does.
class TradeFilterBar extends StatefulWidget {
  /// The wilaya currently filtered on, or null for «كل الولايات».
  final String? wilaya;

  /// The trade slug currently filtered on, or null for no trade filter.
  final String? category;

  /// Fired with null to clear the wilaya.
  final VoidCallback onWilayaTap;

  /// Fired with a slug, or with the same slug again to toggle it off.
  final ValueChanged<String> onCategoryTap;

  /// Fired when «مسح الفلاتر» is tapped. The control only exists when
  /// something is actually filtered, so it cannot appear over a clean bar.
  final VoidCallback onClear;

  const TradeFilterBar({
    super.key,
    required this.wilaya,
    required this.category,
    required this.onWilayaTap,
    required this.onCategoryTap,
    required this.onClear,
  });

  @override
  State<TradeFilterBar> createState() => _TradeFilterBarState();
}

class _TradeFilterBarState extends State<TradeFilterBar> {
  final ScrollController _scroll = ScrollController();

  /// A real [GlobalKey] per trade.
  ///
  /// The reveal needs the chip's [BuildContext] and not just its identity: it
  /// hands the last hop to [Scrollable.ensureVisible], which measures the widget
  /// it is given, and a plain `Key` cannot be resolved to a context.
  final Map<String, GlobalKey> _chipKeys = {
    for (final c in Taxonomy.categories)
      c.slug: GlobalKey(debugLabel: 'trade-${c.slug}'),
  };

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(TradeFilterBar old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) _scheduleReveal();
  }

  /// Runs [_revealActive] after the next frame.
  ///
  /// `initState` runs before the first `build`, so a chip's [GlobalKey] has no
  /// [BuildContext] yet and calling `ensureVisible` there resolves nothing and
  /// silently does nothing — which is the same invisible-filter failure the
  /// previous version of this widget had, wearing a quieter costume. A
  /// post-frame callback is the first moment the keys are real.
  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the selected trade's chip into the strip.
  ///
  /// **Both halves of this are load-bearing, and the first version of the
  /// widget got each one wrong.** The strip builds every chip eagerly (see
  /// [build]) *and* this runs from a post-frame callback, and either fact alone
  /// is enough to make the reveal silently do nothing:
  ///
  ///   * The eager `Row` is why [Scrollable.ensureVisible] can be handed a
  ///     context at all. An earlier version kept the lazy `ListView` and walked
  ///     the strip forward a viewport at a time until the chip was built,
  ///     because a chip past the viewport does not exist and its position
  ///     cannot be measured. That worked right up to the sixteenth trade —
  ///     where the walk ran out of budget at 3,456px of a 4,265px strip and
  ///     stopped with the chip still unbuilt. Sixteen small pills is not a
  ///     performance problem; the lazy list was bought at a price that had to
  ///     be paid back with a scrolling search for a widget the browser could
  ///     have laid out in one frame.
  ///   * The post-frame callback is why a context exists *yet*. `initState`
  ///     runs before the first `build`, so the [GlobalKey] has no
  ///     [BuildContext] there and the call resolves nothing — the same
  ///     invisible-filter failure the previous version of this widget had,
  ///     wearing a quieter costume.
  ///
  /// A no-op for no selection, so the common case costs nothing, and a slug
  /// that is not in the taxonomy is ignored rather than throwing on the tap
  /// that set it.
  void _revealActive() {
    final slug = widget.category;
    final ctx = slug == null ? null : _chipKeys[slug]?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    // `alignment: 0.15` rather than pinning the chip to an edge: two controls
    // have to be legible together here, the trade he filtered on and the place
    // he filtered to, and a jump that clears «كل الولايات» off the strip to
    // show him the trade he already tapped is not the one he asked for.
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: AppMotion.fast,
      curve: AppMotion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = widget.wilaya != null || widget.category != null;
    return SizedBox(
      height: 60,
      child: SingleChildScrollView(
        key: const Key('trade-filter-scroll'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // [AppTheme.gutter], not the 14 this used to read: the strip is the
        // control that filters the list sitting directly under it, and it was
        // 4 dp wider than that list on its start edge — 4 dp outside the
        // search box above it too. The golden `10_browse.png` showed the pill
        // bleeding off the canvas at x=0 while the cards started at x=18.
        // `test/browse_column_test.dart` now asserts the two are equal, which
        // is a comparison a count of literals structurally cannot make.
        padding: const EdgeInsets.fromLTRB(
            AppTheme.gutter, AppTheme.s4, AppTheme.gutter, AppTheme.s4),
        // **Cross-axis stretch, and it is not a style choice.** This `Row`
        // replaced a horizontal `ListView`, and a `ListView` hands its children
        // a *tight* cross-axis constraint while a `Row` hands them a loose one
        // and then centres them. Swapping the container for a non-lazy one is
        // what lets the reveal reach the sixteenth trade — but done naively it
        // quietly shrank every pill from 52 dp to its natural 42 dp, on all
        // sixteen of them, because nothing about the pill itself changed.
        // The golden caught it and nothing else did: `10_browse` diffed by
        // 3,595 px confined to the strip, and the measurement of the pill's own
        // painted height is what said *why* (y140..189 -> y141..186).
        //
        // [CrossAxisAlignment.stretch] restores the height the strip had before
        // the extraction, so the tap target is the one that was audited.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterPill(
              icon: Icons.location_on_rounded,
              label: widget.wilaya == null
                  ? 'كل الولايات'
                  : Taxonomy.wilayaName(widget.wilaya!),
              selected: widget.wilaya != null,
              tint: AppTheme.info,
              wash: AppTheme.infoWash,
              onTap: widget.onWilayaTap,
            ),
            if (hasFilter) ...[
              const SizedBox(width: 8),
              _FilterPill(
                icon: Icons.close_rounded,
                label: 'مسح الفلاتر',
                selected: false,
                tint: AppTheme.danger,
                wash: AppTheme.dangerWash,
                onTap: widget.onClear,
              ),
            ],
            for (final c in Taxonomy.categories) ...[
              const SizedBox(width: 8),
              // Two keys, on purpose. The [GlobalKey] is what the reveal
              // resolves to a [BuildContext] for `ensureVisible`; the
              // [ValueKey] on this wrapper is what a test looks the chip up by.
              // A `GlobalKey`'s identity is its debug label, so one key cannot
              // honestly serve as both.
              Builder(
                key: ValueKey('trade-${c.slug}'),
                builder: (context) => _FilterPill(
                  key: _chipKeys[c.slug],
                  icon: c.icon,
                  label: c.name,
                  selected: widget.category == c.slug,
                  tint: c.tint,
                  wash: c.wash,
                  onTap: () => widget.onCategoryTap(c.slug),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded, fully-coloured filter chip. Deliberately NOT a Material
/// `ChoiceChip`/`FilterChip`: those inherit colours and rendered illegible
/// white-on-white labels before. Selected = navy fill with white label.
///
/// Moved out of `browse_screen.dart` with the rest of the strip so the list of
/// trades is a widget a test can mount and count, rather than a literal buried
/// in a `State` — the literal is exactly what hid the truncation for a month.
class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color tint;
  final Color wash;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
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
                      size: 16, color: selected ? AppTheme.onNavy : tint),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.label.copyWith(
                        fontSize: AppTheme.fsMeta,
                        color:
                            selected ? AppTheme.onNavy : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
