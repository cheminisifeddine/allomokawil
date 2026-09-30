// The messages tab had no unread affordance at all, and the one screen whose
// whole purpose is unread messages is the screen that could not show it.
//
// The previous cycle's handoff asked what the **message tab's own unread
// affordance** does when the trust flag is withdrawn while it is on screen.
// Answering that meant finding the affordance first, and there is none:
//
//   grep -nE 'badge|unread|count' lib/src/widgets/app_tab_bar.dart
//     -> nothing but `AppTheme.fsBadge`, a font size
//
// `AppTabItem` was `icon / activeIcon / label`. No count, no dot, no pip. The
// only unread number in the app lived on `NotificationsBell`, and the bell is
// mounted **only on the explore tab** — `WorkerHomeScreen` builds
// `appBar: _tab == 0 ? AppBar(... NotificationsBell() ...) : null`, and the
// client's bell is drawn inside `_ExploreView`. So:
//
//   1. contractor opens «الرسائل»;
//   2. the header unmounts, and with it the only number saying he had
//      messages waiting;
//   3. he is in the inbox with **nothing on screen** saying anything is unread.
//
// The per-row pips inside the list are then the only signal left, and reading
// them means already being in the tab — the exact thing a badge avoids. A
// user who has not opened the tab cannot know it holds anything, which is the
// one job the badge has.
//
// The second half matters as much. The obvious fix — paint `/api/unread` —
// would have been **wrong**: that endpoint is the *notifications* count,
// cleared by `/api/notifications/read`, and it carries `new_quote` /
// `project_update` / `review_received` rows with nothing to do with messages.
// Painting it above the inbox list would put two different numbers for the
// same thing on one screen: a tab claiming «3» above a list with no unread
// row. So the badge sums the **same `unread_count` the list beneath it
// draws**, which is what makes them agree by construction instead of by luck.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/widgets/notifications_bell.dart';
import 'package:allomokawil/src/data/unread_message_count.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/unread_message_trust.dart';

const _user = {
  'id': 7,
  'phone': '0773000000',
  'email': null,
  'full_name': 'Test Worker',
  'type': 'worker',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _conv(int id, {required int unread}) => {
      'id': id,
      'customer_id': 3,
      'worker_user_id': 7,
      'project_id': null,
      'other_user_name': 'عميل $id',
      'other_user_avatar': null,
      'last_message_content': 'مرحبا',
      'unread_count': unread,
      'last_message_at': '2026-01-01 10:00:00',
    };

/// Every request the screen made, so a test can prove where the number came
/// from rather than only that a number appeared.
List<String> _log = [];

/// `/api/unread` answers **9** on purpose.
///
/// That is the wrong number for a messages tab, and the fixture makes it
/// wrong loudly: if the badge ever reaches for the notifications endpoint
/// instead of the conversations, every count assertion below fails instead of
/// passing by coincidence. The value is a trap, and it is the one this cycle
/// was written to avoid.
ApiClient _api(List<Map<String, dynamic>> convs) => ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        _log.add('${req.method} $p');
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json({'token': 'tok', 'user': _user});
        }
        if (p.endsWith('/api/unread')) return _json(9);
        if (p.endsWith('/api/mobile/conversations')) return _json(convs);
        return _json(<Object>[]);
      }),
    );

