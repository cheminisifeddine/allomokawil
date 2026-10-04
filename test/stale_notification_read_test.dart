// Proves a late-arriving READ on the notification centre cannot overwrite a
// newer one — the generation guard `_load` never had.
//
// The notification centre is the **input to the header's unread pip**:
// `_unread` counts these very rows, so what lands here becomes the number the
// user is shown on the home header one screen later. `notification_copy.dart`
// and `notification_count_trust.dart` both exist to keep that number honest,
// and this screen already withdraws it when a read *fails*.
//
// But `_load` carried no generation token at all, and **five** call sites
// re-issue it:
//
//   didChangeDependencies   the first read, on entry
//   RefreshIndicator        pull-to-refresh
//   _markRead               after a confirmed write
//   _markAllRead            after clearing everything
//   _settleRead             after an unconfirmed write
//
// Any two of those overlap on a connection that is not answering in order.
// They all ask the **same question** — «the whole notification list» — so a
// tab- or id-keyed cache cannot separate them, exactly as the projects screen
// found. The race has two arms, and the second is the worse one:
//
//   read 1  09:00  «مفتوح» — parked on a slow connection —┐
//   read 3  09:40  answers: 2 rows, stamped 09:40        ─┤
//   read 1  09:40  LANDS LAST: 1 row, stamps 09:40       ─┘
//
// The late success does not merely draw a stale list — on this screen it also
// feeds `_unread`, so **the count the header paints is a number from a read
// the user has already been told is newer**. A notification that arrived in
// the last forty minutes disappears from the pip, and nothing on screen says
// so. The pip goes *backwards*, which is the one thing an unread badge must
// never do.
//
// And the failure arm is the same bug wearing a different hat: read 1 parked,
// then read 2 fails and calls `_trust.withdraw()` — correctly, for the read
// that is genuinely on screen — but if read 1's *success* lands after it, the
// doubt has already been published to the header and the fresh rows then
// repaint the centre as if nothing were in doubt. `withdraw()` is one-way by
// design, so nothing takes it back: the header keeps muting a number that is
// now freshly read from the server.
//
// The same generation discipline `projects_screen.dart` landed on the tick
// before (commit 3f6fd3e) applies here, and for the same reason.
import 'dart:async';
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

Map<String, Object?> _sessionUser() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

