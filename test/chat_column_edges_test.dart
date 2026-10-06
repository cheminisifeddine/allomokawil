// The four left edges of a chat thread, measured.
//
// Why this file exists. The R4 sweep in `card_recipe_test.dart` counts *text*:
// it can tell you `chat_screen.dart` stopped typing `14`, and it cannot tell
// you the four bands of the chat column still agree with each other. This file
// is the sibling of `project_new_edges_test.dart`, written after that exact
// failure: a slice moved the thread's own inset from 14 to 16 and left the two
// banners above it at 14, so R4 went **green** on a screen whose column had
// three different left edges — the strip that warns the user his messages are
// unsent was 2 dp outside the bubbles it was warning about.
//
// The lesson from the sibling is applied here too, so it is worth stating:
// **read rects, and measure the band rather than the text inside it.** The
// first cut of that file asserted on a `Text` and got 146.5 — it had found the
// heading's 19 dp icon plus its 8 dp gap and called it misalignment. The count
// pill below carries the same trap: its `Text` starts another dp in because of
// the glyph's own left bearing.
//
// The chat column is not one list. It is, top to bottom:
//   1. `_offlineStrip()`  — full-bleed band, grey, only while `_error`
//   2. the thread         — a `ListView` of `_Bubble`s
//   3. `_pendingBanner()` — full-bleed band, only while messages are unsent
//   4. `_composer()`      — the input row, always
// All four share one left edge, and 1/3/4 are `Padding`s around `Row`s whose
// *icons* carry their own insets, so the `Padding` is the thing that has the
// edge — not the icon, not the text.
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
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

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

/// One message that answers, so the thread is a real list and not a banner
/// with an empty page under it.
const _thread = <Map<String, Object>>[
  {
    'id': 900,
    'conversation_id': 5,
    'sender_id': 31,
    'content': 'السلام عليكم، أرسلت لك العرض',
    'created_at': '2026-09-11 20:20:00',
    'image_url': '',
  }
];

Rect rectOf(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero) &
    tester.renderObject<RenderBox>(f).size;

/// The x at which a band's **content** starts — not the band's own rect.
///
/// This distinction cost the first cut of this file. A `Padding` is laid out
/// at the full width of whatever holds it, so its `RenderBox` starts at the
/// *outer* edge and its padding lives inside it: the composer's `Padding` on
/// a 392 dp phone measures `left = 0.0`, and asserting on that number compares
/// the screen's left edge against itself and passes for any inset at all. The
/// first sabotage run of this test read `Expected: <16.0> Actual: <0.0>` and
/// that 0.0 was the bug: it is the band's outer edge, not the edge the eye
/// follows. The same is true of the `ListView`, whose padding is likewise
/// interior.
///
/// So the edge under test is `rect.left + padding.left` in both cases, which
/// is the number a user is actually reading.
double contentLeft(WidgetTester tester, Finder f) {
  final w = f.evaluate().first.widget;
  // `resolve` rather than a cast: `Padding.padding` is typed
  // `EdgeInsetsGeometry`, and only `EdgeInsets` carries `.left`. A `TextField`
  // inside a `MediaQuery` can hand back a directional inset, so resolving
  // against the ambient text direction is the correct read, not a cast that
  // would throw on the one input nobody typed yet.
  final pad = w is Padding
      ? w.padding.resolve(Directionality.of(
          tester.element(find.byWidget(w))))
      : null;
  return rectOf(tester, f).left + (pad?.left ?? 0);
}

/// The `Padding` that *is* the band's inset — the nearest ancestor `Padding`
/// of [inner], which is what carries the left edge on all four bands.
Finder bandOf(Finder inner) =>
    find.ancestor(of: inner, matching: find.byType(Padding)).first;

