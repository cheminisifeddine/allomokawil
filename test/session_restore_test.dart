import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';

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

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api() => ApiClient(
      httpClient: MockClient((req) async {
        if (req.url.path == '/api/unread') return _ok('0');
        return _ok('[]');
      }),
      baseUrls: ['https://x.test'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restore() never throws out of a boot it cannot read', () {
    test('a non-string auth.user opens logged out and is cleared', () async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': <String, dynamic>{'id': 1, 'phone': '0550000000'},
      });
      final prefs = await SharedPreferences.getInstance();

      // The fixture is the real trigger: a stored value of the wrong type. The
      // typed getter is a hard cast, which is exactly what used to throw.
      expect(prefs.get('auth.user'), isNot(isA<String>()));

      final auth = AuthState(_api());
      await auth.restore(); // Regression: threw _TypeError before runApp.

      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
      expect(prefs.get('auth.token'), isNull);
      expect(prefs.get('auth.user'), isNull);
    });

    test('a non-string auth.token is cleared the same way', () async {
      SharedPreferences.setMockInitialValues({
        'auth.token': <String>['not', 'a', 'token'],
        'auth.user': jsonEncode(_customer),
      });
      final prefs = await SharedPreferences.getInstance();

      final auth = AuthState(_api());
      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(prefs.get('auth.token'), isNull);
      expect(prefs.get('auth.user'), isNull);
    });

    test('a string that is not a user object is cleared', () async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': 'not json at all',
      });
      final prefs = await SharedPreferences.getInstance();

      final auth = AuthState(_api());
      await auth.restore();

      expect(auth.isAuthenticated, isFalse);
      expect(prefs.get('auth.user'), isNull);
      expect(prefs.get('auth.token'), isNull);
    });

    test('half a session signs nobody in and is cleared', () async {
      SharedPreferences.setMockInitialValues({'auth.token': 'test-token'});
      final prefs = await SharedPreferences.getInstance();

      final auth = AuthState(_api());
      await auth.restore();

      expect(auth.isAuthenticated, isFalse);
      expect(prefs.get('auth.token'), isNull);
    });

    test('a healthy stored session still restores', () async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_customer),
      });
      final prefs = await SharedPreferences.getInstance();

      final auth = AuthState(_api());
      await auth.restore();

      expect(auth.isAuthenticated, isTrue);
      expect(auth.role, UserRole.customer);
      expect(auth.user!.fullName, 'Test Client');
      expect(prefs.get('auth.token'), 'test-token');
    });
  });

  testWidgets(
    'a corrupt stored session boots to the landing page, not a white screen',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': <String, dynamic>{'id': 1},
      });

      final api = _api();
      final auth = AuthState(api);
      await auth.restore();

      await tester.pumpWidget(
        AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
      );
      await tester.pumpAndSettle();

      // The logged-out front door, with one way in — never a stuck splash and
      // never an empty tree. The way in is the question it asks first.
      expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('استكشف'), findsNothing);
    },
  );
}
