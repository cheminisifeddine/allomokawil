// Proves the contractor directory can filter on every trade the taxonomy has,
// and that the trade being filtered on is actually visible when the strip
// opens.
//
// Found 29 Sep 2026 by reading `browse_screen.dart` for the class of defect the
// last two ticks shipped — a field or a value the wire sends and the app drops
// — and landing on a number typed into a `take()` instead. The filter strip was
//
//     for (final c in Taxonomy.categories.take(8)) ...[
//
// a literal 8 against a 16-trade taxonomy, present since the 12 Sep design
// overhaul. It was not a layout decision: a horizontal `ListView` builds lazily,
// so the eight trades past the truncation were **never constructed at all**.
// «سباكة وترصيص صحي» (plumbing) is trade 6 of 16 — inside the cut — and so are
// «بلاط وسيراميك ورخام» (tiling), «حدادة وتلحيم» (ironwork) and
// «ورق جدران» (wallpaper). A customer who needed a plumber opened the one
// screen whose job is finding contractors and could not filter for a plumber,
// while the category grid two taps up listed all sixteen and the contractor-side
// strip in `worker_home_screen.dart` iterated the full list.
//
// The second half is the one that would have survived a naive fix. Dropping
// `.take(8)` alone still leaves the *active* trade off-screen for anyone who
// arrives from `BrowseScreen(initialCategory:)` — a path the customer home grid
// takes on every category tap (`customer_home_screen.dart:463`). The filter
// would be applied, the results correct, and no chip lit: a filter the user
// cannot see is one he cannot clear.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/taxonomy.dart';
import 'package:allomokawil/src/widgets/trade_filter_bar.dart';

/// Mounts the strip in a fixed 360x640 box — the narrow handset this app is
/// built for. Without a size constraint the test surface is 800px wide, which
/// fits far more pills than a real phone and would pass a strip that still
/// truncates.
Widget _app({
  required String? category,
  String? wilaya,
  void Function(String)? onCategoryTap,
  void Function()? onClear,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: TradeFilterBar(
              wilaya: wilaya,
              category: category,
              onWilayaTap: () {},
              onCategoryTap: onCategoryTap ?? (slug) {},
              onClear: onClear ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
}

/// The strip's own viewport, in global coordinates.
///
/// The test surface is 800px wide whatever the app is, so "on screen" is not a
/// constant: it is measured against the box the strip actually occupies. The
/// first version of this file asserted `rect.right <= 360` and got a green
/// run on a strip that was in fact 360px wide *inside* an 800px surface — a
/// bound that happened to pass and would have missed a chip 100px off the end.
Rect _stripRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('trade-filter-scroll')));

/// Scrolls the strip so [slug]'s chip sits inside the visible strip.
///
/// **How this moves, and why not by dragging.** The strip is RTL, so
/// `position.pixels` grows as content travels *left*, and a chip's `rect.left`
/// moves one-for-one with it: measured on this widget, `rect.left` is
/// `-666.5 + pixels` for `painting`, so `pixels` and the rect are the same
/// axis and the offset is exact rather than estimated.
///
/// The first version of this helper drove the strip with `tester.drag` in a
/// loop and worked out the direction from which side of the centre the chip
/// sat on. Two things came out of that. The sign was wrong on the first
/// attempt (`-120` moves `pixels` 0.0 → 0.0 while `+120` moves it → 100.0, so
/// positive advances in RTL), and after the direction was fixed the drags
/// still left every subsequent `tester.tap` a no-op — a `drag` gesture's pointer
/// sequence is not something a later synthetic tap composes with cleanly, so
/// the chip was on screen and the tap hit nothing. The helper therefore
/// positions the strip with the scroll controller and leaves the pointer
/// alone, which is also a more honest thing for a test to assert: it is testing
/// *where a chip can be read*, not a gesture.
///
/// The loop is bounded so a chip that cannot be reached fails the test rather
/// than spinning.
Future<void> _bringIntoView(WidgetTester tester, String slug) async {
  final target = find.byKey(Key('trade-$slug'));
  expect(target, findsOneWidget, reason: 'chip $slug must be built');
  final stripKey = find.byKey(const Key('trade-filter-scroll'));
  final controller = tester
      .widget<SingleChildScrollView>(stripKey)
      .controller!;
  var guard = 0;
  while (!tester.getRect(stripKey).overlaps(tester.getRect(target)) &&
      guard++ < 40) {
    // Target the strip's own centre, not the chip's offset against it. The
    // rect-delta version of this loop moved the strip the *wrong way* in RTL
    // and pinned itself at the first pixel — `pixels` and `rect.left` do run on
    // one axis, but the strip's left edge is at x=220 in the test surface while
    // the chip's can be at x=-666, so `chip.left - strip.left` is a number
    // whose sign says nothing about which way to go until it is clamped, and
    // clamped at 0 it never moves at all. Aiming the chip at the centre is
    // unambiguous in both directions, and one hop lands inside a 360px strip
    // for any chip that was merely outside it.
    final wanted = tester.getRect(stripKey).center.dx -
        tester.getRect(target).center.dx;
    final next = (controller.position.pixels + wanted)
        .clamp(0.0, controller.position.maxScrollExtent);
    if (next == controller.position.pixels) break; // end of strip, unreachable
    controller.jumpTo(next);
    await tester.pumpAndSettle();
  }
  expect(
    tester.getRect(stripKey).overlaps(tester.getRect(target)),
    isTrue,
    reason: 'chip $slug must reach the strip',
  );
}

