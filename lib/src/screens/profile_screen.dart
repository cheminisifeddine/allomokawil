import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth_gate.dart';
import '../core/theme/app_theme.dart';
import '../data/repository.dart';
import '../data/taxonomy.dart';
import '../models/enums.dart';
import '../models/plan.dart';
import '../widgets/ui.dart';
import 'verify/verification_screen.dart';
import 'worker/my_portfolio_screen.dart';
import 'worker/profile_edit_screen.dart';
import 'worker/subscription_screen.dart';

/// Lightweight account screen shared by both roles: identity info,
/// wilaya help, and logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final user = scope.auth.user;

    // Signed out the account tab is the visitor's own page: same shape, same
    // app bar, and the one door that leads to a real account.
    if (user == null) {
      return _GuestAccountScreen(
          role: scope.auth.guestRole ?? UserRole.customer);
    }

    final u = user;
    final commune = u.commune?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('حسابي', style: AppTheme.bar),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
        children: [
          // ── Identity ───────────────────────────────────────────────────
          _ProfileHeader(name: u.fullName, role: u.type),

          // ── Account details ────────────────────────────────────────────
          const SectionTitle('معلومات الحساب', icon: Icons.badge_outlined),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsRow(
                  icon: Icons.phone_rounded,
                  title: 'رقم الهاتف',
                  value: u.phone,
                ),
                if (u.wilaya != null) ...[
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.location_on_rounded,
                    title: 'الولاية',
                    value: Taxonomy.wilayaName(u.wilaya!),
                  ),
                ],
                if (commune != null && commune.isNotEmpty) ...[
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.location_city_rounded,
                    title: 'البلدية',
                    value: commune,
                  ),
                ],
              ],
            ),
          ),

          // ── The contractor's own material ──────────────────────────────
          //
          // A contractor opens this tab looking for "my work" and "my papers".
          // Leaving them only on the home tab meant hunting for the one place
          // that uploads; the account screen is where a user looks for their own
          // things, so the same three doors are here too.
          if (u.type == UserRole.worker) ...[
            const SizedBox(height: 14),
            const SectionTitle('ملفي المهني', icon: Icons.handyman_outlined),
            AppCard(
              key: const Key('account-portfolio'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyPortfolioScreen())),
              child: const _SettingsRow(
                icon: Icons.photo_library_outlined,
                title: 'معرض أعمالي',
                value: 'أضف صور أعمالك السابقة',
                tint: AppTheme.accentDeep,
                wash: AppTheme.accentWash,
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              key: const Key('account-documents'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const VerificationScreen())),
              child: const _SettingsRow(
                icon: Icons.verified_user_outlined,
                title: 'المستندات والشهادات',
                value: 'بطاقة الحرفي، الهوية، وشهاداتك',
                tint: AppTheme.info,
                wash: AppTheme.infoWash,
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            AppCard(
              key: const Key('account-edit'),
              padding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              child: const _SettingsRow(
                icon: Icons.tune_rounded,
                title: 'تعديل الملف المهني',
                value: 'التخصصات، النبذة، الأسعار، ومنطقة الخدمة',
                trailing: _Chevron(),
              ),
            ),
            const SizedBox(height: 10),
            // The founder asked for the subscription to be visible where a
            // contractor looks for his own things, not only on the home tab.
            const _PlanAccountRow(),
          ],

          // ── Logout ─────────────────────────────────────────────────────
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            // The queue of unsent messages goes with the session inside
            // `auth.logout()`, which is the only place that knows every way a
            // session can end — including the 401 this screen never sees.
            onTap: scope.auth.logout,
            child: const _SettingsRow(
              icon: Icons.logout_rounded,
              title: 'تسجيل الخروج',
              tint: AppTheme.danger,
              wash: AppTheme.dangerWash,
              titleColor: AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// The contractor's subscription, read live so the account screen never claims
/// a plan the server does not have.
class _PlanAccountRow extends StatefulWidget {
  const _PlanAccountRow();

  @override
  State<_PlanAccountRow> createState() => _PlanAccountRowState();
}

class _PlanAccountRowState extends State<_PlanAccountRow> {
  Future<BillingCatalogue>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= Repository(AppScope.of(context).api).subscription();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('account-subscription'),
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
      child: FutureBuilder<BillingCatalogue>(
        future: _future,
        builder: (context, snap) => _SettingsRow(
          icon: Icons.workspace_premium_outlined,
          title: 'اشتراكي',
          value: _planSummary(snap.data?.current, snap.connectionState),
          tint: AppTheme.accentDeep,
          wash: AppTheme.accentWash,
          trailing: const _Chevron(),
        ),
      ),
    );
  }
}

