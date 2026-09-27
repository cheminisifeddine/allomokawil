// A busy button must not look like a dead one.
//
// `PrimaryButton` (and the `BigButton` wrapper that delegates to it) computed
//     final enabled = onPressed != null && !loading;
// and handed `onPressed: enabled ? onPressed : null` to an `ElevatedButton`
// whose style declares
//     disabledBackgroundColor: AppTheme.line,
//     disabledForegroundColor: AppTheme.textMuted,
// so **every loading button in the app painted in the disabled palette** —
// grey fill, muted text, no amber anywhere on the button that was still
// working. `loading` was implemented as "the button is disabled" rather than
// "the button is busy".
//
// Nine call sites inherit it: sign-in and register submit, posting a project,
// submitting a review, sending a verification document, saving the profile,
// uploading to the portfolio, subscribing to a plan, and — from the previous
// tick — accepting a quote.
//
// The pixel evidence that found it: in
// `/tmp/shots/accept_in_flight.png` the *committing* accept button is 99.6 %
// `e8e8ec`, the disabled fill, and so is each of the two dead sibling buttons
// that surround it. The card the app is working on and the cards it has just
// refused are pixel-identical. In the idle shot the same button is 100 %
// `e8a33d`. The test below pins that difference in the widget's own pixels,
// so a future refactor cannot quietly restore the grey.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/widgets/big_button.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// Colour histogram of the captured boundary, counted in the pixels the user
/// actually sees rather than in the widget tree — the whole point of the item
/// is that the widget tree looked correct.
Future<Map<int, int>> _histogram(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final Map<int, int> hist;
  await tester0.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    Directory('/tmp/shots').createSync(recursive: true);
    // PNG for the founder to look at; the histogram is counted from the same
    // image so the number and the file can never describe different things.
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    hist = <int, int>{};
    for (var i = 0; i < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a < 200) continue; // transparent: not part of what the eye reads
      final r = (rgba[i] * a + 255 * (255 - a)) ~/ 255;
      final g = (rgba[i + 1] * a + 255 * (255 - a)) ~/ 255;
      final b = (rgba[i + 2] * a + 255 * (255 - a)) ~/ 255;
      final k = (r << 16) | (g << 8) | b;
      hist[k] = (hist[k] ?? 0) + 1;
    }
    image.dispose();
  });
  return hist;
}

/// Runs [_histogram] against the live tree of the current test.
late WidgetTester tester0;

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  Future<({double accent, double grey, double navy})> measure(
    WidgetTester tester,
    String name, {
    required bool loading,
    required Widget Function(Widget) builder,
  }) async {
    tester0 = tester;
    tester.view.physicalSize = const Size(392 * 2.75, 320 * 2.75);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: RepaintBoundary(key: key, child: builder(const SizedBox(width: 300)))),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final hist = await _histogram(key, name);
    final total = hist.values.fold<int>(0, (a, b) => a + b);
    // `Color.value` is 32-bit ARGB; the histogram is 24-bit RGB, so the alpha
    // byte has to go or every lookup misses and the test silently measures 0.
    int rgb(Color c) => c.toARGB32() & 0xFFFFFF;
    return (
      accent: (hist[rgb(AppTheme.accent)] ?? 0) / total,
      grey: (hist[rgb(AppTheme.line)] ?? 0) / total,
      navy: (hist[rgb(AppTheme.navy)] ?? 0) / total,
    );
  }

  // ── The defect ──────────────────────────────────────────────────────────
  testWidgets('a busy PrimaryButton keeps the accent, not the disabled grey',
      (tester) async {
    final m = await measure(tester, 'primary_button_loading',
        loading: true,
        builder: (box) => SizedBox(
              width: 300,
              child: PrimaryButton(
                label: 'قبول العرض',
                icon: Icons.check_circle_outline_rounded,
                loading: true,
                onPressed: () {},
              ),
            ));
    expect(m.accent, greaterThan(0.5),
        reason: 'a busy button must keep its amber fill: it is the action '
            'in progress, and grey is the colour this app uses for an action '
            'that is refused. Measured accent ${(m.accent * 100).toStringAsFixed(1)}%, '
            'disabled grey ${(m.grey * 100).toStringAsFixed(1)}%');
    expect(m.grey, lessThan(0.2),
        reason: 'a busy button must not paint the disabled fill. Measured '
            '${(m.grey * 100).toStringAsFixed(1)}%');
  });

  // ── The same guarantee on the wrapper every other screen uses ───────────
  testWidgets('a busy BigButton keeps the accent too', (tester) async {
    final m = await measure(tester, 'big_button_loading',
        loading: true,
        builder: (box) => SizedBox(
              width: 300,
              child: BigButton(
                label: 'تسجيل الدخول',
                icon: Icons.arrow_back_rounded,
                loading: true,
                onPressed: () {},
              ),
            ));
    expect(m.accent, greaterThan(0.5),
        reason: 'BigButton delegates to the same kit and had the same bug: '
            'accent ${(m.accent * 100).toStringAsFixed(1)}%');
  });

  // ── The other half of the same promise: still dead when truly dead ──────
  //
  // A fix that keeps every button amber would be no fix at all: the owner must
  // still be able to see a refused action as refused. This pins the
  // distinction the item is actually about.
  testWidgets('a genuinely disabled button still reads as disabled',
      (tester) async {
    final m = await measure(tester, 'primary_button_disabled',
        loading: false,
        builder: (box) => SizedBox(
              width: 300,
              child: PrimaryButton(
                label: 'قبول العرض',
                icon: Icons.check_circle_outline_rounded,
                onPressed: null,
              ),
            ));
    expect(m.grey, greaterThan(0.5),
        reason: 'a button with no callback must stay in the disabled '
            'palette: grey ${(m.grey * 100).toStringAsFixed(1)}%, '
            'accent ${(m.accent * 100).toStringAsFixed(1)}%');
  });

  // ── And the resting state must not have moved ──────────────────────────
  testWidgets('an idle enabled button is still amber', (tester) async {
    final m = await measure(tester, 'primary_button_idle',
        loading: false,
        builder: (box) => SizedBox(
              width: 300,
              child: PrimaryButton(
                label: 'قبول العرض',
                icon: Icons.check_circle_outline_rounded,
                onPressed: () {},
              ),
            ));
    expect(m.accent, greaterThan(0.5),
        reason: 'regression guard: accent ${(m.accent * 100).toStringAsFixed(1)}%');
  });

  // ── Behaviour, not just paint ───────────────────────────────────────────
  //
  // The fix must keep the button untappable while busy. Turning the button
  // amber invites a second tap, so this is the regression the colour change
  // could cause.
  testWidgets('a busy button still swallows taps', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(392 * 2.75, 320 * 2.75);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: PrimaryButton(
              label: 'قبول العرض',
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // A busy button shows a spinner, not its label, so it is located by its
    // own rect rather than by the text it is currently not showing.
    final btn = find.byType(PrimaryButton);
    expect(find.text('قبول العرض'), findsNothing,
        reason: 'a busy button replaces its label with a spinner');
    await tester.tapAt(tester.getCenter(btn));
    await tester.pump();
    expect(taps, 0,
        reason: 'making the busy button amber must not make it tappable — '
            'that is the double-submit the guard exists to prevent');
  });
}
