import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/motion.dart';
import '../data/taxonomy.dart';
import 'a11y.dart';
import 'ui.dart';

/// Horizontal strip of service categories.
///
/// Each tile is an explicit two-colour pair (tint on wash) from the taxonomy,
/// so a tile can never render an invisible label — the failure mode of the old
/// Material `ChoiceChip` version. Icons are bundled Material icons, not emoji
/// (emoji showed up as tofu boxes on older Android builds).
class CategoryGrid extends StatelessWidget {
  final void Function(String slug)? onTap;
  final String? selected;

  const CategoryGrid({super.key, this.onTap, this.selected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gutter, vertical: AppTheme.s4),
        itemCount: Taxonomy.categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = Taxonomy.categories[i];
          return _CategoryStripTile(
            label: c.name,
            icon: c.icon,
            tint: c.tint,
            wash: c.wash,
            selected: selected == c.slug,
            onTap: onTap == null ? null : () => onTap!(c.slug),
          );
        },
      ),
    );
  }
}

class _CategoryStripTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tint;
  final Color wash;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryStripTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.wash,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: A11y.button(
        selected: selected,
        enabled: onTap != null,
        child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 96,
          // Both literals here were off the 4 dp ladder, and neither was
          // defending anything -- measured, not inferred.
          //
          // The vertical `10` moved ZERO pixels. The column is centred, so the
          // content sits at `labelTop` 311.00 dp whether the padding is 12, 10,
          // 8, 6 or 4; padding around a centred child is arithmetic, not
          // layout. It was not free, though: this tile is `height: 104` inside
          // a 112 dp strip, and the content is 42 icon + 8 gap + 27.5 text =
          // 77.5 dp, so the room is 104 - 2 x 10 - 2 x border = 82.00 plain
          // and 80.00 selected -- 4.50 and 2.50 dp of slack. `s8` is the step
          // that matches the 8 dp gap the column already draws between the icon
          // and the label, and it leaves 8.50 / 6.50.
          //
          // `s12` is why this is a fix and not a rename: it leaves 0.50 dp
          // plain and **-1.50 dp selected**, so the selected tile really would
          // have painted an overflow stripe. The off-grid `10` was one step
          // from a cliff, and `Flexible` clips silently, so nothing in the repo
          // could have seen it coming.
          //
          // The horizontal `6` was off-ladder and cost label room. The widest
          // taxonomy name, «بلاط وسيراميك ورخام», needs 72.25 dp to stay on two
          // lines; the tile left it 82.00 plain and 80.00 selected, so nothing
          // truncated. That makes this the SAME off-ladder number as the
          // `SelectableTile` fixed at `ui.dart:399` but NOT the same defect --
          // that tile was 72.00 against a 72.06 label and missed by 0.06 dp.
          // So the case for `s4` here is the ladder and the headroom, not a fit
          // fix: 86.00 / 84.00 room, 13.75 / 11.75 dp clear, and `s8` would
          // leave only 5.75 / 3.75.
          //
          // Guard: `test/category_strip_fit_test.dart`.
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s4, vertical: AppTheme.s8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentWash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
              width:
                  selected ? AppTheme.hairlineSelected : AppTheme.hairlineResting,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.navy : wash,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 22, color: selected ? AppTheme.onNavy : tint),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label.copyWith(
                    fontSize: AppTheme.fsBadge,
                    height: 1.25,
                    color: selected ? AppTheme.navy : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}

/// A grid version used by pickers. Fixed child aspect ratio keeps rows even
/// (the old `Wrap` produced a ragged 2-column layout that looked broken).
class CategoryGridTiles extends StatelessWidget {
  final String? selected;
  final void Function(String slug) onSelect;

  const CategoryGridTiles({
    super.key,
    this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: Taxonomy.categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, i) {
        final c = Taxonomy.categories[i];
        return SelectableTile(
          icon: c.icon,
          label: c.name,
          tint: c.tint,
          wash: c.wash,
          height: double.infinity,
          selected: selected == c.slug,
          onTap: () => onSelect(c.slug),
        );
      },
    );
  }
}

/// Same grid, but a contractor can tick several trades.
///
/// Tapping a selected tile removes it, which is the behaviour people expect
/// from a checklist — and it keeps the count visible in the tile's own state.
class CategoryGridMultiTiles extends StatelessWidget {
  final Set<String> selected;
  final void Function(String slug) onToggle;

  const CategoryGridMultiTiles({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: Taxonomy.categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemBuilder: (context, i) {
        final c = Taxonomy.categories[i];
        return SelectableTile(
          icon: c.icon,
          label: c.name,
          tint: c.tint,
          wash: c.wash,
          height: double.infinity,
          selected: selected.contains(c.slug),
          onTap: () => onToggle(c.slug),
        );
      },
    );
  }
}