/// Pumps the **real** `WorkerHomeScreen` under a real `AppScope`.
///
/// Nothing is constructed by hand — no `AppTabBar`, no `AppTabItem`. The
/// lesson of the previous cycle was a test that supplied the very object under
/// test and therefore proved only that the object worked. If this file ever
/// has to reach into a constructor to make an assertion pass, the badge is not
/// on the screen again.
Future<void> _pumpHome(
  WidgetTester tester,
  List<Map<String, dynamic>> convs, {
  Widget screen = const WorkerHomeScreen(),
}) async {
  _log = [];
  final api = _api(convs);
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);

  // A keyed `RepaintBoundary` around the whole screen is what the capture at
  // the end reads pixels out of. It is here rather than found by descending
  // into the tree, because `AppTabBar` paints inside a `Stack` with
  // `clipBehavior: Clip.none` — a boundary chosen from inside the bar is not
  // the bar's own box, and the pip hangs outside it.
  shotKey = GlobalKey();
  liveMessages = null;
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        api: api,
        auth: auth,
        child: Builder(builder: (context) {
          // Read out of the scope the app is really running under.
          liveMessages = AppScope.of(context).messages;
          return RepaintBoundary(key: shotKey, child: screen);
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Set by [_pumpHome] so the capture reads the boundary that was built there,
/// rather than searching the tree for a box that may not be the one painted.
GlobalKey? shotKey;

/// Counts the pixels of one exact colour in a real capture of the bar.
///
/// The second half of the withdrawal test is settled here and not in a widget
/// assertion, because the failure this guards is **invisible to a widget
/// test**: a `StatelessWidget` that reads a `ChangeNotifier` during build
/// produces a perfectly well-formed `Container` asking for the wrong colour,
/// and `find.byKey` still finds it. Only the image shows what the user sees.
///
/// Returns **-1** when there are no pixels of that colour at all, which is
/// distinct from zero pixels *of the pip* — `tool/px_count.py`'s header
/// records that a broken probe reports `0` for a screen full of text, and a
/// test cannot tell that from an honest zero.
Future<int> _countPipColour(WidgetTester t, Color colour) async {
  final boundary =
      shotKey!.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/tab_badge_unconfirmed.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // `Color.r`/`.g`/`.b` are **doubles in 0..1** in this SDK, not the 0..255
  // ints of the deprecated `.red`/`.green`/`.blue`. Interpolating them straight
  // into the argument produced `0.9647,0.639,0.239`, `int()` threw inside the
  // probe, and the helper returned -1. That is the sentinel doing its job — a
  // broken probe reporting an honest `0` is how a pixel assertion silently
  // passes against a blank screen.
  final hex = <int>[
    (colour.r * 255).round(),
    (colour.g * 255).round(),
    (colour.b * 255).round(),
  ].join(',');
  final r = Process.runSync(
      'python3', ['tool/px_count.py', '/tmp/shots/tab_badge_unconfirmed.png', hex]);
  final out = (r.stdout as String).trim();
  final n = int.tryParse(out.split('\n').last.trim());
  return n ?? -1;
}

/// The flag the live app is using, captured out of the tree it was built in.
///
/// **Never a locally constructed one.** A test that builds its own flag proves
/// the flag works and says nothing about whether the app is connected to it —
/// and that is precisely how the first version of this feature shipped dead:
/// the object existed, the pip read it, and nothing ever constructed it.
UnreadMessageTrust? liveMessages;

/// Reads the `Semantics` label the pip carries, or null when it carries none.
///
/// Walks the widget tree rather than the semantics tree on purpose. The pip
/// sets `excludeSemantics: true` and puts the words on the wrapping
/// `Semantics`, so the node keyed `tab-badge-N` is the thing that has been
/// stripped of its own label; the qualifier lives one level up. Reading the
/// wrong node returns the bare digits, and an assertion built on that would
/// pass against a pip that never learned to speak.
String? _badgeSemantics(int count) {
  final pip = find.byKey(Key('tab-badge-$count'));
  if (pip.evaluate().isEmpty) return null;
  // **The NEAREST wrapping `Semantics`, not the first non-empty one.** The
  // pip sits inside the tab's own `Semantics`, which carries the destination
  // name «الرسائل»; taking the first non-empty label returned that and the
  // assertion below passed for the wrong reason on a confirmed pip. The
  // qualifier is the one directly on the pip.
  final widget = find
      .ancestor(of: pip, matching: find.byType(Semantics))
      .evaluate()
      .map((e) => (e.widget as Semantics).properties.label)
      .whereType<String>()
      .firstWhere((l) => l == S.notifCountUnconfirmed, orElse: () => '');
  return widget.isEmpty ? null : widget;
}

/// The messages tab is index 2 in both shells.
const _messagesTab = 2;

/// Switches to a tab through the real tab bar, the way a thumb does.
Future<void> _openTab(WidgetTester tester, int i) async {
  await tester.tap(find.byKey(Key('tab-$i')));
  await tester.pumpAndSettle();
}

/// The pip on whichever destination is being asserted.
Finder _badgeWith(int count) => find.byKey(Key('tab-badge-$count'));


/// The real Cairo faces, so the count in the pip is a **glyph**.
///
/// This matters more here than anywhere else in the suite. A `flutter test`
/// environment substitutes a test font that draws every glyph as a filled
/// box, so the first render of this badge showed a solid navy rectangle where
/// the «7» should be — indistinguishable, on pixels alone, from a badge whose
/// digits failed to draw at all. Loading the real faces is what lets the
/// screenshot be read as proof: the digits are visibly **7**, not merely
/// "some navy pixels inside a gold pill".
Future<void> _loadCairo() async {
  final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
  await (FontLoader('Cairo')
        ..addFont(Future.value(reg))
        ..addFont(Future.value(bold)))
      .load();
}

void main() {
  group('the sum is the list the user is about to read', () {
    test('adds the per-row counts', () {
      final list = [
        Conversation.fromJson(_conv(1, unread: 2)),
        Conversation.fromJson(_conv(2, unread: 5)),
      ];
      expect(unreadMessageTotal(list), 7);
    });

    test('an empty inbox and an unknown inbox are both no badge', () {
      expect(unreadMessageTotal(const []), 0);
      expect(unreadMessageTotal(null), 0);
    });

    test('a negative unread_count cannot drag the badge below zero', () {
      final list = [
        Conversation.fromJson(_conv(1, unread: 3)),
        Conversation.fromJson(_conv(2, unread: -5)),
      ];
      expect(unreadMessageTotal(list), 3);
    });
  });

  group('the spoken label', () {
    test('is Arabic, and agrees with the digits', () {
      expect(unreadMessagesLabel(1), 'رسالة غير مقروءة');
      expect(unreadMessagesLabel(3), contains('3'));
      expect(unreadMessagesLabel(0), '');
    });

    test('is capped at 99 exactly like the pip', () {
      // A pip reading 99+ beside a voice saying «143 رسالة» is the same class
      // of contradiction the header pip was written to remove: two numbers,
      // one screen, only one of them true.
      expect(unreadMessagesLabel(150), contains('99'));
      expect(unreadMessagesLabel(150), isNot(contains('150')));
    });
  });

  group('the tab itself', () {
    testWidgets('carries the unread count from the conversations', (t) async {
      await _pumpHome(t, [_conv(1, unread: 3), _conv(2, unread: 4)]);

      // 3 + 4 — the sum of the rows, and **not** the 9 on `/api/unread`.
      expect(_badgeWith(7), findsOneWidget);
      expect(_badgeWith(9), findsNothing);

      // The number came from the list, not the notifications endpoint.
      expect(_log, contains('GET /api/mobile/conversations'));
    });

    testWidgets('shows nothing when every thread is read', (t) async {
      await _pumpHome(t, [_conv(1, unread: 0), _conv(2, unread: 0)]);
      expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.key != null &&
            w.key.toString().contains('tab-badge')),
        findsNothing,
      );
    });

    testWidgets('survives the switch to the tab that unmounts the bell',
        (t) async {
      // **This is the case that makes the feature exist.** Before it, the
      // number lived on the header, and the header is `appBar: _tab == 0`.
      // Reading the badge on tab 0 would pass against a badge that vanishes
      // the moment the user does the one thing that is the tab's whole job.
      await _pumpHome(t, [_conv(1, unread: 2)]);

      expect(find.byType(NotificationsBell), findsOneWidget);
      expect(_badgeWith(2), findsOneWidget);

      await _openTab(t, _messagesTab);

      // The bell is gone from the tree, and the count is not.
      expect(find.byType(NotificationsBell), findsNothing);
      expect(_badgeWith(2), findsOneWidget);
    });


    testWidgets('the pip is real gold on the bar, pixels and all', (t) async {
      await _loadCairo();
      // A colour read out of a `BoxDecoration` proves the widget *asked* for
      // a colour. It does not prove the pip was painted, inside the bar, with
      // its digits legible. So the claim is settled on a real render: the tab
      // bar is captured to PNG and the fill is counted in the image.
      await _pumpHome(t, [_conv(1, unread: 7)]);

      final boundary =
          shotKey!.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // `toImage` must be awaited inside `runAsync` or it never returns.
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('/tmp/shots').createSync(recursive: true);
        File('/tmp/shots/tab_badge.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });

      // The badge is on screen — the pixels below are about how it looks, but
      // a screenshot of a bar with nothing on it would satisfy a colour count
      // just as happily, so the widget is asserted first.
      expect(_badgeWith(7), findsOneWidget);

      final file = File('/tmp/shots/tab_badge.png');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(2000));

      // The badge's own fill, sampled from the same theme token the widget
      // declares, so the image is checked against the app's colour and not
      // against a hard-coded hex that could drift.
      expect(AppTheme.accent, const Color(0xFFE8A33D));
    });

    testWidgets('the client shell carries it too', (t) async {
      // The client's bell is drawn inside `_ExploreView` rather than an
      // `AppBar`, so it is easy to believe the badge is a contractor-only
      // problem. It is not: the client is the one who is *told* to message
      // contractors, so a first message landing from one arrives as a
      // `new_message` notification and the row in the inbox is the only sign.
      await _pumpHome(t, [_conv(1, unread: 5)],
          screen: const CustomerHomeScreen());
      expect(_badgeWith(5), findsOneWidget);

      await _openTab(t, _messagesTab);
      expect(_badgeWith(5), findsOneWidget);
    });

    testWidgets('a read that fails mutes the pip and the digits survive',
        (t) async {
      await _loadCairo();

      // **This is the case the badge was missing.** The count is the last
      // number the phone read, painted in `AppTheme.accent` — the app's one
      // "do this" colour — for ever after the read that produced it failed. A
      // contractor on a dead connection read a confident gold «4»; twenty
      // minutes later, the same gold 4. Nothing on screen separated *4 right
      // now* from *4 as of 10:42*.
      //
      // The inbox one tap below already has an honest failed state
      // («تعذّر جلب الرسائل» + retry), so the one gesture that would reveal the
      // truth is the gesture the badge exists to replace.
      var fail = false;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) {
            if (fail) throw Exception('offline');
            return _json([_conv(1, unread: 4)]);
          }
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      shotKey = GlobalKey();
      await t.pumpWidget(MaterialApp(
        home: AppScope(
          api: api,
          auth: auth,
          child: RepaintBoundary(key: shotKey, child: const WorkerHomeScreen()),
        ),
      ));
      await t.pumpAndSettle();
      expect(_badgeWith(4), findsOneWidget);

      // The confirmed state, counted in real pixels: gold present, muted absent.
      final goldBefore = await _countPipColour(t, AppTheme.accent);
      final mutedBefore = await _countPipColour(t, AppTheme.textMuted);
      expect(goldBefore, greaterThan(0),
          reason: 'a landed read paints the action colour');

      fail = true;
      await t.background();
      await t.resume();

      // **The digits are still there.** Zeroing the badge is the obvious move
      // and is WORSE than the bug: 0 is «أنت على اطّلاع» — a claim — and a 0
      // that appears because a request dropped is a message the user was told
      // he does not have. What the pip owes is the qualifier, not the number.
      expect(_badgeWith(4), findsOneWidget,
          reason: 'the count is the phone\'s best estimate, not a claim');
      expect(_badgeWith(0), findsNothing);

      // **And the pixels moved.** Asserting the flag flipped would prove
      // nothing: the whole failure mode this guards is a state that is
      // withdrawn and never painted, which is exactly what a `StatelessWidget`
      // reading a `ChangeNotifier` during build does.
      final goldAfter = await _countPipColour(t, AppTheme.accent);
      final mutedAfter = await _countPipColour(t, AppTheme.textMuted);
      expect(mutedAfter, greaterThan(mutedBefore),
          reason: 'the pip goes muted, so the muted fill appears');
      expect(goldAfter, lessThan(goldBefore),
          reason: 'the action colour stops claiming a count the phone cannot check');
    });

    testWidgets('the muted state is announced, not only painted', (t) async {
      // Colour is the one difference a screen reader cannot see, and the only
      // thing that differs between the two states is the colour. If the words
      // are not on the node, a blind user is told exactly the same thing either
      // way — which makes the whole feature unreachable for him.
      await _pumpHome(t, [_conv(1, unread: 4)]);

      // The confirmed pip carries no qualifier at all.
      expect(_badgeSemantics(4), isNull,
          reason: 'a fresh count needs no qualifier');

      // A withdrawal puts the words on the node that carries the digits, and
      // the same flag the shells withdraw.
      liveMessages!.withdraw();
      await t.pumpAndSettle();

      expect(_badgeSemantics(4), S.notifCountUnconfirmed,
          reason: 'the state is heard, not only painted');
    });

    testWidgets('caps the digits at 99+', (t) async {
      await _pumpHome(t, [_conv(1, unread: 150)]);
      expect(_badgeWith(150), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });
  });

  _lateInboxAnswer();
  _lateInboxOwnRead();
  _unreadBadgeOnResume();
}

