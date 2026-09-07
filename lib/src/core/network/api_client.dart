import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

/// Thin typed client for the Allo Mokawil API.
///
/// The backend is the same Cloudflare Workers API used by the web app.
/// On mobile, auth uses a bearer token (issued by the auth endpoint)
/// instead of the web's HttpOnly cookie. Base URL is injected via
/// --dart-define=API_BASE_URL to keep secrets out of the repo.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _http;
  final String baseUrl;

  String? _token;

  set token(String? value) => _token = value;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// GET helper, throws [ApiException] on non-2xx.
  Future<dynamic> get(String path) async {
    final res = await _http.get(Uri.parse('$baseUrl$path'),
        headers: _headers);
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _http.post(Uri.parse('$baseUrl$path'),
        headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _http.put(Uri.parse('$baseUrl$path'),
        headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await _http.delete(Uri.parse('$baseUrl$path'),
        headers: _headers);
    return _decode(res);
  }

  /// Multipart upload for project photos / verification documents /
  /// avatar images — mirrors `api/upload`.
  Future<String> uploadPhoto(File file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final body = _decode(res);
    if (body is Map && body['url'] is String) return body['url'] as String;
    throw ApiException('فشل رفع الصورة');
  }

  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? null : _tryJson(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    final message = body is Map
        ? (body['error']?.toString() ?? 'حدث خطأ غير متوقع')
        : 'حدث خطأ (${res.statusCode})';
    throw ApiException(message, statusCode: res.statusCode);
  }

  dynamic _tryJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}