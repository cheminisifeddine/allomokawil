import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/l10n/strings.dart';
import 'core/security/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/scaffold/guest_home_screen.dart';
import 'screens/scaffold/role_home.dart';
import 'widgets/skeletons.dart';

/// Root widget: resolves where the app starts based on auth + role.
///
/// The gate is deliberately thin. A fresh install lands on the marketing
/// landing page (which asks for nothing), and the auth screens are pushed on top
/// of it; once a session exists the same gate swaps in the role-aware home. The
/// two halves of getting an account live together in `AuthScreen`, and the role
/// is chosen there rather than on a gate that stood in front of it.
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
/// to the landing page or the role-aware home.
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
          // The restore takes a few frames. A grey circle mid-screen reads as
          // "broken"; the shape of the home reads as "opening".
          return const Scaffold(body: AppBootSkeleton());
        }
        if (!auth.isAuthenticated) {
          final guest = auth.guestRole;
          if (guest != null) {
            // Browsing must not require an account. The first page asked which
            // side of the marketplace this visitor is on; this is that
            // dashboard, signed out.
            return GuestHomeScreen(role: guest);
          }
          return _LoggedOutView(auth: auth);
        }
        // Route customer vs worker to their own home screens.
        return RoleHome(role: auth.role);
      },
    );
  }
}

/// The landing page, plus the one thing a session that died server-side owes the
/// user: an explanation.
///
/// The founder's report, verbatim: "the jobs are not showing inside the app
/// nothing is showing". What the app was actually doing was holding a token the
/// server no longer knew, so every list came back 401 and every screen drew its
/// own failure line on top of a home page that could never fill in. Nothing on
/// that screen said "sign in again" and there was no way back to the form.
///
/// Now the dead session is dropped and this bar says why, in the same Arabic
/// sentence the API's own copy uses, above the exact button that fixes it.
class _LoggedOutView extends StatelessWidget {
  const _LoggedOutView({required this.auth});

  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    if (!auth.sessionExpired) return const LandingScreen();
    return Column(
      children: [
        _SessionExpiredBar(onDismiss: auth.clearSessionExpiredNotice),
        const Expanded(child: LandingScreen()),
      ],
    );
  }
}

class _SessionExpiredBar extends StatelessWidget {
  const _SessionExpiredBar({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.dangerWash,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(top: 2, end: 10),
                child: Icon(Icons.lock_clock_outlined,
                    size: 20, color: AppTheme.danger),
              ),
              const Expanded(
                child: Text(
                  S.errUnauthorized,
                  style: TextStyle(
                    fontSize: AppTheme.fsMeta,
                    height: 1.5,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDismiss,
                child: const Text('حسناً'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
