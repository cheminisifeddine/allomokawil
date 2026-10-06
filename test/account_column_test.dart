// The account tab's column and its rows, pinned.
//
// `profile_screen.dart` carried 8 off-grid literals — the second-biggest stack
// left in the 8pt sweep — and like the last four slices the count was the least
// interesting part. **All eight were reachable by three `EdgeInsets` calls**,
// and each call hid a different thing R4 cannot see:
//
//   1. `ProfileScreen` and `_GuestAccountScreen` are **the same screen in two
//      states** — the signed-out visitor's tab and the signed-in contractor's,
//      behind the *same* AppBar. They were both at top 14 while every other tab
//      in the shell sits at `pagePad`'s 8. Sweeping one alone makes the
//      account tab's first card jump 6 dp the instant a man signs in, and the
//      man who signed in is the only one who saw both frames.
//   2. `_SettingsRow`'s inset sits inside `AppCard(padding: EdgeInsets.zero)`
//      — ten of them on this screen — so that inset **is** the card inset, and
//      it was 14 while `AppTheme.cardPad` is 16. Three numbers in one column,
//      all agreeing with each other, which is exactly why the disagreement
//      with the rest of the app went unnoticed. R4 skips identifiers by
//      design, so the moment a literal becomes `AppTheme.cardPad` it stops
//      being counted AND stops being wrong: the ratchet cannot distinguish a
//      fixed number from a renamed one.
//   3. `_RowDivider`'s `indent: 70` is `14 + 44 + 12` — the row pad, the icon
//      bubble, and the gap — transcribed and never mentioned again. Move the
//      row pad onto the ladder without moving this and the hairline that
//      separates the account rows starts 2 dp short of the text it lines up
//      under. Nothing measures the divider; it is a `Divider`, not an inset.
//
// So R4's 68 -> 60 understates this slice badly. The three numbers below are
// the ones that were actually wrong, and none of them is a pixel test's job:
// a pixel diff on this screen would measure font antialiasing noise, which is
// what killed a pixel-diff approach two slices ago.
//
// The measurement traps are inherited from `worker_profile_column_test.dart`
// and both fire here:
//   * a `ListView` hands its `padding` to an internal `SliverPadding`, so
//     `ListView.padding` is null and the naive read answers 0.0 — and passing
//     for any inset at all. The signed-in column is a list.
//   * a `Padding` lays out at its parent's full width, so its own rect is the
//     **outer** edge; the inset is `rect + padding`, never `rect`.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/profile_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

/// The signed-in contractor. `type: 'worker'` is what puts the «ملفي المهني»
/// block on the screen at all, so a customer payload would leave the three
/// worker cards unbuilt and the column assertions would pass for the wrong
/// reason.
Map<String, Object?> _user() => <String, Object?>{
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': 'باب الزوار',
      'created_at': '2026-09-11 20:00:00',
    };

Map<String, Object?> _catalogue() => <String, Object?>{
      'currency': 'DZD',
      'note_ar': 'الدفع مسبق',
      'renew_note_ar': 'ادفع مسبقاً',
      'auto_renew': 0,
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': null,
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

ApiClient _api() => ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object?>{'token': 'tok', 'user': _user()});
        }
        if (p.endsWith('/api/mobile/subscription')) return _json(_catalogue());
        if (p.endsWith('/api/unread')) return _json(0);
        return _json(<Object?>[]);
      }),
    );

/// Signs in unless [signedOut], and mounts the real screen.
///
/// A guest is `auth.user == null` — the honest way to get one is to never
/// sign in. A first draft of this file passed a `guest:` flag to `AppScope`,
/// which has no such parameter, and every assertion would have passed against
/// the wrong tree.
Future<AuthState> _boot(WidgetTester tester,
    {required bool signedOut}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthState(_api());
  await auth.restore();
  if (signedOut) {
    expect(auth.user, isNull,
        reason: 'the "guest" screen was not a guest; this file would be '
            'asserting the signed-in tree twice');
  } else {
    await auth.login(phone: '0773000000', password: 'secret123');
    expect(auth.user, isNotNull, reason: 'the account tab stayed in guest mode');
  }

  await tester.pumpWidget(AppScope(
    api: _api(),
    auth: auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const ProfileScreen(),
    ),
  ));
  // Bounded, never pumpAndSettle: the subscription row ages itself once a
  // minute, so a settle waits out the timeout and reports a failure that is
  // not this file's.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return auth;
}

