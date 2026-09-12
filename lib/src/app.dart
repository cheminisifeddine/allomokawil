import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/l10n/strings.dart';
import 'core/security/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'models/enums.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/scaffold/role_home.dart';
import 'widgets/ui.dart';

/// Root widget: resolves where the app starts based on auth + role.
class AlloMokawilApp extends StatelessWidget {
  const AlloMokawilApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return MaterialApp(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _RootGate(auth: auth),
    );
  }
}

/// Shows a loading splash until the persisted session restores, then routes
/// to the login/register gate or the role-aware home.
class _RootGate extends StatelessWidget {
  final AuthState auth;

  const _RootGate({required this.auth});

  @override
  Widget build(BuildContext context) {
    // Listen to the session: a successful register/login flips this gate to the
    // role-aware home with no manual navigation. Without this listener nothing
    // rebuilds on AuthState.notifyListeners(), so the app stayed stuck on the
    // auth screens after a successful sign-in.
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.isRestored) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isAuthenticated) {
          return const Scaffold(body: _GateLanding());
        }
        // Route customer vs worker to their own home screens.
        return RoleHome(role: auth.role);
      },
    );
  }
}

/// Frictionless entry: a branded hero, then two big role cards (I'm a client /
/// I'm a contractor) that lead to sign-in or create-account.
class _GateLanding extends StatelessWidget {
  const _GateLanding();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandHero(),
            const SizedBox(height: 24),
            _RoleCard(
              icon: Icons.home_work_outlined,
              label: S.customerLabel,
              description: S.customerDesc,
              tint: AppTheme.info,
              wash: AppTheme.infoWash,
              onTap: () => _go(context, UserRole.customer),
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.build_outlined,
              label: S.workerLabel,
              description: S.workerDesc,
              tint: AppTheme.accentDeep,
              wash: AppTheme.accentWash,
              onTap: () => _go(context, UserRole.worker),
            ),
            const Spacer(),
            const SizedBox(height: 18),
            const _TermsLine(),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, UserRole role) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (_) => _GateSheet(role: role),
    );
  }
}

/// Navy rounded panel with the brand mark, app name and the Arabic tagline.
class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.navy, AppTheme.navyDeep],
        ),
        borderRadius: BorderRadius.circular(AppTheme.rXl),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.architecture_rounded,
                size: 32, color: AppTheme.navy),
          ),
          const SizedBox(height: 14),
          Text(
            S.appName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display.copyWith(color: AppTheme.onNavy),
          ),
          const SizedBox(height: 6),
          Text(
            'سوق خدمات البناء والتهيئة في الجزائر',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body
                .copyWith(color: AppTheme.onNavyMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Big tappable card: icon, role name, one-line explanation, forward arrow.
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color tint;
  final Color wash;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.tint,
    required this.wash,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          IconBubble(icon: icon, tint: tint, wash: wash, size: 50),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_back_ios_new_rounded,
              size: 14, color: AppTheme.textMuted),
        ],
      ),
    );
  }
}

/// Quiet privacy line pinned at the bottom of the landing gate.
class _TermsLine extends StatelessWidget {
  const _TermsLine();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        const Icon(Icons.verified_user_outlined,
            size: 15, color: AppTheme.textMuted),
        Text(
          'بالاختيار أنت توافق على شروط الاستخدام وسياسة الخصوصية',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

/// Bottom sheet after a role is picked: sign in, or create the account.
class _GateSheet extends StatelessWidget {
  final UserRole role;
  const _GateSheet({required this.role});

  @override
  Widget build(BuildContext context) {
    final isCustomer = role == UserRole.customer;
    final header = isCustomer ? S.customerLabel : S.workerLabel;
    final desc = isCustomer ? S.customerDesc : S.workerDesc;
    final icon = isCustomer ? Icons.home_work_outlined : Icons.build_outlined;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: IconBubble(
                icon: icon,
                tint: AppTheme.navy,
                wash: AppTheme.accentWash,
                size: 56,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              header,
              textAlign: TextAlign.center,
              style: AppTheme.h1.copyWith(color: AppTheme.navy),
            ),
            const SizedBox(height: 6),
            Text(desc, textAlign: TextAlign.center, style: AppTheme.bodySoft),
            const SizedBox(height: 20),
            PrimaryButton(
              label: S.createAccount,
              icon: icon,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => RegisterScreen(role: role))),
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: S.login,
              icon: Icons.login_rounded,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
            ),
          ],
        ),
      ),
    );
  }
}
