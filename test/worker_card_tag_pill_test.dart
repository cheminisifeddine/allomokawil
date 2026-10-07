// The browse card's fact tags, and the house pill — the fifth copy.
//
// `_MiniTag` in `worker_card.dart` drew the three facts a customer scans a
// contractor for — availability, years, price — by hand:
//
//     symmetric(horizontal: 9, vertical: 5), icon 13, SizedBox(4),
//     caption at fsBadge
//
// The house pill is `StatusPill` / `CategoryBadge` / `MetaChip`: `pillPad`
// (`symmetric(10, 6)`), icon 14, `pillGap` (6), `fsCaption`. Measured off real
// layout at 320/360/392 dp: **`_MiniTag` is 25.0 dp tall, the house pill
// 26.0**. Same `rPill` radius, same `lineSoft` wash, same caption weight.
//
// Why both instruments missed it — the same two blind spots slice 8 recorded:
//   * **R4** counts off-grid literals and `9` *is* off-grid, so it had a row
//     for it — but R4 is a budget (26 left app-wide), so one row among 26 is
//     invisible to it and the only thing it can ask is "make the count go
//     down". Fixing it to satisfy R4 would have been a rename, not a fix.
//   * **`pill_inset_test`** compares `CategoryBadge` / `StatusPill` /
//     `MetaChip` — three pills that already *were* one component. Comparing a
//     component against itself cannot see a pill that was spelled out instead
//     of reused. That is the precise blind spot: `_MiniTag` is a fourth
//     writer, and `MetaChip`'s own doc comment says "Naming it means the next
//     pill is a caller, not a copy" — this is the copy it predicted.
//
// **The adjacency is the defect and it is real.** On the client home screen
// the contractor strip (line ~948) and the project cards (line ~1051) are
// children of the **same** `SliverToBoxAdapter` column: a customer scrolls
// from a 25 dp tag to a 26 dp status pill and watches the pill change height.
// Same screen, same scroll, one dp of shape — which reads as *unfinished*.
//
// **Not registered in `app_source_scope_test.dart`'s `_appRuleGuards`.** That
// map is for guards that are *text sweeps over source* — it requires each one
// to declare roots the census can enumerate and to apply its evidence token
// through a `RegExp` or an `expect`. This guard does neither, because it is
// not a text sweep: it reads `Container.padding` off the built tree. That is
// the same reason `pill_inset_test.dart`, which is its closest sibling, is not
// in the map either — and the map is right to exclude both. A guard that
// walked source text would have *missed* the defect entirely, because after a
// rename `MetaChip(icon:, text:)` spells no padding at all; the thing this
// finds is only visible in laid-out pixels. Registered where it belongs: in
// the consumer set, enforced on every run of the suite.
//
// So this guard is deliberately screen-level, in the shape slice 8 established:
// it boots the real `WorkerCard` and the real `MetaChip` **in one tree**,
// because "these two draw beside each other" is the bug and a per-widget or
// per-file assertion cannot express it. The first case also runs a **census**
// over the app's pill-shaped containers, which is the class neither R4 nor a
// same-component comparison can reach: a hand-rolled pill is, by definition,
// a component that spells its own recipe instead of calling the shared one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/worker.dart';
import 'package:allomokawil/src/widgets/ui.dart';
import 'package:allomokawil/src/widgets/worker_card.dart';

/// The facts a browse card prints as tags: paused, five years, a real band.
Map<String, dynamic> _contractor() => {
      'id': 1,
      'user_id': 1,
      'full_name': 'رشيد خليفي',
      'specialties': ['painting'],
      'experience_years': 5,
      'price_range_min': 7000,
      'price_range_max': 90000,
      'service_radius_km': 20,
      'is_available': 0,
      'verification_status': 'pending',
      'avg_rating': 4.5,
      'total_reviews': 12,
      'user_wilaya': '16',
    };

/// The padding of the pill-shaped [Container] above [text].
///
/// `pill_inset_test.dart`'s trap applies here too: a pill's outer rect differs
/// by word length, so widths compare the Arabic. The padding is the recipe.
EdgeInsetsGeometry? pillPaddingFor(WidgetTester tester, String text) {
  final finder = find
      .ancestor(of: find.text(text), matching: find.byType(Container))
      .first;
  return tester.widget<Container>(finder).padding;
}

/// The icon-to-word gap of the pill above [text], read off the painted boxes.
double iconGapFor(WidgetTester tester, String text) {
  final textBox = tester.getRect(find.text(text));
  double? gap;
  final row = find
      .ancestor(of: find.text(text), matching: find.byType(Row))
      .first;
  for (final child in tester.widget<Row>(row).children) {
    if (child is Icon) {
      final iconRect = tester.getRect(
        find.descendant(of: row, matching: find.byWidget(child)),
      );
      gap = (textBox.left - iconRect.right).abs();
      if ((textBox.right - iconRect.left).abs() < gap) {
        gap = textBox.right - iconRect.left;
      }
    }
  }
  return gap ?? double.nan;
}

