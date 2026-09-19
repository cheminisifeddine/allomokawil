import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../auth/auth_screen.dart';
import '../browse/browse_screen.dart';
import '../worker/worker_home_screen.dart';

/// The dashboard a visitor gets without an account.
///
/// The founder's brief, verbatim: «make sure the users can use and browse offer
/// and jobs without sign in, just ask in the first page for if this is مقاول او
/// صاحب عمل and show the related dashboard». The first page asks; this is the
/// answer. A customer browses contractors, a contractor browses the open jobs
/// board — the same public lists a signed-in user sees, minus everything that
/// writes.
///
/// Reading is public on purpose: the only thing a login gates is doing
/// something (posting a project, quoting, chatting).
class GuestHomeScreen extends StatelessWidget {
  final UserRole role;

  const GuestHomeScreen({super.key, required this.role});

  bool get _isWorker => role == UserRole.worker;

  void _auth(BuildContext context, AuthMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(mode: mode, role: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository(AppScope.of(context).api);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          _GuestBar(
            isWorker: _isWorker,
            onSignIn: () => _auth(context, AuthMode.signIn),
            onRegister: () => _auth(context, AuthMode.signUp),
          ),
          Expanded(
            child: _isWorker
                ? MarketplaceView(repo: repo, guest: true)
                : const BrowseScreen(customerSide: true),
          ),
        ],
      ),
    );
  }
}

/// The bar across the top of a guest dashboard: who is signed out, what is free,
/// and the two ways to get an account.
class _GuestBar extends StatelessWidget {
  final bool isWorker;
  final VoidCallback onSignIn;
  final VoidCallback onRegister;

  const _GuestBar({
    required this.isWorker,
    required this.onSignIn,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accentWash,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.s16, AppTheme.s8, AppTheme.s8, AppTheme.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      S.appName,
                      style: AppTheme.label.copyWith(
                        color: AppTheme.navy,
                        fontSize: AppTheme.fsBody,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('guest-sign-in'),
                    onPressed: onSignIn,
                    child: Text(S.loginTitle),
                  ),
                ],
              ),
              Text(
                isWorker
                    ? 'تصفّح المشاريع المفتوحة مجاناً. أنشئ حساب مقاول لإرسال عروضك.'
                    : 'تصفّح المقاولين مجاناً. أنشئ حساباً لنشر مشروعك واستقبال العروض.',
                style: AppTheme.caption
                    .copyWith(color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('guest-create-account'),
                  onPressed: onRegister,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(S.createAccount),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
