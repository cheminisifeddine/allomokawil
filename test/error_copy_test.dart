// Proves the user never sees a raw exception, an HTTP status code or an English
// word — whatever the app throws.
//
// The audit that produced this file found twelve call sites rendering
// `e.toString()` and an HTTP layer rendering `'حدث خطأ (500)'`. Every assertion
// below fails if any of that comes back.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/error_copy.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';
import 'package:allomokawil/src/screens/verify/verification_screen.dart';

/// Every sentence a failure can put on screen.
const Map<String, String> _sentences = {
  'errOffline': S.errOffline,
  'errCheckConnection': S.errCheckConnection,
  'errTimeout': S.errTimeout,
  'errServer': S.errServer,
  'errUnauthorized': S.errUnauthorized,
  'errForbidden': S.errForbidden,
  'errNotFound': S.errNotFound,
  'errValidation': S.errValidation,
  'errConflict': S.errConflict,
  'errTooLarge': S.errTooLarge,
  'errTooMany': S.errTooMany,
  'errUnexpected': S.errUnexpected,
  'errNoServer': S.errNoServer,
  'errUpload': S.errUpload,
  'errPickFailed': S.errPickFailed,
  'errPhotoPermission': S.errPhotoPermission,
  'errCameraPermission': S.errCameraPermission,
};

/// The instruction half of every sentence. A message that only names the
/// problem is the bug this audit exists to kill.
const List<String> _instructions = [
  'أعد المحاولة',
  'ارجع',
  'سجّل',
  'افتح',
  'اختر',
  'تحقّق',
  'انتظر',
  'حدّث',
  'جرّب',
  'راجع',
];

final RegExp _latin = RegExp(r'[A-Za-z]');

void _expectUsableArabic(String copy) {
  expect(isArabicCopy(copy), isTrue, reason: 'not Arabic: $copy');
  expect(_latin.hasMatch(copy), isFalse, reason: 'Latin letters leaked: $copy');
  for (final banned in const ['Exception', 'Error', 'error', 'null', 'HTTP']) {
    expect(copy.contains(banned), isFalse, reason: '$banned leaked: $copy');
  }
  expect(_instructions.any(copy.contains), isTrue,
      reason: 'no next action in: $copy');
}

/// An object the mapper has never seen, shaped like a runtime failure.
class _RawFailure implements Exception {
  @override
  String toString() => 'Bad state: _RawFailure at package:app/main.dart:1:1';
}


/// Rasterises a screen at real phone size into /tmp/shots.
///
/// Same mechanism as design_shots_test.dart and empty_states_test.dart: the app
/// draws to a canvas on device and on web alike, so a PNG of the real widget
/// tree is the only honest look at the result. Cairo is registered first,
/// otherwise the Arabic renders as tofu and the shot proves nothing.
Future<GlobalKey> _pumpShot(
  WidgetTester tester,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: RepaintBoundary(key: key, child: screen),
    ),
  ));
  await tester.pumpAndSettle();
  return key;
}

/// Writes the current tree to /tmp/shots/<name>.png.
Future<String> _capture(
    WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

/// Pump then capture, for a state that needs no interaction first.
Future<String> _shoot(
  WidgetTester tester,
  String name,
  Widget screen,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 850),
}) async =>
    _capture(tester, await _pumpShot(tester, screen, api, auth, logical: logical),
        name);