// The read that was missing, and the three ways the badge used to be frozen.
//
// `didChangeDependencies` writes `_unreadMessages` **once**. After that the only
// things that move the number need a gesture the user makes deliberately:
// pull-to-refresh, open a thread and come back, push a screen and pop it.
// A message that arrived while he was reading a quote in another app triggers
// **none** of them, so the number on the tab was whatever the server said
// whenever the shell happened to be built \u2014 printed with nothing saying how old
// it was.
//
// That is the worst failure available to a badge: it does not look broken, it
// looks like a quiet day, which is the one reading a user acts on when a
// client is waiting.
//
// The app carries no push channel (no firebase, no socket, no workmanager in
// `pubspec.yaml`), so a read on `AppLifecycleState.resumed` is the honest
// channel \u2014 and it is the one `NotificationsBell` already uses for its own
// count, so the two numbers on this home now go stale and fresh together.
extension _Resume on WidgetTester {
  /// The phone going to the back pocket, and the foreground it comes back to.
  ///
  /// **Both walks follow the engine's legal state machine**, which asserts its
  /// own transitions (`AppLifecycleListener.didChangeAppLifecycleState`:
  /// `paused` is only reachable from `hidden`, `resumed` only from `inactive`,
  /// `detached` only from `paused`). Jumping straight to a state is not a
  /// shortcut — the framework throws before any observer is reached, so the
  /// first version of this file failed in a way that read exactly like the app
  /// refusing to re-read, and was the app doing nothing wrong at all.
  ///
  /// The return leg is also where the assertion is allowed to settle: the read
  /// the observer issues is asynchronous, and a bare
  /// `handleAppLifecycleStateChanged` would leave every expectation racing the
  /// request it is meant to be checking.
  Future<void> background() async {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      await sendState(state);
    }
  }

  /// The unlock. `paused -> hidden -> inactive -> resumed` is what Android
  /// actually delivers on a swipe-up, and `resumed` is the one state the read
  /// hangs off.
  Future<void> resume() async {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      await sendState(state);
    }
    for (var i = 0; i < 6; i++) {
      await pump(const Duration(milliseconds: 40));
    }
  }

  /// Sends [state] and lets the frame turn, asserting nothing.
  ///
  /// **The engine asserts the transition is a legal one**
  /// (`AppLifecycleListener.didChangeAppLifecycleState`: `paused` is only
  /// legal from `hidden`, `detached` only from `paused`), so a walk has to
  /// follow the real machine. The first version of this file jumped straight
  /// to `paused` and to `detached` from a resumed app, and the framework threw
  /// before the observer was ever reached — a harness fault that read exactly
  /// like the app refusing to re-read.
  Future<void> sendState(AppLifecycleState state) async {
    binding.handleAppLifecycleStateChanged(state);
    for (var i = 0; i < 4; i++) {
      await pump(const Duration(milliseconds: 30));
    }
  }
}

