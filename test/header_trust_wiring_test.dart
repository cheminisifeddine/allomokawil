// The unconfirmed pip shipped last cycle **was never wired to the phone**.
//
// The previous cycle built `NotificationCountTrust`, made the pip draw muted
// when it is withdrawn, gave the centre a `withdraw()` call, and pinned both
// halves with `test/unconfirmed_pip_test.dart` — 2 green tests, screenshots, a
// contrast check, 1272 passing. All of it true, and none of it reachable:
//
//   grep -rn "NotificationCountTrust(" lib/   ->  no matches
//
// `NotificationCountTrust` is **never constructed in `lib/`**. Both home
// headers build the bell as `const NotificationsBell(onNavy: true)` and
// `const NotificationsBell()`, with no `trust:`. So in the shipped app
//
//   _trust            == null
//   withdraw()        == never called (the `?.` on a null receiver is a no-op)
//   _pip()'s `?? false` -> the pip is *always* `AppTheme.danger`
//
// The mechanism was exercised end to end by tests that **construct the flag
// themselves** and hand it to the bell. So the wiring the tests exercised was
// wiring only they had. A green gate proved the flag works, which is a
// different claim from "the flag is connected to the app", and only the second
// one is a user-visible bug.
//
// What the user actually gets today, on the one path this was written for:
//
//   1. home header shows 3 in alarm red — the server's answer, correctly;
//   2. contractor opens the centre, taps «تعليم الكل كمقروء»;
//   3. the write times out and the re-read cannot run, so the centre prints
//      «تعذّر التأكّد. تحقّق من قائمة الإشعارات عند عودة الاتصال.» —
//      the app admitting, in words, that it does not know;
//   4. he taps back, because he was just told to check the list;
//   5. `_open`'s forced refresh fails on the same dead bar, `catch` keeps the
//      count, and the pip repaints 3 — red, bold, unqualified.
//
// Exactly the contradiction the last cycle was written to remove, still on the
// phone, because the piece that removes it was never plugged in. The test that
// found it is not a widget test: it is a **grep**, and it is the cheapest and
// most embarrassing kind of miss — a feature complete, reviewed, screenshotted
// and committed, with no connection to the screen it was built for.
//
// So the harness here is deliberately the **production path**: the real
// `NotificationsBell` with **no injected `trust:`**, exactly as both headers
// build it. If a future change ever has to inject the flag by hand to make a
// test pass, this file fails — the wiring has to come from the app, not the
// test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/notification_count_trust.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';
import 'package:allomokawil/src/widgets/notifications_bell.dart';

const _user = {
  'id': 7,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test User',
  'type': 'worker',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-01-01 00:00:00',
};

String _stamp(Duration ago) {
  final t = DateTime.now().toUtc().subtract(ago);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, Object?> _row({required int id, int isRead = 0}) => {
      'id': id,
      'type': 'new_quote',
      'title': 'عرض سعر جديد',
      'body': 'لديك عرض سعر',
      'link': null,
      'is_read': isRead,
      'created_at': _stamp(const Duration(hours: 1)),
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

/// A bar that dies at the moment of the write and never comes back.
///
/// `_BadBar` in `unconfirmed_pip_test.dart` is the same idea with per-case
/// timeouts, because that file also has to prove the *restore* direction. This
/// one only has to break, so the timeout is one value and the gate is opened
/// by the test at the points where a read is supposed to land.
class _DyingBar {
  _DyingBar(this.rows, {this.timeout = const Duration(milliseconds: 40)})
      : unread = rows.length;

  List<Map<String, Object?>> rows;
  int unread;
  final List<String> log = [];

  /// Flipped by the write endpoint, so every read *after* the tap fails and
  /// every read before it succeeds. That ordering is the whole scenario: the
  /// launch read is a fact, and everything after the write is a guess.
  bool broken = false;

  final Duration timeout;

  final gate = Completer<void>();
  bool get held => !gate.isCompleted;

  int reads = 0;

  ApiClient get client => ApiClient(
        baseUrls: const ['https://primary.test', 'https://backup.test'],
        timeout: timeout,
        httpClient: MockClient((req) async {
          final path = req.url.path;
          log.add('${req.method} $path');
          switch (path) {
            case '/api/notifications':
              if (broken) {
                throw http.ClientException(
                    'Connection closed before full header was received');
              }
              return _json(rows);
            case '/api/unread':
              reads++;
              final snapshot = unread;
              if (broken) {
                await gate.future;
                throw http.ClientException('connection reset');
              }
              await gate.future;
              return _json({'unread': snapshot});
            case '/api/notifications/read':
              broken = true;
              // The write leaves the phone and nobody answers, so the client
              // gives up and the centre has to call the row unconfirmed.
              await Future<void>.delayed(const Duration(milliseconds: 200));
              return _json({'unread': unread});
            default:
              return _json(const <Object>[]);
          }
        }),
      );

  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  int steps = 60,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    if (done()) return;
    await tester.pump(step);
  }
}

Color _pipFill(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.byKey(const Key('notifications-badge')),
  );
  return (box.decoration! as BoxDecoration).color!;
}

