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

      // No session yet -> the public landing page: the mark, one sentence and
      // the one question it asks. The account row the founder removed is gone.
      expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
      expect(find.byKey(const Key('landing-contractor-link')), findsOneWidget);
      expect(find.byKey(const Key('landing-create-account')), findsNothing);

      // Browsing first, exactly as the founder asked: no form on arrival.
      await tester.tap(find.byKey(const Key('landing-role-customer')));
      await tester.pumpAndSettle();
      expect(find.text('استكشف'), findsOneWidget);
      expect(find.text('أنشئ حسابك في دقيقة'), findsNothing);

      await auth.register(
        phone: '0550000000',
        email: '',
        fullName: 'Test Client',
        password: 'secret123',
        role: UserRole.customer,
      );
      await tester.pumpAndSettle();

      // Regression: a successful register must replace the tree the visitor was
      // looking at with the member one. The gate renders the same `RoleHome`
      // for both, so without the session key it stayed on the visitor tree
      // until the app was closed and reopened.
      expect(find.textContaining('Test Client'), findsWidgets,
          reason: 'the dashboard greets the account that was just created');
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

    expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
    expect(find.byKey(const Key('landing-create-account')), findsNothing);
  });

  testWidgets('the landing opens ONE auth screen, with the role inside it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final client = MockClient((req) async => _ok('[]'));
    final api = ApiClient(httpClient: client, baseUrls: ['https://x.test']);
    final auth = AuthState(api);
    await auth.restore();

    await tester.pumpWidget(
      AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
    );
    await tester.pumpAndSettle();

    // Arriving opens nothing: the first page asks one question and the answer
    // is a dashboard, not a form.
    expect(find.text('أنشئ حسابك في دقيقة'), findsNothing);

    await tester.tap(find.byKey(const Key('landing-role-customer')));
    await tester.pumpAndSettle();
    expect(find.text('أنشئ حسابك في دقيقة'), findsNothing);
    expect(find.text('استكشف'), findsOneWidget);

    // Doing the thing that needs an account is what opens it.
    await tester.tap(find.byKey(const Key('tab-action')));
    await tester.pumpAndSettle();

    // One screen holds both halves, and the account type is asked HERE.
    expect(find.text('أنشئ حسابك في دقيقة'), findsOneWidget);
    expect(find.text('نوع الحساب'), findsOneWidget);
    expect(find.text('أنا صاحب مشروع'), findsOneWidget);
    expect(find.text('أنا مقاول/حرفي'), findsOneWidget);

    // Switching to sign-in drops the role question: an existing account
    // already knows what it is.
    await tester.tap(find.byKey(const Key('auth-tab-signin')));
    await tester.pumpAndSettle();

    expect(find.text('أهلاً بعودتك'), findsOneWidget);
    expect(find.text('نوع الحساب'), findsNothing);
  });
}
