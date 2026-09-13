// One short, skippable Arabic explainer that asks the only question the landing
// page cannot answer for the visitor: which side of the app is he on.
//
// Why: the sign-up form does ask `نوع الحساب`, but it asks it after the visitor
// has started typing a phone number, and the landing page offers a single
// «إنشاء الحساب» button that never mentions that this app has two sides. A
// first-time visitor — often a contractor on a modest phone, reading Arabic —
// has no way to know that the app serves both the person who posts the work and
// the person who does it. So the question moves one step earlier: two big tiles
// that say it in plain words, and one tap to leave.
//
// Nothing here is a dead end. Skipping hands the visitor to the form, which asks
// the same question in its own words; the landing page keeps its
// «أنت مقاول أو حرفي؟» line for the contractor who skipped by mistake.
import 'package:flutter/material.dart';

import '../core/l10n/strings.dart';
import '../core/theme/app_theme.dart';
import '../models/enums.dart';
import 'motion.dart';
import 'ui.dart';

/// Opens the explainer. Resolves to the role the visitor chose for himself, or
/// `null` when he skipped.
Future<UserRole?> showRoleGuide(BuildContext context) {
  return showModalBottomSheet<UserRole>(
    context: context,
    // Scroll-controlled, not the 9/16 default: two tiles plus their sentences
    // are taller than that on a short phone at a large text scale, and a
    // clipped «تخطّي» is a trap. See the overflow this fix retired in the loop
    // that shipped it.
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    barrierColor: AppTheme.navyDeep.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
    ),
    builder: (_) => const RoleGuideSheet(),
  );
}

/// The sheet itself, public so a test can pump it without a navigation stack.
class RoleGuideSheet extends StatelessWidget {
  const RoleGuideSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A grabber says "this panel can be dismissed" without a word.
              Center(
                child: Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.line,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'ماذا تريد أن تفعل؟',
                style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'هذا يحدّد ما يظهر في الصفحة الرئيسية. اختر الأقرب لك.',
                style: AppTheme.bodySoft.copyWith(height: 1.6),
              ),
              const SizedBox(height: 18),
              _RoleCard(
                key: const Key('role-guide-customer'),
                icon: Icons.home_work_outlined,
                label: S.customerLabel,
                note: 'انشر مشروعك، استقبل عروض المقاولين، واختر الأنسب — بدون رسوم.',
                tint: AppTheme.info,
                wash: AppTheme.infoWash,
                onTap: () => Navigator.of(context).pop(UserRole.customer),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                key: const Key('role-guide-worker'),
                icon: Icons.build_outlined,
                label: S.workerLabel,
                note: 'اعرض أعمالك السابقة، أرسل عروضك، واحصل على عملاء جدد.',
                tint: AppTheme.accentDeep,
                wash: AppTheme.accentWash,
                onTap: () => Navigator.of(context).pop(UserRole.worker),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('role-guide-skip'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppTheme.tapMin),
                ),
                child: Text(
                  'تخطّي الآن',
                  style: AppTheme.label
                      .copyWith(fontSize: AppTheme.fsBody, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One side of the app, said the way a user would say it. Not a `SelectableTile`:
/// that control is a *choice* whose answer is already made elsewhere, this one
/// carries a sentence of explanation next to the label, and a note squeezed into
/// a 104 dp tile is the kind of clipping earlier loops had to fix.
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String note;
  final Color tint;
  final Color wash;
  final VoidCallback onTap;

  const _RoleCard({
    super.key,
    required this.icon,
    required this.label,
    required this.note,
    required this.tint,
    required this.wash,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: AppCard(
        onTap: onTap,
        padding: AppTheme.cardPadRail,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
                  child: Icon(icon, size: 21, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.label
                            .copyWith(fontSize: AppTheme.fsLead, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        note,
                        style: AppTheme.caption
                            .copyWith(color: AppTheme.textSecondary, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_left_rounded,
                    size: 22, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
    );
  }
}