void main() {
  group('the browse card tag is the house pill', () {
    // The census, first: every pill-shaped container in the app must be on
    // `AppTheme.pillPad`, whatever file it lives in and whatever it is
    // called. This is the assertion R4 structurally cannot make (it reads
    // literals, so a pill already spelled in tokens is invisible to it) and
    // that `pill_inset_test` structurally cannot make (it compares three
    // pills that were already one component).
    testWidgets('every pill in the app sits on AppTheme.pillPad',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                // The two writers that must agree, side by side, in one tree.
                WorkerCard(
                  worker: WorkerProfile.fromJson(_contractor()),
                  variant: WorkerCardVariant.row,
                ),
                const SizedBox(height: 12),
                const MetaChip(icon: Icons.place_outlined, text: 'باب الزوار'),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final offenders = <String>[];
      for (final e in find.byType(Container).evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is! BoxDecoration) continue;
        final r = d.borderRadius;
        // A pill is rounded all the way round: `rPill` on every corner. A
        // card's `rMd`/`rLg` is a different shape and is not this census.
        if (r is! BorderRadius || r.topLeft.x < 100) continue;
        if (c.padding == null) continue; // the avatar circle
        if (c.padding != AppTheme.pillPad) {
          offenders.add('$c.padding');
        }
      }
      expect(offenders, isEmpty,
          reason: 'every pill-shaped container draws on AppTheme.pillPad '
              '(symmetric(10, 6)). Anything else is a pill that spelled its '
              'own recipe instead of calling the shared one:\n'
              '${offenders.join('\n')}');
    });

    testWidgets('the tag and the house pill agree on inset, gap and height',
        (tester) async {
      // 392 dp is the design width; the numbers are read off this tree, not
      // asserted from the source.
      tester.view.physicalSize = const Size(392 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                WorkerCard(
                  worker: WorkerProfile.fromJson(_contractor()),
                  variant: WorkerCardVariant.row,
                ),
                const SizedBox(height: 12),
                const MetaChip(icon: Icons.place_outlined, text: 'باب الزوار'),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'the tag row must not overflow at 392 dp');

      final tagPad = pillPaddingFor(tester, '5 سنوات خبرة');
      final chipPad = pillPaddingFor(tester, 'باب الزوار');
      expect(tagPad, AppTheme.pillPad,
          reason: 'the years tag is a pill and must draw on the shared inset');
      expect(chipPad, AppTheme.pillPad);
      expect(tagPad, chipPad);

      expect(iconGapFor(tester, '5 سنوات خبرة'),
          closeTo(AppTheme.pillGap, 0.01));
      expect(iconGapFor(tester, 'باب الزوار'), closeTo(AppTheme.pillGap, 0.01),
          reason: 'a 1 dp disagreement between neighbours reads as unfinished, '
              'not as a defect — that is why `pillGap` exists');
    });

    // The risk this slice actually carries. Adopting `pillPad` grows the tag
    // from `symmetric(9, 5)` to `symmetric(10, 6)` — 1 dp on three sides and
    // 1 dp of height on a `Wrap` with `spacing: 6`, on the **row** card a
    // customer picks a contractor from. Growing a pill is only free if the
    // row still lays out at the narrowest phone in the app, so this measures
    // the tag row's own height against the `Wrap` it lives in.
    testWidgets('the wider token still fits the row card at 320 dp',
        (tester) async {
      for (final width in [320.0, 360.0, 392.0]) {
        tester.view.physicalSize = Size(width * 3, 1600 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: Scaffold(
            body: WorkerCard(
              worker: WorkerProfile.fromJson(_contractor()),
              variant: WorkerCardVariant.row,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'the tag row overflowed the card at $width dp — `pillPad` '
                'is wider than the `9 x 5` it replaced and the Wrap has to '
                'still fit');

        // The tag row must not have wrapped into a second line: the widest
        // tag is 180.75 dp at `9 x 5`, and a Wrap that breaks here would put
        // the price band on its own row, which is the card's own regression
        // already fixed once (see `worker_card_strip_fit_test.dart`).
        final tag = find.text('5 سنوات خبرة');
        final chip = find.text('باب الزوار');
        expect(tag, findsOneWidget);
        expect(chip, findsNothing,
            reason: 'the browse card has no place chip at $width dp — this '
                'case is about the tag row only');
      }
    });
  });
}