/// Boots the thread on the app's own logical size.
///
/// [messagesAnswer] is the one seam that matters: the offline strip only
/// exists while `_error` is set, and `_error` is only set when the messages
/// read fails. A single case cannot measure both states, because the strip and
/// the thread are mutually exclusive — the code path that shows the strip
/// with no queued message is the one that hides the pending banner.
Future<({ApiClient api, AuthState auth, ChatOutbox outbox})> _boot(
  WidgetTester tester, {
  required bool messagesAnswer,
  bool queueOne = true,
}) async {
  tester.view.physicalSize = const Size(392, 860) * 2.75;
  tester.view.devicePixelRatio = 2.75;
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
      if (req.url.path.startsWith('/api/messages/')) {
        if (!messagesAnswer) {
          throw http.ClientException('no route to host');
        }
        return http.Response(jsonEncode(_thread), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(<Object?>[]), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

  // One queued message, unconfirmed: that is the state where the pending
  // banner and the thread are stacked on each other, which is the whole
  // reason this file exists.
  final outbox = ChatOutbox(store: MemoryOutboxStore());
  if (queueOne) {
    await outbox.add(conversationId: 5, text: 'الطابق الأول');
  }
  return (api: api, auth: auth, outbox: outbox);
}

/// Mounts the thread and lets it settle.
Future<void> _pumpThread(
  WidgetTester tester, {
  required bool messagesAnswer,
  bool queueOne = true,
}) async {
  final b = await _boot(tester,
      messagesAnswer: messagesAnswer, queueOne: queueOne);
  await tester.pumpWidget(AppScope(
    api: b.api,
    auth: b.auth,
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
        repo: Repository(b.api),
        outbox: b.outbox,
      ),
    ),
  ));
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  group('the chat column', () {
    testWidgets('the four bands share one left edge', (tester) async {
      await _pumpThread(tester, messagesAnswer: true);

      // All three must be present, or this test is measuring one band and
      // calling it a column.
      expect(find.text('اكتب رسالة...'), findsOneWidget,
          reason: 'the composer is not on screen — nothing to compare');
      expect(find.textContaining('غير مرسلة'), findsWidgets,
          reason: 'the pending banner is not on screen, so this run proves '
              'nothing about the banner');

      // The thread's own `ListView`, its composer padding, its banner padding.
      // Three content edges, read off the widgets rather than transcribed from
      // the source, so the test fails when the code moves and not when a
      // number here is edited to match it.
      //
      // The thread is measured **through the rows, not through the `ListView`'s
      // own `padding`**, and the second version of this test got that wrong:
      // a `ListView` hands its `padding` to an internal `SliverPadding`, so
      // `ListView.padding` is null on the widget and the helper answered 0.0 —
      // a green that would have passed for any inset. A `SliverPadding`'s
      // `resolvedPadding` *is* the list's inset, so that is what is read here.
      final sliverPads = tester
          .widgetList<SliverPadding>(find.descendant(
              of: find.byType(ListView).first,
              matching: find.byType(SliverPadding)))
          .map((e) => e.padding.resolve(TextDirection.ltr).left)
          .where((l) => l > 0);
      final thread = rectOf(tester, find.byType(ListView).first).left +
          (sliverPads.isEmpty ? 0.0 : sliverPads.first);
      final composer = contentLeft(tester, bandOf(find.byType(TextField)));
      final banner =
          contentLeft(tester, bandOf(find.textContaining('غير مرسلة').first));

      // 1. Composer and thread share one edge. This is the assertion that
      //    would have caught the half-finished slice: the thread moved to 16
      //    and the composer stayed at 12, so the send button sat 4 dp inside
      //    the bubbles above it — and R4 stayed green, because both numbers
      //    had become identifiers by then.
      expect(composer, thread,
          reason: 'the composer and the thread must share the column\'s left '
              'edge; measured composer $composer against thread $thread');

      // 2. The banner is a *different* kind of band: it is full-bleed by
      //    design, so its padding is its own text inset rather than a column
      //    edge. What must hold is that its text starts where the bubbles do,
      //    which is what makes the banner read as belonging to the thread
      //    instead of floating above it.
      expect(banner, thread,
          reason: 'the pending banner\'s text must start where the bubbles '
              'start; measured banner $banner against thread $thread');

      // 3. All three on the 4 dp grid.
      for (final r in <(String, double)>[
        ('thread', thread),
        ('composer', composer),
        ('banner', banner),
      ]) {
        expect(r.$2 % 4, 0,
            reason: '${r.$1} measured content left edge ${r.$2} dp is off '
                'the 4 dp grid');
      }
    });

    // The strip is the fourth band and it needs its own state, because it is
    // **mutually exclusive** with what the first case measures: it only draws
    // while `_error` is set, and it draws *instead of* the empty-thread page.
    //
    // This case exists because of a comment that had been true for one run and
    // then quietly stopped being true. The first cut of this file asserted the
    // strip in the success case, which cannot reach it — the two sabots below
    // are the proof, not the assertion: reverting the strip's inset to 14 with
    // this case in place fails, and leaving it in the success case would have
    // shipped a file whose header promised four edges and measured three.
    testWidgets('the offline strip starts where the composer starts',
        (tester) async {
      // The read fails, so `_error` is set. One queued message is still needed
      // for the composer, which is always on screen.
      await _pumpThread(tester, messagesAnswer: false);

      expect(find.textContaining('لا يوجد اتصال'), findsOneWidget,
          reason: 'the offline strip did not draw — a failing read is the '
              'only state that produces it, so this run proves nothing');

      final composer = contentLeft(tester, bandOf(find.byType(TextField)));
      // The strip is a `Container` whose `padding` is its own inset. The icon
      // inside it carries a further inset of its own, so the icon is NOT the
      // edge — which is the sibling file's 146.5 mistake again.
      // Found by its own Arabic text and then taken to the `Padding` above it,
      // rather than by counting `Container`s. A `Container` that carries a
      // padding *builds an internal `Padding`*, so the nearest ancestor
      // `Padding` of the strip's sentence is the strip's inset itself — no
      // index to go stale when a sibling `Container` is added, which is the
      // failure mode this file already paid for once.
      final strip =
          contentLeft(tester, bandOf(find.textContaining('لا يوجد اتصال')));

      expect(strip, composer,
          reason: 'the strip that warns the user his messages are unsent must '
              'start at the same left edge as the bubbles it is warning '
              'about; measured strip $strip against composer $composer');
      expect(strip % 4, 0,
          reason: 'strip measured content left edge $strip dp is off the '
              '4 dp grid');
    });
  });
}
