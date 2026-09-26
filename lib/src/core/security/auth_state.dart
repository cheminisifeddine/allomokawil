import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/chat_outbox.dart';
import '../../models/enums.dart';
import '../../models/user.dart';
import '../l10n/strings.dart';
import '../network/api_client.dart';

/// Holds the signed-in user and role, gates which home screen is shown,
/// and persists the session token locally.
class AuthState extends ChangeNotifier {
  /// [outbox] is injectable so a test can hold the queue in memory. It defaults
  /// to the real device-local queue rather than to nothing: the invariant below
  /// is the whole point of this change, and an opt-in one could be forgotten at
  /// a construction site and silently reinstate the leak. Construction costs
  /// nothing — the store is opened on first use, inside a `try`.
  AuthState(this._api, {ChatOutbox? outbox}) : _outbox = outbox ?? ChatOutbox() {
    // The session owner is the only object that can act on a rejected token, so
    // the hook is installed here rather than at each construction site: production
    // and tests both get the recovery path without remembering to wire it.
    _api.onUnauthorized = handleUnauthorized;
  }

  final ApiClient _api;

  /// The phone's queue of chat messages the server has not stored yet.
  ///
  /// Held here so that *every* way out of a session takes the queue with it.
  /// The outbox holds unsent words addressed to one account: a client telling a
  /// contractor where to come. It is device storage, not account storage, so
  /// the person who signs in next on this phone would otherwise inherit it and
  /// the thread would auto-send those words under *their* token, with *their*
  /// name on them. See [logout].
  final ChatOutbox _outbox;

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

  /// Drops the session: token, user and guest choice off the device.
  ///
  /// The chat outbox goes with them, **here** and not in the screen that
  /// happens to call this. `logout()` has two callers, and only one of them
  /// remembered to clear the queue:
  ///
  ///   * the profile screen, which taps «تسجيل الخروج» — it did clear it, in
  ///     the screen, before calling;
  ///   * [handleUnauthorized], when the server answers 401 and the stored
  ///     session is dead. This is not the rare path. It is what happens when a
  ///     token simply goes stale, which is the failure the founder already
  ///     reported from a real phone, and it never touched the queue at all.
  ///
  /// So the one way a session dies most often left the previous account's
  /// unsent words sitting on the device. They are addressed to *that* account's
  /// counterpart — a client telling a contractor where to come — and the next
  /// person to sign in on the phone inherited them: the inbox showed a badge
  /// for a thread they had never opened, and opening it auto-sent the first
  /// user's message under the second user's token, from the second user's
  /// account, to the first user's contractor.
  ///
  /// Nothing is lost that the user can still act on: [PendingMessage] only
  /// ever holds what the server had *refused*, and the session that could have
  /// re-sent it no longer exists. Anything the server may already hold was
  /// settled against the last successful read.
  Future<void> logout() async {
    _api.token = null;
    _user = null;
    _guestRole = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_guestKey);
    // After the keys, not before: a store that will not open must not stop the
    // session from being dropped, and the session is the part the user sees.
    await _clearOutbox();
    notifyListeners();
  }

  /// Empties the device queue. Never throws and never blocks the sign-out: a
  /// queue that cannot be cleared is a privacy problem to report, not a reason
  /// to leave a dead session on screen.
  Future<void> _clearOutbox() async {
    try {
      await _outbox.clear();
    } catch (error) {
      debugPrint('auth: could not clear the chat queue on sign-out ($error)');
    }
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
