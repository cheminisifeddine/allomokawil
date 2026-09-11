import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

/// Thin typed client for the Allo Mokawil API.
///
/// The backend is the same Cloudflare Workers API used by the web app.
/// On mobile, auth uses a bearer token (issued by the auth endpoint)
/// instead of the web's HttpOnly cookie. Base hosts are injected via
/// --dart-define=API_BASE_URL / API_FALLBACK_URL to keep secrets out of the repo.
///
/// Every request is attempted against the primary host and, on a network-level
/// failure (DNS, timeout, TLS), retried against the fallback host. The host
/// that answers is remembered for the rest of the session. This is what makes
/// the app survive a single provider's DNS being unreachable on some Algerian
/// networks, and it converts raw SocketExceptions into a friendly Arabic
/// message instead of a stack trace on screen.
class ApiClient {
  ApiClient({http.Client? httpClient, List<String>? baseUrls})
      : _http = httpClient ?? http.Client(),
        _baseUrls = List<String>.from(baseUrls ?? AppConfig.apiBaseUrls);

  final http.Client _http;
  final List<String> _baseUrls;

  /// Index of the host that last answered (starts on the primary).
  int _active = 0;

  static const Duration _timeout = Duration(seconds: 20);

  String? _token;

  set token(String? value) => _token = value;

  /// Host currently believed to be healthy.
  String get baseUrl => _baseUrls.isEmpty ? '' : _baseUrls[_active];

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Runs [send] against each configured host until one answers, remembering
  /// the winner. Throws a friendly [ApiException] when all hosts fail.
  Future<http.Response> _withFailover(
    String path,
    Future<http.Response> Function(Uri uri) send,
  ) async {
    if (_baseUrls.isEmpty) {
      throw ApiException('لم يتم ضبط عنوان الخادم');
    }
    Object? lastError;
    for (var i = 0; i < _baseUrls.length; i++) {
      final index = (_active + i) % _baseUrls.length;
      final host = _baseUrls[index];
      try {
        final res = await send(Uri.parse('$host$path')).timeout(_timeout);
        _active = index;
        return res;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    throw ApiException(
      'تعذّر الاتصال بالخادم. تأكّد من اتصالك بالإنترنت ثم أعد المحاولة.',
      cause: lastError,
    );
  }

  /// GET helper, throws [ApiException] on non-2xx.
  Future<dynamic> get(String path) async {
    final res =
        await _withFailover(path, (uri) => _http.get(uri, headers: _headers));
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _withFailover(
        path,
        (uri) => _http.post(uri,
            headers: _headers, body: jsonEncode(body ?? {})));
    return _decode(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    final res = await _withFailover(
        path,
        (uri) => _http.put(uri,
            headers: _headers, body: jsonEncode(body ?? {})));
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await _withFailover(
        path, (uri) => _http.delete(uri, headers: _headers));
    return _decode(res);
  }

  /// Multipart upload for project photos / verification documents /
  /// avatar images — mirrors `api/upload`.
  Future<String> uploadPhoto(File file) async {
    final res = await _withFailover('/api/upload', (uri) async {
      final req = http.MultipartRequest('POST', uri);
      if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
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

  /// Original network error, kept for logging only — never shown to the user.
  final Object? cause;

  ApiException(this.message, {this.statusCode, this.cause});

  @override
  String toString() => message;
}
