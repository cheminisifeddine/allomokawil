// Pins the decode-sizing rule, because the saving is invisible by design: a
// photo that is decoded too small still looks right on screen, it is just
// blurrier, and nothing in the app would ever notice. These tests exist so a
// later change that drops `cacheWidth` (or "simplifies" the arithmetic away)
// fails here instead of quietly costing 4 MB per thumbnail again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/widgets/net_image.dart';

void main() {
  group('NetImage.decodeWidth', () {
    test('an unsized photo is decoded at full resolution', () {
      // A fullscreen viewer has no size, and capping it would be the bug.
      expect(NetImage.decodeWidth(logical: null, pixelRatio: 3), isNull);
    });

    test('a small avatar on a dense screen still clears the floor', () {
      // 46 * 3 = 138, below the 160px floor, so the floor applies. The point
      // is not that it returns 138: it is that a 46px avatar is never fetched
      // at 46 physical pixels and upscaled into a blur on a 3x screen.
      expect(NetImage.decodeWidth(logical: 46, pixelRatio: 3),
          NetImage.minDecodePx);
    });

    test('a tiny photo still clears the decode floor', () {
      // Under the floor a second codec pass costs more than the pixels save.
      expect(NetImage.decodeWidth(logical: 24, pixelRatio: 1),
          NetImage.minDecodePx);
      expect(NetImage.decodeWidth(logical: 1, pixelRatio: 1),
          NetImage.minDecodePx);
    });

    test('never asks the codec for more pixels than the photo has', () {
      expect(
        NetImage.decodeWidth(logical: 3000, pixelRatio: 3, sourceWidth: 1024),
        1024,
      );
    });

    test('rounds a fractional device pixel up, never down', () {
      // 220 * 2.625 = 577.5. Truncating would decode 577 and lose a real
      // half-pixel of sharpness on a 2.625x screen (Galaxy S-class).
      expect(NetImage.decodeWidth(logical: 220, pixelRatio: 2.625), 578);
    });

    test('a non-finite or non-positive size decodes nothing rather than zero',
        () {
      // cacheWidth: 0 trips an assert in Image.network, and infinity is not a
      // number of pixels. Both must collapse to "no resize" instead.
      expect(NetImage.decodeWidth(logical: double.infinity, pixelRatio: 3),
          isNull);
      expect(NetImage.decodeWidth(logical: double.nan, pixelRatio: 3), isNull);
      expect(NetImage.decodeWidth(logical: 0, pixelRatio: 3), isNull);
      expect(NetImage.decodeWidth(logical: -10, pixelRatio: 3), isNull);
    });

    test('an absurd pixel ratio cannot ask for an absurd decode', () {
      // MediaQuery can hand back garbage during a transition; the result must
      // still be a finite integer, because it goes straight to cacheWidth.
      final px = NetImage.decodeWidth(logical: 76, pixelRatio: 1e9);
      expect(px, isA<int>());
      expect(px!.isFinite, isTrue);
      // A nan or zero ratio is treated as 1x rather than propagated, and the
      // floor then applies to the resulting 76.
      expect(NetImage.decodeWidth(logical: 76, pixelRatio: double.nan),
          NetImage.minDecodePx);
      expect(NetImage.decodeWidth(logical: 76, pixelRatio: 0),
          NetImage.minDecodePx);
    });

    test('the sizes this app actually draws all come out finite and sane', () {
      // The real call sites, so a change to any one of them shows up as a
      // number rather than as a jank report nobody can reproduce.
      for (final logical in [46.0, 52.0, 58.0, 76.0, 78.0, 110.0, 220.0, 400.0]) {
        for (final dpr in [1.0, 2.0, 2.625, 3.0, 4.0]) {
          final px = NetImage.decodeWidth(
              logical: logical, pixelRatio: dpr, sourceWidth: 1024)!;
          expect(px, greaterThan(0), reason: '$logical @ $dpr');
          expect(px, lessThanOrEqualTo(1024), reason: '$logical @ $dpr');
          expect(px, greaterThanOrEqualTo(NetImage.minDecodePx));
        }
      }
    });
  });

  group('NetImage widget', () {
    /// The width the widget asked the codec for, read back off the real
    /// `Image` it built. `Image.network` wraps its `NetworkImage` in a
    /// `ResizeImage` exactly when `cacheWidth` is non-null, so this is the
    /// decode request the engine will really be handed — not a field we set
    /// and then hope gets used. This is the wiring test: it fails if
    /// `cacheWidth` is ever dropped between the arithmetic above and the
    /// widget.
    int? cacheWidthIn(WidgetTester tester) {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      return provider is ResizeImage ? provider.width : null;
    }

    /// No test image is ever fetched: the test binding answers every request
    /// with a 400, and a widget with no `errorBuilder` turns that into a test
    /// failure instead of the fallback it is meant to be exercising. Every
    /// widget here therefore supplies one, so only the wiring is under test.
    const swallow = SizedBox.shrink();

    testWidgets('an explicitly sized photo is capped', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: NetImage('https://x.test/a.png',
                  width: 76, errorBuilder: (_, __, ___) => swallow),
            ),
          ),
        ),
      ));
      // 76 logical px on a 3x screen, against a 1024px source: 4 MB -> 83 KB.
      expect(cacheWidthIn(tester), 228);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a photo sized only by its layout is measured, not guessed',
        (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 110,
                height: 110,
                child:
                    NetImage('https://x.test/b.png', errorBuilder: (_, __, ___) => swallow),
              ),
            ),
          ),
        ),
      ));
      // A portfolio tile is sized by the grid, not by a literal in the widget,
      // so the measurement has to come off the real constraints — a hardcoded
      // number here would go stale the first time the grid changed.
      expect(cacheWidthIn(tester), 220);
    });

    testWidgets('an unbounded box decodes at full resolution', (tester) async {
      // The fullscreen chat viewer: no ResizeImage at all, because capping it
      // would defeat the only reason that screen exists.
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: UnconstrainedBox(
                child: NetImage('https://x.test/c.png',
                    errorBuilder: (_, __, ___) => swallow),
              ),
            ),
          ),
        ),
      ));
      expect(cacheWidthIn(tester), isNull);
    });

    testWidgets('a broken photo still reaches the caller fallback',
        (tester) async {
      // The fallback is the user's only cue that a photo is missing, so it must
      // survive the retype: narrowing the decode must not narrow the errors.
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3),
        child: MaterialApp(
          home: Scaffold(
            body: NetImage(
              'https://x.test/boom.png',
              width: 76,
              errorBuilder: (_, __, ___) => const Text('fallback'),
            ),
          ),
        ),
      ));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.errorBuilder, isNotNull);
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 228);
    });
  });
}
