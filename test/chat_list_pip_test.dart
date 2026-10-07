// `chat_list_screen.dart` — two count pips in one column, two numerals.
//
// The trailing column of an inbox row draws **two** count pips and nothing
// else: a grey cloud pip for messages this phone has not sent yet, and a solid
// accent pip for messages the server has not acknowledged as read. Both are
// `rPill`, both are `minWidth: 24`, both are `symmetric(horizontal: 8,
// vertical: 3)` — byte-identical boxes, painted 7 dp apart in the same column,
// stacked one above the other.
//
// **The defect.** The two boxes agreed to the byte and the two *numerals* did
// not. The queued pip's text is `AppTheme.fsBadge` (11 dp); the unread pip's
// text is `AppTheme.fsCaption` (12.5 dp). So on the one row that carries both —
// a conversation with unsent messages *and* unread ones, which is the state a
// user reaches on a flaky Algerian connection and the exact state the queued
// pip exists to warn about — the same box holds a 12.5 dp number over an 11 dp
// number. The numerals are 1.5 dp apart in size inside a box whose own vertical
// inset is 3, so the taller glyph is visibly off-centre inside its own capsule
// while the box around it lines up perfectly with the one below.
//
// Why the existing guards structurally cannot see it, which is the point:
//   * R4 counts off-grid literals inside `EdgeInsets`. Both pips are on the
//     grid — `8` and `3` are the only literals and `3` is the pill's own
//     proportion, off the ladder by design and documented as such in
//     `chat_screen.dart`. R4 was reading the *box* and blind to the glyph.
//   * `test/chat_column_edges_test.dart` measures the four bands' **left
//     edges** on the thread screen, not the numbers drawn inside them.
//   * `test/pill_inset_test.dart` compares `StatusPill` against `StatusPill`.
//     Neither of these pips is a `StatusPill`; they are hand-rolled
//     `Container`s, so a same-component comparison cannot reach them and a
//     per-file literal counter never counted the font.
//
// So this asserts the one thing none of those own: that the **two numerals in
// the same trailing column are the same size**, measured off the laid-out
// `Text` widgets in a real boot of the screen, and only in the one state where
// both pips exist at once.
//
// The measurement traps, all three paid for on the first draft:
//   * **The state has to be built, not assumed.** A row with `unreadCount: 0`
//     draws no unread pip and a row with nothing queued draws no queued pip, so
//     a naive boot finds one or zero pips and a comparison against "the other
//     one" has nothing to compare. `find.byType(Text)` on a booted inbox also
//     returns the name, the preview and the age — the pips are located by their
//     *own* box, not by guessing at text.
//   * **A bare `MaterialApp` answers the wrong numbers.** `AppTheme.light` sets
//     `toolbarHeight: 60` against the Material 3 default of 56, which moves
//     every control on the screen by 4 dp. Same trap as
//     `profile_edit_clearance_test.dart`; the theme is loaded explicitly here.
//   * **Read the glyph's box, not the capsule's.** The capsule is the `Container`
//     and its rect is the box, which both pips already agree on — asserting on
//     it proves nothing, which is exactly how the bug stayed invisible.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';

const _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 00:00:00',
};

/// One conversation carrying **both** pips: unread on the server, and a
/// message this phone still owes it. Without both, one of the two pips is not
/// on screen and the comparison has nothing on the other side.
const _convs = <Map<String, Object>>[
  {
    'id': 5,
    'customer_id': 30,
    'worker_user_id': 31,
    'project_id': '900',
    'other_user_name': 'كريم بلعيد',
    'other_user_avatar': '',
    'last_message_content': 'السلام عليكم',
    'unread_count': 3,
    'last_message_at': '2026-09-11 20:20:00',
  }
];

/// The queued pip's number is the queued count; the unread pip's is the
/// unread count. Two different numbers is the point — the assertion is on the
/// *glyphs*, never on the text.
Finder pipGlyph(WidgetTester tester, String value) =>
    find.descendant(
      of: find.byWidgetPredicate(
              (w) => w is Container && w.constraints != null &&
                  w.constraints!.minWidth == _pipMinW,
              description: 'a count pip capsule ($_pipMinW dp wide)'),
      matching: find.text(value),
    );

const double _pipMinW = AppTheme.pipMinW;

