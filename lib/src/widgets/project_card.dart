import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
import '../models/project.dart';
import 'net_image.dart';
import 'ui.dart';

/// Compact card for a posted project in search results and project lists.
class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback? onTap;

  const ProjectCard({super.key, required this.project, this.onTap});

  @override
  Widget build(BuildContext context) {
    final placeLabel = Taxonomy.wilayaNameOrNull(project.wilaya);
    return AppCard(
      onTap: onTap,
      padding: AppTheme.cardPad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(project: project),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h2.copyWith(fontSize: AppTheme.fsBody),
                ),
                const SizedBox(height: 7),
                // The primary trade, plus how many more the job covers. A card
                // is one line tall; the full list lives on the project page.
                Row(
                  children: [
                    Flexible(child: CategoryBadge(slug: project.category)),
                    if (project.allCategories.length > 1) ...[
                      const SizedBox(width: AppTheme.s8),
                      Text(
                        '+${project.allCategories.length - 1}',
                        style: AppTheme.label.copyWith(
                            fontSize: AppTheme.fsCaption,
                            color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
                // The place row is *server* data, so the wilaya can be missing
                // or a code this build has not heard of. The row then drops
                // entirely rather than naming Algiers: before, `''` fell
                // through to the fallback and every project without a wilaya
                // was published in «الجزائر». See `Taxonomy.wilayaNameOrNull`.
                if (placeLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          placeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  children: [StatusPill.project(project.status)],
                ),
                // The budget gets its own full-width strip. A range like
                // "من 60 ألف إلى 600 ألف دج" is the first thing a contractor
                // reads, and beside the status pill it was clipped mid-number
                // ("60000 - 6000…") — the one field that must never be cut.
                if (project.budgetMin != null || project.budgetMax != null) ...[
                  const SizedBox(height: 8),
                  // The budget band was a pill drawn by hand: a 14 dp glyph, a
                  // tight gap to its word, and an inset off the 4 dp ladder on
                  // both axes. It shares a card with a `CategoryBadge` above it
                  // and a `StatusPill` 9 dp higher, and those two already sit on
                  // [AppTheme.pillPad] and [AppTheme.pillGap] — so one card
                  // carried three capsules and the third disagreed with both.
                  //
                  // The horizontal already matched, which is exactly what hid
                  // it: a number that is on the ladder reads as deliberate, and
                  // the two dp that were actually wrong are the ones a reader
                  // sees as *unfinished* rather than as a defect.
                  //
                  // [AppTheme.pillPad] binds here, not the trade filter's larger
                  // tap-target inset, because this band is a label: it takes no
                  // `onTap` and nothing wraps it in a `GestureDetector` or an
                  // `InkWell`. Its `rSm` is NOT the capsule radius — it is a
                  // full-bleed strip, and it stays as it is. Only the inset and
                  // the gap were wrong. See
                  // `test/project_card_budget_strip_test.dart`.
                  Container(
                    width: double.infinity,
                    padding: AppTheme.pillPad,
                    decoration: BoxDecoration(
                      color: AppTheme.accentWash,
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                    ),
                    child: Row(
                      // No Spacer here: Spacer is itself an Expanded, so it
                      // competed with the amount for the free space and the
                      // range kept ellipsising. spaceBetween separates the two
                      // groups while the Flexible gets the whole remainder.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments_rounded,
                                size: 14, color: AppTheme.accentDeep),
                            // The app-wide gap between a pill's glyph and its
                            // word. This one was a private number, 1 dp tighter
                            // than every sibling pill — the same disagreement
                            // the kit's own comment on `StatusPill` records.
                            const SizedBox(width: AppTheme.pillGap),
                            Text(
                              'الميزانية',
                              style: AppTheme.label.copyWith(
                                  fontSize: AppTheme.fsCaption, color: AppTheme.accentDeep),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            project.budgetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.label.copyWith(
                                fontSize: AppTheme.fsMeta, color: AppTheme.navy),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Project project;
  const _Thumb({required this.project});

  @override
  Widget build(BuildContext context) {
    final img = project.images.isNotEmpty ? project.images.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rSm),
      child: Container(
        width: 76,
        height: 76,
        color: Taxonomy.categoryWash(project.category),
        child: img != null
            ? NetImage(
                img,
                width: 76,
                height: 76,
                semanticLabel: 'صورة المشروع',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Center(
        child: Icon(
          Taxonomy.categoryIcon(project.category),
          size: 30,
          color: Taxonomy.categoryTint(project.category),
        ),
      );
}