/// One line under «اشتراكي»: what the contractor is actually on right now.
String _planSummary(SubscriptionStatus? s, ConnectionState state) {
  if (s == null) {
    return state == ConnectionState.waiting
        ? 'جارٍ التحقق من اشتراكك…'
        : 'اختر خطتك — شهري أو سنوي';
  }
  if (s.isFree) return 'الباقة المجانية — اطّلع على الخطط';
  final end = s.expiresAt?.split(' ').first;
  return end == null ? s.nameAr : '${s.nameAr} — نشط حتى $end';
}

/// The account tab for a visitor who has not made an account: same app bar,
/// same shape, and the sign-in form only when he asks for it.
class _GuestAccountScreen extends StatelessWidget {
  final UserRole role;

  const _GuestAccountScreen({required this.role});

  @override
  Widget build(BuildContext context) {
    final worker = role == UserRole.worker;
    return Scaffold(
      appBar: AppBar(title: Text('حسابي', style: AppTheme.bar)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: AppCard(
              padding: AppTheme.cardPad,
              child: Row(
                children: [
                  const IconBubble(
                    icon: Icons.person_outline_rounded,
                    tint: AppTheme.navy,
                    wash: AppTheme.lineSoft,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('زائر',
                            style: AppTheme.h1
                                .copyWith(color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        StatusPill(
                          label: worker ? 'حرفي — بدون حساب' : 'صاحب مشروع — بدون حساب',
                          color: AppTheme.accentDeep,
                          wash: AppTheme.accentWash,
                          icon: worker
                              ? Icons.handyman_rounded
                              : Icons.person_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SignInWall(
              title: 'حسابك في الو مقاول',
              body: worker
                  ? 'سجّل الدخول لتُرسل عروضك على المشاريع المفتوحة وتُدير طلباتك وصور أعمالك.'
                  : 'سجّل الدخول لتتواصل مع المقاولين وتنشر مشروعك وتستقبل العروض.',
              role: role,
              note: 'كل التصفّح متاح بدون حساب.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar + name + role badge. The role is the one thing a user may not
/// remember choosing, so it stays visible on the account screen.
class _ProfileHeader extends StatelessWidget {
  final String name;
  final UserRole role;

  const _ProfileHeader({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppTheme.cardPad,
      child: Row(
        children: [
          InitialAvatar(name: name, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h1.copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                StatusPill(
                  label: _roleLabel(role),
                  color: AppTheme.accentDeep,
                  wash: AppTheme.accentWash,
                  icon: _roleIcon(role),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row: leading [IconBubble] + label (+ optional value).
/// Colours are always explicit so a row can never vanish.
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final Color tint;
  final Color wash;
  final Color titleColor;

  final Widget? trailing;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.value,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.titleColor = AppTheme.textPrimary,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          IconBubble(icon: icon, tint: tint, wash: wash, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.label
                      .copyWith(fontSize: AppTheme.fsSmall, color: titleColor),
                ),
                if (value != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Right-pointing chevron for a row that opens another screen.
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_left_rounded,
        size: 20, color: AppTheme.textMuted);
  }
}

/// Hairline between rows, indented so it starts after the icon bubble.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 70, color: AppTheme.lineSoft);
  }
}

String _roleLabel(UserRole role) {
  switch (role) {
    case UserRole.worker:
      return 'مقاول حرفي';
    case UserRole.admin:
      return 'مسؤول';
    case UserRole.customer:
      return 'صاحب مشروع';
  }
}

IconData _roleIcon(UserRole role) {
  switch (role) {
    case UserRole.worker:
      return Icons.handyman_rounded;
    case UserRole.admin:
      return Icons.admin_panel_settings_rounded;
    case UserRole.customer:
      return Icons.person_rounded;
  }
}
