import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/core/theme/motion.dart';
import 'package:allomokawil/src/widgets/big_button.dart';
import 'package:allomokawil/src/widgets/motion.dart';

import 'support/source_text.dart';

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

      double fadeNow() => tester
          .widget<FadeTransition>(find.byType(FadeTransition))
          .opacity
          .value;
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

      final Widget tree =
          const AppPageTransitionsBuilder().buildTransitions<void>(
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

    testWidgets(
        'sliding off cancels the press so a scroll leaves nothing stuck',
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
          body: Reveal(
              child: SizedBox(
                  height: 40,
                  child: TextButton(
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
      final Transform lift = tester.widget<Transform>(find
          .descendant(of: find.byType(Reveal), matching: find.byType(Transform))
          .first);
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

    // Both patterns now live in `tempoRules` (test/support/source_text.dart)
    // and are read from there, rather than being typed a second time here.
    // They were two independent copies until this tick, which is how the rule
    // and `app_source_scope_test.dart`'s `_ruleEvidence` could end up
    // describing two different rules; a literal that must be typed twice is a
    // literal that gets updated in one place.
    //
    // The `duration:` pattern widened from `duration:` to `\w*[Dd]uration:` on
    // purpose. See the planted-proof below for why, and for the census that
    // says a *positional* `Duration` is still deliberately out of scope.
    final List<RegExp> rules = tempoRules;
    final List<String> offenders = <String>[];

    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('core/theme/motion.dart')) continue;
      offenders.addAll(ruleHits(entity.readAsStringSync(), rules)
          .map((RuleHit hit) => '${entity.path}:${hit.toString()}'));
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use AppMotion.* for a duration or a curve:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the tempo rule reads whole files, not lines', () {
    // The scan unit is part of the rule, so it is pinned here rather than left
    // to the reading of whoever edits this file next.
    //
    // `duration:\s*(?:const\s+)?Duration\(` was applied to `lines[i]`, and
    // `\s` matches a newline -- so the pattern was written to span a line
    // break and could then never match one. The shape that got past it is not
    // a deliberate dodge: it is what `dart format` emits at 80 columns, and
    // this tree already holds 51 argument labels alone on a line.
    //
    // Both halves are asserted on one string: the split call must be found, and
    // the call that is genuinely a timeout must not be mistaken for one.
    const String wrapped =
        'return AnimatedContainer(\n    duration:\n        const Duration(milliseconds: 777),\n  );';
    expect(
      offendingLines(
          wrapped, <RegExp>[RegExp(r'duration\s*:\s*(?:const\s+)?Duration\(')]),
      hasLength(1),
      reason: 'a duration wrapped over two lines is the shape `dart format` '
          'produces and the shape this rule must still catch:\n$wrapped',
    );

    // And the reader must not fire on the rule being *discussed*: a doc comment
    // and an Arabic string both quote the exact shape this guard polices, and
    // neither is an animation. Prose shadowing code has cost this repository
    // one guard already (`_rootsOf` read the old root out of the comment
    // explaining the fix).
    //
    // Three hits expected, and each one is named so a failure says which kind
    // leaked:
    //   * the comment naming the shape -> must not be counted,
    //   * the string holding the shape -> must not be counted,
    //   * the real call, wrapped over two lines -> must be counted, once.
    // The first draft of this case expected three and counted the string, so
    // it proved nothing: it would have passed with the comment counted and the
    // real call missed.
    const String discussed = '''
      // Use AppMotion.* for a duration:
      //   duration: const Duration(milliseconds: 140),
      const String tip = 'duration: const Duration(milliseconds: 140),';
      return AnimatedContainer(
        duration:
            const Duration(milliseconds: 777),
      );
    ''';
    final List<String> hits = offendingLines(
        discussed, <RegExp>[RegExp(r'duration\s*:\s*(?:const\s+)?Duration\(')]);
    expect(hits, hasLength(1),
        reason: 'one hit: the wrapped real call. The comment and the Arabic '
            'string quote the same shape and neither is code:\n'
            '${hits.join('\n')}');
    expect(hits.single, contains('duration:'),
        reason: 'the hit must be the declaration line, not a comment:\n$hits');
  });

  test('the tempo rule sees a duration label in any casing', () {
    // **Found by planting, not by reading.** The 25th tick's next-step note
    // said the obvious hole was a *positional* `Duration(...)` in a widget
    // versus a timeout everywhere else, and called that "a different rule
    // needing a shape-aware reader". Planting the shape it named showed the
    // real hole was somewhere else entirely, and the premise was wrong.
    //
    // The rule's pattern was lowercase `duration:`. Flutter spells the same
    // animation slot `reverseDuration:` -- with a capital D -- and this app
    // already uses it at `lib/src/widgets/motion.dart:39`. So planting
    //
    //   reverseDuration: const Duration(milliseconds: 777),
    //
    // in `category_grid.dart` left the guard **green at +15**: a hand-typed
    // 777 ms animation duration on a real screen, caught by nothing. That is
    // the same failure as the wrapped `duration:` the 25th tick found, one
    // letter away, and it was live the whole time that tick was hunting a
    // positional-duration reader.
    //
    // Widened to `\w*[Dd]uration:`, which matches `duration:`, `Duration:`
    // and `reverseDuration:` alike. Each shape is asserted, and so is the case
    // that must stay clean -- 15 real timeouts in lib/ are positional and the
    // widening must not touch them.
    final List<RegExp> rules = <RegExp>[tempoDurationRule];

    for (final String shape in <String>[
      'duration: const Duration(milliseconds: 140),',
      'duration:\n    const Duration(milliseconds: 140),',
      'reverseDuration: const Duration(milliseconds: 140),',
      'reverseDuration:\n    const Duration(milliseconds: 140),',
    ]) {
      expect(offendingLines(shape, rules), hasLength(1),
          reason: 'an animation duration is an animation duration whatever it '
              'is called and however it wraps:\n$shape');
    }

    // And what the widening must NOT do: catch the 15 real timeouts in lib/.
    for (final String timeout in <String>[
      '_ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {});',
      '.timeout(const Duration(seconds: 6));',
      'static const Duration defaultTimeout = Duration(seconds: 20);',
      'foo(const Duration(milliseconds: 777));',
    ]) {
      expect(offendingLines(timeout, rules), isEmpty,
          reason: 'a timeout is not a tempo and the rule must stay silent on '
              'it:\n$timeout');
    }

    // The widening is only safe because Flutter has no positional
    // animation-duration parameter at all -- every one is a named `duration:`
    // argument (`AnimationController`, `animateTo`, `animateBack`,
    // `AnimationStyle`, `AnimatedContainer`, `AnimatedSize`). A positional
    // `Duration` reaching a widget is therefore not something this rule could
    // judge, and the census behind that is 12 `Timer.periodic`, one
    // `.timeout(...)` and two field initialisers in this tree.
  });

  test('the tempo rule reads its patterns from one definition', () {
    // `app_source_scope_test.dart` holds `_ruleEvidence`, which must name the
    // literal each guard carries, so the pattern is written there as a string
    // and here as a RegExp -- two copies of one literal. Two copies is how the
    // evidence map ended up describing a rule the guard no longer enforced.
    //
    // This asserts the *shipped* patterns are the ones the map names, rather
    // than trusting that a hand-typed string somewhere still matches.
    final String durationLiteral = tempoDurationRule.pattern;
    expect(durationLiteral, r'\w*[Dd]uration\s*:\s*(?:const\s+)?Duration\(');
    expect(tempoCurveRule.pattern, r'Curves\.');
    expect(tempoRules, hasLength(2));
    expect(tempoRules.first.pattern, durationLiteral);
  });

  test('the tempo rule is enforced by the lib scan, not only named', () {
    // **The hole the map could not see, found by planting on 3 Oct (27th).**
    // The previous tick moved the two patterns out of this file into
    // `tempoRules` (test/support/source_text.dart) so they would be written
    // once, and updated `_ruleEvidence` to name the new literal. But
    // `_ruleEvidence` is read back with `_blankComments`, and this file's
    // `_blankComments` blanks comments while **keeping string bodies**
    // (`blankStrings: false`) -- deliberately, because a guard's root is
    // written `Directory('lib')` and blanking it would erase the very
    // directory the census reports.
    //
    // So the token for the motion rule can now be satisfied by a *string
    // literal* in this file and by nothing that enforces anything -- the
    // shape pinned at the end of this case. Planting both halves:
    //
    //   * drop `tempoDurationRule` from the scan and use `tempoCurveRule`
    //     alone, so the lib sweep enforces no duration rule at all;
    //   * type a real `duration: const Duration(milliseconds: 777)` into
    //     `lib/src/widgets/category_grid.dart:74`.
    //
    // Result: **+28 All tests passed!** -- the read-back stayed green because
    // it matched this file's own assertion string, the census stayed green
    // because the sweep still walks `lib/`, and only the sweep's behaviour
    // was wrong. A guard can now be deleted from the app and its own name
    // still read back as proof, which is the one failure shape
    // `app_source_scope_test.dart` exists to prevent.
    //
    // A shape test cannot fix it here: `tempoRules` has to be *named* in this
    // file for the guard to work at all, and naming it is exactly what
    // satisfies the map. So what is pinned is the mechanism instead -- the
    // reader the map uses keeps string bodies, which is what makes a name
    // satisfiable without enforcement.
    //
    // `app_source_scope_test.dart` reads its tokens through
    // `blankComments(src, blankStrings: false)`, because a guard's root is
    // `Directory('lib')` and blanking the body would erase the directory the
    // census reports. Asserted here so the day that flag changes, this case
    // fails and names itself, rather than the map quietly losing the ability
    // to be fooled.
    const String stringIsAllThereIs = """
      // The duration rule: no screen types its own duration.
      final RegExp neverUsed = RegExp(r'PLACEHOLDER_DURATION_TOKEN');
    """;
    // The token appears ONLY inside a string literal -- no comment, no code
    // that could enforce anything. This is the shape the planted run produced
    // in this file after the rules moved to `source_text.dart`.
    const String token = 'PLACEHOLDER_DURATION_TOKEN';

    // The reader the map uses KEEPS string bodies, so the token survives and
    // the read-back is satisfied. This is the hole, asserted rather than
    // described: `app_source_scope_test.dart` cannot tell a token enforced in
    // code from a token merely written down somewhere in the file.
    expect(
        blankComments(stringIsAllThereIs, blankStrings: false), contains(token),
        reason: 'this is the mechanism that let the planted run pass: a token\n'
            'in a string body satisfies a read-back that blanks only comments.');

    // The reader the *scan* uses (this file's own, strings blanked) must not
    // see it -- that is what keeps prose and sample text out of the sweep.
    expect(blankComments(stringIsAllThereIs), isNot(contains(token)),
        reason: 'a token that exists only in a string is not code, and the\n'
            'sweep reader must not count it as one.');

    // And it must still blank comments, or a token could survive in the doc
    // comment explaining the rule even with every enforcement line deleted --
    // the failure this reader was originally written to stop.
    expect(blankComments('// $token'), isNot(contains(token)),
        reason: 'comments must be blanked, or a rule that is only *described*\n'
            'reads back as enforced.');
  });
}
