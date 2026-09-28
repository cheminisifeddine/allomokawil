// The pip must not re-issue, in red, the answer the app just withdrew.
//
// The previous cycle closed the mark-read -> pop-back -> pip round trip for the
// **successful** write and named the gap it left, verbatim:
//
//   the refused write is untested on this path: `_markRead` shows the centre's
//   own «أعد المحاولة» copy when the re-read cannot confirm, and then `_open`
//   still fires a forced `_refresh`, which re-reads a count the user was just
//   told the app does not know.
//
// Reading the code found the round trip is not the worst of it. The sentence
// the user reads in the centre is not one thing but two, and the copy splits
// them on purpose:
//
//   landed  — «تم تعليم الإشعار كمقروء.»  the server proved it
//   missing — «لم نتمكن… أعد المحاولة.»  the server refused; the count below is
//                                                  a FACT, it just is not zero
//   unknown — «تعذّر التأكّد…»             the phone cannot read the server at
//                                                  all; the count is a GUESS
//
// Only `unknown` puts a guess on screen. And that is precisely the case where
// the header came back and redrew it:
//
//   1. read open on a slow bar, holding 3;
//   2. user marks a row read, the write times out, the re-read cannot run;
//   3. centre prints «تعذّر التأكّد. تحقّق من قائمة الإشعارات…»;
//   4. user taps back — the honest thing to do, because he was just told to
//      check the list;
//   5. `_open` fires a forced `_refresh`, which **fails on the same bad bar**;
//   6. `catch (_)` keeps the last known count, and the pip repaints 3 — in
//      `AppTheme.danger`, the app's alarm red, at full confidence.
//
// Step 6 is the bug, and it is two bugs wearing one coat. First: the app told
// the user it does not know, then painted a number anyway, in the colour it
// reserves for «this is wrong — act now». The sentence was withdrawn and the
// pip re-asserted it one gesture later. Second: step 5 makes it worse than a
// stale pip, because the user's *own attempt to follow the instruction* is what
// causes the repaint. Doing what the app said is what breaks it.
//
// The fix is one flag with an unusual direction of travel, in
// `notification_count_trust.dart`: the centre may **withdraw** confidence, and
// only a read of `/api/unread` may **restore** it. The `_refresh` catch is
// where the old behaviour came from — it keeps the count, which is right, and
// restoring trust there would be a claim the transport never made.
//
// A successful `GET /api/notifications` deliberately does NOT restore trust,
// and that is the assertion most likely to be got wrong: proving one row is
// read says nothing about how many are unread in total, so restoring on a list
// read would re-introduce the exact claim this cycle removes.
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
import 'package:allomokawil/src/widgets/notifications_bell.dart';

