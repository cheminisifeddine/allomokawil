// The role explainer — one question, asked once, with a way out.
//
// The founder's rule for this screen: a first-time visitor must not have to
// guess whether this app is for him. The landing page has exactly one create
// button, so the guess used to happen on the form, after the phone number. These
// tests pin the new order: tap → «ماذا تريد أن تفعل؟» → the form opens with the
// answer already selected; skip → the form still opens; and neither happens
// twice, because the answer is remembered (see `data/onboarding.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/data/onboarding.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'package:allomokawil/src/screens/landing/landing_screen.dart';

Future<void> pumpLanding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: LandingScreen()));
  await tester.pumpAndSettle();
}

/// The landing button is the only way into sign-up; `ensureVisible` because the
/// landing scrolls on short viewports.
Future<void> tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('landing-create-account')));
  await tester.tap(find.byKey(const Key('landing-create-account')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only an exact true counts as already explained', () {
    expect(roleGuideSeenFrom(true), isTrue);
    // A store holding anything else — a legacy string, a number, nothing —
    // must ask the question again rather than skip it for good.
    expect(roleGuideSeenFrom('true'), isFalse);
    expect(roleGuideSeenFrom(1), isFalse);
    expect(roleGuideSeenFrom(null), isFalse);
  });

  testWidgets('a fresh install is told which side of the app it is on',
      (tester) async {
    await pumpLanding(tester);
    // Nothing is asked before the visitor asks to start.
    expect(find.byKey(const Key('role-guide-customer')), findsNothing);

    await tapCreate(tester);

    expect(find.text('ماذا تريد أن تفعل؟'), findsOneWidget);
    expect(find.byKey(const Key('role-guide-customer')), findsOneWidget);
    expect(find.byKey(const Key('role-guide-worker')), findsOneWidget);
    expect(find.byKey(const Key('role-guide-skip')), findsOneWidget);
    expect(find.text(S.customerLabel), findsOneWidget);
    expect(find.text(S.workerLabel), findsOneWidget);
  });

  testWidgets('choosing the contractor side opens the form already on it',
      (tester) async {
    await pumpLanding(tester);
    await tapCreate(tester);

    await tester.tap(find.byKey(const Key('role-guide-worker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-submit')), findsOneWidget);
    expect(find.text('أنشئ حسابك في دقيقة'), findsOneWidget);
    // The role sentence under the tiles is the form's own proof of selection.
    expect(find.text(S.workerDesc), findsOneWidget);
    expect(find.text(S.customerDesc), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(roleGuideSeenKey), isTrue);
  });

  testWidgets('skipping still signs you up, and never asks twice',
      (tester) async {
    await pumpLanding(tester);
    await tapCreate(tester);

    await tester.tap(find.byKey(const Key('role-guide-skip')));
    await tester.pumpAndSettle();

    // Skipping is not a dead end: the form opens on the default role.
    expect(find.text('أنشئ حسابك في دقيقة'), findsOneWidget);
    expect(find.text(S.customerDesc), findsOneWidget);

    // Back out and try again: the question has been answered by default.
    await tester.tap(find.byKey(const Key('auth-back')));
    await tester.pumpAndSettle();
    await tapCreate(tester);

    expect(find.byKey(const Key('role-guide-customer')), findsNothing);
    expect(find.text('ماذا تريد أن تفعل؟'), findsNothing);
    expect(find.text('أنشئ حسابك في دقيقة'), findsOneWidget);
  });

  testWidgets('a corrupted flag re-asks instead of skipping forever',
      (tester) async {
    SharedPreferences.setMockInitialValues({roleGuideSeenKey: 'yes'});
    await pumpLanding(tester);
    await tapCreate(tester);

    expect(find.byKey(const Key('role-guide-customer')), findsOneWidget);
  });

  testWidgets('the contractor link is unchanged: it goes straight to the form',
      (tester) async {
    await pumpLanding(tester);
    await tester.ensureVisible(find.byKey(const Key('landing-contractor-link')));
    await tester.tap(find.byKey(const Key('landing-contractor-link')));
    await tester.pumpAndSettle();

    // That visitor has already said which side he is on.
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byKey(const Key('role-guide-worker')), findsNothing);
    expect(find.text(S.workerDesc), findsOneWidget);
  });
}
