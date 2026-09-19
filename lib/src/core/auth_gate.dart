import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'l10n/strings.dart';
import 'theme/app_theme.dart';
import '../models/enums.dart';
import '../screens/auth/auth_screen.dart';
import '../widgets/big_button.dart';
import '../widgets/ui.dart';

/// Guest mode: the app is fully readable without an account, and the account
/// form appears at the exact moment an action actually needs one.
///
/// The founder's brief, verbatim:
///   «When i use app wihtout sign up show the app exactly as if i'm signed»
///   «only take the client to sign up or login page when he try to contact a
///    handcraft man or do any activity that need an account first»
///
/// So there is no separate "guest" application: a signed-out visitor gets the
/// same shell, the same tabs and the same content as a signed-in one. What
/// differs is only the private material — his projects, his conversations, his
/// dossier — which is what [SignInWall] stands in front of, and the actions
/// that write to the database, which go through [requireAuth].
///
/// Reading this file is reading the entire guest contract: everything else in
/// the app is shared code.
class AuthGate {
  const AuthGate._();

  /// True when nobody is signed in (a first-run visitor, or one who picked a
  /// side on the first page but never made an account).
  ///
  /// A tree with no [AppScope] above it is NOT a visitor: a screen pumped on its
  /// own — a widget test, a route pushed by a bare navigator — has no session
  /// store to consult, and rendering its own content is the honest answer. This
  /// matters: keying "no scope" as "signed out" put the sign-in wall in front of
  /// screens that had a signed-in user in their own test.
  static bool isGuest(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    return scope != null && scope.auth.user == null;
  }

  /// The role a signed-out visitor is browsing as, so the same screens can tell
  /// him what he is missing instead of showing him a stranger's data.
  static UserRole guestRole(BuildContext context) =>
      AppScope.maybeOf(context)?.auth.guestRole ?? UserRole.customer;

  /// Runs [action] when a session exists; otherwise opens the sign-in form and
  /// returns false, so the caller can simply `if (!await requireAuth(...)) return;`.
  ///
  /// [what] is the sentence the visitor was trying to do, printed as the reason
  /// the form appeared: "سجّل الدخول لتتواصل مع المقاول".
  static Future<bool> requireAuth(BuildContext context,
      {required String what, UserRole? as}) async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return false; // No session store (widget tests): do nothing.
    if (scope.auth.user != null) return true;
    final role = as ?? scope.auth.guestRole ?? UserRole.customer;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AuthScreen(mode: AuthMode.signUp, role: role),
    ));
    // The form may have created the account before it popped, which is exactly
    // the outcome the caller wanted — so report what is true now, not what was
    // true when the visitor tapped.
    return scope.auth.user != null;
  }

  /// The reason line shown above the form. Kept in one place so the same words
  /// are used everywhere an action is gated.
  static String reason(String what) => 'سجّل الدخول أو أنشئ حساباً $what';
}

/// What a signed-out visitor reads where private material would be.
///
/// It is a placeholder, not a wall: the visitor can walk away and keep reading
/// the marketplace, which is why every wall repeats the tab it replaced and
/// never traps the back gesture.
class SignInWall extends StatelessWidget {
  /// The headline: what this tab is for.
  final String title;

  /// Why an account is needed for it, in one line.
  final String body;

  /// The gate this wall answers to, so the form opens on the right side.
  final UserRole role;

  /// Optional: a smaller line under the button (e.g. what is free).
  final String? note;

  /// Optional override for the primary action, for the rare wall whose real
  /// answer is a different screen (a client's empty inbox points at the
  /// contractor directory).
  final VoidCallback? onBrowse;

  const SignInWall({
    super.key,
    required this.title,
    required this.body,
    this.role = UserRole.customer,
    this.note,
    this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.s20),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const IconBubble(
                icon: Icons.lock_outline_rounded,
                tint: AppTheme.navy,
                wash: AppTheme.accentWash,
              ),
              const SizedBox(height: AppTheme.s12),
              Text(title, style: AppTheme.h2, textAlign: TextAlign.center),
              const SizedBox(height: AppTheme.s8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTheme.body
                    .copyWith(color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppTheme.s16),
              BigButton(
                key: const Key('signin-wall-primary'),
                label: S.createAccount,
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AuthScreen(mode: AuthMode.signUp, role: role),
                )),
              ),
              const SizedBox(height: AppTheme.s8),
              TextButton(
                key: const Key('signin-wall-signin'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppTheme.tapMin),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AuthScreen(mode: AuthMode.signIn, role: role),
                )),
                child: Text(S.loginTitle),
              ),
              if (onBrowse != null) ...[
                const SizedBox(height: AppTheme.s4),
                TextButton(
                  key: const Key('signin-wall-browse'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppTheme.tapMin),
                  ),
                  onPressed: onBrowse,
                  child: const Text('تابع التصفّح بدون حساب'),
                ),
              ],
              if (note != null) ...[
                const SizedBox(height: AppTheme.s8),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
