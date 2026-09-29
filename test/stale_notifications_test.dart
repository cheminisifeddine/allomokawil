// Proves a failed *refresh* on the notification centre keeps the rows, says
// the doubt out loud, and stops the header's pip claiming the number is the
// server's.
//
// The **eighth** screen in the failed-read family and the only member that
// failed **silently**. The other seven destroyed the data *and* reported it —
// wrong, but loud. This one kept the rows and reported nothing, because
// `_load` assigned `_error` and `_body` read it only inside
// `if (_items.isEmpty)`. On a populated list the field was unreachable, so a
// failed pull-to-refresh — the most ordinary failure on this screen — left the
// centre drawing yesterday's rows as if nothing had happened, and silence is
// indistinguishable from "nothing happened".
//
// It mattered more here than anywhere else because this list is the *input*
// to the unread pip the home header paints: `_unread` counts these very rows,
// so a stale read here is the source of a number the user looks at one screen
// later. `notification_count_trust.dart` already existed to stop exactly that
// number being drawn as a fact, and this screen already withdrew it for the
// one failure it could see — the `_settleRead` re-read that could not run.
// A plain refresh was the odd one out.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean.
import 'dart:convert';

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
import 'package:allomokawil/src/data/notification_count_trust.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stale_notifications_copy.dart';
import 'package:allomokawil/src/screens/notifications/notifications_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, Object?> _sessionUser() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

/// A notification the D1 row shape produces, stamped in the past so the
/// relative-time column is «قبل ساعة» rather than «الآن».
Map<String, Object?> _row({int id = 5}) {
  final t = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  String two(int v) => v.toString().padLeft(2, '0');
  return {
    'id': id,
    'type': 'new_quote',
    'title': 'عرض جديد على مشروعك',
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
  group('staleNotificationsLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      final line = staleNotificationsLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is the state the
      // screen could already be in; what was missing is the second clause —
      // the only thing that says the rows in front of the reader are real.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('says there may be notifications the user has not seen', () {
      // The half a list that *stays* on screen can never say for itself. The
      // rows are real, but the whole point of this screen is what arrived
      // while it was closed — so a stale read is not a neutral fact here, it
      // is a possible miss, and the copy has to say so.
      expect(staleNotificationsLineAr(S.errOffline),
          contains('قد تكون هناك إشعارات لم تصلك بعد'));
    });

    test('a failure with no sentence still warns about unseen notifications',
        () {
      expect(staleNotificationsLineAr('   '),
          'قد تكون هناك إشعارات لم تصلك بعد');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleNotificationsLineAr('  ${S.errOffline}  ');
      expect(
          line,
          contains(
              'لم نتمكن من تحديث الإشعارات — هذه آخر قائمة قرأناها، وقد تكون هناك إشعارات لم تصلك بعد. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });
  });

  group('NotificationsScreen — a failed refresh is not a silent one', () {
    /// Renders the centre against a GET that succeeds once and then fails,
    /// exactly the shape of a pull-to-refresh on a dropped connection.
    Future<void> loadThenFailRefresh(
      WidgetTester tester, {
      required Future<void> Function(WidgetTester, NotificationCountTrust)
          afterLoad,
    }) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_sessionUser()),
      });

      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (path == '/api/notifications') {
            reads++;
            if (reads == 1) {
              return _json(<Object>[_row()]);
            }
            return http.Response('', 503,
                headers: const {'content-type': 'application/json'});
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
      await tester.pumpAndSettle();

      // The first read worked: the row is on screen and there is no banner,
      // because there is nothing to doubt yet.
      expect(reads, 1);
      expect(find.byKey(const Key('stale-notifications')), findsNothing,
          reason: 'a successful first read must not warn about anything');
      expect(trust.unconfirmed, isFalse);

      await afterLoad(tester, trust);
    }

    testWidgets('a failed pull-to-refresh keeps the rows and says so',
        (tester) async {
      await loadThenFailRefresh(tester,
          afterLoad: (t, trust) async {
        // The gesture the screen itself offers.
        await t.drag(find.text('عرض سعر جديد'), const Offset(0, 320));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      // The defect: no banner at all. The row was still there — that was never
      // the bug — but nothing said the read had failed, so the screen claimed
      // its list was current.
      expect(find.byKey(const Key('stale-notifications')), findsOneWidget,
          reason: 'a failed refresh must state the doubt');
      expect(find.byKey(const Key('stale-notifications-line')), findsOneWidget);
      // And the rows stayed. A list that is quietly wrong is not the fix.
      expect(find.text('عرض سعر جديد'), findsOneWidget,
          reason: 'the rows that survived the last good read must stay');
    });

    testWidgets('the banner is a header, not a replacement for the list',
        (tester) async {
      await loadThenFailRefresh(tester, afterLoad: (t, trust) async {
        await t.drag(find.text('عرض سعر جديد'), const Offset(0, 320));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });
      // The doubt is an annotation *on* the data, so the banner is a child of
      // the scrolling list itself. Asserted as a descendant rather than as an
      // item count, because a count would still pass if the banner were
      // swapped in for a row: the thing that must not happen is the list being
      // replaced, and only the tree shape rules that out.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byKey(const Key('stale-notifications')),
        ),
        findsOneWidget,
        reason: 'the banner must be a header inside the list, not the list',
      );
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('عرض سعر جديد'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed refresh also withdraws the header pip\'s trust',
        (tester) async {
      // The half that reaches the *next* screen. `_unread` counts these rows,
      // so a failed read here means the number behind the home header's pip is
      // the phone's memory — and `notification_count_trust.dart` exists to stop
      // the header drawing that as a fact. The screen already withdrew it for
      // the `_settleRead` failure; a plain refresh did not.
      await loadThenFailRefresh(tester, afterLoad: (t, trust) async {
        expect(trust.unconfirmed, isFalse,
            reason: 'a good read leaves the pip a fact');
        await t.drag(find.text('عرض سعر جديد'), const Offset(0, 320));
        await t.pumpAndSettle(const Duration(seconds: 3));
        expect(trust.unconfirmed, isTrue,
            reason: 'a failed refresh must mute the pip the rows feed');
      });
    });

    testWidgets('a failed FIRST read is still the full-screen error',
        (tester) async {
      // The other half of the split, and the reason this is a fix and not a
      // deletion: with no rows to keep, there is genuinely nothing to draw and
      // the retry button is the whole answer.
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_sessionUser()),
      });
      final api = ApiClient(
        baseUrls: const ['https://api.test'],
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/notifications') {
            return http.Response('', 503,
                headers: const {'content-type': 'application/json'});
          }
          return _json(<String, Object?>{});
        }),
      );
      final auth = AuthState(api);
      await auth.restore();
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
          home: NotificationsScreen(
            repo: Repository(api),
            clock: () => DateTime.now(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stale-notifications')), findsNothing,
          reason: 'there are no rows to annotate, so there is no banner');
      expect(find.text(S.retry), findsOneWidget,
          reason: 'the retry button is the whole answer when nothing loaded');
    });
  });
}
