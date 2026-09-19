// The founder's brief, verbatim: «When i use app without sign up show the app
// exactly as if i m signed» and «only take the client to sign up or login page
// when he try to contact a handcraft man or do any activity that needs an
// account first», plus «remove الو مقاول / تغيير / تسجيل الدخول / تصفح المقاولين
// مجاناً ... because now it sucks».
//
// So this file holds three properties down:
//   1. a visitor gets the same four tabs the account holder gets — the same
//      dashboard, not a teaser page wearing a sign-in bar;
//   2. the promotional strip is gone for good;
//   3. an action that needs a session is what opens the account form, and it is
//      reached by doing the thing, not by arriving.
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
import 'package:allomokawil/src/screens/auth/auth_screen.dart';

http.Response _ok(String body) => http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );

/// The two dashboards talk to the same collections; an empty list for every one
/// of them is enough for the shell to draw.
MockClient _quietBackend() => MockClient((req) async {
      if (req.url.path == '/api/unread') return _ok('0');
      return _ok('[]');
    });

Future<AuthState> _pumpGuest(WidgetTester tester, UserRole role) async {
  // A real phone: the tab bar's centre action and the guest banner only lay out
  // as they do on a device once the viewport is phone-shaped.
  tester.view.physicalSize = const Size(392, 850) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(httpClient: _quietBackend(), baseUrls: ['https://x.test']);
  final auth = AuthState(api);
  await auth.restore();
  await auth.enterAsGuest(role);

  await tester.pumpWidget(
    AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a visitor gets the whole contractor dashboard', (tester) async {
    await _pumpGuest(tester, UserRole.worker);

    // The same four tabs a signed-in contractor sees, in the same bar.
    expect(find.text('المنصة'), findsWidgets);
    expect(find.text('مشاريعي'), findsWidgets);
    expect(find.text('الرسائل'), findsWidgets);
    expect(find.text('حسابي'), findsWidgets);
  });

  testWidgets('a visitor gets the whole client dashboard', (tester) async {
    await _pumpGuest(tester, UserRole.customer);

    expect(find.text('استكشف'), findsWidgets);
    expect(find.text('مشاريعي'), findsWidgets);
    expect(find.text('الرسائل'), findsWidgets);
    expect(find.text('حسابي'), findsWidgets);
  });

  testWidgets('the promotional strip the founder removed is not in the app',
      (tester) async {
    await _pumpGuest(tester, UserRole.customer);

    expect(
      find.textContaining('تصفح المقاولين مجاناً أنشئ حساباً لنشر مشروعك'),
      findsNothing,
      reason: 'the visitor bar was removed at his request',
    );
    expect(find.text('تغيير'), findsNothing,
        reason: 'the role switch that sat in that bar is gone with it');
    expect(find.byKey(const Key('signin-wall-browse')), findsNothing,
        reason: 'he is already browsing — saying so is the noise he cut');
  });

  testWidgets('arriving does not open the account form', (tester) async {
    await _pumpGuest(tester, UserRole.customer);

    expect(find.byType(AuthScreen), findsNothing,
        reason: 'browsing needs no account');
  });

  testWidgets('posting a project is what opens the account form',
      (tester) async {
    await _pumpGuest(tester, UserRole.customer);

    await tester.tap(find.byKey(const Key('tab-action')));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget,
        reason: 'the first action that needs a session asks for one');
  });

  testWidgets('the inbox is a wall with an explanation, not a failing request',
      (tester) async {
    await _pumpGuest(tester, UserRole.worker);

    await tester.tap(find.text('الرسائل').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signin-wall-primary')), findsWidgets,
        reason: 'a signed-out inbox offers the door');
  });

  testWidgets('the account tab holds the door inside the normal chrome',
      (tester) async {
    await _pumpGuest(tester, UserRole.worker);

    await tester.tap(find.text('حسابي').first);
    await tester.pumpAndSettle();

    // The screen is the ordinary account page — app bar and all — with a
    // sign-in card in the body.
    expect(find.byKey(const Key('signin-wall-primary')), findsWidgets);
    expect(find.text('زائر'), findsWidgets);
  });

  testWidgets('a signed-in customer is untouched by any of this', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode({
        'id': 1,
        'phone': '0550000000',
        'email': null,
        'full_name': 'Test Client',
        'type': 'customer',
        'avatar_url': null,
        'wilaya': '16',
        'commune': null,
        'created_at': '2026-01-01 00:00:00',
      }),
    });

    final api = ApiClient(httpClient: _quietBackend(), baseUrls: ['https://x.test']);
    final auth = AuthState(api);
    await auth.restore();

    await tester.pumpWidget(
      AppScope(api: api, auth: auth, child: const AlloMokawilApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('استكشف'), findsWidgets);
    expect(find.byKey(const Key('signin-wall-primary')), findsNothing);
  });
}
