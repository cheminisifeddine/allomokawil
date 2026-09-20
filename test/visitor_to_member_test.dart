// A visitor who makes an account becomes that account — now, not after a
// restart, and without ever being shown a failing request for data he cannot
// have yet.
//
// The founder, verbatim:
//   «When i login as a visitor and i create an accoint i fidnt automaticaly get
//    logef in and i stay a visitor till i exit the app and open it again»
//   «remove ... as mokawil: تعذر جلب ملفك»
//   «And as a sahb machro3: تعذر جلب المشاريع تحقق من اتصالك بالإنترنت ثم أعد
//    المحاولة»
//
// The reason the first one happened: the root gate renders `RoleHome` for a
// visitor and `RoleHome` for the member he just created. Same widget, same
// props, so Flutter updated the element that was already there and the visitor
// tree stayed on screen until a restart rebuilt it. `app.dart` now keys that
// subtree by the session, and these tests are what keeps the key there.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/location/place_state.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';

const _client = {
  'id': 7,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test Client',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

const _contractor = {
  'id': 8,
  'phone': '0550000001',
  'email': null,
  'full_name': 'Test Contractor',
  'type': 'worker',
  'avatar_url': null,
  'wilaya': '31',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

/// Answers the register call with [user], and every collection the dashboards
/// read with an empty list.
MockClient _backend(Map<String, Object?> user) => MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/register' || path == '/api/login') {
        return http.Response(
          jsonEncode({'token': 'test-token', 'user': user}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      // The contractor's own card, so the member dashboard has something true
      // to draw where the visitor saw the door.
      if (path == '/api/mobile/my/profile') {
        return _ok(jsonEncode({
          'id': 8,
          'user_id': 8,
          'full_name': 'Test Contractor',
          'specialties': <String>[],
          'experience_years': 5,
          'service_radius_km': 20,
          'verification_status': 'pending',
          'verification_pending_docs': 0,
          'wilaya': '31',
        }));
      }
      if (path == '/api/unread') return _ok('0');
      return _ok('[]');
    });

/// Brings the strip that needs a session into view.
///
/// A `CustomScrollView` only builds the slivers near the viewport, and the card
/// these tests look for sits under the explore shelves on a 392 dp phone.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    320,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth) async {
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: auth,
      place: PlaceState.detached(),
      child: const AlloMokawilApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the first page is the mark and one question — nothing else',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(httpClient: _backend(_client));
    final auth = AuthState(api);
    await auth.restore();
    await _pump(tester, api, auth);

    expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
    expect(find.byKey(const Key('landing-contractor-link')), findsOneWidget);

    // The account block the founder quoted, word for word.
    expect(find.byKey(const Key('landing-create-account')), findsNothing);
    expect(find.text('تسجيل الدخول'), findsNothing);
    expect(find.text('إنشاء الحساب'), findsNothing);
    expect(
      find.text('بالمتابعة أنت توافق على شروط الاستخدام وسياسة الخصوصية.'),
      findsNothing,
    );
  });

  testWidgets('a visitor who registers becomes the client, without a restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(httpClient: _backend(_client));
    final auth = AuthState(api);
    await auth.restore();
    await _pump(tester, api, auth);

    // Browse as a client, signed out.
    await tester.tap(find.byKey(const Key('landing-role-customer')));
    await tester.pumpAndSettle();

    expect(find.text('استكشف'), findsOneWidget);
    expect(find.textContaining('Test Client'), findsNothing);
    // Nothing was requested that a visitor cannot have.
    expect(find.textContaining('تعذّر جلب المشاريع'), findsNothing);
    expect(find.textContaining('تحقق من اتصالك بالإنترنت'), findsNothing);
    await _reveal(tester, find.byKey(const Key('guest-projects-invite')));
    expect(find.byKey(const Key('guest-projects-invite')), findsOneWidget);

    await auth.register(
      phone: '0550000000',
      email: '',
      fullName: 'Test Client',
      password: 'secret123',
      role: UserRole.customer,
    );
    await tester.pumpAndSettle();

    // The regression: same role before and after, so the gate's widget is
    // byte-for-byte the same type — only the session key separates them. The
    // greeting is the marker: the visitor's header has no name to print.
    expect(
      find.textContaining('Test Client'),
      findsWidgets,
      reason: 'the dashboard must be the member one, not the visitor tree',
    );
    expect(auth.isAuthenticated, isTrue);
  });

  testWidgets('a visitor who registers as a contractor loses the visitor card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(httpClient: _backend(_contractor));
    final auth = AuthState(api);
    await auth.restore();
    await _pump(tester, api, auth);

    await tester.tap(find.byKey(const Key('landing-contractor-link')));
    await tester.pumpAndSettle();

    // The market, signed out: one way in and no failing profile request.
    expect(find.text('سوق المقاولين'), findsOneWidget);
    expect(find.byKey(const Key('header-create-account')), findsOneWidget);
    expect(find.text('تعذّر جلب ملفك'), findsNothing);

    await auth.register(
      phone: '0550000001',
      email: '',
      fullName: 'Test Contractor',
      password: 'secret123',
      role: UserRole.worker,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('header-create-account')), findsNothing);
    expect(find.text('سوق المقاولين'), findsNothing);
    expect(find.text('تعذّر جلب ملفك'), findsNothing);
    expect(find.textContaining('Test Contractor'), findsWidgets,
        reason: 'the header must be the member card, not the visitor one');
  });

  testWidgets('a visitor is never told his projects failed to load',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(httpClient: _backend(_client));
    final auth = AuthState(api);
    await auth.restore();
    await auth.enterAsGuest(UserRole.customer);
    await _pump(tester, api, auth);

    // The strip that needs a session shows the door, never an error: nothing
    // was attempted, so nothing can have failed.
    await _reveal(tester, find.byKey(const Key('guest-projects-invite')));
    expect(find.byKey(const Key('guest-projects-invite')), findsOneWidget);
    expect(find.textContaining('تعذّر جلب المشاريع'), findsNothing);
    expect(find.textContaining('أعد المحاولة'), findsNothing);
  });
}
