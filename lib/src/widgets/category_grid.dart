import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentWash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
              width: selected ? 2 : 1,
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
                    fontSize: 11.5,
                    height: 1.25,
                    color: selected ? AppTheme.navy : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