/// The capsule around [value]'s glyph — located by its own `minWidth`, which
/// is the one property of these two boxes R4 cannot see and the eye reads
/// first. [pipGlyph] finds the number; this finds the pill it sits in.
Finder _capsuleOf(WidgetTester tester, String value) => find
    .ancestor(
      of: pipGlyph(tester, value),
      matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.constraints!.minWidth == _pipMinW,
          description: 'the count pip capsule'),
    )
    .first;

/// Boots the real inbox on the one row that draws both pips.
Future<void> _pumpInbox(
  WidgetTester tester, {
  int unread = 3,
  int queued = 2,
}) async {
  tester.view.physicalSize = const Size(392, 860) * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      if (req.url.path.endsWith('/api/login')) {
        return http.Response(
          jsonEncode(<String, Object?>{'token': 'tok', 'user': _me}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.endsWith('/api/mobile/conversations')) {
        return http.Response(
          jsonEncode(<Map<String, Object>>[
            {..._convs.first, 'unread_count': unread},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode(<Object?>[]), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

  final outbox = ChatOutbox(store: MemoryOutboxStore());
  for (var i = 0; i < queued; i++) {
    await outbox.add(conversationId: 5, text: 'رسالة $i');
  }

  await tester.pumpWidget(AppScope(
    api: api,
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
      home: ChatListScreen(repo: Repository(api), outbox: outbox),
    ),
  ));
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The font size the laid-out [Text] under [f] was given.
double glyphSize(WidgetTester tester, Finder f) {
  final text = tester.widget<Text>(f);
  return text.style?.fontSize ?? double.nan;
}

void main() {
  group('the two count pips in one column', () {
    testWidgets('both pips are on screen at once, in one state', (tester) async {
      await _pumpInbox(tester);
      // Guard the guard: if the harness has not produced both pips, every
      // assertion below would pass against nothing.
      expect(pipGlyph(tester, '2'), findsOneWidget,
          reason: 'the queued pip must be drawn');
      expect(pipGlyph(tester, '3'), findsOneWidget,
          reason: 'the unread pip must be drawn');
    });

    testWidgets('both numerals are the same size', (tester) async {
      await _pumpInbox(tester);
      final queued = glyphSize(tester, pipGlyph(tester, '2'));
      final unread = glyphSize(tester, pipGlyph(tester, '3'));

      expect(queued, AppTheme.fsBadge,
          reason: 'the queued pip is a count pip and is drawn at the count '
              'pip size — this is the writer this slice left alone');
      expect(unread, queued,
          reason: 'two count pips, one column, one numeral size: the taller '
              'glyph sits visibly off-centre inside a box that lines up with '
              'the one below it (queued ${queued}dp vs unread ${unread}dp)');
    });

    testWidgets('both capsules are the same height', (tester) async {
      await _pumpInbox(tester);
      // The padding is identical (`symmetric(horizontal: 8, vertical: 3)`) and
      // the line factor is identical (`height: 1.2`), so the capsule's height
      // is `fontSize * 1.2 + 6` and **nothing else**. Two count pips in one
      // column whose boxes disagree in height are two capsules of two sizes
      // stacked on each other, and that is what a reader sees first — the
      // numbers are 1.5 dp apart in glyph size, the boxes 1.8 dp apart in
      // height, from the same padding on both sides.
      final heights = <String, double>{};
      for (final value in ['2', '3']) {
        final capsule = _capsuleOf(tester, value);
        heights[value] = tester.getRect(capsule).height;
      }
      expect(heights['3'], closeTo(heights['2']!, 0.01),
          reason: 'one column, one capsule size: the queued pip measures '
              '${heights['2']!.toStringAsFixed(2)}dp and the unread pip '
              '${heights['3']!.toStringAsFixed(2)}dp, from byte-identical '
              'padding — the only thing that can differ is the numeral');
    });

    testWidgets('each numeral is centred in its own capsule', (tester) async {
      await _pumpInbox(tester);
      // Read the glyph, not the capsule: the capsule is the box both pips
      // already agree on, and asserting on it proves nothing — which is
      // precisely how this bug stayed invisible for however long it did.
      for (final value in ['2', '3']) {
        final capRect = tester.getRect(_capsuleOf(tester, value));
        final glyphRect = tester.getRect(pipGlyph(tester, value));
        final above = glyphRect.top - capRect.top;
        final below = capRect.bottom - glyphRect.bottom;
        expect((above - below).abs(), lessThan(1.0),
            reason: 'the numeral "$value" must sit centred in its capsule: '
                '${above.toStringAsFixed(2)}dp above vs '
                '${below.toStringAsFixed(2)}dp below');
      }
    });
  });
}
