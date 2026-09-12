import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/enums.dart';
import '../../models/user.dart';
import '../network/api_client.dart';

/// Holds the signed-in user and role, gates which home screen is shown,
/// and persists the session token locally.
class AuthState extends ChangeNotifier {
  AuthState(this._api);

  final ApiClient _api;

  static const _tokenKey = 'auth.token';
  static const _userKey = 'auth.user';

  User? _user;
  bool _restored = false;

  User? get user => _user;
  UserRole get role => _user?.type ?? UserRole.customer;
  bool get isAuthenticated => _user != null;
  bool get isRestored => _restored;

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
    final res = await _api.post('/api/login', body: {
      'phone': phone,
      'password': password,
      'remember_me': rememberMe,
    }) as Map<String, dynamic>;
    final token = res['token'] as String;
    final user = User.fromJson(res['user'] as Map<String, dynamic>);
    await _persist(token, user);
  }

  Future<void> register({
    required String phone,
    required String email,
    required String fullName,
    required String password,
    required UserRole role,
  }) async {
    final res = await _api.post('/api/register', body: {
      'phone': phone,
      'email': email,
      'full_name': fullName,
      'password': password,
      'type': role.wire,
    }) as Map<String, dynamic>;
    final token = res['token'] as String;
    final user = User.fromJson(res['user'] as Map<String, dynamic>);
    await _persist(token, user);
  }

  Future<void> _persist(String token, User user) async {
    _api.token = token;
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    _api.token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    notifyListeners();
  }
}