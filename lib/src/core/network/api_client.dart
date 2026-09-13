import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/app_config.dart';
import '../l10n/error_copy.dart';
import '../l10n/strings.dart';

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
      throw ApiException(S.errNoServer);
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
    throw ApiException(S.errOffline, cause: lastError);
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

  Future<dynamic> patch(String path, {Object? body}) async {
    final res = await _withFailover(
        path,
        (uri) => _http.patch(uri,
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
      req.files.add(await http.MultipartFile.fromPath('file', file.path,
          contentType: photoMediaType(file.path)));
      final streamed = await req.send();
      return http.Response.fromStream(streamed);
    });
    final body = _decode(res);
    if (body is Map && body['url'] is String) return body['url'] as String;
    throw ApiException(S.errUpload);
  }

  /// Decodes a response, turning any non-2xx into an [ApiException] whose
  /// message is Arabic copy that carries a next action.
  ///
  /// The status code is kept on the exception for callers that branch on it and
  /// is never rendered: `apiErrorCopy` picks the sentence, and it refuses
  /// non-Arabic server text so an English `Method not allowed` cannot reach the
  /// screen.
  dynamic _decode(http.Response res) {
    final body = res.body.isEmpty ? null : _tryJson(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw ApiException(
      apiErrorCopy(res.statusCode, body),
      statusCode: res.statusCode,
    );
  }

  dynamic _tryJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}

class ApiException implements Exception, ArabicCopyError, StatusCopyError {
  @override
  final String message;
  @override
  final int? statusCode;

  /// Original network error, kept for logging only — never shown to the user.
  final Object? cause;

  ApiException(this.message, {this.statusCode, this.cause});

  @override
  String toString() => message;
}

/// The media type of a photo, read off its file extension.
///
/// `MultipartFile.fromPath` labels a part `application/octet-stream` whenever
/// it is not told otherwise, and the Worker stores the declared type on the R2
/// object. So before this helper every photo the app uploaded — chat images,
/// portfolio shots, the avatar and the verification documents — was kept as an
/// unnamed binary: `GET /api/images/...` answered `application/octet-stream`
/// for a PNG, which makes a browser download the URL instead of showing it and
/// leaves anything downstream (the web app, a link preview, an image cache)
/// unable to tell a photo from a document. Same class of bug as the upload
/// route that used to answer 401 for every photo: the bytes were fine, the
/// label was not.
///
/// Measured on the deployed Worker: the identical 64x64 PNG came back
/// `application/octet-stream` before this change and `image/png` after it.
http.MediaType photoMediaType(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return http.MediaType('image', 'jpeg');
    case 'png':
      return http.MediaType('image', 'png');
    case 'webp':
      return http.MediaType('image', 'webp');
    case 'gif':
      return http.MediaType('image', 'gif');
    case 'heic':
    case 'heif':
      return http.MediaType('image', 'heic');
    default:
      // No extension, or one we do not know: say the honest thing rather than
      // declare a type the object may not be.
      return http.MediaType('application', 'octet-stream');
  }
}
