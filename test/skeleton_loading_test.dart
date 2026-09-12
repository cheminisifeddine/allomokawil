// Proves the app never answers "loading" with a grey circle in the middle of an
// empty page.
//
// Why this is a test and not a taste call: a spinner mid-screen tells a
// first-time user on a slow Algerian connection that the app is stuck, while
// blocks the size of the coming content tell them it is arriving. So the
// assertion is not "a skeleton exists" — it is "no loading screen anywhere
// still shows a spinner, and the sweep really moves".
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// An API that never answers. This is the worst case a user can hit — a dead
/// connection that has not errored yet — and the exact moment the old spinner
/// was on screen.
ApiClient _deadApi() => ApiClient(
      baseUrls: ['https://x.test'],
      httpClient: MockClient((_) => Completer<http.Response>().future),
    );

/// Bounded pumps: the sweep animates forever, so `pumpAndSettle` never returns
/// on a screen that is still loading. That is deliberate — it is what "the app
/// is waiting" means — so the tests step the clock instead.
Future<void> _step(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

MaterialApp _frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      // Without the real delegates the Arabic locale throws and the tree under
      // test is not the tree that ships.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(backgroundColor: AppTheme.bg, body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => SkeletonMotion.enabled = true);

  testWidgets('a project feed that has not answered shows cards, not a spinner',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final api = _deadApi();
    final auth = AuthState(api);
    await auth.restore();

    await tester.pumpWidget(AppScope(
      api: api,
      auth: auth,
      child: _frame(ProjectsScreen(repo: Repository(api))),
    ));
    await _step(tester);

    // The tab is still waiting on the network at this point, so what is on
    // screen is the loading state — and it must be card-shaped.
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a waiting list must not render a spinner');
    expect(find.byType(Shimmer), findsWidgets,
        reason: 'the waiting feed must be the animated skeleton, not a still page');
    expect(find.byType(SkeletonBox), findsWidgets);

    // Geometry, not just presence. A spinner is one 36 px circle in the middle
    // of the page; the skeleton is a project-card row — a 76 px thumbnail plus
    // three text bars — so the real cards land in the space already reserved.
    final rows = tester
        .widgetList<Container>(find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 76))
        .length;
    expect(rows, greaterThan(0),
        reason: 'the skeleton must reserve the card thumbnail box');

    // Let the client's own 20 s timeout fire: the test must not end with a
    // pending timer, and a dead connection has to end in the Arabic retry
    // state rather than a page that waits forever.
    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('إعادة المحاولة'), findsWidgets);
  });

  testWidgets('the inbox skeleton is card-shaped and spinner-free',
      (tester) async {
    await tester.pumpWidget(_frame(const Shimmer(child: SkeletonCardList(count: 3))));
    await _step(tester, frames: 2);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Three cards, each with a thumbnail and three text bars.
    expect(find.byType(SkeletonBox), findsNWidgets(12));
  });

  testWidgets('a chat thread under load reads as a conversation',
      (tester) async {
    await tester.pumpWidget(_frame(const SkeletonChatThread()));
    await _step(tester, frames: 2);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final bubbles = find.byWidgetPredicate((w) =>
        w is Align &&
        (w.alignment == AlignmentDirectional.centerEnd ||
            w.alignment == AlignmentDirectional.centerStart));
    expect(bubbles, findsNWidgets(6));
    // Both sides: a one-sided thread would read as a list, not as messages.
    expect(
      find.byWidgetPredicate(
          (w) => w is Align && w.alignment == AlignmentDirectional.centerEnd),
      findsNWidgets(3),
    );
  });

  testWidgets('the first paint of the app is a home, not a grey circle',
      (tester) async {
    await tester.pumpWidget(_frame(const AppBootSkeleton()));
    await _step(tester, frames: 2);

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'session restore must not show a spinner');
    expect(find.byType(Shimmer), findsOneWidget);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('every form and detail skeleton is spinner-free', (tester) async {
    for (final widget in <Widget>[
      const SkeletonFormPage(fields: 4),
      const SkeletonDetailPage(),
      const SkeletonGrid(),
      const SkeletonRowList(),
    ]) {
      await tester.pumpWidget(_frame(widget));
      await _step(tester, frames: 2);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: '${widget.runtimeType} must not render a spinner');
      expect(find.byType(SkeletonBox), findsWidgets);
    }
  });

  testWidgets('the sweep actually moves: two frames do not render alike',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: RepaintBoundary(
        key: key,
        child: const ColoredBox(
          color: AppTheme.bg,
          child: AppBootSkeleton(),
        ),
      ),
    ));

    Future<List<int>> shot() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      late List<int> bytes;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data!.buffer.asUint8List().toList();
        image.dispose();
      });
      return bytes;
    }

    await tester.pump(const Duration(milliseconds: 100));
    final first = await shot();
    await tester.pump(const Duration(milliseconds: 400));
    final second = await shot();

    expect(first, isNotEmpty);
    expect(second, isNot(equals(first)),
        reason: 'the highlight must travel across the blocks; two frames that '
            'rasterise identically mean the shimmer is frozen');
  });

  testWidgets('reduce motion keeps the blocks still', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const ColoredBox(
          color: AppTheme.bg,
          child: AppBootSkeleton(),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ShaderMask), findsNothing,
        reason: 'an OS-level reduce-motion request must stop the sweep');
    expect(find.byType(SkeletonBox), findsWidgets,
        reason: 'the blocks stay; only the motion goes');
  });

  testWidgets('the motion kill switch removes the sweep, not the content',
      (tester) async {
    SkeletonMotion.enabled = false;
    await tester.pumpWidget(_frame(const Shimmer(child: SkeletonCardList(count: 2))));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ShaderMask), findsNothing);
    expect(find.byType(SkeletonBox), findsWidgets);
  });
}