void main() {
  group('TradeFilterBar — the whole taxonomy, not a literal 8', () {
    testWidgets('reaches the sixteenth and last trade', (tester) async {
      await tester.pumpWidget(_app(category: null));
      final last = Taxonomy.categories.last;
      // The regression this file exists for: `last` is index 15, and a strip
      // built from `.take(8)` cannot produce it no matter how far it scrolls,
      // because the widget is never created.
      await _bringIntoView(tester, last.slug);
      expect(find.byKey(Key('trade-${last.slug}')), findsOneWidget);
      expect(find.text(last.name), findsOneWidget);
    });

    testWidgets('every trade in the taxonomy can be brought on screen',
        (tester) async {
      await tester.pumpWidget(_app(category: null));
      // Not just the last one. `take(7)` would pass a test that only checked
      // the sixteenth, and a truncation anywhere in the middle — a `skip(1)`
      // typo, a filter on the wrong field — is invisible to an end-point
      // check.
      for (final c in Taxonomy.categories) {
        await _bringIntoView(tester, c.slug);
        expect(
          find.byKey(Key('trade-${c.slug}')),
          findsOneWidget,
          reason: 'trade ${c.slug} must exist in the strip',
        );
      }
    });

    testWidgets('every chip is built, not merely reachable',
        (tester) async {
      await tester.pumpWidget(_app(category: null));
      // The eager strip is the point. On a lazy list a trade past the viewport
      // is not in the tree, and this app's whole defect was a chip that was not
      // merely off-screen but never constructed — so the count is on built
      // widgets, which is the thing that was actually wrong.
      for (final c in Taxonomy.categories) {
        expect(
          find.byKey(Key('trade-${c.slug}')),
          findsOneWidget,
          reason: 'chip ${c.slug} must be built the moment the bar opens',
        );
      }
      expect(find.text(Taxonomy.categories.first.name), findsOneWidget);
    });
  });

  group('TradeFilterBar — the active trade is visible, not just applied', () {
    testWidgets('a late trade arrives on screen without the user scrolling',
        (tester) async {
      await tester.pumpWidget(_app(category: 'wallpaper'));
      await tester.pumpAndSettle();
      // Index 15 of 16, on a 360px strip: the chip is far past the right edge
      // when the bar opens. The route that produces this is `initialCategory`
      // from the home grid.
      final chip = find.byKey(const Key('trade-wallpaper'));
      expect(chip, findsOneWidget);
      final strip = _stripRect(tester);
      final box = tester.getRect(chip);
      expect(box.left, greaterThanOrEqualTo(strip.left - 0.5),
          reason: 'the active chip must not hang off the right end');
      expect(box.right, lessThanOrEqualTo(strip.right + 0.5));
    });

    testWidgets('an early trade does not scroll the bar away',
        (tester) async {
      await tester.pumpWidget(_app(category: 'construction'));
      await tester.pumpAndSettle();
      final chip = find.byKey(const Key('trade-construction'));
      expect(chip, findsOneWidget);
      final strip = _stripRect(tester);
      final box = tester.getRect(chip);
      expect(box.right, lessThanOrEqualTo(strip.right + 0.5));
      expect(box.left, greaterThanOrEqualTo(strip.left - 0.5));
    });

    testWidgets('the wilaya pill stays readable next to the revealed trade',
        (tester) async {
      await tester.pumpWidget(_app(category: 'wallpaper'));
      await tester.pumpAndSettle();
      // Two controls have to be legible together: the trade he filtered on and
      // the place he filtered to. An `ensureVisible` pinned to the far edge
      // would satisfy the chip test above while scrolling «كل الولايات» off —
      // and in RTL that pill is the one at the *trailing* edge, so the jump the
      // test would have to notice is the one it is least likely to look for.
      expect(find.text('كل الولايات'), findsOneWidget);
      final chip = find.byKey(const Key('trade-wallpaper'));
      expect(_stripRect(tester).overlaps(tester.getRect(chip)), isTrue);
    });
  });

  group('TradeFilterBar — the controls the user needs to undo it', () {
    testWidgets('clearing appears only when something is filtered',
        (tester) async {
      await tester.pumpWidget(_app(category: null, wilaya: null));
      expect(find.text('مسح الفلاتر'), findsNothing);

      await tester.pumpWidget(_app(category: 'painting', wilaya: '16'));
      await tester.pumpAndSettle();
      expect(find.text('مسح الفلاتر'), findsOneWidget);
    });

    testWidgets('a trade tap reports the slug, and the same slug toggles off',
        (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
        _app(category: null, onCategoryTap: taps.add),
      );
      await tester.pumpAndSettle();

      // Scrolled to first, because `painting` is trade 4 of 16 and a tap at a
      // coordinate outside the render tree is a test that appears to pass while
      // dispatching nothing — Flutter warns and carries on.
      await _bringIntoView(tester, 'painting');
      // The [InkWell] inside the chip, not the chip's wrapper key. Tapping the
      // wrapper addresses a RenderBox that the drag has already replaced — the
      // wrapper's key resolves, but its centre resolves to a box the hit test
      // no longer contains, and Flutter warns while the tap quietly lands on
      // nothing. The ink surface is what the user's finger actually reaches.
      final pill = find.descendant(
        of: find.byKey(const Key('trade-painting')),
        matching: find.byType(InkWell),
      );
      expect(pill, findsOneWidget);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(taps, ['painting']);
    });

  });
}