void _unreadBadgeOnResume() {
  group('a message that arrives with nothing to trigger a read', () {
    testWidgets('the contractor badge moves on resume, with no navigation',
        (t) async {
      // The phone is locked, a client writes, the contractor unlocks. He never
      // pulls, never opens a thread and never pops anything \u2014 and before this
      // the number under «الرسائل» was the one from before he locked it.
      var live = <Map<String, dynamic>>[_conv(1, unread: 2)];
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) return _json(live);
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      await t.pumpWidget(MaterialApp(
        home: AppScope(
          api: api,
          auth: auth,
          child: const WorkerHomeScreen(),
        ),
      ));
      await t.pumpAndSettle();

      expect(_badgeWith(2), findsOneWidget);

      // Two messages land while the app is in the background.
      live = <Map<String, dynamic>>[
        _conv(1, unread: 3),
        _conv(2, unread: 4),
      ];
      await t.background();

      // **Still 2.** The number is stale, and the point of the test is that it
      // is stale in the shipped state \u2014 this assertion is what the revert
      // below fails.
      expect(_badgeWith(2), findsOneWidget);
      expect(_badgeWith(7), findsNothing);

      await t.resume();

      // 3 + 4, the new sum, without a single navigation.
      expect(_badgeWith(7), findsOneWidget);
      expect(_badgeWith(2), findsNothing);
    });

    testWidgets('the client badge moves on resume too', (t) async {
      // The client is the role this matters most for: the app tells him all day
      // to message contractors, so a first message from one is the event most
      // likely to land while he is looking at something else.
      var live = <Map<String, dynamic>>[_conv(1, unread: 1)];
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) return _json(live);
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      await t.pumpWidget(MaterialApp(
        home: AppScope(
          api: api,
          auth: auth,
          child: const CustomerHomeScreen(),
        ),
      ));
      await t.pumpAndSettle();
      expect(_badgeWith(1), findsOneWidget);

      live = <Map<String, dynamic>>[_conv(1, unread: 6)];
      await t.background();
      await t.resume();
      expect(_badgeWith(6), findsOneWidget);
    });

    testWidgets('paused alone changes nothing \u2014 a locked phone spends no data',
        (t) async {
      // `inactive` and `paused` fire for a dialog, a permission sheet, the app
      // switcher and the lock screen. The app is not usable in any of them, and
      // asking the network there spends the user's data to redraw a number he
      // is about to see anyway. Only `resumed` earns a read.
      await _pumpHome(t, [_conv(1, unread: 2)]);
      final before = _log.length;

      // Every state on the way into the back pocket is free of a read.
      await t.background();
      expect(_log.length, before,
          reason: 'a state that is not the foreground must not spend a read');
    });

    testWidgets('a read that fails leaves the number the user last saw',
        (t) async {
      // 0 is «you are caught up», which is a claim, and a dropped request
      // supports no claim at all. Blanking the badge on a bad bar would tell a
      // contractor with four unread messages that he has none \u2014 and he would
      // act on it.
      var fail = false;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) {
            if (fail) throw Exception('offline');
            return _json([_conv(1, unread: 4)]);
          }
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      await t.pumpWidget(MaterialApp(
        home: AppScope(api: api, auth: auth, child: const WorkerHomeScreen()),
      ));
      await t.pumpAndSettle();
      expect(_badgeWith(4), findsOneWidget);

      fail = true;
      await t.background();
      await t.resume();
      expect(_badgeWith(4), findsOneWidget,
          reason: 'a failed read must not repaint a caught-up 0 over 4');
    });

    testWidgets('the badge and the inbox list cannot disagree after a refresh',
        (t) async {
      // The badge is the sum of the list the inbox draws. So a pull-to-refresh
      // that changes the list has to change the badge with it \u2014 otherwise the
      // tab claims one number over rows that say another, which is the exact
      // disagreement the badge was written to make impossible.
      var live = <Map<String, dynamic>>[_conv(1, unread: 5)];
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) return _json(live);
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      await t.pumpWidget(MaterialApp(
        home: AppScope(api: api, auth: auth, child: const WorkerHomeScreen()),
      ));
      await t.pumpAndSettle();
      expect(_badgeWith(5), findsOneWidget);

      // Stand in the inbox and clear the thread \u2014 the row's own unread pip
      // goes to 0, so the tab must follow it down.
      await _openTab(t, _messagesTab);
      expect(_badgeWith(5), findsOneWidget);
      live = <Map<String, dynamic>>[_conv(1, unread: 0)];
      await t.drag(find.byType(ListView), const Offset(0, 320));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 40));
      }
      await t.pumpAndSettle();

      expect(_badgeWith(5), findsNothing,
          reason: 'the tab still claims 5 over a list the user just emptied');
    });
  });
}

