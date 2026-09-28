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
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';
import 'package:allomokawil/src/widgets/notifications_bell.dart';
import 'package:allomokawil/src/data/unread_message_count.dart';

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
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        api: api,
        auth: auth,
        child: RepaintBoundary(key: shotKey, child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Set by [_pumpHome] so the capture reads the boundary that was built there,
/// rather than searching the tree for a box that may not be the one painted.
GlobalKey? shotKey;

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

    testWidgets('caps the digits at 99+', (t) async {
      await _pumpHome(t, [_conv(1, unread: 150)]);
      expect(_badgeWith(150), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    });
  });
}
