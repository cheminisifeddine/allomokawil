import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/l10n/strings.dart';
import 'core/security/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/scaffold/role_home.dart';
import 'widgets/place_warmup.dart';
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
      home: PlaceWarmup(child: _RootGate(auth: auth)),
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
            // Browsing must not require an account, and it must not look like a
            // different application either. The visitor gets the same shell the
            // signed-in user gets, with the same tabs and the same content; the
            // only walls in it are the private ones (see core/auth_gate.dart).
            //
            // The key is load bearing. A visitor who picked «مقاول» and then
            // made a contractor account flips from `guest-worker` to
            // `user-<id>-worker` — the same `RoleHome` the framework would
            // happily reuse, keeping the signed-out state of every screen under
            // it. The founder hit exactly that: «when i login as a visitor and
            // i create an account i didn't automatically get logged in and i
            // stay a visitor till i exit the app and open it again». Keying the
            // subtree by the session's identity tears the guest tree down and
            // builds the member tree in the same frame.
            return KeyedSubtree(
              key: ValueKey('guest-${guest.name}'),
              child: RoleHome(role: guest),
            );
          }
          return _LoggedOutView(auth: auth);
        }
        // Route customer vs worker to their own home screens.
        return KeyedSubtree(
          key: ValueKey('user-${auth.user?.id ?? 0}-${auth.role.name}'),
          child: RoleHome(role: auth.role),
        );
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
        _SessionExpiredBar(
          onDismiss: auth.clearSessionExpiredNotice,
          // The way back in, shown exactly when it is needed. The first page
          // itself carries no account row any more (the founder asked for it
          // off), so the one moment a user is staring at a dead session is the
          // one moment the sign-in button belongs next to the notice.
          onSignIn: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AuthScreen(mode: AuthMode.signIn),
          )),
        ),
        const Expanded(child: LandingScreen()),
      ],
    );
  }
}

class _SessionExpiredBar extends StatelessWidget {
  const _SessionExpiredBar({required this.onDismiss, required this.onSignIn});

  final VoidCallback onDismiss;
  final VoidCallback onSignIn;

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
                key: const Key('landing-sign-in'),
                onPressed: onSignIn,
                child: const Text(S.loginTitle),
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
