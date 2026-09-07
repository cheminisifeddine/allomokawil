import 'package:flutter/material.dart';

import '../data/taxonomy.dart';
import '../models/project.dart';

/// Compact card for a posted project in search results and project lists.
class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback? onTap;

  const ProjectCard({super.key, required this.project, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E7E3)),
        ),
        padding: const EdgeInsets.all(14),
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
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Taxonomy.categoryIcon(project.category)} ${Taxonomy.categoryName(project.category)}',
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '📍 ${Taxonomy.wilayaName(project.wilaya)}',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _StatusChip(project.status),
                      const Spacer(),
                      if (project.budgetMin != null || project.budgetMax != null)
                        Flexible(
                          child: Text(
                            project.budgetLabel,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 84,
        height: 84,
        color: const Color(0xFFF0EFEB),
        child: img != null
            ? Image.network(img, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _FallbackPic())
            : const _FallbackPic(),
      ),
    );
  }
}

class _FallbackPic extends StatelessWidget {
  const _FallbackPic();
  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.home_work_outlined, size: 32, color: Color(0xFFB9B8B2));
}

class _StatusChip extends StatelessWidget {
  final ProjectStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final (Color bg, String label) = switch (status) {
      ProjectStatus.open => (const Color(0xFFE3F2E1), 'مفتوح للعروض'),
      ProjectStatus.inProgress => (const Color(0xFFFFF3D6), 'قيد التنفيذ'),
      ProjectStatus.completed => (const Color(0xFFE3EAF6), 'منجز'),
      ProjectStatus.cancelled => (const Color(0xFFF5F0F0), 'ملغى'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}