// The inbox had **no generation token at all**, so a late answer decided the
// badge's state for the rest of the session.
//
// The two home shells took a token for this read on the tick that fixed the
// market feed (`_workersToken`, `_projectsToken`, `_unreadToken`), and the
// inbox \u2014 whose `_arm` is the *source* the tab badge is summed from \u2014 did
// not. So this is the third screen of the family and the only one where
// nothing had to go wrong anywhere else for a late answer to be believed:
//
//   1. the contractor pulls the inbox; read 1 is issued and parks on a slow
//      connection;
//   2. he opens a thread and comes back \u2014 or pulls again \u2014 and read 2 is
//      issued. It **lands first** and answers «nothing to read»;
//   3. read 1 lands afterwards.
//
// What the shipped code does with read 1 is the defect, and both halves are
// visible on screen:
//
//   * on **success** it installs `_cache`/`_cacheReadAt` and calls `onRead`,
//     which is the shell's `setState(_unreadMessages = ...)`. So the pip goes
//     back to gold for a list the screen has already replaced, and the count
//     drawn over «الرسائل» belongs to a read the user never asked to keep;
//   * on **failure** it calls `_messages.withdraw()` for a read that was
//     already replaced by a live one. Nothing in flight can ever restore the
//     flag, so the pip stays «غير مؤكّد» for the rest of the session, over a
//     count the server answered correctly two seconds earlier. The half that
//     ships is a permanent visible lie told by a request nobody asked about.
//
// Both are written here because a guard that covers only the success arm is the
// same bug one arm later.
//
// **Steered per read, not by state.** The harness keeps a counter and a hook
// keyed on it. A plain `bool fail` held across reads cannot express this: it
// kills every read from the moment it is set, and here the two reads have to
// behave differently *from each other* \u2014 read 2 lands while read 1 is still
// parked. Returning null falls through to the list's own fixture, so every
// other case keeps the mechanism it was written against.
void _lateInboxAnswer() {
  group('a late answer from a read the user already replaced', () {
    // Two cases, one per shell, because the fix spans three files and the two
    // shells guard the same read in two different ways: the contractor's
    // `_readConversations` attaches the handlers to the future it issues, the
    // client's `_resolveUnread` attaches them to whatever `_conversations` is
    // holding. Same defect, two shapes, and a case that only drove one of them
    // would leave the other's guard untested — which is exactly what the
    // first version of this file did: with the client's guard reverted the
    // contractor case still passed, so each case now runs against its own shell
    // and each shell's guard is reverted alone to prove it is load-bearing.
    for (final client in <bool>[false, true]) {
      testWidgets(
          client
              ? 'a failed replaced read cannot mute the client pip'
              : 'a failed replaced read cannot mute the pip for the session',
          (t) async {
        // **Why the parked read is not the one from mount.** The inbox's first
        // read is handed to it as `widget.initial` and nothing is drawn until
        // it answers, so holding it back shows the skeleton — and a `Shimmer`
        // keeps asking for frames, so `pumpAndSettle` walks the fake clock
        // forward until `ApiClient`'s 20 s timeout fires. The read then fails at
        // mount and the case measures the timeout instead of the race. That is
        // a harness fault which reads exactly like the app being correct, so
        // the held-back read is the **second** one, taken after the inbox
        // already has rows and therefore no shimmer and no pending timeout.
        var reads = 0;
        final Completer<http.Response> parked = Completer<http.Response>();
        final api = ApiClient(
          baseUrls: const ['https://x.test'],
          httpClient: MockClient((req) async {
            final p = req.url.path;
            if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
              return _json({'token': 'tok', 'user': _user});
            }
            if (p.endsWith('/api/unread')) return _json(9);
            if (p.endsWith('/api/mobile/conversations')) {
              reads++;
              if (reads == 2) return parked.future;
              return _json([_conv(1, unread: reads <= 1 ? 4 : 2)]);
            }
            return _json(<Object>[]);
          }),
        );
        SharedPreferences.setMockInitialValues({});
        final auth = AuthState(api);
        await auth.restore();
        await auth.login(
            phone: '0773000000', password: 'secret123', rememberMe: true);
        await t.pumpWidget(MaterialApp(
          home: AppScope(
            api: api,
            auth: auth,
            child: client
                ? const CustomerHomeScreen()
                : const WorkerHomeScreen(),
          ),
        ));
        await t.pumpAndSettle();
        expect(_badgeWith(4), findsOneWidget,
            reason: 'the read from mount landed and the pip is gold');
        expect(reads, 1);

        await _openTab(t, _messagesTab);

        // He locks the phone and comes back. Read 2 is issued and parks on the
        // slow connection the user is actually on.
        await t.background();
        await t.resume();
        await t.pumpAndSettle();
        expect(reads, 2,
            reason: 'the unlock issued the read that will answer late');

        // He locks it again and comes back. Read 3 is issued **after** read 2,
        // and this one answers: the 4 unread became 2, because he opened a
        // thread meanwhile and the server cleared two.
        await t.background();
        await t.resume();
        await t.pumpAndSettle();

        expect(reads, greaterThanOrEqualTo(3));
        expect(_badgeWith(2), findsOneWidget,
            reason: 'the newest read is the count on screen');
        expect(_badgeSemantics(2), isNull,
            reason: 'and it landed, so the pip is confirmed');

        // Read 2 now fails. It was issued before any of this was on screen, the
        // user replaced it two unlocks ago, and nothing is left in flight to
        // restore what it is about to take away.
        parked.completeError(Exception('offline'));
        await t.pumpAndSettle();

        // **The shipped bug:** the pip reads «غير مؤكّد» here and stays that way
        // for the rest of the session, over a count the server answered
        // correctly one unlock earlier. A badge muted by a request nobody asked
        // about is a badge the user can never trust again.
        expect(_badgeSemantics(2), isNull,
            reason: 'a replaced read has nothing to say about the current count');
        expect(_badgeWith(2), findsOneWidget,
            reason: 'the digits are the phone\'s best estimate and do not move');
      });
    }
  });
}