/// The x where a list's **rows** start — `SliverPadding`, not `ListView.padding`
/// (which is null and answers 0.0, passing for any inset).
double _rowsLeft(WidgetTester tester, Finder list) {
  final pads = tester
      .widgetList<SliverPadding>(find.descendant(
          of: list, matching: find.byType(SliverPadding)))
      .map((e) => e.padding.resolve(TextDirection.rtl).left)
      .where((l) => l > 0);
  return tester.renderObject<RenderBox>(list).localToGlobal(Offset.zero).dx +
      (pads.isEmpty ? 0.0 : pads.first);
}

double _rectLeft(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero).dx;

/// The x of a box's **start** edge, which in this app's RTL is its RIGHT edge.
/// Every inset here is measured from the start edge, so measuring `left` puts
/// the arithmetic 60 dp out and the assertion fails for a reason that has
/// nothing to do with the seam.
double _startEdge(WidgetTester tester, Finder f) {
  final b = tester.renderObject<RenderBox>(f);
  return b.localToGlobal(Offset.zero).dx + b.size.width;
}

/// The gap the settings row declares after its icon bubble.
///
/// Not every `SizedBox` under [row]: an `Icon` builds its own 22x22 box inside
/// itself, and the title/value stack declares a 3 dp vertical gap below it. A
/// descendant scan finds all three and a first draft of this test summed the
/// icon's. So the bubble's own boxes are subtracted — what is left is the gap
/// between the bubble and the text, which is the number the hairline is cut to.
List<double> _rowGapWidths(WidgetTester tester, Finder row, Finder bubble) {
  final inside = find.descendant(of: bubble, matching: find.byType(SizedBox));
  final out = <double>[];
  for (final e in find
      .descendant(of: row, matching: find.byType(SizedBox))
      .evaluate()) {
    if (inside.evaluate().contains(e)) continue;
    final w = (e.widget as SizedBox).width;
    if (w != null && w > 0) out.add(w);
  }
  return out;
}

double _rectTop(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero).dy;

/// The account-details card: the first one that **holds settings rows**, found
/// by what it contains rather than by position, so a row added above it does
/// not silently re-point this at a different card.
Finder _rowCard(WidgetTester tester) {
  final cards = find.byType(AppCard);
  for (final e in cards.evaluate()) {
    final f = find.byWidget(e.widget);
    if (find.descendant(of: f, matching: find.byType(IconBubble))
        .evaluate()
        .isNotEmpty) {
      return f;
    }
  }
  throw StateError('no settings card on the account tab');
}

