// Browsing without an account.
//
// The founder's brief, verbatim: «make sure the users can use and browse offer
// and jobs without sign in, just ask in the first page for if this is مقاول او
// صاحب عمل and show the related dashboard». Two halves to hold down: the choice
// survives a restart (otherwise the question is asked every launch), and the
// first page is the thing that asks it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/screens/landing/landing_screen.dart';

Future<void> pumpLanding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: LandingScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('choosing a side records it and survives a restart', () async {
    final auth = AuthState(ApiClient());
    await auth.enterAsGuest(UserRole.worker);

    expect(auth.guestRole, UserRole.worker);
    expect(auth.isGuest, isTrue);
    expect(auth.isAuthenticated, isFalse);

    final restored = AuthState(ApiClient());
    await restored.restore();
    expect(restored.guestRole, UserRole.worker);
  });

  test('a stored value we do not recognise is ignored, not guessed at', () async {
    SharedPreferences.setMockInitialValues({'auth.guestRole': 'engineer'});
    final auth = AuthState(ApiClient());
    await auth.restore();
    expect(auth.guestRole, isNull);
  });

  test('going back to the first page forgets the choice', () async {
    final auth = AuthState(ApiClient());
    await auth.enterAsGuest(UserRole.customer);
    await auth.leaveGuest();
    expect(auth.guestRole, isNull);

    final restored = AuthState(ApiClient());
    await restored.restore();
    expect(restored.guestRole, isNull);
  });

  testWidgets('the first page asks which side the visitor is on',
      (tester) async {
    await pumpLanding(tester);

    expect(find.text(LandingScreen.tagline), findsOneWidget);
    expect(find.byKey(const Key('landing-role-customer')), findsOneWidget);
    expect(find.byKey(const Key('landing-contractor-link')), findsOneWidget);
    expect(find.text('التصفّح مجاني وبدون حساب.'), findsOneWidget);
  });

  testWidgets('the copy the founder asked to remove is gone', (tester) async {
    await pumpLanding(tester);

    expect(find.text('كل خدمات البناء والتهيئة في مكان واحد.'), findsNothing);
    expect(find.text('مقاولون موثّقون'), findsNothing);
    expect(find.text('تقييمات حقيقية'), findsNothing);
    expect(find.text('بدون رسوم'), findsNothing);
  });

  testWidgets('with no scope above it the role button still opens the form',
      (tester) async {
    await pumpLanding(tester);

    await tester.tap(find.byKey(const Key('landing-role-customer')));
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
