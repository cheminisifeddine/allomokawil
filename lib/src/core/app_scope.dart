import 'package:flutter/widgets.dart';

import '../data/notification_count_trust.dart';
import '../data/unread_message_trust.dart';
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
    NotificationCountTrust? trust,
    UnreadMessageTrust? messages,
    required super.child,
  })  : place = place ?? PlaceState.detached(),
        trust = trust ?? NotificationCountTrust(),
        messages = messages ?? UnreadMessageTrust();

  final ApiClient api;
  final AuthState auth;

  /// Where the phone is, or a store that answers "unknown" forever.
  final PlaceState place;

  /// Whether the unread count the header pip paints is still a server answer.
  ///
  /// **This is the piece that was missing, and its absence is why a finished
  /// feature was invisible on the phone.** The flag existed, the pip read it,
  /// the centre withdrew it — and nothing ever *constructed* it, because it
  /// was a constructor parameter that no caller passed. `trust: null` made
  /// every withdrawal a no-op on a null receiver and left `_pip()`'s
  /// `?? false` painting the alarm red for ever, on the exact path the flag
  /// was written for.
  ///
  /// It lives here and not in the bell, because the two screens that share
  /// the number sit on **opposite sides of a navigation push**. A flag owned
  /// by the header is destroyed by the pop, so the centre could never
  /// withdraw anything the header would still be able to see. It has to
  /// outlive the route, and the scope already sits above the navigator for
  /// exactly this kind of reason.
  ///
  /// **Never null, and that is the point.** The bell and the centre keep
  /// taking a nullable flag so a screen pumped on its own — a widget test, a
  /// design shot — still builds, but in the app both sides now read one object
  /// without either having to pass it along. A test that wants to watch the
  /// withdrawal reads it back out of this scope instead of constructing its
  /// own, which is precisely the mistake that let the gap through: a test
  /// holding its own flag proves that flag works, and says nothing about
  /// whether the app is connected to it.
  final NotificationCountTrust trust;

  /// Whether the unread count the «الرسائل» tab paints is still a server
  /// answer.
  ///
  /// **A second flag, and never [trust].** The two pips are drawn from two
  /// different tables — [trust] is the notifications row count over
  /// `/api/unread`, this is the sum of per-thread `unread_count` over
  /// `/api/mobile/conversations` — and the reason they cannot share a flag is
  /// the same reason the badge exists at all. See
  /// `unread_message_count.dart`.
  ///
  /// It lives here for the reason [trust] does: a flag owned by the header is
  /// destroyed by the pop, and the tab bar has to outlive the route that
  /// withdrew it.
  ///
  /// **Never null**, for the same reason: a screen pumped on its own still
  /// builds, and a test reads the flag back out of this scope rather than
  /// constructing its own — a test holding its own flag proves that flag
  /// works and says nothing about whether the app is connected to it.
  final UnreadMessageTrust messages;

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
      api != old.api ||
      auth != old.auth ||
      place != old.place ||
      trust != old.trust;
}