/// A notification as the D1 row shape produces it. [id] is what the tile is
/// keyed and asserted on, so each read can be told apart by its own id.
Map<String, Object?> _row(int id) {
  final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'id': id,
    'type': 'new_quote',
    'title': 'عرض سعر جديد',
    'body': 'دهان شقة 3 غرف',
    'link': null,
    'is_read': 0,
    'created_at':
        '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
  };
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  group('NotificationsScreen — a late read cannot overwrite a newer one', () {
    /// Two reads in flight, the first held open until the test says so.
    ///
    /// [parked] is completed by the test after the second read has landed, so
    /// the late write is genuinely late — a real out-of-order arrival on one
    /// connection, not a second call to the same mock.
    Future<({
      WidgetTester tester,
      NotificationCountTrust trust,
      Completer<List<Map<String, Object?>>> parked,
      int reads,
    })> pumpWithTwoReads(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_sessionUser()),
      });

      final parked = Completer<List<Map<String, Object?>>>();
      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/notifications') {
            reads++;
            if (reads == 1) {
              // Parked: the request is issued and answered by the test, not by
              // the clock. Read 1 sees ONE row.
              return _json(await parked.future);
            }
            // Read 2 is the newer answer: TWO rows, so the newest read has
            // strictly more to say than the one that will land after it.
            return _json(<Object>[_row(2), _row(3)]);
          }
          return _json(<String, Object?>{});
        }),
      );

      final auth = AuthState(api);
      await auth.restore();
      final trust = NotificationCountTrust();
      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        trust: trust,
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
          home: NotificationsScreen(
            repo: Repository(api),
            trust: trust,
            clock: () => DateTime.now(),
          ),
        ),
      ));
      return (tester: tester, trust: trust, parked: parked, reads: reads);
    }

    testWidgets('a read parked on a slow connection cannot delete a row the '
        'newer read listed', (tester) async {
      final f = await pumpWithTwoReads(tester);
      // Read 1 is in flight and has not answered. Nothing is on screen yet.
      await tester.pump();
      expect(find.byKey(const Key('notification-1')), findsNothing);

      // Read 2 — issued by the pull gesture — answers first, with two rows.
      // Read 1 stays parked: `f.parked` is deliberately not completed yet.
      await tester.drag(find.byType(ListView).first, const Offset(0, 320));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byKey(const Key('notification-2')), findsOneWidget,
          reason: 'the newer read must be on screen while the older is parked');
      expect(find.byKey(const Key('notification-3')), findsOneWidget);

      // Now read 1 lands LAST, carrying one row and a stale list.
      f.parked.complete([_row(1)]);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // The defect: the older read won. Row 3 — which the newest read listed —
      // is GONE from the centre, and it is also gone from `_unread`, which is
      // what feeds the home header's pip. Nothing on screen says so.
      expect(
        find.byKey(const Key('notification-3')),
        findsOneWidget,
        reason: 'a read the user already replaced must not delete a row the '
            'newest read listed',
      );
      expect(find.byKey(const Key('notification-2')), findsOneWidget);
    });

    testWidgets('a late FAILURE cannot mute the header pip for a list the '
        'screen already replaced', (tester) async {
      // The other arm, and the one that reaches the *next* screen.
      //
      // Read 1 is parked. Read 2 lands and is newer, so the centre is drawing
      // a fresh list and the pip is the server's answer — `trust` is confirmed.
      // Then read 1 finally fails, and its catch calls `_trust.withdraw()`.
      //
      // That withdraw is correct *for a read that is on screen* and wrong here:
      // the doubt it publishes is about a list nobody is looking at, and
      // `NotificationCountTrust.withdraw` is one-way by design — only a real
      // read of `/api/unread` puts it back. So the header goes on muting a
      // number that was freshly read from the server, and the user sees a
      // grey pip for a count the app actually has.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_sessionUser()),
      });

      final parked = Completer<List<Map<String, Object?>>>();
      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/notifications') {
            reads++;
            if (reads == 1) {
              // Read 1: issued, then failed — but only after read 2 landed.
              await parked.future;
              return http.Response('', 503,
                  headers: const {'content-type': 'application/json'});
            }
            return _json(<Object>[_row(2), _row(3)]);
          }
          return _json(<String, Object?>{});
        }),
      );

      final auth = AuthState(api);
      await auth.restore();
      final trust = NotificationCountTrust();
      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        trust: trust,
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
          home: NotificationsScreen(
            repo: Repository(api),
            trust: trust,
            clock: () => DateTime.now(),
          ),
        ),
      ));
      await tester.pump();

      // Read 2 answers first: the newest list is on screen.
      await tester.drag(find.byType(ListView).first, const Offset(0, 320));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byKey(const Key('notification-2')), findsOneWidget,
          reason: 'the newer read must be on screen');
      expect(trust.unconfirmed, isFalse,
          reason: 'a fresh read leaves the pip a server fact');

      // Read 1 now fails, for a list that has already been replaced.
      parked.complete(const <Map<String, Object?>>[]);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(trust.unconfirmed, isFalse,
          reason: 'a read the screen already replaced must not mute the pip '
              'for a count that was freshly read from the server');
      // And the rows stay the newer read's, with no doubt painted over them.
      expect(find.byKey(const Key('notification-2')), findsOneWidget);
      expect(find.byKey(const Key('notification-3')), findsOneWidget);
      expect(find.byKey(const Key('stale-notifications')), findsNothing,
          reason: 'the doubt belongs to the abandoned read, not this list');
    });
  });
}
