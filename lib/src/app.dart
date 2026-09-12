import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/l10n/strings.dart';
import 'core/security/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/scaffold/role_home.dart';

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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!auth.isAuthenticated) {
          return const LandingScreen();
        }
        // Route customer vs worker to their own home screens.
        return RoleHome(role: auth.role);
      },
    );
  }
}
