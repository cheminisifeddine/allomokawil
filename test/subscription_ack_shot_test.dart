// Rasterizes the confirmation the contractor reads after tapping «ادفع».
//
// The web+CDP path in step 5 of the protocol needs Chrome and a JDK, and this
// box has neither (`/usr/lib/jvm` does not exist), so the bundle cannot be built
// here. This goes through the same `tester.runAsync` + `toImage` capture
// `design_shots_test.dart` uses, which is the real rasterizer, with the real
// Cairo loaded through `FontLoader` — a bare widget test draws Arabic as tofu.
//
// Two mistakes this file made first, kept here because they are easy to repeat
// and both produced shots that *measured* as valid:
//
//   1. A `SnackBar` mounted outside a `ScaffoldMessenger` throws in `initState`.
//      The first version rendered one inside a plain `Column`, so all three
//      captures were the same 21 KB blank.
//   2. The `RepaintBoundary` has to sit INSIDE the `Navigator`, wrapping the
//      `Scaffold` — a SnackBar is painted into the overlay above the app's own
//      subtree. With the boundary outside `MaterialApp` the surface was
//      captured and the glyphs were not: three identical solid-navy bands that
//      passed a "is there ink?" check while showing no text at all.
//
// The assertions below are the ones that catch version 2: the count of
// *light* pixels on the snackbar's own navy surface. Navy-on-navy text has
// zero of them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/subscription_ack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = '/tmp/shots';

/// The message the screen shows, rendered the way the app renders it: a real
/// `ScaffoldMessenger` pushing a real `SnackBar` into a real `Scaffold`.
class _Toast extends StatelessWidget {
  const _Toast(this.messages, this.boundaryKey);

  final List<String> messages;
  final GlobalKey boundaryKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AppScope(
          api: ApiClient(baseUrls: ['https://probe.invalid']),
          auth: AuthState(ApiClient(baseUrls: ['https://probe.invalid'])),
          child: RepaintBoundary(
            key: boundaryKey,
            child: Builder(
              builder: (context) {
                // Queued after the first frame, exactly as the screen calls it.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final messenger = ScaffoldMessenger.of(context);
                  for (final m in messages) {
                    messenger.showSnackBar(SnackBar(content: Text(m)));
                  }
                });
                return Scaffold(
                  backgroundColor: AppTheme.bg,
                  body: Directionality(
                    textDirection: TextDirection.rtl,
                    child: const SizedBox(width: 380, height: 200),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

/// Light pixels **inside the snackbar's own band** — the glyph count.
///
/// The first version of this counted light pixels across the whole capture and
/// got ~1.75 million for every message, because the page behind the snackbar
/// is white. The number has to be scoped to the rows the snackbar occupies, or
/// it measures the background and passes for any input at all.
///
/// The band is found by its own surface: `navy` is (0x16, 0x21, 0x3E), and
/// glyphs are the markedly lighter pixels inside those rows. A capture that
/// shows the surface and not a single character therefore returns 0.
Future<int> _countGlyphs(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await boundary.toImage(pixelRatio: 2.0);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  // The boundary is the Scaffold's own subtree, so the capture is whatever the
  // Scaffold laid out; read the real dimensions back rather than assuming them.
  final width = boundary.size.width.round();
  final height = boundary.size.height.round();
  const scale = 2.0;
  final stride = (width * scale).round();
  final rows = (height * scale).round();
  var glyphs = 0;
  for (var y = 0; y < rows; y++) {
    final rowStart = y * stride * 4;
    if (rowStart + stride * 4 > bytes.length) break;
    var navyInRow = 0;
    var lightInRow = 0;
    for (var x = 0; x < stride; x++) {
      final i = rowStart + x * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if (r < 0x30 && g < 0x40 && b < 0x60) navyInRow++;
      if (r > 150 && g > 150 && b > 150) lightInRow++;
    }
    // Only rows the snackbar itself occupies count.
    if (navyInRow > stride ~/ 2) glyphs += lightInRow;
  }
  return glyphs;
}

Future<void> _shoot(
    WidgetTester tester, String name, List<String> messages) async {
  final key = GlobalKey();
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(_Toast(messages, key));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final loader = FontLoader('Cairo')..addFont(Future.value(reg));
    await loader.load();
  });

  testWidgets('a yearly purchase names the figure and the term', (t) async {
    // The live answer to POST /api/mobile/subscription {plan: basic,
    // period: year} — request 42, 26 Sep 2026.
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(_Toast([
      subscriptionAckAr(SubscriptionAck.tryParse(const {
        'ok': true,
        'request_id': 42,
        'period': 'year',
        'months': 12,
        'amount_dzd': 15000,
      }))!,
    ], key));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final light = (await t.runAsync(() async => _countGlyphs(key)))!;
    // ignore: avoid_print
    print('GLYPHS year >> $light');
    expect(light, greaterThan(3000),
        reason: 'no glyph pixels: the text did not rasterise');
    await _shoot(t, 'zz_ack_year', [
      subscriptionAckAr(SubscriptionAck.tryParse(const {
        'ok': true,
        'request_id': 42,
        'period': 'year',
        'months': 12,
        'amount_dzd': 15000,
      }))!,
    ]);
  });

  testWidgets('the pre-fix confirmation, for comparison', (t) async {
    final key = GlobalKey();
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(_Toast(const [S.planRequestOk], key));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    final light = (await t.runAsync(() async => _countGlyphs(key)))!;
    // ignore: avoid_print
    print('GLYPHS before >> $light');
    await _shoot(t, 'zz_ack_before', [S.planRequestOk]);
  });

  testWidgets('a figure that disagrees with the price warns', (t) async {
    await _shoot(t, 'zz_ack_mismatch', [
      subscriptionAckAr(SubscriptionAck.tryParse(const {
        'ok': true,
        'period': 'month',
        'amount_dzd': 4250,
      }))!,
      subscriptionAmountMismatchAr(1500, 4250)!,
    ]);
  });
}
