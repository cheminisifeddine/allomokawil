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
  ApiClient({http.Client? httpClient, List<String>? baseUrls, Duration? timeout})
      : _http = httpClient ?? http.Client(),
        _baseUrls = List<String>.from(baseUrls ?? AppConfig.apiBaseUrls),
        _timeout = timeout ?? defaultTimeout;

  final http.Client _http;
  final List<String> _baseUrls;

  /// Index of the host that last answered (starts on the primary).
  int _active = 0;

  /// How long one host gets before its attempt counts as failed.
  ///
  /// Injectable so the write-safety rule below is testable without a test that
  /// waits twenty real seconds for the timer to fire.
  static const Duration defaultTimeout = Duration(seconds: 20);
  final Duration _timeout;

  /// The bearer token every request carries, once a session exists.
  String? token;

  /// Fired when the server rejects the bearer token we just sent.
  ///
  /// A 401 is not an ordinary API failure: the session behind the stored token
  /// is gone — the account was removed, the session was dropped server-side, or
  /// another release invalidated it. Without this hook the app kept its stored
  /// user, so every screen rendered its own "could not load" line and the user
  /// sat on a signed-in home that could never load anything again, with no path
  /// back to the login form. The handler drops the dead session and returns to
  /// the landing page.
  void Function()? onUnauthorized;

  /// Host currently believed to be healthy.
  String get baseUrl => _baseUrls.isEmpty ? '' : _baseUrls[_active];

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Runs [send] against each configured host until one answers, remembering
  /// the winner. Throws a friendly [ApiException] when all hosts fail.
  ///
  /// [idempotent] decides whether a *write* may try the second host. Both hosts
  /// answer from the same Worker, so re-sending a request that already reached
  /// it duplicates the row: one tap on «انشر مشروعك» whose answer never came
  /// back inside [_timeout] would create the project twice, and its owner would
  /// find two copies of it in «مشاريعي». The rule is therefore the conservative
  /// one — a write moves to the other host only when the failure proves the
  /// request never left the phone (see [_neverReached]), and otherwise the user
  /// is told the outcome is unknown instead of being handed a guess.
  Future<http.Response> _withFailover(
    String path,
    Future<http.Response> Function(Uri uri) send, {
    bool idempotent = false,
  }) async {
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
      if (!idempotent && !_neverReached(lastError)) {
        throw ApiException(S.errWriteUnconfirmed, cause: lastError);
      }
    }
    throw ApiException(S.errOffline, cause: lastError);
  }

  /// True when a failure proves the request never reached the server, so
  /// re-sending it to the other host cannot duplicate anything.
  ///
  /// Two shapes qualify: a TLS handshake that never completed, and a host that
  /// did not answer at the transport layer at all — no name resolved, the port
  /// refused, or the network had no route. Everything else is ambiguous by
  /// construction: a response that never arrived inside [_timeout], or a
  /// connection dropped mid-flight, leaves the write *possibly delivered*, and
  /// that is exactly the case that must not be retried.
  ///
  /// The messages are matched, not only the exception types, because
  /// `package:http` wraps a `SocketException` in a `ClientException` that
  /// *implements* `SocketException` (`io_client.dart`, http 1.6.0) — the text
  /// survives the wrap, and it is the only thing that separates "could not
  /// resolve" from "server went quiet".
  bool _neverReached(Object? error) {
    if (error is HandshakeException) return true;
    final text = switch (error) {
      SocketException e => e.message,
      http.ClientException e => e.message,
      _ => '',
    }.toLowerCase();
    const nothingSent = <String>[
      'failed host lookup',
      'name or service not known',
      'nodename nor servname',
      'no address associated',
      'connection refused',
      'network is unreachable',
      'host is unreachable',
      'no route to host',
    ];
    return nothingSent.any(text.contains);
  }

  /// GET helper, throws [ApiException] on non-2xx.
  Future<dynamic> get(String path) async {
    final res = await _withFailover(
        path, (uri) => _http.get(uri, headers: _headers),
        idempotent: true);
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _withFailover(
        path,
        (uri) => _http.post(uri,
            headers: _headers, body: jsonEncode(body ?? {})),
        // Never re-sent: every POST in this API creates something — a project,
        // a quote, a message, a review, a subscription.
        idempotent: false);
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
            headers: _headers, body: jsonEncode(body ?? {})),
        // A PATCH here writes a fixed set of fields to one row, so a re-send
        // lands the same values: it cannot create a second row.
        idempotent: true);
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await _withFailover(path,
        (uri) => _http.delete(uri, headers: _headers),
        // HTTP-idempotent: a repeat leaves the same state behind.
        idempotent: true);
    return _decode(res);
  }

  /// Multipart upload for project photos / verification documents /
  /// avatar images — mirrors `api/upload`.
  Future<String> uploadPhoto(File file) async {
    final res = await _withFailover('/api/upload', (uri) async {
      final req = http.MultipartRequest('POST', uri);
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
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
      // A 2xx whose body is not JSON is never one of our payloads. It is a
      // captive portal, an ISP notice or a Cloudflare interstitial — an HTML
      // page the Worker never wrote. Returning that string used to make every
      // caller's cast blow up with a `TypeError`, an `Error` that no
      // `on Exception` clause in the screens can see, so the user tapped the
      // button and watched nothing happen with no sentence explaining why.
      if (body is String && body.isNotEmpty) {
        throw ApiException(
          S.errUnexpected,
          statusCode: res.statusCode,
          // Logging only, and bounded: a portal page can be kilobytes.
          cause: body.length > 200 ? body.substring(0, 200) : body,
        );
      }
      return body;
    }
    // A 401 while we were holding a token means the session is dead, not that
    // this one request failed. Tell the owner of that token before the screen
    // gets a chance to render a message the user cannot act on.
    if (res.statusCode == 401 && token != null) {
      onUnauthorized?.call();
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
