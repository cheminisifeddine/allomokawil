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
      // The page column, by its own name. It was a uniform all-around gutter,
      // which agreed with [AppTheme.pagePad] on the two sides *because*
      // `gutter` happens to have that value — an agreement by coincidence,
      // which is what hid it — and disagreed on both verticals: the first
      // skeleton card sat 10 dp lower than the first real row and the last one
      // stopped 10 dp short of the bottom, so the whole column jumped twice,
      // once as the shimmer appeared and once as the rows landed.
      //
      // Both callers draw their real rows with `padding: AppTheme.pagePad`
      // (`browse_screen.dart:347`, `chat_list_screen.dart:328`), so this is
      // the token that keeps the skeleton's shape equal to the shape it is
      // standing in for. `test/loading_list_column_test.dart` reads both
      // numbers off the built tree rather than trusting either one.
      padding: AppTheme.pagePad,
      itemCount: count,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: AppTheme.cardPad,
        decoration: AppTheme.cardDecoration,
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
          borderRadius: BorderRadius.circular(AppTheme.rXs),
        ),
      );
}
