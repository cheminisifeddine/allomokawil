// A notification the user tapped was struck off the list, and the server was
// never asked whether that was true.
//
// Fourteen write audits in, the backlog closed `markNotificationsRead` with a
// note that it "re-reads unconditionally, so it cannot claim a false landing".
// Reading the file found the claim describes the *reload* and not the method,
// and the gap is the one case that matters most:
//
//     setState(() { _items = [... ids → asRead() ...] });    // the flip
//     try { await _repo.markNotificationsRead(ids: ids); }
//     catch (_) { /* the reload puts the row back */ }        // the shrug
//     await _load();                                          // the reload
//
// The reload is the source of truth **only when it succeeds**. `_load` sets
// `_error`, and `_body` reads `_error` only when `_items.isEmpty` — so a failed
// reload on a populated list is unreachable state. The optimistic flip from the
// first line stands, the gold «جديد» pip disappears, and the user is left
// believing a notification was cleared which the database still holds unread.
// The write is ambiguous exactly when the network is worst, and the one screen
// whose whole job is the unread pip is the one that went quiet.
//
// The `catch (_)` is the second half: it swallows `errWriteUnconfirmed` — the
// network layer's explicit "this left the phone and nobody answered" — with
// the same arm that would swallow a 403. Seven other screens already know the
// two are different.
//
// **And the two writes are not the same shape, which is why the copy differs.**
// `openConversation` is a get-or-create POST whose retry may make a second
// thread, so `threadOpenOutcomeCopy` refuses every retry. Marking a
// notification read is **idempotent by construction** — marking an already-read
// id changes nothing — so «missing» here may honestly say «أعد المحاولة». The
// tests below pin that asymmetry, because the natural instinct is to reuse the
// shared line and that reuse would be wrong in both directions at once.
//
// Red before green: the pure cases fail because the file did not exist; the
// screen case fails against the pre-fix screen because it prints **nothing** —
// the defect is silence, so the assertion that catches it is the one that
// requires a sentence to exist.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
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
import 'package:allomokawil/src/data/notification_read_outcome.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/notification.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

AppNotification _n(int id, {int isRead = 0}) => AppNotification(
      id: id,
      type: 'new_quote',
      title: 'عنوان',
      body: 'نص',
      link: null,
      isRead: isRead,
      createdAt: DateTime(2026, 9, 28),
    );

