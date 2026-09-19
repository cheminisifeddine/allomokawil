import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/onboarding.dart';
import '../../models/enums.dart';
import '../../widgets/big_button.dart';
import '../../widgets/role_guide.dart';
import '../auth/auth_screen.dart';

/// The first screen of a fresh install — one question, not a brochure.
///
/// The founder's brief for this page, verbatim:
///   «Make sure the users can use and browse offer and jobs without sign. In
///    just ask in the first page for If this is مقاول او صاحب عمل and show the
///    related dashboard»
///   «Make the first page simple»
///   «Chahnge كل خدمات البناء والتهيئة في مكان واحد. هنا تجد افضل المقاولين و
///    الحرفيين»
///   «Remove مقاولون موثوقون … تقييمات حقيقية … بدون رسوم … from first page»
///
/// What is left is the mark, that one line, and the question with its two
/// answers. The trust badges that used to fill the middle are gone: a visitor
/// can start reading the app without being sold to first, because both buttons
/// open the real dashboards signed out.
///
/// The black background this page once had teaches the shape below: the root is
/// a `Scaffold`, so the canvas is always painted.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  /// The one line that says what the app is for.
  static const tagline = 'هنا تجد أفضل المقاولين والحرفيين';

  /// Opens the dashboard for [role] without an account.
  ///
  /// Pumped without an [AppScope] (widget tests, the design shots) there is no
  /// session to record, so the tap falls back to the sign-up form instead of
  /// doing nothing.
  Future<void> _enter(BuildContext context, UserRole role) async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) {
      _openAuth(context, AuthMode.signUp, role: role);
      return;
    }
    await scope.auth.enterAsGuest(role);
  }

  void _openAuth(BuildContext context, AuthMode mode,
      {UserRole role = UserRole.customer}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(mode: mode, role: role)),
    );
  }

  /// «إنشاء الحساب» is the one button that has to answer a question the visitor
  /// cannot answer himself: is he the one who needs work done, or the one who
  /// does it? The form asks it too, but only after a phone number has been
  /// typed, so a first-time visitor gets the explainer once, here. Whatever he
  /// answers — or if he skips — the tap still ends on the same sign-up form.
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // `spaceEvenly` rather than `Spacer`: inside a scroll view
                    // the height is unbounded, and flex children there throw.
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const _Welcome(),
                      _RoleQuestion(
                        onCustomer: () => _enter(context, UserRole.customer),
                        onWorker: () => _enter(context, UserRole.worker),
                      ),
                      _AccountBlock(
                        onCreate: () => _startSignUp(context),
                        onSignIn: () => _openAuth(context, AuthMode.signIn),
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

/// The mark, the name, and the one line that says what the app is for.
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
          width: 168,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        Text(
          S.appName,
          textAlign: TextAlign.center,
          style: AppTheme.h1.copyWith(
            color: AppTheme.navy,
            fontSize: AppTheme.fsHero,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          LandingScreen.tagline,
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

/// The first page's question, and the only two answers that matter.
class _RoleQuestion extends StatelessWidget {
  final VoidCallback onCustomer;
  final VoidCallback onWorker;

  const _RoleQuestion({required this.onCustomer, required this.onWorker});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'كيف تريد أن تبدأ؟',
          textAlign: TextAlign.center,
          style: AppTheme.body.copyWith(
            color: AppTheme.navy,
            fontSize: AppTheme.fsBody,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        BigButton(
          key: const Key('landing-role-customer'),
          label: 'صاحب مشروع',
          icon: Icons.person_search_rounded,
          onPressed: onCustomer,
        ),
        const _RoleHint('أبحث عن مقاول أو حرفي لمشروعي'),
        const SizedBox(height: 12),
        BigButton(
          // The tap-target test knows this button by this key: it is the way a
          // contractor gets in, and it must stay >= 56 dp tall.
          key: const Key('landing-contractor-link'),
          label: 'مقاول أو حرفي',
          icon: Icons.construction_rounded,
          onPressed: onWorker,
        ),
        const _RoleHint('أبحث عن مشاريع مفتوحة وأرسل عروضي'),
        const SizedBox(height: 10),
        Text(
          'التصفّح مجاني وبدون حساب.',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

class _RoleHint extends StatelessWidget {
  final String text;

  const _RoleHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}

/// Sign in, or make an account. The guest buttons above need neither.
class _AccountBlock extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onSignIn;

  const _AccountBlock({required this.onCreate, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('لديك حساب؟',
                style: AppTheme.caption.copyWith(color: AppTheme.textMuted)),
            TextButton(
              // Named for the session-expired test, which proves the front door
              // keeps a way in next to the notice explaining why it is showing.
              key: const Key('landing-sign-in'),
              onPressed: onSignIn,
              child: Text(S.loginTitle),
            ),
          ],
        ),
        TextButton(
          key: const Key('landing-create-account'),
          onPressed: onCreate,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(AppTheme.tapMin),
          ),
          child: Text(S.createAccount),
        ),
      ],
    );
  }
}