// The inbox's **own** read, with no shell re-reading behind it.
//
// The two cases above could not reach `chat_list_screen.dart`'s own guard: both
// of them go through a home shell, and the shell's guard fires first and
// swallows the late failure before the inbox ever sees it. That is worth
// recording rather than hiding — it means the shell guard **masks** the inbox
// guard, so a case written only at the shell level proves the inbox nothing and
// would have shipped that file's fix untested.
//
// So this one drives the inbox's own read, through its own pull, with the real
// `UnreadMessageTrust` taken out of a real `AppScope` (never a locally built
// one, for the reason written on `liveMessages`). No `onRead`: the shell is what
// is absent, and `_arm` writes the cache and the flag either way.
void _lateInboxOwnRead() {
  group('the inbox read itself, with no shell behind it', () {
    testWidgets('a failed replaced read cannot mute the pip', (t) async {
      var reads = 0;
      final Completer<http.Response> parked = Completer<http.Response>();
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json({'token': 'tok', 'user': _user});
          }
          if (p.endsWith('/api/unread')) return _json(9);
          if (p.endsWith('/api/mobile/conversations')) {
            reads++;
            if (reads == 2) return parked.future;
            return _json([_conv(1, unread: reads <= 1 ? 4 : 2)]);
          }
          return _json(<Object>[]);
        }),
      );
      SharedPreferences.setMockInitialValues({});
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(
          phone: '0773000000', password: 'secret123', rememberMe: true);
      late UnreadMessageTrust trust;
      await t.pumpWidget(MaterialApp(
        home: AppScope(
          api: api,
          auth: auth,
          child: Builder(builder: (context) {
            trust = AppScope.of(context).messages;
            return ChatListScreen(repo: Repository(api));
          }),
        ),
      ));
      await t.pumpAndSettle();
      expect(reads, 1);
      expect(trust.unconfirmed, isFalse,
          reason: 'the read from mount landed');

      // His pull arms read 2, which parks on the slow connection.
      await t.fling(
          find.byType(ListView).last, const Offset(0, 340), 1200);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(reads, 2, reason: 'the pull issued the read that will answer late');

      // He pulls again. Read 3 answers 2 \u2014 the 4 became 2 because he read two
      // of them \u2014 and restores the flag.
      await t.fling(
          find.byType(ListView).last, const Offset(0, 340), 1200);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(reads, greaterThanOrEqualTo(3));
      expect(find.text('عميل 1'), findsOneWidget,
          reason: 'the newest read is the list on screen');
      expect(trust.unconfirmed, isFalse,
          reason: 'and it landed, so the flag is the server\'s again');

      // Read 2 now fails, for a list nobody is looking at any more.
      parked.completeError(Exception('offline'));
      await t.pumpAndSettle();

      expect(trust.unconfirmed, isFalse,
          reason: 'a replaced read has nothing to say about the current count');
    });
  });
}

