import 'dart:convert';

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

/// Responses the customer home needs so it renders instead of erroring.
http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'registering flips the root gate from the landing page to the dashboard',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/register' || path == '/api/login') {
          return http.Response(
            jsonEncode({'token': 'test-token', 'user': _customer}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/api/unread') return _ok('0');
        // Every collection the home tabs load (workers, projects, conversations).
        return _ok('[]');
      });

      final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
      final auth = AuthState(api);
      await auth.restore();

      await tester.pumpWidget(
        AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
      );
      await tester.pumpAndSettle();

      // No session yet -> the two-choice landing gate.
      expect(find.text('أنا صاحب مشروع'), findsOneWidget);

      await auth.register(
        phone: '0550000000',
        email: '',
        fullName: 'Test Client',
        password: 'secret123',
        role: UserRole.customer,
      );
      await tester.pumpAndSettle();

      // Regression: a successful register must replace the gate with the
      // dashboard. It previously stayed on the landing/register screen forever.
      expect(find.text('أنا صاحب مشروع'), findsNothing);
      expect(find.text('استكشف'), findsOneWidget);
      expect(find.text('مشاريعي'), findsOneWidget);
    },
  );

  testWidgets('logging out returns to the landing gate', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_customer),
    });

    final client = MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/unread') return _ok('0');
      return _ok('[]');
    });

    final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
    final auth = AuthState(api);
    await auth.restore();

    await tester.pumpWidget(
      AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
    );
    await tester.pumpAndSettle();

    // A persisted session goes straight to the dashboard on cold start.
    expect(find.text('استكشف'), findsOneWidget);

    await auth.logout();
    await tester.pumpAndSettle();

    expect(find.text('أنا صاحب مشروع'), findsOneWidget);
  });
}