void main() {
  // ── The proof, as a pure function ────────────────────────────────────────

  group('what counts as proof the notification is now read', () {
    test('a fresh list with every id read proves the write landed', () {
      expect(
        notificationsProvenRead(fresh: [_n(1, isRead: 1), _n(2, isRead: 1)],
            ids: [1, 2]),
        isTrue,
      );
    });

    test('one still-unread id means the write did not land', () {
      expect(
        notificationsProvenRead(fresh: [_n(1, isRead: 1), _n(2, isRead: 0)],
            ids: [1, 2]),
        isFalse,
        reason: 'asking for 2 and getting 2 back unread is a refusal, not a gap',
      );
    });

    test('an id the fresh list never mentions is not proof of anything', () {
      expect(
        notificationsProvenRead(fresh: [_n(1, isRead: 1)], ids: [1, 2]),
        isFalse,
        reason: 'absence is not confirmation: row 2 may have been deleted',
      );
    });

    test('the empty-ids form is proven by a list with nothing unread', () {
      expect(
        notificationsProvenRead(fresh: [_n(1, isRead: 1), _n(2, isRead: 1)]),
        isTrue,
      );
      expect(notificationsProvenRead(fresh: [_n(1, isRead: 0)]), isFalse);
      expect(notificationsProvenRead(fresh: const []), isTrue,
          reason: 'nothing unread is what mark-all asks for');
    });

    test('an empty list proves mark-all even when it may prove nothing else',
        () {
      // The one asymmetry, and it is deliberate: "no row is unread" is exactly
      // the postcondition of the mark-all write, while "row 7 is read" needs the
      // row to still be there to be true at all.
      expect(notificationsProvenRead(fresh: const [], ids: [7]), isFalse);
    });
  });

  // ── The classifier ───────────────────────────────────────────────────────

  group('what the re-read proves', () {
    test('a list that agrees is landed', () async {
      expect(
        await resolveNotificationReadOutcome(
          recheck: () async => [_n(1, isRead: 1)],
          ids: [1],
        ),
        NotificationReadOutcome.landed,
      );
    });

    test('a list that still holds the row unread is missing', () async {
      expect(
        await resolveNotificationReadOutcome(
          recheck: () async => [_n(1, isRead: 0)],
          ids: [1],
        ),
        NotificationReadOutcome.missing,
      );
    });

    test('a failed re-read is unknown, never missing', () async {
      // The distinction that keeps the app from claiming a write failed on the
      // evidence of a second network failure.
      expect(
        await resolveNotificationReadOutcome(
          recheck: () async => throw const _Offline(),
          ids: [1],
        ),
        NotificationReadOutcome.unknown,
      );
    });

    test('a row that vanished is unknown, not landed', () async {
      // Reporting success for a row that is not there is the more expensive
      // lie: the user stops looking.
      expect(
        await resolveNotificationReadOutcome(
          recheck: () async => const [],
          ids: [1],
        ),
        NotificationReadOutcome.unknown,
      );
    });
  });

  // ── The copy, and the asymmetry with the thread screen ───────────────────

  group('what the user is told', () {
    test('every outcome has its own Arabic sentence', () {
      for (final outcome in NotificationReadOutcome.values) {
        final copy = notificationReadOutcomeCopy(outcome);
        expect(copy, isNotEmpty, reason: '$outcome');
        expect(RegExp(r'[A-Za-z]').hasMatch(copy), isFalse, reason: '$outcome');
      }
    });

    test('a refusal the server stated may offer a retry — the write is '
        'idempotent', () {
      // Marking a read id read changes nothing, so a second POST cannot make a
      // duplicate. This is the opposite of the thread-open write, and reusing
      // that screen's copy here would be wrong in both directions at once.
      expect(
        notificationReadOutcomeCopy(NotificationReadOutcome.missing),
        contains('أعد المحاولة'),
        reason: 'the app\'s instruction verb, as every other sentence uses',
      );
    });

    test('an unreadable server must never offer a retry', () {
      // Re-sending a write of unknown outcome is the habit this app spent last
      // cycle removing from the chat screen.
      expect(
        notificationReadOutcomeCopy(NotificationReadOutcome.unknown),
        isNot(contains(S.retry)),
      );
      expect(
        notificationReadOutcomeCopy(NotificationReadOutcome.unknown),
        contains('تحقّق'),
        reason: 'the user is sent to the list, which is a GET',
      );
    });

    test('a landed write is reported as settled, not as a success to celebrate',
        () {
      expect(
        notificationReadOutcomeCopy(NotificationReadOutcome.landed),
        S.notifReadUnconfirmedLanded,
      );
    });

    test('none of these sentences is the thread screen’s, or the shared one',
        () {
      // Guards the copy against a future edit that aliases it to the family
      // line in `write_outcome.dart`, which is a claim about finding a row.
      const threadSentences = {
        'وجدناه في القائمة — الطلب وصل بنجاح',
        'لم نجده في القائمة — الطلب لم يصل، أعد المحاولة',
      };
      for (final outcome in NotificationReadOutcome.values) {
        expect(threadSentences, isNot(contains(notificationReadOutcomeCopy(outcome))));
      }
    });
  });

  // ── The screen: the silence this file exists to kill ─────────────────────

  group('the centre, when the server never answers the write', () {
    testWidgets('a timed-out write that landed is confirmed from the re-read',
        (tester) async {
      final h = _Centre(onRead: _ReadMode.landAfterTimeout, rows: [
        _row(1),
        _row(2),
      ], unread: 2);

      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('notification-1')));
      final said = await _collectBars(tester, taps: 1);

      expect(said, contains(S.notifReadUnconfirmedRecheck));
      expect(said, contains(S.notifReadUnconfirmedLanded),
          reason: 'the re-read showed it read — the write is settled, not guessed');
      // The list comes from the re-read, not from the optimistic flip.
      expect(await _pipsBackOnCentre(tester), 1,
          reason: 'the re-read showed row 1 read and row 2 still unread');
    });

    testWidgets('a timed-out write that never landed says so, and offers the '
        'retry that is safe here', (tester) async {
      final h = _Centre(onRead: _ReadMode.refuseAfterTimeout, rows: [
        _row(1),
        _row(2),
      ], unread: 2);

      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('notification-1')));
      final said = await _collectBars(tester, taps: 1);

      expect(said, contains(S.notifReadUnconfirmedMissing));
      // The pip is back, because the server still says unread.
      expect(await _pipsBackOnCentre(tester), 2,
          reason: 'the row was never read on the server, so the pip must return');
    });

    testWidgets('a re-read that cannot run says it proves nothing, and never '
        'offers the retry', (tester) async {
      // **This is the case the pre-fix screen was silently wrong about.** The
      // write times out and the reload fails too, so `_error` is set while
      // `_items` is not empty — unreachable state, no sentence drawn, and the
      // pip stays gone. A test that only asserted the row was back would have
      // passed against that screen; the assertion that catches it is the one
      // demanding the app admit it does not know.
      final h = _Centre(onRead: _ReadMode.offline, rows: [
        _row(1),
        _row(2),
      ], unread: 2);

      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('notification-1')));
      final said = await _collectBars(tester, taps: 1);

      expect(said, contains(S.notifReadUnconfirmedUnknown));
      expect(said, isNot(contains(S.notifReadUnconfirmedLanded)));
      expect(said.any((s) => s.contains(S.retry)), isFalse,
          reason: 'the phone cannot read the server, so re-sending is a guess');
    });

    testWidgets('a server that plainly refuses still just reloads', (tester) async {
      // A stated refusal is not in doubt, so it keeps the old path: no verdict
      // theatre, the reload puts the row back. Guards against the new branch
      // swallowing every failure and turning a 403 into a recheck.
      final h = _Centre(onRead: _ReadMode.forbidden, rows: [
        _row(1),
        _row(2),
      ], unread: 2);

      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('notification-1')));
      final said = await _collectBars(tester, taps: 1);

      expect(said, isNot(contains(S.notifReadUnconfirmedRecheck)));
      expect(said, isNot(contains(S.notifReadUnconfirmedLanded)));
      expect(said, isNot(contains(S.notifReadUnconfirmedMissing)));
      expect(said, isNot(contains(S.notifReadUnconfirmedUnknown)),
          reason: 'a stated refusal is not in doubt, so it gets no verdict');
      expect(await _pipsBackOnCentre(tester), 2,
          reason: 'the reload restored the row');
    });

    testWidgets('marking everything read is settled the same way', (tester) async {
      final h = _Centre(onRead: _ReadMode.landAfterTimeout, rows: [
        _row(1),
        _row(2),
      ], unread: 2);

      await _pump(tester, h);
      await tester.tap(find.byKey(const Key('notifications-mark-all')));
      final said = await _collectBars(tester, taps: 1);

      expect(said, contains(S.notifReadUnconfirmedRecheck));
      expect(said, contains(S.notifReadUnconfirmedLanded));
      expect(find.byKey(const Key('notifications-mark-all')), findsNothing,
          reason: 'nothing is unread any more, so the action is gone');
    });
  });

  // ── The pixels ───────────────────────────────────────────────────────────
  //
  // This cycle's whole visible output is one SnackBar, and a SnackBar is the
  // one widget this app had never rendered in a shot. The previous cycle in
  // this family shipped two settled states that drew the same grey icon
  // because the widget fields were right and the paint was not, so the bar is
  // rendered on the **real screen**, written to /tmp/shots, and looked at.

  testWidgets('the unknown verdict is drawn over the real centre',
      (tester) async {
    final h = _Centre(onRead: _ReadMode.offline, rows: [_row(1)], unread: 1);
    final path = await _shootCentreVerdict(tester, h,
        tap: find.byKey(const Key('notification-1')));
    expect(File(path).lengthSync(), greaterThan(20000),
        reason: 'a shot this small means nothing rendered');
  });

}

