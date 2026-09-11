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
import 'widgets/big_button.dart';

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

/// Frictionless entry: two big choices (I'm a client / I'm a contractor)
/// then sign-in or create-account, with a clear return path.
class _GateLanding extends StatelessWidget {
  const _GateLanding();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Text(
              S.appName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'سوق خدمات البناء والتهيئة في الجزائر',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xFF6E6E73)),
            ),
            const SizedBox(height: 40),
            BigButton(
              label: S.customerLabel,
              icon: Icons.home_work_outlined,
              onPressed: () => _go(context, UserRole.customer),
            ),
            const SizedBox(height: 12),
            BigButton(
              label: S.workerLabel,
              icon: Icons.build_outlined,
              onPressed: () => _go(context, UserRole.worker),
            ),
            const SizedBox(height: 24),
            Text(
              'بالاختيار أنت توافق على شروط الاستخدام وسياسة الخصوصية',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
            ),
            const SizedBox(height: 16),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _GateSheet(role: role),
    );
  }
}

class _GateSheet extends StatelessWidget {
  final UserRole role;
  const _GateSheet({required this.role});

  @override
  Widget build(BuildContext context) {
    final isCustomer = role == UserRole.customer;
    final header = isCustomer ? S.customerLabel : S.workerLabel;
    final desc = isCustomer ? S.customerDesc : S.workerDesc;
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
              child: Text(
                header,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6E6E73))),
            const SizedBox(height: 20),
            OutlineButton(
              label: S.login,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen())),
            ),
            const SizedBox(height: 12),
            BigButton(
              label: S.createAccount,
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => RegisterScreen(role: role))),
            ),
          ],
        ),
      ),
    );
  }
}