// `chat_screen.dart` — the thread banner's count pip, the last one off-token.
//
// The previous slice found two count pips in one inbox row's trailing column
// drawn at two numeral sizes: 11 dp (`fsBadge`) over 12.5 dp (`fsCaption`),
// 19.2 dp and 21.0 dp as capsules, stacked directly on each other. It fixed
// both by moving them onto `AppTheme.pipNumeral` / `pipPad` / `pipMinW`.
//
// This file is the follow-through, and the reason the sweep found it one slice
// late is the interesting part: **the thread banner's pip is the same control,
// written a third time, in a different file, with the same defect.** Same
// `rPill`, same `minWidth: 24` — byte-identical to the box the previous slice
// measured — and `fsCaption` for the numeral, so the app had two capsules of
// 21.0 dp and two of 19.2 dp, and nothing anywhere compared them.
//
// Why no existing guard could see it, which is the whole reason for a file:
//   * **R4** counts off-grid literals inside `EdgeInsets` constructors. The
//     `vertical: 3` here was counted; `pipNumeral`'s predecessor `fsCaption`
//     never counted once, because a `fontSize` is not an `EdgeInsets`. And the
//     counted literal goes green the instant it becomes an identifier, so the
//     counter's own decrement was reporting a fix that did not touch the glyph.
//   * `test/chat_list_pip_test.dart` compares the two pips **against each
//     other, in one screen**. This pip is on the *thread* screen, so there is
//     never a second pip in the same tree to disagree with it — a
//     same-component comparison cannot reach across a screen boundary.
//   * `test/pill_inset_test.dart` owns the *word* pills (`pillPad`, 10 x 6),
//     not the count pips. It cannot see this either, by construction.
//
// So the assertion cannot be "the other pip" — there is no other pip here. It
// is the numeral against [AppTheme.pipNumeral] itself, which is the token the
// whole app's counts are named by, and the capsule's measured height, because
// height is the quantity that actually moved (21.0 -> 19.2 dp).
//
// The two harness traps, both paid for on the first draft:
//   * **The count only draws above one.** `if (_unresolved.length > 1)` — a
//     single unresolved message is described by the sentence beside it. So a
//     naive boot finds no pip at all, and every assertion here would compare
//     nothing. The queue is loaded with three unconfirmed records and the
//     thread is put into the state that produces them (the read fails after
//     the composer has been used), exactly as `chat_recheck_shot_test.dart`
//     does for the same banner.
//   * **Locate the pip by its own `minWidth`, never by its text.** The banner
//     carries `«رسائل غير مرسلة»`, `«تحقّق»` and the digits themselves; `find
//     .text('3')` would also match a message body. `minWidth == pipMinW` is
//     the one property of this box that is a token and therefore unique to it.
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
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

/// The pip capsule: the only box on this screen constrained to [AppTheme.pipMinW].
Finder _capsule() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints != null &&
          w.constraints!.minWidth == AppTheme.pipMinW,
      description: 'the count pip capsule (pipMinW wide)',
    );

/// The numeral inside [_capsule].
Finder _glyph() => find.descendant(of: _capsule(), matching: find.byType(Text));

double _glyphSize(WidgetTester tester) =>
    tester.widget<Text>(_glyph()).style?.fontSize ?? double.nan;

/// Boots the thread in the one state that draws the banner's pip: three
/// unconfirmed records and a re-read that cannot answer.
Future<void> _pumpPending(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});

  var reads = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return http.Response(
            jsonEncode(<String, Object?>{'token': 'tok', 'user': _me}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.endsWith('/api/unread')) {
        return http.Response('0', 200,
            headers: {'content-type': 'application/json'});
      }
      if (p.startsWith('/api/messages/')) {
        if (req.method == 'GET') {
          reads++;
          // The thread cannot be re-read: the phone is offline, which is the
          // state the queued pip exists to describe.
          if (reads > 1) throw http.ClientException('no route to host');
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    }),
  );

  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

  final outbox = ChatOutbox(store: MemoryOutboxStore());
  for (final t in const ['الطابق الأول', 'الطابق الثاني', 'الطابق الثالث']) {
    await outbox.add(
        conversationId: 5, text: t, uncertain: SendState.unconfirmed);
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
      home: ChatScreen(
        conversationId: 5,
        otherUserId: 31,
        repo: Repository(api),
        outbox: outbox,
      ),
    ),
  ));
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('the thread banner pip is the app count pip', () {
    testWidgets('the pip is drawn, or nothing below is measuring anything',
        (tester) async {
      await _pumpPending(tester);
      expect(find.text('تحقّق'), findsOneWidget,
          reason: 'the banner with the unresolved count is the state under '
              'test; without it every assertion here compares nothing');
      expect(_capsule(), findsOneWidget,
          reason: 'the pip is the only box on this screen at pipMinW');
      expect(_glyph(), findsOneWidget);
    });

    testWidgets('the numeral is the app count numeral', (tester) async {
      await _pumpPending(tester);
      final size = _glyphSize(tester);
      expect(size, AppTheme.pipNumeral,
          reason: 'a count is drawn at one size in this app: the tab bar, the '
              'bell, and the two pips in an inbox row are all '
              '[AppTheme.pipNumeral]. This one measured ${size}dp against '
              'their ${AppTheme.pipNumeral}dp — the same box, 1.5 dp of glyph '
              'difference inside an inset that is 3 dp on each side.');
    });

    testWidgets('the capsule is the app pip height, measured off layout',
        (tester) async {
      await _pumpPending(tester);
      // Padding is [pipPad] (3 top, 3 bottom) and the line factor is 1.2, so
      // height is the Text's own line box plus 6, and nothing else. This is the
      // quantity that actually moved: **21.00 dp at fsCaption, 19.00 dp at
      // pipNumeral**, both measured off this tree.
      //
      // **19.00, not `11 * 1.2 + 6 = 19.2`.** The first draft computed the
      // expectation as `fontSize * height + padding` and asserted 19.2, and
      // the fixed build failed it at 19.0 — because a Text's line box is
      // snapped to whole logical pixels, so 13.2 of line box lays out as 13.
      // The arithmetic was the wrong instrument, not the fix; the red-before-
      // green proof above had already separated the two cases cleanly (21.00
      // reverted, 19.00 restored). So the constant below is the measured one,
      // in the same spirit as the sampled `#E7E7E9` wash in
      // `chat_recheck_shot_test.dart`: a number read off the capture rather
      // than chosen to make an assertion pass.
      final h = tester.getRect(_capsule()).height;
      const measured = 19.0;
      expect(h, closeTo(measured, 0.01),
          reason: 'the capsule measures ${h.toStringAsFixed(2)}dp against '
              '${measured.toStringAsFixed(2)}dp. Two pills of two sizes is what '
              'the previous slice found in an inbox row, and this is the same '
              'pair one screen over: the tab bar and the bell carry 19 dp '
              'pips, and this one carried 21.');
    });

    testWidgets('the numeral sits centred in its own capsule', (tester) async {
      await _pumpPending(tester);
      final cap = tester.getRect(_capsule());
      final glyph = tester.getRect(_glyph());
      final above = glyph.top - cap.top;
      final below = cap.bottom - glyph.bottom;
      expect((above - below).abs(), lessThan(1.0),
          reason: '${above.toStringAsFixed(2)}dp above vs '
              '${below.toStringAsFixed(2)}dp below — a numeral drawn a size '
              'too big sits visibly high inside a capsule whose box still '
              'lines up with its neighbours');
    });
  });
}