// ── Harness ─────────────────────────────────────────────────────────────────

/// What the fake server does with `POST /api/notifications/read`.
enum _ReadMode {
  /// The write times out — the answer never came — but it did land.
  landAfterTimeout,

  /// Times out, and did not land. The re-read still works.
  refuseAfterTimeout,

  /// Times out, and the re-read cannot run either.
  offline,

  /// A 403: the server answered, and said no.
  forbidden,
}

class _Offline implements Exception {
  const _Offline();
}

Map<String, Object?> _row(int id) => {
      'id': id,
      'type': 'new_quote',
      'title': 'عنوان',
      'body': 'نص الإشعار',
      'link': null,
      'is_read': 0,
      'created_at': '2026-09-28 10:00:00',
    };

/// A centre whose read endpoint fails in the way under test.
///
/// The timeout is real: the mock delays past the client's own `_timeout`, so
/// `ApiClient` raises `errWriteUnconfirmed` exactly as it does on a phone that
/// loses signal mid-POST. Faking the exception by hand would test the screen's
/// branch without ever exercising the contract that produces it.
class _Centre {
  _Centre({
    required this.rows,
    required this.unread,
    required this.onRead,
  });

  List<Map<String, Object?>> rows;
  int unread;
  final _ReadMode onRead;
  final List<String> log = [];