const _user = {
  'id': 7,
  'phone': '0550000000',
  'email': null,
  'full_name': 'Test User',
  'type': 'customer',
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

/// A backend where the write times out, the re-read cannot run, and
/// `/api/unread` can be held open.
///
/// Every failure here is *silent at the transport level* — a `TimeoutException`
/// or a dropped socket — because that is the only shape the network layer maps
/// to `S.errWriteUnconfirmed`, and the whole path under test is that branch.
class _BadBar {
  _BadBar(this.rows, {this.timeout = const Duration(milliseconds: 40)})
      : unread = rows.length;

  List<Map<String, Object?>> rows;
  int unread;
  final List<String> log = [];

  /// Set once the mark-read is attempted, so the re-read and the pop-back read
  /// both fail the way a phone on a dying bar fails.
  bool broken = false;

  /// How long one host gets before the client calls the write unconfirmed.
  ///
  /// Per case, and not a constant, because the two need opposite answers from
  /// the same clock. The unconfirmed case needs a read to *miss* its deadline;
  /// the restore case needs one to *meet* it, and `_until` pumps in 100 ms
  /// steps — which sail straight over a 40 ms deadline and produce a timeout
  /// nobody asked for. That is not theoretical: with one shared 40 ms value
  /// this file passed alone and failed in the full run, on the fake and not on
  /// the code. The restore case is therefore given room to answer normally.
  final Duration timeout;

  /// Held open by [release]; the launch read blocks on it.
  final gate = Completer<void>();
  bool get held => !gate.isCompleted;

  int requests = 0;

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
              requests++;
              final snapshot = unread;
              if (broken) {
                // Held *and* broken: the answer the pop-back asks for cannot
                // arrive, so whatever the pip shows is memory, not a fact.
                await gate.future;
                throw http.ClientException('connection reset');
              }
              await gate.future;
              return _json({'unread': snapshot});
            case '/api/notifications/read':
              broken = true;
              // The write leaves the phone and nobody answers.
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

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

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

/// The fill the pip is painted with.
///
/// Read from the `BoxDecoration` rather than sampled from pixels. Three
/// pixel-probe versions were written and all three were wrong, each in a way
/// that would have quietly made this file pass for the wrong reason: sampling
/// the geometric centre reads **white** (the middle of a count pip is the
/// white digit), walking the row and taking the first dark pixel reads a
/// **blend** of the fill and the white rim at alpha 0.9, and the modal colour of
/// the interior came back white because the pip is laid out with
/// `clipBehavior: Clip.none` and sits *outside* its parent's bounds. A
/// contrast-averaged region test would have been the robust version of the
/// same mistake — it can tell red from grey, but it cannot tell the pip from
/// the page behind it.
///
/// The pixel claim is not dropped, it is made where a pixel is honest: the
/// screenshots this file writes, checked by `tool/png_read.py` and
/// `tool/contrast_audit.py` against the same two tokens.
Color _pipFill(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.byKey(const Key('notifications-badge')),
  );
  final fill = (box.decoration! as BoxDecoration).color!;
  return fill;
}

/// Writes the current header to [_outDir], so the colour claim has a picture
/// behind it rather than only a decoded field.
///
/// The capture must live inside `tester.runAsync`: `toImage` reaches outside
/// the fake-async zone the test body runs in, and called bare it never returns
/// — it hangs until the case dies on the outer timeout, which is exactly what
/// the first run of this file did.
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

const _outDir = '/tmp/shots';

/// The capture surface. Both cases wrap the app in it so the header is
/// photographed as the user sees it.
final shotKey = GlobalKey();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'a count the app just disclaimed is not redrawn in red after the user '
      'follows the instruction', (tester) async {
    final h = _BadBar([_row(id: 1), _row(id: 2), _row(id: 3)]);
    h.unread = 3;
    final trust = NotificationCountTrust();

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
            child: NotificationsBell(
              repo: Repository(h.client),
              trust: trust,
            ),
          ),
        ),
      ),
    );
    // The launch read is open and holds 3.
    await tester.pump();
    h.release();
    await _until(tester,
        () => find.byKey(const Key('notifications-badge')).evaluate().isNotEmpty);
    expect(find.text('3'), findsOneWidget, reason: 'the pip shows 3 to begin with');
    final confirmedColour = _pipFill(tester);
    expect(confirmedColour, AppTheme.danger,
        reason: 'a server answer is drawn in the alarm colour, as before');

    // Mark a row read: the write times out and the re-read cannot run.
    await tester.tap(find.byKey(const Key('notifications-bell')));
    // `_open` awaits the auth gate before it pushes, so the route lands a frame
    // after the tap. Without this pump the finder below runs against the home
    // header and the whole case silently exercises nothing.
    await tester.pump();
    await _until(tester,
        () => find.byKey(const Key('notifications-mark-all')).evaluate().isNotEmpty);
    // **«تعليم الكل كمقروء», not a row tap, and that is load-bearing.** Tapping a
    // row also *navigates* — `new_quote` resolves to the projects list — so the
    // back button pops that, and every assertion below runs against the
    // centre still sitting on top of the home header. It fails as
    // `Found 0 widgets with key notifications-badge`, which reads like a missing
    // pip and is actually a test that tapped the wrong thing. The action button
    // reaches the same `_settleRead` branch and moves nowhere.
    await tester.tap(find.byKey(const Key('notifications-mark-all')));
    await _until(tester,
        () => find.text(S.notifReadUnconfirmedUnknown).evaluate().isNotEmpty);
    expect(find.text(S.notifReadUnconfirmedUnknown), findsOneWidget,
        reason: 'the app must admit it cannot check the server');
    expect(trust.unconfirmed, isTrue,
        reason: 'the count on the header is now the phone\'s guess');

    // The user does what he was told: he goes back to look at the list.
    //
    // The two pumps are not tidiness — the pop is a route transition, and
    // `await tester.tap` resolves before the animation runs. Skipping them
    // leaves the centre on top with the home header disposed, and every
    // assertion below then passes or fails against a tree that is not the one
    // the user sees. `_open` fires its forced refresh in the same microtask
    // the pop completes, so the read is already in flight by the second pump.
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _until(tester, () => h.requests >= 2);
    // Let the pop-back read fail, so `_refresh`'s catch has run — the catch is
    // the half that used to quietly leave the pip claiming a fact.
    await _until(tester, () => false, steps: 12);
    // Two hosts are configured, and a failing read is tried against each, so
    // this is 2 or 3 and never 1. The point of the assertion is the floor: the
    // pop-back must spend a read even when that read cannot land. Pinning the
    // exact number would be pinning the failover policy, which is a different
    // test and lives with the client.
    expect(h.requests, greaterThanOrEqualTo(2),
        reason: 'the pop-back must spend a read even when it is going to fail');

    expect(find.byKey(const Key('notifications-badge')), findsOneWidget,
        reason: 'the pip is not hidden — the number is still worth showing');
    final withdrawn = _pipFill(tester);
    expect(withdrawn, isNot(AppTheme.danger),
        reason: 'the app withdrew this number in the centre; red would '
            're-assert it louder than the sentence did');
    expect(withdrawn, AppTheme.textMuted,
        reason: 'a disclaimed count is drawn in the muted fill, same weight, '
            'no claim attached');
    expect(find.text('3'), findsOneWidget,
        reason: 'the same digits — this is a change of confidence, not of data');

    // A picture of the claim, for `tool/png_read.py` to check.
    await _shootHeader(tester, 'pip_withdrawn');
    expect(File('$_outDir/pip_withdrawn.png').lengthSync(), greaterThan(1000),
        reason: 'a shot this small means nothing rendered');
  });

  testWidgets('a real read of the count restores the claim', (tester) async {
    // The other direction, so the flag cannot degenerate into "muted forever":
    // once the phone can read the server again, the pip goes back to red
    // without the user having to do anything but wait.
    final h = _BadBar([_row(id: 1)], timeout: const Duration(seconds: 5));
    final trust = NotificationCountTrust()..withdraw();

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
            child: NotificationsBell(
              repo: Repository(h.client),
              trust: trust,
            ),
          ),
        ),
      ),
    );
    // `pumpWidget` has already built one frame, so the launch read is open and
    // blocked on the gate before this line runs. Releasing the gate any earlier
    // would mean no read was ever open to hold, and the case would pass for the
    // wrong reason — testing a completed gate, not a restored claim.
    expect(h.held, isTrue, reason: 'the launch read is still waiting');
    h.release();
    await _until(tester,
        () => find.byKey(const Key('notifications-badge')).evaluate().isNotEmpty);
    expect(trust.unconfirmed, isFalse,
        reason: 'the read came back, so the count is the server\'s again');
    expect(_pipFill(tester), AppTheme.danger);
    await _shootHeader(tester, 'pip_confirmed');
  });
}
