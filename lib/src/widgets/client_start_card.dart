import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'ui.dart';

/// One step of the client's first-run path.
class StartStep {
  final String title;
  final String detail;
  final IconData icon;

  const StartStep(this.title, this.detail, this.icon);
}

/// What a project owner does between installing the app and hiring somebody.
/// Three steps, in the order they happen: publish, compare, agree.
const List<StartStep> clientStartSteps = [
  StartStep(
    'انشر مشروعك',
    'اكتب ما تريد إنجازه وحدّد الميزانية والولاية',
    Icons.add_home_work_rounded,
  ),
  StartStep(
    'قارن عروض المقاولين',
    'يصلك عرض بالسعر والمدة من كل مقاول',
    Icons.request_quote_rounded,
  ),
  StartStep(
    'تواصل واختر الأنسب',
    'افتح محادثة واتفق على الموعد داخل التطبيق',
    Icons.chat_bubble_outline_rounded,
  ),
];

/// The client home's first-run guide.
///
/// A brand-new project owner landed on the marketplace with no named next step,
/// while a brand-new contractor got a checklist. This is the client's half of
/// that: it names the first step («انشر مشروعك»), makes it a real tap target,
/// and leads with the one action that starts everything. It is rendered on the
/// client home only while [clientNeedsFirstRunGuide] says so, and the post
/// banner below it is suppressed while it is up, so the screen never shows the
/// same call to action twice.
class ClientStartCard extends StatelessWidget {
  /// Publishes a project — step one, and the primary action of the screen.
  final VoidCallback onPost;

  /// Browsing contractors first is a legitimate choice, so it is offered right
  /// here rather than only behind the search bar.
  final VoidCallback onBrowseWorkers;

  const ClientStartCard({
    super.key,
    required this.onPost,
    required this.onBrowseWorkers,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: AppCard(
        key: const Key('client-start-card'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBubble(
                  icon: Icons.rocket_launch_rounded,
                  tint: AppTheme.accentDeep,
                  wash: AppTheme.accentWash,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ابدأ من هنا',
                        style: AppTheme.h2
                            .copyWith(fontSize: 16, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'ثلاث خطوات تفصلك عن مقاول موثوق',
                        style: AppTheme.caption.copyWith(
                            fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < clientStartSteps.length; i++)
              _StepRow(
                key: Key('client-start-step-${i + 1}'),
                index: i + 1,
                step: clientStartSteps[i],
                first: i == 0,
              ),
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('client-start-cta'),
              label: 'انشر مشروعك الأول',
              icon: Icons.add_home_work_rounded,
              onPressed: onPost,
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              key: const Key('client-start-browse'),
              label: 'تصفّح المقاولين',
              icon: Icons.search_rounded,
              onPressed: onBrowseWorkers,
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered step. The first one carries the amber ball because it is the one
/// the buttons under the list perform; the rest are quiet grey.
class _StepRow extends StatelessWidget {
  final int index;
  final StartStep step;
  final bool first;

  const _StepRow({
    super.key,
    required this.index,
    required this.step,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = first ? AppTheme.navy : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: first ? AppTheme.accent : AppTheme.lineSoft,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: AppTheme.caption.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: first ? AppTheme.accent : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      step.icon,
                      size: 16,
                      color: first ? AppTheme.accent : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        step.title,
                        style: AppTheme.label.copyWith(
                          fontSize: 13.5,
                          color: titleColor,
                          fontWeight: first ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  step.detail,
                  style: AppTheme.caption.copyWith(
                      fontSize: 12, height: 1.45, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
