import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
import '../models/project.dart';
import 'ui.dart';

/// Compact card for a posted project in search results and project lists.
class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback? onTap;

  const ProjectCard({super.key, required this.project, this.onTap});

  @override
  Widget build(BuildContext context) {
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
                CategoryBadge(slug: project.category),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        Taxonomy.wilayaName(project.wilaya),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.caption,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [StatusPill.project(project.status.name)],
                ),
                // The budget gets its own full-width strip. A range like
                // "من 60 ألف إلى 600 ألف دج" is the first thing a contractor
                // reads, and beside the status pill it was clipped mid-number
                // ("60000 - 6000…") — the one field that must never be cut.
                if (project.budgetMin != null || project.budgetMax != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                            const SizedBox(width: 5),
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
            ? Image.network(
                img,
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
