import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
import '../models/enums.dart';
import '../widgets/ui.dart';

/// Lightweight account screen shared by both roles: identity info,
/// wilaya help, and logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final u = scope.auth.user!;
    final commune = u.commune?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('حسابي', style: AppTheme.h1.copyWith(fontSize: 18)),
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

          // ── Logout ─────────────────────────────────────────────────────
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            onTap: () async {
              await scope.auth.logout();
            },
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

/// Avatar + name + role badge. The role is the one thing a user may not
/// remember choosing, so it stays visible on the account screen.
class _ProfileHeader extends StatelessWidget {
  final String name;
  final UserRole role;

  const _ProfileHeader({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
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

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.value,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.titleColor = AppTheme.textPrimary,
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
                      .copyWith(fontSize: 14.5, color: titleColor),
                ),
                if (value != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption
                        .copyWith(fontSize: 12.5, color: AppTheme.textMuted),
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