/// Boots an ApiClient/AuthState pair over a client that always answers [res].
Future<(ApiClient, AuthState)> _boot(http.Response Function() res) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    httpClient: MockClient((_) async => res()),
    baseUrls: ['https://x.test'],
  );
  final auth = AuthState(api);
  await auth.restore();
  return (api, auth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the Arabic failure sentences', () {
    test('every one is Arabic-only and ends with an instruction', () {
      for (final entry in _sentences.entries) {
        _expectUsableArabic(entry.value);
        expect(entry.value.trim().endsWith('.') || entry.value.trim().endsWith('ة'),
            isTrue,
            reason: '${entry.key} is not a finished sentence: ${entry.value}');
      }
    });

    test('no two sentences say the same thing', () {
      // Duplicates are how one path quietly keeps an older, useless wording.
      expect(_sentences.values.toSet().length, _sentences.length);
    });
  });

  group('errorCopy', () {
    test('an English platform exception becomes Arabic permission copy', () {
      final denied = PlatformException(
        code: 'photo_access_denied',
        message: 'Photo access denied. Please grant permission.',
      );
      final copy = errorCopy(denied);
      _expectUsableArabic(copy);
      expect(copy, S.errPhotoPermission);

      final camera = PlatformException(
          code: 'camera_access_denied', message: 'camera_access_denied');
      expect(errorCopy(camera), S.errCameraPermission);
      _expectUsableArabic(errorCopy(camera));

      final other = PlatformException(code: 'unknown', message: 'boom');
      expect(errorCopy(other), S.errPickFailed);
      _expectUsableArabic(errorCopy(other));
    });

    test('a dead socket becomes the offline sentence, not a stack trace', () {
      final copy = errorCopy(SocketException('Failed host lookup: api.test'));
      expect(copy, S.errOffline);
      _expectUsableArabic(copy);

      expect(errorCopy(HandshakeException('certificate verify failed')),
          S.errOffline);
      expect(errorCopy(http.ClientException('Connection closed')), S.errOffline);
    });

    test('a timeout is its own sentence', () {
      expect(errorCopy(TimeoutException('no response in 20s')), S.errTimeout);
      _expectUsableArabic(errorCopy(TimeoutException('no response in 20s')));
    });

    test('an unmapped runtime failure falls back to the generic sentence', () {
      final copy = errorCopy(_RawFailure());
      expect(copy, S.errUnexpected);
      _expectUsableArabic(copy);
      expect(copy.contains('_RawFailure'), isFalse);
    });

    test('the site-specific fallback wins where the remedy differs', () {
      final copy = errorCopy(_RawFailure(), fallback: S.errUpload);
      expect(copy, S.errUpload);
      _expectUsableArabic(copy);
      // …but a raw English string still cannot ride along on a fallback.
      expect(errorCopy('Method not allowed', fallback: S.errUpload), S.errUpload);
    });

    test('null, an English string and an Arabic string are all handled', () {
      expect(errorCopy(null), S.errUnexpected);
      expect(errorCopy('Method not allowed'), S.errUnexpected);
      // Thrown Arabic copy (the API layer's own message) is kept verbatim.
      const arabic = 'رقم الهاتف أو كلمة المرور غير صحيحة';
      expect(errorCopy(arabic), arabic);
    });

    test('an ApiException whose body was not Arabic is replaced, not shown',
        () {
      final e = ApiException('Method not allowed', statusCode: 405);
      expect(errorCopy(e), S.errUnexpected);
      _expectUsableArabic(errorCopy(e));
    });
  });

  group('apiErrorCopy', () {
    test('an English server body never reaches the screen', () {
      final copy = apiErrorCopy(400, {'error': 'Method not allowed'});
      expect(copy, S.errValidation);
      _expectUsableArabic(copy);

      final html = apiErrorCopy(500, '<html>Internal Server Error</html>');
      expect(html, S.errServer);
      _expectUsableArabic(html);
    });

    test('the status number is never part of the sentence', () {
      for (final status in const [400, 401, 403, 404, 408, 409, 413, 422, 429,
        500, 502, 503, 504]) {
        final copy = apiErrorCopy(status, null);
        _expectUsableArabic(copy);
        expect(copy.contains('$status'), isFalse,
            reason: 'status $status leaked into: $copy');
        expect(RegExp(r'\d').hasMatch(copy), isFalse,
            reason: 'a bare number leaked into: $copy');
      }
    });

    test('the login endpoint keeps its own precise Arabic sentence', () {
      const wrong = 'رقم الهاتف أو كلمة المرور غير صحيحة';
      expect(apiErrorCopy(401, {'error': wrong}), wrong);
    });

    test('a bare denial is expanded into an instruction', () {
      expect(apiErrorCopy(401, {'error': 'غير مصرح'}), S.errUnauthorized);
      expect(apiErrorCopy(403, {'error': 'ممنوع'}), S.errForbidden);
      expect(apiErrorCopy(400, {'error': 'بيانات غير صالحة'}), S.errValidation);
    });

    test('infrastructure statuses get our sentence, not the server noun', () {
      expect(apiErrorCopy(404, {'error': 'العرض غير موجود'}), S.errNotFound);
      expect(apiErrorCopy(500, {'error': 'خلل في قاعدة البيانات'}), S.errServer);
      expect(apiErrorCopy(429, null), S.errTooMany);
      expect(apiErrorCopy(413, null), S.errTooLarge);
      expect(apiErrorCopy(409, null), S.errConflict);
    });
  });

  group('through the real HTTP layer', () {
    ApiClient apiReturning(http.Response res) => ApiClient(
          httpClient: MockClient((_) async => res),
          baseUrls: ['https://x.test'],
        );

    test('a 500 with an English HTML body surfaces as Arabic copy', () async {
      final api = apiReturning(http.Response(
          '<html><body>Internal Server Error</body></html>', 500,
          headers: {'content-type': 'text/html'}));

      Object? thrown;
      try {
        await api.get('/api/mobile/projects');
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<ApiException>());
      final copy = errorCopy(thrown);
      _expectUsableArabic(copy);
      expect(copy.contains('500'), isFalse);
      expect(copy.contains('html'), isFalse);
    });

    test('a Worker answering in English is not shown verbatim', () async {
      final api = apiReturning(http.Response(
          jsonEncode({'error': 'Method not allowed'}), 405,
          headers: {'content-type': 'application/json'}));

      Object? thrown;
      try {
        await api.post('/api/login', body: const {});
      } catch (e) {
        thrown = e;
      }
      final copy = errorCopy(thrown);
      _expectUsableArabic(copy);
      expect(copy.contains('Method'), isFalse);
    });

    test('an Arabic server message is preserved', () async {
      final api = apiReturning(http.Response(
          jsonEncode({'error': 'رقم الهاتف مسجل مسبقاً'}), 409,
          headers: {'content-type': 'application/json'}));

      Object? thrown;
      try {
        await api.post('/api/register', body: const {});
      } catch (e) {
        thrown = e;
      }
      expect(errorCopy(thrown), 'رقم الهاتف مسجل مسبقاً');
    });

    test('a dead host yields the offline sentence', () async {
      final api = ApiClient(
        httpClient: MockClient((_) async {
          throw SocketException('Failed host lookup: x.test');
        }),
        baseUrls: ['https://x.test'],
      );

      Object? thrown;
      try {
        await api.get('/api/mobile/projects');
      } catch (e) {
        thrown = e;
      }
      expect(errorCopy(thrown), S.errOffline);
      _expectUsableArabic(errorCopy(thrown));
    });
  });

  group('on screen', () {
    Future<void> pumpSignIn(WidgetTester tester, MockClient client) async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
      final auth = AuthState(api);
      await auth.restore();
      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        child: const MaterialApp(home: AuthScreen(mode: AuthMode.signIn)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> submitSignIn(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, '0550000000');
      await tester.enterText(find.byKey(const Key('auth-password')), 'secret123');
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
    }

    testWidgets('a platform exception shows Arabic, never its own message',
        (tester) async {
      await pumpSignIn(tester, MockClient((_) async {
        throw PlatformException(
          code: 'photo_access_denied',
          message: 'Photo access denied. Please grant permission.',
        );
      }));

      await submitSignIn(tester);

      // The exact sentence, rendered.
      expect(find.text(S.errPhotoPermission), findsOneWidget);
      // And nothing exception-shaped anywhere on the screen.
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data;
        if (data == null) continue;
        expect(data.contains('PlatformException'), isFalse);
        expect(data.contains('photo_access_denied'), isFalse);
      }
    });

    testWidgets('a dead network shows the offline sentence with an action',
        (tester) async {
      await pumpSignIn(tester, MockClient((_) async {
        throw SocketException('Failed host lookup: x.test');
      }));

      await submitSignIn(tester);

      expect(find.text(S.errOffline), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data;
        if (data == null) continue;
        expect(data.contains('SocketException'), isFalse);
        expect(data.contains('Failed host lookup'), isFalse);
      }
    });

    testWidgets('a server answer in English is replaced with Arabic copy',
        (tester) async {
      await pumpSignIn(tester, MockClient((_) async => http.Response(
            jsonEncode({'error': 'Method not allowed'}), 405,
            headers: {'content-type': 'application/json'},
          )));

      await submitSignIn(tester);

      expect(find.text(S.errUnexpected), findsOneWidget);
      expect(find.textContaining('Method not allowed'), findsNothing);
    });
  });

  // ── Proof: the copy above, drawn by the real screens ─────────────────────
  group('rendered', () {
    setUpAll(() async {
      final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      await (FontLoader('Cairo')
            ..addFont(Future.value(reg))
            ..addFont(Future.value(bold)))
          .load();
    });

    testWidgets('every failure screen rasterises with the Arabic copy in it',
        (tester) async {
      final shots = <String>[];

      // 1. The sign-in notice, after a dead network.
      // The notice only exists after a submit, so the capture happens on the
      // live tree rather than on a freshly pumped form.
      final down = await _boot(() => http.Response('', 503));
      final authKey = await _pumpShot(
          tester, const AuthScreen(mode: AuthMode.signIn), down.$1, down.$2);
      await tester.enterText(find.byType(TextField).first, '0550000000');
      await tester
          .enterText(find.byKey(const Key('auth-password')), 'secret123');
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text(S.errServer), findsOneWidget);
      shots.add(await _capture(tester, authKey, 'err_auth_notice'));

      // 2. The project detail error state (was a bare centred sentence).
      //
      //    Only the project call fails here. The screen also starts its quotes
      //    request in initState and never observes it until a project renders —
      //    failing both would raise an unhandled async error instead of showing
      //    the state under test. (That unobserved sibling future is logged as a
      //    gap for the Phase 4 "every API call wrapped" item, not fixed here.)
      SharedPreferences.setMockInitialValues({});
      final routing = ApiClient(
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/quotes')) {
            return http.Response('[]', 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('boom', 500);
        }),
        baseUrls: ['https://x.test'],
      );
      final routingAuth = AuthState(routing);
      await routingAuth.restore();

      await tester.pumpWidget(AppScope(
        api: routing,
        auth: routingAuth,
        child: MaterialApp(
          home: ProjectDetailScreen(
              projectId: 'p1', repo: Repository(routing)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.errServer), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      shots.add(await _shoot(tester, 'err_project_detail',
          ProjectDetailScreen(projectId: 'p1', repo: Repository(routing)),
          routing, routingAuth));

      // 3. The verification error state (was a bare centred sentence too).
      final broken = await _boot(() => http.Response('boom', 500));
      await tester.pumpWidget(AppScope(
        api: broken.$1,
        auth: broken.$2,
        child: const MaterialApp(home: VerificationScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.errServer), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      shots.add(await _shoot(tester, 'err_verification',
          const VerificationScreen(), broken.$1, broken.$2));

      for (final path in shots) {
        stdout.writeln('SHOT $path ${File(path).lengthSync()}b');
      }
    });
  });
}
