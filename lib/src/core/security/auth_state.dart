import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/enums.dart';
import '../../models/user.dart';
import '../l10n/strings.dart';
import '../network/api_client.dart';

/// Holds the signed-in user and role, gates which home screen is shown,
/// and persists the session token locally.
class AuthState extends ChangeNotifier {
  AuthState(this._api) {
    // The session owner is the only object that can act on a rejected token, so
    // the hook is installed here rather than at each construction site: production
    // and tests both get the recovery path without remembering to wire it.
    _api.onUnauthorized = handleUnauthorized;
  }

  final ApiClient _api;

  static const _tokenKey = 'auth.token';
  static const _userKey = 'auth.user';
  static const _guestKey = 'auth.guestRole';

  User? _user;
  bool _restored = false;
  bool _sessionExpired = false;
  UserRole? _guestRole;

  User? get user => _user;
  UserRole get role => _user?.type ?? UserRole.customer;
  bool get isAuthenticated => _user != null;
  bool get isRestored => _restored;

  /// The role a visitor picked on the first page when they chose to look around
  /// before signing up — مقاول or صاحب مشروع.
  ///
  /// The founder's brief, verbatim: «make sure the users can use and browse
  /// offer and jobs without sign in, just ask in the first page for if this is
  /// مقاول او صاحب عمل and show the related dashboard». It lives next to the
  /// session because it decides which dashboard the root gate opens.
  UserRole? get guestRole => _guestRole;

  /// True while the app is being used without an account.
  bool get isGuest => _user == null && _guestRole != null;

  /// True when the last thing that happened was the server refusing our token.
  ///
  /// The landing page reads this to explain *why* the user is suddenly signed
  /// out, instead of showing a form with no reason attached to it.
  bool get sessionExpired => _sessionExpired;

  /// The API answered 401 for a request that carried our bearer token.
  ///
  /// The session it belonged to no longer exists on the server, so nothing this
  /// device can send will work again: keeping the stored user would leave the
  /// app on a home screen whose every list is empty and whose every button
  /// fails. Drop the session and put the user back in front of the login form.
  ///
  /// Safe to call repeatedly — several in-flight requests can each answer 401
  /// for the same dead token, and each one lands here.
  Future<void> handleUnauthorized() async {
    if (_user == null && _api.token == null) {
      // Already signed out: a 401 on a request that carried no token (a wrong
      // password on the login form, say) is not an expired session.
      return;
    }
    _sessionExpired = true;
    await logout();
  }

  /// Called by the landing page once the notice has been shown and dismissed.
  void clearSessionExpiredNotice() {
    if (!_sessionExpired) return;
    _sessionExpired = false;
    notifyListeners();
  }

