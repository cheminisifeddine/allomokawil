// The first screen of a fresh install — deliberately ONE screen.
//
// The founder's brief, verbatim: "Change this first page when a clients
// install the app, make it super easy. Don't make it very complicated, just
// simple information and then asking to login or create an account to start
// using the app." And: "the photo in the background is black. Fix that."
//
// So this page answers three questions and stops: what is this, can I trust
// it, how do I start. No "how it works" tour, no service grid, no marketing
// paragraphs — all of that lives inside the app, one tap away. What is left
// above the buttons is a glance; what is below is a button.
//
// The black background was real and had one cause: this was the only screen
// in the app whose root was not a `Scaffold`, so nothing ever painted the
// canvas and the engine's black clear colour showed through on device. The
// `Scaffold` below is the fix, not decoration.
import 'package:flutter/material.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/onboarding.dart';
import '../../models/enums.dart';
import '../../widgets/role_guide.dart';
import '../../widgets/ui.dart';
import '../auth/auth_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _openAuth(BuildContext context, AuthMode mode,
      {UserRole role = UserRole.customer}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(mode: mode, role: role)),
    );
  }

  /// «إنشاء الحساب» is the one button that has to answer a question the visitor
  /// cannot answer himself: is he the one who needs work done, or the one who
  /// does it? The form asks it too, but only after a phone number has been typed,
  /// so a first-time visitor gets the explainer once, here. Whatever he answers —
  /// or if he skips — the tap still ends on the same sign-up form.
  Future<void> _startSignUp(BuildContext context) async {
    var role = UserRole.customer;
    final seen = await roleGuideSeen();
    if (!context.mounted) return;
    if (!seen) {
      final picked = await showRoleGuide(context);
      await markRoleGuideSeen();
      if (picked != null) role = picked;
    }
    if (!context.mounted) return;
    _openAuth(context, AuthMode.signUp, role: role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // The whole "what is this / can I trust it" half stays
                      // together at the top; the one free-space gap falls just
                      // above the buttons, where it reads as breathing room.
                      const _Welcome(),
                      const _Promises(),
                      _StartBlock(
                        onCreate: () => _startSignUp(context),
                        onSignIn: () => _openAuth(context, AuthMode.signIn),
                        onContractor: () => _openAuth(context, AuthMode.signUp,
                            role: UserRole.worker),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The mark, the name, and one line that says what the app is for.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // The mark on its own: no tile, no ring, nothing behind it.
        Image.asset(
          'assets/brand/mark.png',
          // Decoration: the app name is printed right underneath it.
          excludeFromSemantics: true,
          width: 200,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 20),
        Text(
          S.appName,
          textAlign: TextAlign.center,
          style: AppTheme.h1.copyWith(
            color: AppTheme.navy,
            fontSize: AppTheme.fsHero,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'كل خدمات البناء والتهيئة في مكان واحد.',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(
            color: AppTheme.textSecondary,
            fontSize: AppTheme.fsBody,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Three lines — what the user gets, before they are asked for anything.
class _Promises extends StatelessWidget {
  const _Promises();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PromiseRow(
          icon: Icons.verified_user_rounded,
          label: 'مقاولون موثّقون',
          note: 'كل حساب مقاول يُراجع قبل النشر',
          tint: AppTheme.info,
        ),
        SizedBox(height: 24),
        _PromiseRow(
          icon: Icons.star_rounded,
          label: 'تقييمات حقيقية',
          note: 'تقييم بالنجوم بعد كل عمل يُنجز',
          tint: AppTheme.star,
        ),
        SizedBox(height: 24),
        _PromiseRow(
          icon: Icons.payments_rounded,
          label: 'بدون رسوم',
          note: 'نشر المشروع واستقبال العروض مجاناً',
          tint: AppTheme.success,
        ),
      ],
    );
  }
}

class _PromiseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String note;
  final Color tint;

  const _PromiseRow({
    required this.icon,
    required this.label,
    required this.note,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.rSm),
          ),
          child: Icon(icon, size: 24, color: tint),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption
                    .copyWith(color: AppTheme.textSecondary, fontSize: AppTheme.fsMeta),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The only thing the user has to do: create an account, or sign in.
class _StartBlock extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onSignIn;
  final VoidCallback onContractor;

  const _StartBlock({
    required this.onCreate,
    required this.onSignIn,
    required this.onContractor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          key: const Key('landing-create-account'),
          label: S.createAccount,
          icon: Icons.person_add_alt_1_rounded,
          onPressed: onCreate,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          key: const Key('landing-sign-in'),
          label: S.loginTitle,
          icon: Icons.login_rounded,
          onPressed: onSignIn,
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('landing-contractor-link'),
          onPressed: onContractor,
          child: Text(
            'أنت مقاول أو حرفي؟ أنشئ حساب مقاول',
            textAlign: TextAlign.center,
            style: AppTheme.label.copyWith(fontSize: AppTheme.fsSmall, color: AppTheme.info),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'بالمتابعة أنت توافق على شروط الاستخدام وسياسة الخصوصية.',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(
            color: AppTheme.textMuted,
            fontSize: AppTheme.fsBadge,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
