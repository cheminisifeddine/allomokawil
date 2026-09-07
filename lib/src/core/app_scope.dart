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

  @override
  bool updateShouldNotify(AppScope old) =>
      api != old.api || auth != old.auth;
}