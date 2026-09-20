import 'package:flutter/widgets.dart';

import 'location/place_state.dart';
import 'network/api_client.dart';
import 'security/auth_state.dart';

/// Lightweight dependency scope. `AppScope.of(context)` gives access to the
/// shared [ApiClient] and [AuthState], kept above the navigation stack so
/// every screen and the role gate share one source of truth.
class AppScope extends InheritedWidget {
  /// Not `const` any more: [place] falls back to a storage-free store, which is
  /// how a screen pumped on its own (a widget test, a design shot) keeps the
  /// same API without touching the platform's preferences.
  AppScope({
    super.key,
    required this.api,
    required this.auth,
    PlaceState? place,
    required super.child,
  }) : place = place ?? PlaceState.detached();

  final ApiClient api;
  final AuthState auth;

  /// Where the phone is, or a store that answers "unknown" forever.
  final PlaceState place;

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
      api != old.api || auth != old.auth || place != old.place;
}