const _outDir = '/tmp/shots';
final shotKey = GlobalKey();

Future<void> _shootHeader(WidgetTester tester, String name) async {
  final boundary =
      shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the app builds a trust flag at all', () {
    // The assertion that has no widget in it, and is the reason this file
    // exists. It is written against the **source**, not against behaviour, on
    // purpose: a behavioural test can only see the bell through the test's
    // own `trust:` parameter, and that parameter is exactly what was never
    // wired. This one cannot be satisfied by injecting the flag in the test.
    final lib = Directory('lib').listSync(recursive: true).whereType<File>();
    final sources =
        lib.map((f) => f.readAsStringSync()).join('\n');
    expect(
      RegExp(r'NotificationCountTrust\s*\(').hasMatch(sources),
      isTrue,
      reason: 'the app never constructs NotificationCountTrust, so the pip '
          'has nothing to be unconfirmed with and is always drawn in red — '
          'the withdrawal the centre makes is a no-op on a null receiver',
    );
  });

  testWidgets(
      'the header the phone actually builds stops claiming a count the centre '
      'withdrew', (tester) async {
    // **No `trust:` here, deliberately.** This is the bell exactly as both
    // home headers construct it. The flag has to reach the pip from the app —
    // from the scope above the navigator — or this test fails, which is the
    // defect it exists to catch.
    final h = _DyingBar([_row(id: 1), _row(id: 2), _row(id: 3)]);
    h.unread = 3;

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_user),
    });
    final auth = AuthState(h.client);
    await auth.restore();
    await tester.pumpWidget(
      AppScope(
        api: h.client,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: shotKey,
            child: NotificationsBell(repo: Repository(h.client)),
          ),
        ),
      ),
    );
    await tester.pump();
    h.release();
    await _until(tester,
        () => find.byKey(const Key('notifications-badge')).evaluate().isNotEmpty);
    expect(find.text('3'), findsOneWidget,
        reason: 'the launch read came back and the pip shows 3');
    expect(_pipFill(tester), AppTheme.danger,
        reason: 'a server answer is red, as it should be');

    // Open the centre through the bell and clear it, on a bar that then dies.
    await tester.tap(find.byKey(const Key('notifications-bell')));
    await tester.pump();
    await _until(tester,
        () => find.byKey(const Key('notifications-mark-all')).evaluate().isNotEmpty);
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await _until(tester,
        () => find.text(S.notifReadUnconfirmedUnknown).evaluate().isNotEmpty);
    expect(find.text(S.notifReadUnconfirmedUnknown), findsOneWidget,
        reason: 'the app must admit it cannot check the server');

    // Back, the way he was told to go, and the pop-back read fails too.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _until(tester, () => h.reads >= 2);
    await _until(tester, () => false, steps: 12);

    expect(find.byKey(const Key('notifications-badge')), findsOneWidget,
        reason: 'the pip is not hidden — the digits are still worth showing');
    expect(_pipFill(tester), AppTheme.textMuted,
        reason: 'the centre withdrew this number and the header kept the '
            'withdrawal: on the real header, with no injected flag');
    expect(find.text('3'), findsOneWidget,
        reason: 'same digits — a change of confidence, not of data');

    await _shootHeader(tester, 'header_withdrawn');
    expect(File('$_outDir/header_withdrawn.png').lengthSync(), greaterThan(1000),
        reason: 'a shot this small means nothing rendered');
  });

  testWidgets(
      'a centre opened by any route but the bell still withdraws the pip', (tester) async {
    // The reason the fallback is on **both** sides rather than just the header.
    //
    // The bell hands the centre the flag it is already listening to, so on
    // that route the two are the same object without the scope being consulted
    // a second time. But the centre is not only reachable that way: the
    // in-app route and any future deep link push `NotificationsScreen`
    // directly, with no bell in the story. A caller that passed no flag made
    // the withdrawal a no-op, so the pip behind that screen stayed red while
    // the screen under the user's thumb said «تعذّر التأكّد» — the exact
    // contradiction, reached by a different door.
    //
    // This pushes the centre **bare**, as those routes do, and asserts the
    // withdrawal lands on the flag the header behind it is watching.
    final h = _DyingBar([_row(id: 1), _row(id: 2)]);
    h.unread = 2;

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_user),
    });
    final auth = AuthState(h.client);
    await auth.restore();
    late final NotificationCountTrust trust;
    await tester.pumpWidget(
      AppScope(
        api: h.client,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(builder: (context) {
            trust = AppScope.of(context).trust;
            // The centre as a deep link builds it: **no `trust:`**.
            return NotificationsScreen(repo: Repository(h.client));
          }),
        ),
      ),
    );
    await _until(tester,
        () => find.byKey(const Key('notifications-mark-all')).evaluate().isNotEmpty);
    h.release();
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await _until(tester,
        () => find.text(S.notifReadUnconfirmedUnknown).evaluate().isNotEmpty);
    expect(find.text(S.notifReadUnconfirmedUnknown), findsOneWidget);
    expect(trust.unconfirmed, isTrue,
        reason: 'the centre withdraws the flag the header watches even when it '
            'was not handed one — a deep link cannot leave a red pip standing '
            'behind a sentence that says the app does not know');

    // **Added 30 Sep, and it is a teardown the app change made necessary, not
    // a test that got stricter.** `_until` returns the instant the sentence is
    // found, and it used to be safe to stop there: the recheck line was still
    // up holding the slot, and a visible bar keeps its `Timer` counted, so the
    // framework's `!timersPending` check at teardown was satisfied. The centre
    // now calls `hideCurrentSnackBar()` before drawing the verdict, so the
    // outgoing bar is taken down and the answer is drawn in its place — and
    // the tree can be disposed while the *new* bar's four-second timer is
    // still running. The case then fails on a pending timer with every
    // assertion above it already green, which reads like an app bug and is not
    // one: the sentence is correct, and the bar is simply still up.
    //
    // The bar is closed the way a user closes it, through the messenger, and
    // then the tree is pumped until the overlay is actually empty.
    // `pumpAndSettle` alone is not enough — the same lesson as
    // `notification_read_outcome_test.dart`'s capture helper, where it drains
    // the very bar the assertions are about.
    final messenger = tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
    messenger.hideCurrentSnackBar();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(SnackBar).evaluate().isEmpty) break;
    }
  });

  testWidgets('a real read of the count restores the claim on the real header',
      (tester) async {
    // The other direction on the same production path, so the flag cannot
    // degenerate into "muted forever" once it is actually connected: when the
    // phone can read the server again the pip goes back to red by itself.
    //
    // The flag is **read back off the app's own scope**, never handed in. A
    // test that passed its own `NotificationCountTrust` would be testing its
    // own object, which is how the last cycle's two green tests came to prove
    // something true and unreachable.
    final h = _DyingBar([_row(id: 1)], timeout: const Duration(seconds: 5));

    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'auth.token': 'test-token',
      'auth.user': jsonEncode(_user),
    });
    final auth = AuthState(h.client);
    await auth.restore();
    late final NotificationCountTrust trust;
    await tester.pumpWidget(
      AppScope(
        api: h.client,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(
            key: shotKey,
            child: Builder(builder: (context) {
              // Read the flag the app itself owns, from the scope the bell
              // also reads it out of.
              trust = AppScope.of(context).trust;
              return NotificationsBell(repo: Repository(h.client));
            }),
          ),
        ),
      ),
    );
    trust.withdraw();
    await tester.pump();
    // `pumpWidget` has built a frame already, so the launch read is open and
    // blocked on the gate before this line — release it any earlier and no read
    // was ever open to hold, and the case would pass for the wrong reason.
    expect(h.held, isTrue, reason: 'the launch read is still waiting');
    h.release();
    await _until(tester,
        () => find.byKey(const Key('notifications-badge')).evaluate().isNotEmpty);
    expect(trust.unconfirmed, isFalse,
        reason: 'the read came back, so the count is the server\'s again');
    expect(_pipFill(tester), AppTheme.danger);
    await _shootHeader(tester, 'header_confirmed');
  });
}
