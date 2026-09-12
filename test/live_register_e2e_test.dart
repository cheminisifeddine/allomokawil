// End-to-end test of the exact bug the founder reported: creating an account
// must land on the dashboard. Runs the REAL ApiClient against the LIVE deployed
// backend and the REAL widget tree — no mocks.
//
// Two flutter_test gotchas handled here:
//  1. the binding installs an HttpOverrides that fails every request, so each
//     test clears it after binding init;
//  2. testWidgets runs in a fake-async zone, so real socket I/O must go through
//     tester.runAsync() or it simply never completes.
//
// Run with:  flutter test test/live_register_e2e_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/app.dart';
import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';

const _live = 'https://allomokawil.colisify.com';

/// The dashboard's loading skeleton animates forever, so pumpAndSettle would
/// never return. Pump a bounded number of frames instead.
Future<void> settle(WidgetTester tester, {int frames = 60}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The dashboard fetches data as soon as it mounts and ApiClient guards every
/// request with a 20s timeout. Those timers are still pending when the test body
/// ends, which flutter_test reports as a failure — so fire them and let the
/// futures (handled by FutureBuilder) finish.
Future<void> drainTimers(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.pump(const Duration(seconds: 21));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
  await settle(tester, frames: 4);
}

Future<AuthState> boot(WidgetTester tester,
    {List<String> hosts = const [_live]}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final api = ApiClient(baseUrls: hosts);
  final auth = AuthState(api);
  await tester.runAsync(() => auth.restore());

  await tester.pumpWidget(
    AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
  );
  await settle(tester, frames: 12);
  return auth;
}

void main() {
  testWidgets('LIVE: create an account -> lands on the dashboard',
      (tester) async {
    HttpOverrides.global = null;
    final auth = await boot(tester);

    // Nothing signed in yet: the front door is the landing page, which no
    // longer asks the visitor to pick a side before they can do anything.
    expect(find.byKey(const Key('landing-create-account')), findsOneWidget,
        reason: 'the landing must be visible before registering');
    expect(find.text('أنا صاحب مشروع'), findsNothing,
        reason: 'the role gate must NOT be the first screen any more');

    // Pad to a full 10-digit Algerian number: `% 1000000` yields fewer than six
    // digits roughly one time in ten, and a 9-digit number is correctly rejected
    // by the app's own validator -- which made this test flaky. Both tests in this
    // file run inside the same second, so they used to fail together.
    final phone =
        '0774${(DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
    debugPrint('LIVE registering phone=$phone');

    await tester.runAsync(() => auth.register(
          phone: phone,
          email: '',
          fullName: 'زبون تجربة حقيقي',
          password: 'secret123',
          role: UserRole.customer,
        ));
    debugPrint('LIVE register returned: authenticated=${auth.isAuthenticated} '
        'role=${auth.role}');
    await settle(tester);

    // THE BUG: after creating an account the gate must show the dashboard.
    expect(auth.isAuthenticated, isTrue,
        reason: 'register must persist a session');
    expect(find.byKey(const Key('landing-create-account')), findsNothing,
        reason: 'the landing must be replaced after registering');
    expect(find.text('استكشف'), findsOneWidget,
        reason: 'the customer dashboard must be on screen after registering');
    debugPrint('LIVE PASS: dashboard reached after register');
    await drainTimers(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('LIVE: sign out then sign back in with the same account',
      (tester) async {
    HttpOverrides.global = null;
    final auth = await boot(tester);

    final phone =
        '0775${(DateTime.now().millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0')}';
    await tester.runAsync(() => auth.register(
          phone: phone,
          email: '',
          fullName: 'زبون دخول',
          password: 'secret123',
          role: UserRole.customer,
        ));
    await settle(tester);
    expect(auth.isAuthenticated, isTrue);

    await tester.runAsync(() => auth.logout());
    await settle(tester, frames: 20);
    expect(find.byKey(const Key('landing-create-account')), findsOneWidget,
        reason: 'signing out returns to the landing');

    await tester.runAsync(() => auth.login(
        phone: phone, password: 'secret123', rememberMe: true));
    debugPrint('LIVE login ok=${auth.isAuthenticated} phone=$phone');
    await settle(tester);

    expect(auth.isAuthenticated, isTrue, reason: 'login must succeed');
    expect(find.text('استكشف'), findsOneWidget,
        reason: 'the dashboard must appear after logging in');
    debugPrint('LIVE PASS: dashboard reached after login');
    await drainTimers(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));
}