  ApiClient get client => ApiClient(
        baseUrls: const ['https://primary.test', 'https://backup.test'],
        timeout: const Duration(milliseconds: 30),
        httpClient: MockClient((req) async {
          final path = req.url.path;
          log.add('${req.method} $path');
          if (path == '/api/notifications') {
            if (onRead == _ReadMode.offline && _wrote) {
              // The re-read fails: the phone is still down.
              throw const _Offline();
            }
            return _json(rows);
          }
          if (path == '/api/notifications/read') {
            _wrote = true;
            final body = req.body.isEmpty
                ? const <String, Object?>{}
                : jsonDecode(req.body) as Map<String, Object?>;
            final ids = (body['ids'] as List?)
                ?.map((v) => (v as num).toInt())
                .toSet();
            switch (onRead) {
              case _ReadMode.landAfterTimeout:
                // Only the ids asked for — the real endpoint clears a subset
                // when ids are given, and a fake that cleared everything would
                // make the unread-row assertions prove nothing.
                rows = [
                  for (final r in rows)
                    if (ids == null || ids.contains(r['id']))
                      {...r, 'is_read': 1}
                    else
                      r,
                ];
                unread = rows.where((r) => r['is_read'] == 0).length;
                // Applied, then the answer never arrives.
                await Future<void>.delayed(const Duration(milliseconds: 150));
                return _json({'unread': 0});
              case _ReadMode.refuseAfterTimeout:
                await Future<void>.delayed(const Duration(milliseconds: 150));
                return _json({'unread': unread});
              case _ReadMode.offline:
                await Future<void>.delayed(const Duration(milliseconds: 150));
                return _json({'unread': unread});
              case _ReadMode.forbidden:
                return http.Response('{}', 403,
                    headers: const {'content-type': 'application/json'});
            }
          }
          return _json(const <Object>[]);
        }),
      );

