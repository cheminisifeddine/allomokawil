// The notification centre was counting unread out of a list the server caps.
//
// Measured on production by `tool/notification_read_audit.py` on 10 Oct 2026:
//
//     GET  /api/notifications  -> 100 rows, and a HARD cap at 100
//     GET  /api/unread         -> the server's real count (140)
//
// `if (_unread > 0)` therefore read *drawn* unread, and a user who cleared
// every row he could see drove that to 0 -- which **removed**
// «تعليم الكل كمقروء» while the server still held 40. The app asserted nothing
// was unread about a set it was holding 100 rows of.
//
// These cases pin the arithmetic and the wording separately from the widget,
// and the widget cases at the bottom prove the screen *reads* `/api/unread` at
// all -- because a pure test of `NotificationShortfall` passes just as happily
// when the screen never constructs one, which is the guard that cannot fail.
//
// **The state under test is the measured one, not a tidy one.** 140 unread,
// 100 rows drawn, and the user has read every one of them. That is not a
// corner case -- it is where the defect lived, and a fixture where the drawn
// rows are still unread would never reach it.
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
import 'package:allomokawil/src/data/notification_count_trust.dart';
import 'package:allomokawil/src/data/notification_shortfall_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

// ── The arithmetic ──────────────────────────────────────────────────────────

