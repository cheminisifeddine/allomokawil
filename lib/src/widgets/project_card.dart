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
      padding: const EdgeInsets.all(13),
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
                  style: AppTheme.h2.copyWith(fontSize: 15.5),
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
                        style: AppTheme.caption.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    StatusPill.project(project.status.name),
                    const Spacer(),
                    if (project.budgetMin != null ||
                        project.budgetMax != null) ...[
                      Flexible(
                        child: Text(
                          project.budgetLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.label.copyWith(
                              fontSize: 13, color: AppTheme.navy),
                        ),
                      ),
                    ],
                  ],
                ),
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
