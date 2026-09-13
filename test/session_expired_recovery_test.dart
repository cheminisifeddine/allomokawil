// The founder's report, verbatim: "the jobs are not showing inside the app
// nothing is showing". The screen he photographed said «انتهت جلستك. سجّل الدخول
// من جديد» under an empty list, on a home page that still had his name on it.
//
// That combination has exactly one cause: the app was holding a bearer token the
// server no longer knew. Every authed request answered 401, so every list drew
// its own failure line, and there was no path back to the login form — the app
// looked empty rather than signed out.
//
// These tests pin the recovery path: a 401 on a request that carried a token
// drops the dead session, returns to the landing page, and says why. A 401 on a
// request that carried no token (a wrong password on the login form) must NOT
// claim the session expired.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';

const _customer = {
  'id': 1,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test Client',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

/// Every request answers 401 — the server has forgotten this token.
ApiClient _deadSessionApi() => ApiClient(
      httpClient: MockClient((req) async => http.Response(
            jsonEncode({'error': 'انتهت الجلسة'}),
            401,
            headers: {'content-type': 'application/json'},
          )),
      baseUrls: ['https://x.test'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 401 on a request that carried a token drops the session', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'dead-token',
      'auth.user': jsonEncode(_customer),
    });
    final prefs = await SharedPreferences.getInstance();

    final api = _deadSessionApi();
    final auth = AuthState(api);
    await auth.restore();
    expect(auth.isAuthenticated, isTrue, reason: 'restored from storage');

    await expectLater(
      api.get('/api/mobile/my/profile'),
      throwsA(isA<ApiException>()),
    );
    // The handler is installed by the constructor, so this needs no wiring in
    // the test either: the point is that the invariant lives in AuthState.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.isAuthenticated, isFalse);
    expect(auth.user, isNull);
    expect(auth.sessionExpired, isTrue);
    expect(api.token, isNull);
    expect(prefs.get('auth.token'), isNull);
    expect(prefs.get('auth.user'), isNull);
  });

  test('a 401 with no token is a bad password, not an expired session',
      () async {
    SharedPreferences.setMockInitialValues({});
    final api = _deadSessionApi();
    final auth = AuthState(api);
    await auth.restore();

    await expectLater(
      api.post('/api/login', body: {'phone': '0550000000', 'password': 'x'}),
      throwsA(isA<ApiException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.sessionExpired, isFalse,
        reason: 'the login form must not accuse the user of losing a session');
  });

  testWidgets(
    'a dead session lands on the landing page with a notice, not an empty home',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'dead-token',
        'auth.user': jsonEncode(_customer),
      });

      final api = _deadSessionApi();
      final auth = AuthState(api);
      await auth.restore();

      await tester.pumpWidget(
        AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
      );
      await tester.pumpAndSettle();

      // The dead session is gone and the front door is back.
      expect(auth.isAuthenticated, isFalse);
      expect(find.byKey(const Key('landing-create-account')), findsOneWidget);

      // The landing page also asks for a second reason to be there: the front
      // door has a way in, and it says why the app sent him back here.
      expect(find.byKey(const Key('landing-sign-in')), findsOneWidget);
      expect(find.text(S.errUnauthorized), findsOneWidget);

      // ضغط «حسناً» يزيل التنبيه ولا يُبقي الواجهة معلّقة على رسالة قديمة.
      await tester.tap(find.text('حسناً'));
      await tester.pumpAndSettle();
      expect(find.text(S.errUnauthorized), findsNothing);
      expect(auth.sessionExpired, isFalse);
      expect(find.byKey(const Key('landing-sign-in')), findsOneWidget);
    },
  );
}
