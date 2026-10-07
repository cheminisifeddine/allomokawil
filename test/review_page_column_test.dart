// The review screen called its own local variable `pagePad`.
//
// That is the whole defect, and neither of the app's two spacing guards could
// see it:
//
//   * **R4** (`card_recipe_test.dart`) counts off-grid numbers inside
//     `EdgeInsets` literals. `EdgeInsets.fromLTRB(pagePad, 14, pagePad, 28)`
//     contains exactly one literal, `14`, which is on-grid — so R4 saw a
//     compliant screen and its count never moved.
//   * **R5** is the census for hand-typed page columns, and it matches **four
//     plain numbers**. Two of the four edges here were the identifier `pagePad`,
//     so R5 skipped the site for the same reason R4 did.
//
// The column it actually drew was `L/R 20, T 14, B 28` on a phone wide enough
// and `L/R 8, T 14, B 28` below that, while the house token is
// `fromLTRB(gutter, s8, gutter, s28)` = `18/8/18/28`. So it agreed with the
// house column on the bottom edge only, and disagreed on three — while being
// named as if it were the house column. A reader auditing this screen would
// read `pagePad` and conclude the token was in use.
//
// What is pinned here, in order of how much it is worth:
//
//  1. **No local may shadow a house inset token's name.** That is the
//     structural hole, and it outlives this file: a shadow is invisible to a
//     literal census *by construction*, because the whole point of the shadow
//     is that the value is spelled as a name somewhere else. This is the one
//     check that would have caught it on the day it was written.
//  2. **The column is the house column**, on a wide phone, read off the
//     rendered tree and compared edge by edge rather than as a literal.
//  3. **The narrow branch is load-bearing and lands where the geometry says**,
//     recomputed from the tokens instead of repeating `318`, so if `gutter`
//     or `tapMin` moves the assertion moves with them and turns red instead of
//     quietly blessing the old number.
//
// Trap, from the files this borrows from: a `ListView` hands its padding to an
// internal `SliverPadding` and its own `padding` field can be **null** — a
// naive read answers 0.0 and passes for any inset whatsoever. That is the
// exact trap `worker_profile_column_test.dart` documents, and it is why these
// read the `SliverPadding` when the widget's own field is null.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/review/review_screen.dart';

/// A repository that answers nothing interesting — the review form reads no
/// data before it draws, so an empty list is the whole fake.
Repository _repo() => Repository(ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async => http.Response('[]', 200,
          headers: {'content-type': 'application/json'})),
    ));

/// The column the screen actually drew, in logical pixels, read off the
/// viewport's `SliverPadding` rather than `ListView.padding` (see the header).
EdgeInsets drawnColumn(WidgetTester tester) => tester
    .widget<SliverPadding>(find.byType(SliverPadding))
    .padding
    .resolve(TextDirection.rtl);

Future<void> _pumpReview(WidgetTester tester, double widthDp) async {
  tester.view.physicalSize = Size(widthDp, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    home: ReviewScreen(projectId: 'p-1', workerId: 16, repo: _repo()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Where the house column stops fitting the picker: five tap targets, two
/// gutters, and the card's own border on each side. Derived, never repeated.
const double fitsColumnAt =
    AppTheme.tapMin * 5 + AppTheme.gutter * 2 + AppTheme.cardLineWidth * 2;

void main() {
  group('no screen may shadow a house inset token', () {
    test('a local named after a token is a shadow, not a use', () {
      // The names that carry an inset in this app. `pagePad` is the one this
      // defect used, and it is the most dangerous of them because it is the
      // name of a column rather than of a size: a screen that shadows it looks
      // like the screen that got it right.
      final insetTokens = <String>[
        'pagePad',
        'cardPad',
        'cardPadRail',
        'cardPadRows',
        'fieldPad',
        'pillPad',
        'gutter',
        'cardLineWidth',
      ];
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('app_theme.dart')) {
          continue;
        }
        final s = f.readAsStringSync();
        // `final pagePad = AppTheme.pagePad` would be a legitimate alias
        // (none exists today); what must never happen is a local *holding a
        // different value* under one of these names. So the declaration is
        // matched by name, then checked for a reference to the token it shadows.
        for (final m in RegExp(
                r'(?:^|\n)\s*(?:final|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=')
            .allMatches(s)) {
          final name = m.group(1)!;
          if (!insetTokens.contains(name)) continue;
          final tail = s.substring(m.end);
          final end = tail.indexOf(';');
          final init =
              (end < 0 ? tail : tail.substring(0, end)).trim();
          if (!init.contains('AppTheme.$name')) {
            offenders.add('${f.path}:'
                '${s.substring(0, m.start).split('\n').length} '
                '$name = $init');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a local named after a house inset token, holding something '
              'else, is invisible to R4 (which reads literals) and to R5 '
              '(which reads four plain numbers) — it only reads as a use of the '
              'token. Compose the column from the token, or name the local for '
              'what it actually decides:\n${offenders.join('\n')}');
    });
  });

  group('the review form opens on the house column', () {
    testWidgets('a phone wide enough for the column gets exactly pagePad',
        (tester) async {
      await _pumpReview(tester, fitsColumnAt + 74);
      expect(drawnColumn(tester), AppTheme.pagePad.resolve(TextDirection.rtl),
          reason: 'the house column is fromLTRB(gutter, s8, gutter, s28) and '
              'nothing else');
    });

    testWidgets('just below the boundary it keeps the top and bottom',
        (tester) async {
      await _pumpReview(tester, fitsColumnAt - 2);
      final drawn = drawnColumn(tester);
      // The page gives up its gutter and NOTHING else: the top and the bottom
      // are still the house edges, so the screen does not change height as it
      // changes width.
      expect(drawn.top, AppTheme.pagePad.top);
      expect(drawn.bottom, AppTheme.pagePad.bottom);
      expect(drawn.left, AppTheme.s8);
      expect(drawn.right, AppTheme.s8);
    });

    testWidgets('the narrow branch is the boundary, not a round number',
        (tester) async {
      // One below the boundary the picker does not fit; at it, it does. This
      // is the branch's whole justification, asserted as geometry so the day
      // the tokens move, this goes red instead of blessing a stale 318.
      await _pumpReview(tester, fitsColumnAt);
      expect(tester.takeException(), isNull,
          reason: 'at $fitsColumnAt dp the five targets plus the column and '
              'the card border fit exactly');
    });
  });
}
