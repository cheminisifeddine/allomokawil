import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../models/enums.dart';
import '../../widgets/big_button.dart';
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

  /// «إنشاء الحساب» left this page with the account block: a visitor who wants
  /// an account reaches the same form from the dashboard the buttons open, at
  /// the first action that needs it (see core/auth_gate.dart).

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
                  padding: const EdgeInsets.all(AppTheme.s24),
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
          width: 140,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 14),
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
///
/// Two buttons, no explainer text above them and no hint under each one: the
/// labels carry the meaning, the way a first screen should. The keys are load
/// bearing — the tap-target test proves both are at least 56 dp tall.
class _RoleQuestion extends StatelessWidget {
  final VoidCallback onCustomer;
  final VoidCallback onWorker;

  const _RoleQuestion({required this.onCustomer, required this.onWorker});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigButton(
          key: const Key('landing-role-customer'),
          label: 'صاحب مشروع',
          icon: Icons.person_search_rounded,
          onPressed: onCustomer,
        ),
        const SizedBox(height: 12),
        BigButton(
          key: const Key('landing-contractor-link'),
          label: 'مقاول أو حرفي',
          icon: Icons.construction_rounded,
          onPressed: onWorker,
        ),
        const SizedBox(height: AppTheme.s12),
        Text(
          'التصفّح مجاني وبدون حساب.',
          textAlign: TextAlign.center,
          style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

/// Sign in, or make an account — moved off this page.
///
/// The founder's brief, verbatim:
///   «Remove this section تسجيل الدخول إنشاء الحساب بالمتابعة أنت توافق على شروط
///    الاستخدام وسياسة الخصوصية. From first page»
///
/// So the first page is now the mark, the line and the one question it asks.
/// The way back into an existing account did not disappear with the row: it
/// lives in `_LoggedOutView`'s session notice and on the «حسابي» tab of the
/// dashboard both buttons open — that is, exactly where the user is when he
/// needs it, instead of in front of every first-time visitor.

