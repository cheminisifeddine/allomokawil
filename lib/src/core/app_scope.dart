import 'package:flutter/widgets.dart';

import 'network/api_client.dart';
import 'security/auth_state.dart';

/// Lightweight dependency scope. `AppScope.of(context)` gives access to the
/// shared [ApiClient] and [AuthState], kept above the navigation stack so
/// every screen and the role gate share one source of truth.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.auth,
    required super.child,
  });

  final ApiClient api;
  final AuthState auth;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!;
  }

  /// The scope when there is one, null otherwise.
  ///
  /// Widget tests pump single screens with no scope above them; a screen that
  /// must work both inside the app and alone (the landing page) asks this way
  /// instead of asserting.
  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  @override
  bool updateShouldNotify(AppScope old) =>
      api != old.api || auth != old.auth;
}