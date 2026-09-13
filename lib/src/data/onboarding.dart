// The memory of the one question the landing page cannot answer for a visitor:
// which side of the app is he on.
//
// The explainer itself lives in `widgets/role_guide.dart`. This file owns the
// rule for when it is shown, so the rule can be tested without a widget.
import 'package:shared_preferences/shared_preferences.dart';

/// Set once the visitor has answered — or skipped — the role explainer.
const String roleGuideSeenKey = 'onboarding.role_guide_seen';

/// A store that holds anything other than exactly `true` has not been through
/// the explainer: a corrupt or migrated value must ask the question again rather
/// than silently skip it. Same defence as the session restore in
/// `core/security/auth_state.dart` — read the untyped value, narrow it here.
bool roleGuideSeenFrom(Object? stored) => stored == true;

/// Reads the flag. A store that cannot be reached answers "not seen", which
/// shows the explainer once more instead of hiding it forever.
Future<bool> roleGuideSeen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return roleGuideSeenFrom(prefs.get(roleGuideSeenKey));
  } catch (_) {
    return false;
  }
}

/// Records the answer. Failing to write it is not worth an error screen: the
/// worst case is that the explainer is offered one more time.
Future<void> markRoleGuideSeen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(roleGuideSeenKey, true);
  } catch (_) {
    // Deliberately silent — see above.
  }
}
