import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'skeletons.dart';

/// Friendly empty state for lists with no content yet.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppTheme.lineSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.h2,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTheme.bodySoft,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading skeleton for list screens — calm grey blocks rather than spinners,
/// which read as "the app is thinking" instead of "the app is broken".
class LoadingList extends StatelessWidget {
  final int count;
  const LoadingList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    // A viewport (ListView) never overflows vertically, unlike a plain Column,
    // and shrinkWrap lets it size to its content when a parent (e.g. a
    // SliverToBoxAdapter) hands it unbounded height.
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      itemCount: count,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(color: AppTheme.line),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: SkeletonTone.base,
                borderRadius: BorderRadius.circular(AppTheme.rSm),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Bar(width: 150, height: 14),
                  SizedBox(height: 10),
                  _Bar(width: 100, height: 11),
                  SizedBox(height: 10),
                  _Bar(width: 70, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  final double height;
  const _Bar({required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: SkeletonTone.base,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}
