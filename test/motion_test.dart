import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/core/theme/motion.dart';
import 'package:allomokawil/src/widgets/big_button.dart';
import 'package:allomokawil/src/widgets/motion.dart';

/// Pins the motion spec: one tempo for the whole app.
///
/// The app used to animate at four different speeds — eight hand-typed
/// `Duration(milliseconds: 140)`, a 160 in the auth reveal, Material's 300 ms
/// route zoom, and a 1300 ms shimmer loop. Nothing looked broken on its own,
/// but the app never felt like one thing. [AppMotion] is now the only place a
/// duration or a curve may be written, and the source scan at the bottom fails
/// the build if a screen types its own again.
void main() {
  group('AppMotion', () {
    test('the ladder is ordered from a finger to a screen', () {
      expect(AppMotion.press, lessThan(AppMotion.fast));
      expect(AppMotion.fast, lessThan(AppMotion.reveal));
      expect(AppMotion.reveal, lessThan(AppMotion.screen));
      expect(AppMotion.screen, lessThan(AppMotion.shimmer));
    });

    test('every duration in the spec is listed in AppMotion.all', () {
      expect(
        AppMotion.all.toSet(),
        {
          AppMotion.fast,
          AppMotion.press,
          AppMotion.reveal,
          AppMotion.screen,
          AppMotion.shimmer,
        },
      );
      expect(AppMotion.all.toSet().length, AppMotion.all.length);
    });

    test('entering and leaving do not share a curve', () {
      expect(AppMotion.enter, isNot(AppMotion.exit));
    });

    test('a press moves the control less than a reveal moves a row', () {
      // 3 % of a 56 dp button is 1.7 dp; 8 px on a row is visible. These are
      // deliberately different: a press is felt, a reveal is seen.
      expect(AppMotion.pressScale, greaterThan(0.9));
      expect(AppMotion.pressScale, lessThan(1.0));
      expect(AppMotion.revealOffset, greaterThan(0));
    });
  });

  group('page transitions', () {
    test('every platform the app builds for uses the app transition', () {
      final theme = AppTheme.light.pageTransitionsTheme;
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(
          theme.builders[platform],
          isA<AppPageTransitionsBuilder>(),
          reason: 'no app transition for $platform — Material default would '
              'push at its own speed',
        );
      }
    });

    test('a route lasts AppMotion.screen', () {
      expect(const AppPageTransitionsBuilder().transitionDuration,
          AppMotion.screen);
      expect(const AppPageTransitionsBuilder().reverseTransitionDuration,
          AppMotion.screen);
    });

    testWidgets('the incoming page fades and lifts at the same tempo',
        (tester) async {
      final AnimationController route =
          AnimationController(vsync: tester, duration: AppMotion.screen);
      addTearDown(route.dispose);

      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(builder: (BuildContext context0) {
          context = context0;
          return const SizedBox();
        }),
      ));

      const builder = AppPageTransitionsBuilder();
      final Widget tree = builder.buildTransitions<void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        context,
        route,
        const AlwaysStoppedAnimation<double>(0),
        const Text('صفحة'),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: tree,
      ));

      double fadeNow() =>
          tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
      double liftNow() => tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .map((SlideTransition s) => s.position.value.dy)
          .reduce((double a, double b) => a.abs() > b.abs() ? a : b);

      expect(fadeNow(), 0);
      expect(liftNow(), closeTo(AppMotion.screenOffset, 0.0001));

      route.value = 0.5;
      await tester.pump();
      final double mid = fadeNow();
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));
      // Halfway through, the page is still on its way up — but by less than it
      // started, on the ease-out curve.
      expect(liftNow(), lessThan(AppMotion.screenOffset));

      route.value = 1;
      await tester.pump();
      expect(fadeNow(), 1);
      expect(liftNow(), closeTo(0, 0.0001));
    });

    testWidgets('reduce motion removes the transition instead of shortening it',
        (tester) async {
      final AnimationController route =
          AnimationController(vsync: tester, duration: AppMotion.screen);
      addTearDown(route.dispose);

      // The builder reads the MediaQuery of the context it is handed, so the
      // context has to be captured *under* the reduced-motion MediaQuery.
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(builder: (BuildContext context0) {
            context = context0;
            return const SizedBox();
          }),
        ),
      ));

      final Widget tree = const AppPageTransitionsBuilder().buildTransitions<void>(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        context,
        route,
        const AlwaysStoppedAnimation<double>(0),
        const Text('صفحة'),
      );
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: tree,
      ));

      expect(find.byType(FadeTransition), findsNothing);
      expect(find.byType(SlideTransition), findsNothing);
      expect(find.text('صفحة'), findsOneWidget);
    });
  });

  group('press feedback', () {
    testWidgets('a finger shrinks the button, lifting it restores it',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: BigButton(label: 'حفظ', onPressed: () => taps++),
          ),
        ),
      ));

      // Read the x-axis scale directly. `getMaxScaleOnAxis()` would measure
      // the z axis too, and Transform.scale leaves z at 1.0 — so a correct
      // shrink reads as "no shrink" through that method.
      double scaleNow() => tester
          .widget<Transform>(find
              .descendant(
                  of: find.byType(BigButton), matching: find.byType(Transform))
              .first)
          .transform
          .entry(0, 0);

      expect(scaleNow(), closeTo(1, 0.0001));

      final TestGesture finger =
          await tester.startGesture(tester.getCenter(find.byType(BigButton)));
      await tester.pump();
      await tester.pump(AppMotion.press);
      final double pressed = scaleNow();
      expect(pressed, closeTo(AppMotion.pressScale, 0.005));

      await finger.up();
      await tester.pumpAndSettle();
      expect(scaleNow(), closeTo(1, 0.0001));
      // The wrapper is a Listener, not a gesture detector: the button still
      // received exactly one tap.
      expect(taps, 1);
    });

    testWidgets('sliding off cancels the press so a scroll leaves nothing stuck',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: BigButton(label: 'حفظ', onPressed: () {})),
        ),
      ));

      // Read the x-axis scale directly. `getMaxScaleOnAxis()` would measure
      // the z axis too, and Transform.scale leaves z at 1.0 — so a correct
      // shrink reads as "no shrink" through that method.
      double scaleNow() => tester
          .widget<Transform>(find
              .descendant(
                  of: find.byType(BigButton), matching: find.byType(Transform))
              .first)
          .transform
          .entry(0, 0);

      final Offset start = tester.getCenter(find.byType(BigButton));
      final TestGesture finger = await tester.startGesture(start);
      // One frame to start the ticker (its first tick is the baseline), then
      // AppMotion.press to run the shrink to its end.
      await tester.pump();
      await tester.pump(AppMotion.press);
      expect(scaleNow(), lessThan(1));

      // A thumb that travels further than the slop is scrolling, not pressing.
      await finger.moveBy(const Offset(0, -AppMotion.pressSlop - 10));
      await tester.pumpAndSettle();
      expect(scaleNow(), closeTo(1, 0.0001));
      await finger.up();
    });

    testWidgets('a disabled button does not answer at all', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: BigButton(label: 'حفظ'))),
      ));
      expect(find.byType(Pressable), findsOneWidget);

      final Finder shrink = find.descendant(
          of: find.byType(BigButton), matching: find.byType(Transform));
      expect(shrink, findsNothing,
          reason: 'a disabled button has nothing to respond to, so it is not '
              'wrapped at all');

      final TestGesture finger =
          await tester.startGesture(tester.getCenter(find.byType(BigButton)));
      await tester.pump(AppMotion.press);
      expect(shrink, findsNothing);
      await finger.up();
    });
  });

  group('list reveals', () {
    testWidgets('a revealed row arrives after AppMotion.reveal, not instantly',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Reveal(child: SizedBox(height: 40, child: TextButton(
            onPressed: () {},
            child: const Text('صف'),
          ))),
        ),
      ));

      Opacity opacityNow() =>
          tester.widget<Opacity>(find.byType(Opacity).first);

      expect(opacityNow().opacity, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityNow().opacity, greaterThan(0));
      expect(opacityNow().opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(opacityNow().opacity, 1);

      // The row is tappable where it sits, even mid-flight: hit testing ignores
      // the lift, so an animation can never move a target away from a thumb.
      final Transform lift = tester.widget<Transform>(
          find.descendant(of: find.byType(Reveal), matching: find.byType(Transform)).first);
      expect(lift.transformHitTests, isFalse);
    });

    testWidgets('reduce motion shows the row immediately', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: Reveal(child: Text('صف'))),
        ),
      ));
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('صف'), findsOneWidget);
    });
  });

  test('no screen types its own animation duration or curve', () {
    // The law that keeps the tempo: durations and curves live in
    // lib/src/core/theme/motion.dart, exactly the way font sizes live in the
    // type scale. Same idea as test/type_scale_test.dart.
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run from the package root — flutter test does');

    final RegExp typedDuration = RegExp(r'duration:\s*(?:const\s+)?Duration\(');
    final RegExp typedCurve = RegExp(r'Curves\.');
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('core/theme/motion.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (typedDuration.hasMatch(lines[i]) || typedCurve.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use AppMotion.* for a duration or a curve:\n'
          '${offenders.join('\n')}',
    );
  });
}
