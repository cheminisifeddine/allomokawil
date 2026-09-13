/// The single place where a failure turns into Arabic copy a user can act on.
///
/// Before this file the app rendered `e.toString()` at twelve call sites and
/// `'حدث خطأ (${res.statusCode})'` in the HTTP layer. On a good day the thrown
/// object was an [ArabicCopyError] carrying Arabic; on a bad one the screen
/// showed `PlatformException(photo_access_denied, ...)`, a `SocketException`, a
/// bare `401`, or the Worker's own English `Method not allowed`. None of those
/// is a sentence, and none of them tells a contractor what to do next.
///
/// Invariants, enforced by `test/error_copy_test.dart`:
///  * the returned string always contains Arabic and never a Latin letter,
///  * it never contains an HTTP status code or a raw exception name,
///  * it always ends with an action the user can take right now.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'strings.dart';

/// A thrown object that already carries curated Arabic copy.
///
/// Declared here instead of importing `api_client.dart` so the network layer can
/// depend on this mapper without a circular import.
abstract interface class ArabicCopyError implements Exception {
  /// Arabic sentence safe to render as-is.
  String get message;
}

/// A failure that still knows the HTTP status it came from.
///
/// Needed because copy and status can disagree: a 402 whose JSON body arrived
/// empty (or as an HTML error page from a proxy) is not Arabic, so it cannot be
/// shown — but the status alone is enough to pick the right sentence, and
/// "raise your plan" is a far better answer than "unexpected error".
abstract interface class StatusCopyError implements Exception {
  int? get statusCode;
}

/// One Arabic letter, across the ranges Flutter can shape.
final RegExp _arabic = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');

/// True when [text] was written for an Arabic reader.
///
/// Used to decide whether text that came from outside the app may be shown: a
/// Worker path answering `Method not allowed`, an HTML error page from a proxy
/// or a stack trace are all indistinguishable from real copy except by the
/// script they are written in.
bool isArabicCopy(String text) => _arabic.hasMatch(text);

/// The exact sentence a screen may render for [error].
///
/// [fallback] replaces the generic sentence for a call site whose failure has a
/// specific remedy — an upload, for instance.
String errorCopy(Object? error, {String? fallback}) {
  final generic = fallback ?? S.errUnexpected;
  if (error == null) return generic;
  // Read the status once: a failure that carries one can still be answered
  // correctly even when its body held no usable copy — see [StatusCopyError].
  final status = error is StatusCopyError ? error.statusCode : null;
  if (error is ArabicCopyError) {
    // Curated by the network layer per status code, unless something upstream
    // replaced the body with non-Arabic text.
    if (isArabicCopy(error.message)) return error.message;
    // Nothing usable arrived in the body. If the failure still carries its
    // status, the status decides: a body-less 402 is a paywall, not a mystery.
    if (status != null) return apiErrorCopy(status, null);
    return generic;
  }
  if (error is String) return isArabicCopy(error) ? error : generic;
  // Order matters: TimeoutException is not an IOException, and
  // http.ClientException wraps the socket failures the http package raises
  // instead of letting them through.
  if (error is TimeoutException) return S.errTimeout;
  if (error is SocketException ||
      error is HandshakeException ||
      error is HttpException ||
      error is http.ClientException) {
    return S.errOffline;
  }
  if (error is PlatformException) return _platformCopy(error);
  return generic;
}

/// Platforms report a machine code, never a sentence.
String _platformCopy(PlatformException e) {
  final code = e.code.toLowerCase();
  if (code.contains('camera')) return S.errCameraPermission;
  if (code.contains('photo') ||
      code.contains('gallery') ||
      code.contains('image') ||
      code.contains('media') ||
      code.contains('storage')) {
    return S.errPhotoPermission;
  }
  return S.errPickFailed;
}

/// The sentence for a failed HTTP call, given its [status] and decoded [body].
///
/// The number itself is never shown — `401` means nothing to a user. The
/// server's own Arabic words win wherever they describe *this* user's input: the
/// form is on screen, so `رقم الهاتف أو كلمة المرور غير صحيحة` or
/// `رقم الهاتف مسجل مسبقاً` is the precise instruction, and replacing it with
/// our sentence would only make it vaguer. A server phrase that names the
/// problem without the remedy (`غير مصرح`, `بيانات غير صالحة`) is expanded — see
/// [_terseServerCopy].
///
/// Infrastructure statuses are the exception: a 5xx body is a noun like
/// `خلل في قاعدة البيانات` that no user can act on, so our sentence wins and he
/// is told to retry.
String apiErrorCopy(int status, Object? body) {
  final server = _serverMessage(body);
  final shown = server == null ? null : (_terseServerCopy[server] ?? server);
  if (apiErrorCopyPrefersServerText(status)) return shown ?? _curated(status);
  return _curated(status);
}

/// True when the server's own Arabic message beats the generic sentence.
///
/// Exposed so the test can pin the rule instead of re-deriving it.
bool apiErrorCopyPrefersServerText(int status) {
  switch (status) {
    case 400:
    case 401:
    // 402 is our paywall: the server's sentence names the plan and the quota
    // that was hit — strictly more precise than a generic "upgrade" line.
    case 402:
    case 403:
    case 409:
    case 422:
      return true;
  }
  return false;
}

String _curated(int status) {
  switch (status) {
    case 400:
    case 422:
      return S.errValidation;
    case 401:
      return S.errUnauthorized;
    case 403:
      return S.errForbidden;
    case 404:
      return S.errNotFound;
    case 408:
      return S.errTimeout;
    case 409:
      return S.errConflict;
    case 402:
      return S.errPlanLimit;
    case 413:
      return S.errTooLarge;
    case 429:
      return S.errTooMany;
  }
  if (status >= 500) return S.errServer;
  return S.errUnexpected;
}

/// Server copy that names the problem but not the next action, expanded here.
const Map<String, String> _terseServerCopy = {
  'غير مصرح': S.errUnauthorized,
  'ممنوع': S.errForbidden,
  'بيانات غير صالحة': S.errValidation,
  'بيانات خاطئة': S.errValidation,
  'إجراء غير معروف': S.errUnexpected,
  'إجراء غير صالح': S.errUnexpected,
};

/// The `error` field of a JSON error body, if it is Arabic.
String? _serverMessage(Object? body) {
  if (body is! Map) return null;
  final raw = body['error'];
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty || !isArabicCopy(text)) return null;
  return text;
}