void main() {
  group('the gap between the server count and the rows on screen', () {
    test('the measured shape reports the rows it cannot show', () {
      const s = NotificationShortfall(serverUnread: 140);
      expect(s.hidden, 140);
      expect(s.stranded, isTrue);
    });

    test('a list that already holds everything is not stranded', () {
      const s =
          NotificationShortfall(serverUnread: 12, unreadDrawn: 12, drawn: 20);
      expect(s.hidden, 0);
      expect(s.stranded, isFalse);
    });

    // The three distinctions, each of which the old code collapsed into one
    // number. Every one of them was a different truth wearing the same face.
    test('an unknown count is NOT a count of zero', () {
      const s =
          NotificationShortfall(serverUnread: null, unreadDrawn: 3, drawn: 40);
      expect(s.serverUnread, isNull);
      // Not stranded, and emphatically not "0 unread": the phone simply has no
      // fact. This is the state that keeps a failed read from inventing a
      // number to go with an invented band.
      expect(s.stranded, isFalse);
      expect(s.worthReporting, isFalse);
    });

    // The rows may outnumber the server's answer when the two reads raced, or
    // when the count is from another account. Claiming «there are more above»
    // over such a list is the fabrication this file exists to prevent.
    test('a count below the rows floors at zero instead of going negative', () {
      const s =
          NotificationShortfall(serverUnread: 2, unreadDrawn: 9, drawn: 9);
      expect(s.hidden, 0);
      expect(s.stranded, isFalse);
    });

    // A band attached to an empty screen points at nothing the user can scroll
    // to, and «40 unread» over an empty centre reads as a broken button.
    test('an empty centre is not worth a band however big the gap', () {
      const s = NotificationShortfall(serverUnread: 140);
      expect(s.hidden, 140);
      expect(s.stranded, isTrue);
      expect(s.worthReporting, isFalse);
      expect(notificationShortfallLineAr(s), isEmpty);
    });

    test('the one gap that is worth drawing: rows on screen, more behind them',
        () {
      const s = NotificationShortfall(
          serverUnread: 140, unreadDrawn: 100, drawn: 100);
      expect(s.worthReporting, isTrue);
      expect(notificationShortfallLineAr(s), isNotEmpty);
    });

    // The defect this file's two-field split closes, pinned as the state the
    // server audit actually walked into on production:
    //
    //     140 unread on the server, 100 rows drawn, the user has read every
    //     visible one -> the drawn *unread* count is 0 and the drawn *list* is
    //     still 100 rows.
    //
    // One field answering both questions made `worthReporting` false here --
    // the band was suppressed by the very condition it exists to report, so
    // the count the server gave was never reported and the gap was silently
    // re-hidden. Executed on the real source against the pre-fix build:
    // `NotificationShortfall(serverUnread: 40, rows: 0)` printed
    // `stranded = true` **and** `worthReporting = false` with an empty line.
    test('a cleared list is still a full list', () {
      const s =
          NotificationShortfall(serverUnread: 140, unreadDrawn: 0, drawn: 100);
      // The subtraction is against unread rows drawn, so the gap survives.
      expect(s.hidden, 140);
      expect(s.stranded, isTrue);
      // And the band is not gated off by the user having read everything.
      expect(s.worthReporting, isTrue);
      expect(notificationShortfallLineAr(s), contains('140'));
    });

    // The converse, so the split cannot be satisfied by simply deleting the
    // guard: a genuinely EMPTY centre still gets no band.
    test('an empty list is still empty, however big the gap', () {
      const s = NotificationShortfall(serverUnread: 140);
      expect(s.worthReporting, isFalse);
      expect(notificationShortfallLineAr(s), isEmpty);
    });

    // `drawn` and `unreadDrawn` are independent knobs; a guard reading either
    // one of them is wrong in exactly one of these two rows.
    test('drawn and unreadDrawn move independently', () {
      const read =
          NotificationShortfall(serverUnread: 40, unreadDrawn: 0, drawn: 100);
      const all =
          NotificationShortfall(serverUnread: 40, unreadDrawn: 40, drawn: 100);
      const empty = NotificationShortfall(serverUnread: 40);
      // Read every visible row: the gap is still the server's whole answer.
      expect(read.hidden, 40);
      // None read yet: the gap is nothing, the server is fully drawn.
      expect(all.hidden, 0);
      expect(all.worthReporting, isFalse);
      // Nothing on screen to hang a band on.
      expect(empty.worthReporting, isFalse);
    });

    test('copyWith keeps the count when only the rows move', () {
      const s = NotificationShortfall(
          serverUnread: 140, unreadDrawn: 100, drawn: 100);
      final after = s.copyWith(unreadDrawn: 0, drawn: 0);
      expect(after.serverUnread, 140);
      expect(after.worthReporting, isFalse);
    });
  });

  group('the sentence', () {
    // Measured against `arabicCounted`, the app's one agreement helper, rather
    // than against my idea of the grammar: 40 is the **accusative** singular
    // («40 إشعار»), because 11-99 take the counted noun. The first draft of
    // this case asserted «40 إشعارات» and failed, and the helper was right --
    // which is the whole reason the noun comes from it and is not spelled here.
    test('names the server number, in Arabic, and counts by agreement', () {
      expect(notificationHiddenCountAr(1), 'إشعار');
      expect(notificationHiddenCountAr(2), 'إشعاران');
      expect(notificationHiddenCountAr(3), '3 إشعارات');
      // 11+ and 40 are the accusative form, and they are the two numbers this
      // screen actually prints: the measured gap is 40.
      expect(notificationHiddenCountAr(40), '40 إشعار');
      expect(notificationHiddenCountAr(11), '11 إشعار');
    });

    test('a count of zero has no noun to print', () {
      expect(notificationHiddenCountAr(0), isEmpty);
      expect(notificationHiddenCountAr(-4), isEmpty);
    });

    test('never prints a Latin developer key or a raw JSON number', () {
      // 140 unread, 100 drawn -> a gap of 40. The first draft asked for
      // `serverUnread: 40, unreadDrawn: 100`, a count *below* the rows: the
      // floor correctly returned an empty line and this failed. A test that
      // reaches for a number without checking the shape it puts it in is how
      // the band would ship claiming a gap in the wrong direction.
      final line = notificationShortfallLineAr(const NotificationShortfall(
          serverUnread: 140, unreadDrawn: 100, drawn: 100));
      expect(line, isNot(contains('unread')));
      expect(line, isNot(contains('serverUnread')));
      expect(line, contains('40'));
    });

    // The instruction the band used to give, pinned so it cannot come back.
    //
    // `tool/notification_read_audit.py` measured against production that the
    // 100-row cap **cannot be raised from the client**: `?limit=200`,
    // `?limit=500&page=1`, `?page=2`, `?offset=100` and `?all=1` all return the
    // same 100 rows, byte-identical. So «اسحب للأسفل للتحميل» told the reader to
    // perform a gesture that provably does nothing -- and a test that only
    // asserted `contains('40')` would have shipped it, because the number was
    // right and only the instruction was a lie.
    //
    // This asserts the absence of an unachievable action, which is the half a
    // positive-content test structurally cannot reach: `isNotEmpty` is
    // satisfied by a sentence that ends «اسحب للأسفل للتحميل».
    test('never instructs a gesture the cap makes impossible', () {
      final line = notificationShortfallLineAr(const NotificationShortfall(
          serverUnread: 140, unreadDrawn: 100, drawn: 100));
      expect(line, isNotEmpty);
      // No refresh / load-more / paging instruction, in any of the phrasings
      // the app has used for one.
      for (final verb in const ['اسحب', 'تحديث', 'للتحميل', 'المزيد']) {
        expect(line, isNot(contains(verb)),
            reason: '«$verb» asks for a gesture this endpoint cannot honour: '
                'limit/page/offset/all were all measured to return the same '
                '100 rows');
      }
    });

    test('an empty line for every state the app cannot claim', () {
      // No count. No rows. No gap. Each is its own refusal and all three must
      // produce silence rather than a sentence built on a guess.
      expect(
          notificationShortfallLineAr(const NotificationShortfall(
              serverUnread: null, unreadDrawn: 100, drawn: 100)),
          isEmpty);
      expect(
          notificationShortfallLineAr(
              const NotificationShortfall(serverUnread: 140)),
          isEmpty);
      expect(
          notificationShortfallLineAr(const NotificationShortfall(
              serverUnread: 5, unreadDrawn: 5, drawn: 5)),
          isEmpty);
    });
  });

  // ── The screen ───────────────────────────────────────────────────────────
  //
  // Everything above is arithmetic on a value. These prove the screen builds
  // one — a file of green cases that the widget never reads is coverage of
  // nothing, which is the failure this repo has shipped seven guards of.
  group('the centre reads /api/unread', () {
    late List<String> log;

    // [drawnUnread] is how many of the [rowsDrawn] rows come back UNREAD. It
    // is a separate knob from the server's [unread] count because the measured
    // defect needs them to DISAGREE: the whole failure is a centre whose drawn
    // unread reaches 0 while the server still holds rows.
    //
    // The first draft derived the drawn count from the server count
    // (`is_read: i < rowsDrawn - unread`), which silently made `_unread` > 0
    // on every fixture. Reverting the button gate to the old `_unread > 0`
    // then still passed all 15 cases -- a green guard that could not fail, which
    // is the failure this repo has shipped seven of. The knob is explicit now so
    // the mutation below has something to catch.
    ApiClient backend({
      required int unread,
      required int rowsDrawn,
      int drawnUnread = 0,
      bool failUnread = false,
    }) =>
        ApiClient(
          baseUrls: const ['https://api.test'],
          httpClient: MockClient((req) async {
            log.add(req.url.path);
            if (req.url.path == '/api/unread') {
              if (failUnread) {
                return http.Response('{"error":"boom"}', 500,
                    headers: const {'content-type': 'application/json'});
              }
              return http.Response(jsonEncode({'unread': unread}), 200,
                  headers: const {'content-type': 'application/json'});
            }
            if (req.url.path == '/api/notifications') {
              return http.Response(
                  jsonEncode([
                    for (var i = 0; i < rowsDrawn; i++)
                      {
                        'id': i + 1,
                        'type': 'new_quote',
                        'title': 'عنوان $i',
                        'body': 'نص',
                        'link': null,
                        'is_read': i < drawnUnread ? 0 : 1,
                        'created_at': '2026-10-10 09:00:00',
                      }
                  ]),
                  200,
                  headers: const {'content-type': 'application/json'});
            }
            return http.Response('{}', 200,
                headers: const {'content-type': 'application/json'});
          }),
        );

    setUp(() => log = <String>[]);

    Future<void> pumpCentre(WidgetTester tester, ApiClient api) async {
      SharedPreferences.setMockInitialValues({
        'auth.token': 't',
        'auth.user': jsonEncode(const {
          'id': 7,
          'phone': '0550000000',
          'email': null,
          'full_name': 'Test User',
          'type': 'customer',
          'avatar_url': null,
          'wilaya': '16',
          'commune': null,
          'created_at': '2026-01-01 00:00:00',
        }),
      });
      final auth = AuthState(api);
      await auth.restore();
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        trust: NotificationCountTrust(),
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
          home: NotificationsScreen(repo: Repository(api)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the measured shape: 100 drawn, 140 unread on the server',
        (tester) async {
      // Every drawn row read, so the old `_unread` is 0 -- the exact state the
      // measurement walked into.
      final api = backend(unread: 140, rowsDrawn: 100);
      await pumpCentre(tester, api);

      expect(log, contains('/api/unread'),
          reason: 'the screen never asked the server how many are unread');

      // The button the old gate removed, on the server's evidence.
      expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);

      // And the reason for it is on screen, not merely true in the model.
      expect(find.byKey(const Key('short-notifications')), findsOneWidget);
      final line = tester
          .widget<Text>(find.byKey(const Key('short-notifications-line')))
          .data!;
      expect(line, contains('40'));
      expect(line, isNot(contains('unread')));
    });

    // The widget case for the state the audit walked into, and the one whose
    // absence is why the defect survived: the drawn rows are all READ, so the
    // drawn *unread* count is 0 while the list still holds 100 rows. Before the
    // two-field split this rendered **no band at all** -- the screen was gated
    // off by the very condition it was built to report.
    testWidgets('the band survives the user reading every visible row',
        (tester) async {
      // unread: 140 on the server; drawn: 100; drawnUnread: 0.
      final api = backend(unread: 140, rowsDrawn: 100, drawnUnread: 0);
      await pumpCentre(tester, api);

      expect(log, contains('/api/unread'));
      // 100 rows are on screen, so there is something for the band to sit on.
      expect(find.byKey(const Key('short-notifications')), findsOneWidget);
      // ...and it reports the gap rather than claiming the centre is complete.
      final line = tester
          .widget<Text>(find.byKey(const Key('short-notifications-line')))
          .data!;
      expect(line, contains('140'));
      // The rows are NOT all off the list: an empty list must not carry the
      // band, which is the other half of the same guard.
      expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget);
    });

    // The off-by-one a *second* header would cause, asserted on the delegate's
    // own count rather than by scrolling: reading `rows` for the header block
    // instead of `drawn` made the offset disagree with the item count, which
    // shifts every row up by one and drops the last notification off the
    // list. Counting children is deterministic; a fling is not.
    testWidgets('the band does not push the last row off the list',
        (tester) async {
      final api = backend(unread: 140, rowsDrawn: 100, drawnUnread: 0);
      await pumpCentre(tester, api);
      expect(find.byKey(const Key('short-notifications')), findsOneWidget);

      // `ListView.separated` counts **separators as children**, so the number
      // is items + (items - 1): 101 items (100 rows + 1 band) means 201
      // children.
      //
      // The assertion is unambiguous: the old bug read `rows` (the unread
      // count, 0 here) as the header count, giving 100 items -> 199 children,
      // one row short, the last notification unreachable and every row index
      // off by one. Both that wrong-header value (199) and a double-counted
      // band (203) are excluded by pinning 201.
      //
      // This expectation was corrected BY THIS RUN rather than by reading the
      // code: the first draft counted items and forgot the separators the
      // builder is handed, and the red run is what said so.
      final list = tester.widget<ListView>(find.byType(ListView));
      final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, 201);
    });

    testWidgets('a server count of zero retires the button, with no band',
        (tester) async {
      final api = backend(unread: 0, rowsDrawn: 100);
      await pumpCentre(tester, api);

      expect(find.byKey(const Key('notifications-mark-all')), findsNothing);
      expect(find.byKey(const Key('short-notifications')), findsNothing);
    });

    testWidgets('a failed count read invents nothing', (tester) async {
      final api = backend(unread: 140, rowsDrawn: 100, failUnread: true);
      await pumpCentre(tester, api);

      expect(find.byKey(const Key('short-notifications')), findsNothing,
          reason: 'a band quoting a number the phone could not read');
      // ...and the rows are still drawn. The count is a qualifier, and its
      // failure must not cost the list.
      expect(find.byKey(const Key('notifications-mark-all')), findsOneWidget,
          reason: 'drawn rows still prove there is something to clear');
    });

    testWidgets('the count follows the rows through a reload', (tester) async {
      final api = backend(unread: 140, rowsDrawn: 100);
      await pumpCentre(tester, api);
      expect(find.byKey(const Key('short-notifications')), findsOneWidget);

      // Pull-to-refresh with the same server answer must not double the band,
      // drop it, or install a second copy of the header row.
      await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('short-notifications')), findsOneWidget);
    });
  });
}