void main() {
  group('the account tab is ONE screen in TWO states, on ONE column', () {
    test('the two page columns are the same token', () {
      // Asserted as a **value**, so a screen that merely agrees with another
      // literal cannot satisfy it. `gutter` is 18 and is deliberately off the
      // 4 dp grid — it is a page margin, not a component gap — which is exactly
      // why it is the one number R4 will never count.
      expect(AppTheme.gutter, 18.0);
      expect(AppTheme.pagePad.resolve(TextDirection.rtl).left, AppTheme.gutter);
      expect(AppTheme.pagePad.resolve(TextDirection.rtl).top, AppTheme.s8);
    });

    testWidgets('signed in: the rows start on the gutter, not on a literal',
        (tester) async {
      await _boot(tester, signedOut: false);
      final list = find.byType(ListView).first;
      // Asserted against the token, and read off the sliver the list actually
      // built — so it holds for a screen that spells the token and for one that
      // re-types 18. R4 cannot tell those apart; this one does not need to.
      expect(_rowsLeft(tester, list), AppTheme.gutter);
    });

    testWidgets('the first card does not move when a man signs in',
        (tester) async {
      // The load-bearing one, and the reason this file exists. It renders BOTH
      // states and compares them inside the SAME test: two separate tests would
      // each be green while the two columns sat 6 dp apart, because each would
      // only ever compare its own state against a constant.
      //
      // It compares the FIRST card of each state, which is the right pair — the
      // visitor's «زائر» identity card and the contractor's name card, both at
      // the top of the same page column behind the same AppBar. A first draft
      // compared the guest's first card against the contractor's «معرض أعمالي»
      // card, which is the fourth thing down the list, and went red on 68 vs
      // 469 — a comparison that says nothing about the column at all.
      await _boot(tester, signedOut: true);
      expect(find.byType(AppCard), findsWidgets,
          reason: 'the visitor state built no card');
      final guestTop = _rectTop(tester, find.byType(AppCard).first);
      final guestLeft = _rectLeft(tester, find.byType(AppCard).first);
      expect(guestLeft, AppTheme.gutter);

      // Re-mount as the signed-in contractor. `pumpWidget` replaces the tree
      // outright, so this is the visitor's frame measured, then the man's —
      // not two screens on screen at once.
      await _boot(tester, signedOut: false);
      expect(find.text('معلومات الحساب'), findsOneWidget,
          reason: 'the account-details card is missing, so the card being '
              'compared is not the one the sweep moved');
      final signedInTop = _rectTop(tester, find.byType(AppCard).first);

      expect(signedInTop, moreOrLessEquals(guestTop, epsilon: 0.01),
          reason: 'the account tab first card moved when a man signed in: '
              'guest $guestTop, signed-in $signedInTop. Same AppBar, same page '
              'column — these two frames are one column in two states.');
    });

    testWidgets('the account rows sit on the app-wide card inset',
        (tester) async {
      await _boot(tester, signedOut: false);
      // Measured, not hunted: the row inset is the distance from the card's own
      // edge to the icon bubble it holds, because the card is
      // `padding: EdgeInsets.zero` and the row's inset IS the card's inset.
      // Ten of those cards on this screen, so this is the number that decides
      // whether the account rows are 2 dp tighter than every other card in the
      // app. A first draft picked the first symmetric Padding it could find and
      // read a StatusPill's 10 off it.
      final card = _rowCard(tester);
      final bubble = find.descendant(
          of: card, matching: find.byType(IconBubble)).first;
      // Plus the recipe's own 1 dp hairline, because this is measured from the
      // card's OUTER edge and the border sits between the edge and the content.
      // That is not a fudge: the first draft of this assertion read 17 and
      // declared the screen wrong when the screen was right, which is the one
      // way a geometry guard becomes a lie and gets switched off.
      final inset = _startEdge(tester, card) - _startEdge(tester, bubble);

      expect(inset,
          AppTheme.cardPad.resolve(TextDirection.rtl).left +
              AppTheme.cardLineWidth,
          reason: 'the row inset IS the card inset here, so it should be the '
              'recipe inset like every other card, not a column of its own');
    });

    testWidgets('the hairline starts where the text starts', (tester) async {
      await _boot(tester, signedOut: false);
      expect(find.byType(Divider), findsWidgets,
          reason: 'this contractor has a wilaya AND a commune, so two dividers '
              'are built; none means the seam below was never measured');

      final card = _rowCard(tester);
      final bubble = find.descendant(
          of: card, matching: find.byType(IconBubble)).first;

      // Measured from the row's own layout boxes, NOT from the glyph box of the
      // title text. A first draft measured the text and came out 1 dp out: a
      // `Text`'s paragraph box is the advance width rounded up to whole
      // pixels, so the last glyph's box sits up to 1 dp inside the layout edge
      // — a font-metric artefact with nothing to do with the seam, and one that
      // would have made this test red on a correct screen.
      //
      // So: the distance from the card's start edge to the icon bubble's start
      // edge (that is the card inset + the bubble, both rendered), plus the gap
      // the row declares after it (read off the row's own `SizedBox`). Their sum
      // is the text column, and that is what the hairline must be cut to.
      final row = find.ancestor(of: bubble, matching: find.byType(Row)).first;
      final gaps = _rowGapWidths(tester, row, bubble);
      expect(gaps, hasLength(1),
          reason: 'the settings row should declare exactly one horizontal gap; '
              'found $gaps, so the sum below is not measuring one thing');

      final indent = tester
          .widgetList<Divider>(find.byType(Divider))
          .map((d) => d.indent)
          .firstWhere((i) => i != null);
      final toBubble = _startEdge(tester, card) - _startEdge(tester, bubble);
      final bubbleW = tester.renderObject<RenderBox>(bubble).size.width;

      // `toBubble` is measured from the card's OUTER edge, so it carries the
      // recipe's 1 dp hairline; a `Divider`'s `indent` is measured from the
      // card's inner edge, which is one border-width inside. That single dp is
      // the whole difference between this summing to 73 and it being right —
      // and it is why this assertion is written as rendered geometry rather
      // than as `rowPad + 44 + 12`, which would be a second hand-typed copy of
      // the same sum and would drift from this one silently.
      final textColumn = toBubble - AppTheme.cardLineWidth + bubbleW +
          gaps.single;

      expect(indent, moreOrLessEquals(textColumn, epsilon: 0.01),
          reason: 'the hairline between two account rows is cut to start at '
              'the text column, and that column is the card inset + the icon '
              'bubble + the gap after it. It was written down as the literal '
              '70, which is the sum for the OLD card inset — so sweeping the '
              'pad alone leaves this hairline pointing between the glyphs '
              'instead of at them, and nothing else in the app notices.');
    });
  });
}
