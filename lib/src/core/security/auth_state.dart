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
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userRaw = prefs.getString(_userKey);
    if (token != null && userRaw != null) {
      try {
        _api.token = token;
        _user = User.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
      } catch (_) {
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      }
    }
    _restored = true;
    notifyListeners();
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