  /// Load a previously stored session at app start.
  ///
  /// This is awaited *before* `runApp`, so it must never throw: an exception
  /// that escapes leaves the process launched with no first frame — a blank
  /// white page on every start, no error, no retry, no way back.
  ///
  /// The keys are therefore read through [SharedPreferences.get] and narrowed
  /// by hand instead of using `getString`. The typed getters are hard casts
  /// (`_preferenceCache[key] as String?`), so a single value of the wrong type
  /// under `auth.user` — a corrupted or migrated preferences file — used to
  /// throw a `_TypeError` out of `main()`. Anything that is not two strings
  /// forming a parseable user is not a session: the keys are dropped and the
  /// app opens on the logged-out landing page.
  Future<void> restore() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final tokenRaw = prefs.get(_tokenKey);
      final userRaw = prefs.get(_userKey);
      if (tokenRaw is String && userRaw is String) {
        // Decode before touching state: assigning the token first would leave
        // a credential attached to a session with nobody in it.
        final user = User.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
        _api.token = tokenRaw;
        _user = user;
      } else if (tokenRaw != null || userRaw != null) {
        // Wrong type, or only half of the pair.
        await _discardSession(prefs);
      } else {
        // No session, but this device already answered the first page's
        // question: reopen that dashboard signed out instead of asking again.
        _guestRole = _roleFromName(prefs.get(_guestKey));
      }
    } catch (error) {
      // Unreadable JSON, a value we cannot cast, or a store that will not open.
      // Start logged out instead of not starting at all.
      _api.token = null;
      _user = null;
      if (prefs != null) {
        await _discardSession(prefs);
      }
      debugPrint('restore: stored session discarded ($error)');
    } finally {
      _restored = true;
      notifyListeners();
    }
  }

  /// Remove both session keys, so the next launch starts from a known state.
  ///
  /// Never rethrows: a preferences store that refuses the write is still not a
  /// reason to fail the launch.
  Future<void> _discardSession(SharedPreferences prefs) async {
    try {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    } catch (error) {
      debugPrint('restore: could not clear the stored session ($error)');
    }
  }

  Future<void> login({
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    final session = _session(await _api.post('/api/login', body: {
      'phone': phone,
      'password': password,
      'remember_me': rememberMe,
    }));
    await _persist(session.token, session.user);
  }

  Future<void> register({
    required String phone,
    required String email,
    required String fullName,
    required String password,
    required UserRole role,
  }) async {
    final session = _session(await _api.post('/api/register', body: {
      'phone': phone,
      'email': email,
      'full_name': fullName,
      'password': password,
      'type': role.wire,
    }));
    await _persist(session.token, session.user);
  }

  Future<void> _persist(String token, User user) async {
    _api.token = token;
    _user = user;
    // A real account answers the first page's question: the dashboard is now
    // the signed-in one, so the stored guest choice is dropped.
    _guestRole = null;
    // A fresh session answers the notice: whatever token failed before is gone.
    _sessionExpired = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    await prefs.remove(_guestKey);
    notifyListeners();
  }

  /// Opens the dashboard for [role] without an account.
  ///
  /// Browsing jobs and contractors must not require a login — that is the
  /// founder's call — so this stores the choice and lets the root gate show the
  /// matching dashboard. Anything that writes (posting a project, sending a
  /// quote, writing in the chat) still leads to the auth screen.
  Future<void> enterAsGuest(UserRole role) async {
    _guestRole = role;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestKey, role.name);
    } catch (error) {
      // A store that refuses the write still gets a usable guest session; the
      // choice is simply forgotten on the next launch.
      debugPrint('guest: could not persist the role ($error)');
    }
  }

  /// Returns to the first page from a guest dashboard.
  Future<void> leaveGuest() async {
    if (_guestRole == null) return;
    _guestRole = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestKey);
    } catch (error) {
      debugPrint('guest: could not clear the role ($error)');
    }
  }

  Future<void> logout() async {
    _api.token = null;
    _user = null;
    _guestRole = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_guestKey);
    notifyListeners();
  }
}

/// The stored guest role, or null when the value is not one we know.
///
/// Read by hand rather than with a cast: a preferences file written by another
/// version must not be able to throw out of `restore()`.
UserRole? _roleFromName(Object? raw) {
  if (raw is! String) return null;
  for (final role in UserRole.values) {
    if (role.name == raw) return role;
  }
  return null;
}

/// A signed-in session as the two things every caller needs: the bearer token
/// and the account it belongs to.
class _Session {
  const _Session(this.token, this.user);

  final String token;
  final User user;
}

/// The `{token, user}` pair a successful auth answer must carry.
///
/// Both fields used to be read with a hard cast (`res['token'] as String`,
/// `res['user'] as Map<String, dynamic>`), so a 200 whose body was an ack, a
/// portal page or a row with a missing column raised a `TypeError` — an
/// `Error`, invisible to the screens' `on Exception` clauses and to
/// `errorCopy` — and the button simply did nothing. Now the wrong shape is the
/// same Arabic, retryable sentence as every other API failure.
_Session _session(Object? body) {
  if (body is Map<String, dynamic>) {
    final token = body['token'];
    final user = body['user'];
    if (token is String && token.isNotEmpty && user is Map<String, dynamic>) {
      try {
        return _Session(token, User.fromJson(user));
      } catch (error) {
        throw ApiException(S.errUnexpected, cause: error);
      }
    }
  }
  throw ApiException(S.errUnexpected, cause: body);
}