  bool _wrote = false;
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

const _sessionUser = {
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

Future<void> _pump(WidgetTester tester, _Centre h) async {
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_sessionUser),
  });
  final auth = AuthState(h.client);
  await auth.restore();
  await tester.pumpWidget(AppScope(
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
      home: NotificationsScreen(repo: Repository(h.client)),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every sentence the screen painted, sampled as it went.
///
/// A `SnackBar` leaves the tree when it times out, and the verdict lands
/// behind the «نتحقّق من الإشعارات…» line — so reading the tree once at the end
/// returns an empty list and the test passes against a screen that said nothing.
/// That is not hypothetical: the last two write-audit files both shipped a first
/// draft that measured the queue instead of the verdict.
Future<List<String>> _collectBars(WidgetTester tester, {required int taps}) async {
  final said = <String>[];
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    for (final bar in tester.widgetList<SnackBar>(find.byType(SnackBar))) {
      final text = (bar.content as Text).data;
      if (text != null && !said.contains(text)) said.add(text);
    }
  }
  return said;
}

/// The number of gold «جديد» pips, counted on the **centre**.
///
/// Tapping a row navigates — `_open` pushes whatever the notification is about
/// — so the centre is offstage while the verdict is on screen and the finder
/// skips it. The pips are therefore counted after popping back, which is also
/// the state a user is in when he looks. The first draft of this file asserted
/// straight after the tap and was reading the pushed screen's widgets.
Future<int> _pipsBackOnCentre(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
  if (nav.canPop()) {
    nav.pop();
    await tester.pumpAndSettle();
  }
  return _shown(tester).where((s) => s == S.newTag).length;
}
List<String> _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

/// Taps a row on the **real** `NotificationsScreen` and captures the screen
/// with the verdict bar on it.
///
/// Two things this got wrong first, both found by looking at the file rather
/// than by reasoning:
///
///  * the `RepaintBoundary` was placed *inside* `MaterialApp`, which captured
///    the centre and nothing else — a `SnackBar` is painted by the
///    `ScaffoldMessenger` into an `Overlay` **above** the navigator, so the
///    whole 1200x2700 capture came back a flat sheet of the bar's own red and
///    proved nothing. The boundary has to sit *above* `MaterialApp` to include
///    the overlay, which is legal in a test and is what makes the shot honest.
///  * `pumpAndSettle` never returns while a SnackBar is up: its dismiss timer
///    always has another frame queued, so the first draft hung the suite for
///    four and a half minutes and was killed by the outer timeout, taking the
///    nineteen green cases with it. Every pump here is bounded, and the last
///    one outlives the bar's four-second duration so the pending timer fires
///    and the test can actually end.
Future<String> _shootCentreVerdict(
  WidgetTester tester,
  _Centre h, {
  required Finder tap,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'auth.token': 'test-token',
    'auth.user': jsonEncode(_sessionUser),
  });
  final auth = AuthState(h.client);
  await auth.restore();

  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: AppScope(
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
        home: NotificationsScreen(repo: Repository(h.client)),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  await tester.tap(tap);
  // Pump in bounded steps and **stop the moment the verdict is on screen**.
  //
  // The two bars are queued: «نتحقّق من الإشعارات…» holds the slot for its
  // four-second duration, and the verdict only appears after that one leaves.
  // So a fixed number of long pumps is a race — ten 400 ms steps stopped one
  // second *before* the sentence was drawn, and the first draft of this file
  // asserted against a bar that had already timed out and left the tree. The
  // stop condition is the presence of the words.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(S.notifReadUnconfirmedUnknown).evaluate().isNotEmpty) break;
  }
  expect(find.text(S.notifReadUnconfirmedUnknown), findsOneWidget,
      reason: 'the sentence this whole cycle exists to print');

  const path = '/tmp/shots/notif_read_unknown.png';
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // `toImage` reaches outside the fake-async zone the test runs in, so it only
  // completes inside `runAsync`. Called bare it simply never returns, and the
  // case dies on the outer timeout with every assertion above it already green
  // — which is exactly what the first two drafts of this file did. Same reason
  // `error_copy_test.dart` and `design_shots_test.dart` wrap their captures.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  // Close the bar out before the test ends.
  //
  // A SnackBar holds a `Timer` for its whole duration, and the test framework
  // fails the case on a pending timer even though every assertion above
  // passed. So the bar is taken down the way a user takes it down — closed
  // through the messenger — and then the tree is pumped until the overlay is
  // actually empty. `pumpAndSettle` alone hangs here for the same reason the
  // capture did, so the loop is bounded and the stop condition is checked.
  final messenger = tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
  messenger.hideCurrentSnackBar();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(SnackBar).evaluate().isEmpty) break;
  }
  return path;
}
