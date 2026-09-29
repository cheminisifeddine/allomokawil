// Proves a failed *refresh* on «الرسائل» keeps the rows and states the doubt.
//
// The inverse of the subscription bug and the worse half of the pair: that
// screen kept its data and hid the failure, this one hid the data *and* showed
// the failure. The cache was written for exactly this state — "kept so a
// re-read does not blank the screen" — and a *pending* re-read used it, while a
// *failed* one answered `null` and replaced the inbox with the full-screen
// error. On the one surface that admits unsent messages (the per-row queued
// pill), the bad connection that stopped a message sending is the same one
// that hid the evidence it never sent, and an empty inbox in this app is a
// true statement with a real meaning.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stale_inbox_copy.dart';
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _inbox() => {
      'id': 7,
      'customer_id': 391,
      'worker_user_id': 392,
      'other_user_name': 'سمير بن عمر',
      'last_message_content': 'بخصوص ديال المطبخ',
      'unread_count': 2,
      'last_message_at': '2026-09-29T10:00:00Z',
    };

Map<String, dynamic> _me() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

void main() {
  group('staleInboxLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      final line = staleInboxLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is the state the
      // screen was already in; what was missing is the second clause, the only
      // thing that says the conversations in front of the reader are real.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('a failure with no sentence still says the list may be old', () {
      expect(staleInboxLineAr('   '), 'هذه المحادثات قد لا تكون محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleInboxLineAr('  ${S.errOffline}  ');
      expect(line, contains('لم نتمكن من تحديث المحادثات — هذه آخر قائمة قرأناها. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });
  });

  group('ChatListScreen — a failed refresh is not a blank inbox', () {
    /// Renders the inbox against a GET that succeeds once and then fails,
    /// exactly the shape of a pull-to-refresh on a dropped connection.
    Future<void> loadThenFailRefresh(
      WidgetTester tester, {
      required Future<void> Function(WidgetTester) afterLoad,
    }) async {
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          // A real session first: `AuthGate.isGuest` swaps the whole inbox for
          // a sign-in wall when there is no user, so an unauthenticated test
          // would pass against a screen that never drew a conversation at all.
          if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
            return http.Response(
                jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
                200,
                headers: {'content-type': 'application/json'});
          }
          if (path.endsWith('/api/mobile/conversations')) {
            reads++;
            if (reads == 1) {
              return http.Response(jsonEncode(<dynamic>[_inbox()]), 200,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

      final repo = Repository(api);
      final auth = AuthState(api);
      await auth.restore();
      await auth.login(phone: '0773000000', password: 'secret123',
          rememberMe: true);
      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: ChatListScreen(repo: repo),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The first read worked: the row is on screen and there is no banner,
      // because there is nothing to doubt yet.
      expect(reads, 1);
      expect(find.byKey(const Key('stale-inbox')), findsNothing,
          reason: 'a successful first read must not warn about anything');
      expect(find.text('سمير بن عمر'), findsOneWidget);

      await afterLoad(tester);
    }

    testWidgets('a failed pull-to-refresh keeps the rows and says so',
        (tester) async {
      await loadThenFailRefresh(tester, afterLoad: (t) async {
        // The gesture the screen itself offers.
        await t.drag(find.text('سمير بن عمر'), const Offset(0, 320));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      // The defect: the row was replaced by «تعذّر جلب الرسائل», so the user
      // was told there is nothing here — and the queued pill that proves a
      // message never left went with it.
      expect(find.text('تعذّر جلب الرسائل'), findsNothing,
          reason: 'a failed refresh must not claim the inbox is empty');
      expect(find.text('سمير بن عمر'), findsOneWidget,
          reason: 'the rows that survived the last good read must stay');
      expect(find.byKey(const Key('stale-inbox')), findsOneWidget,
          reason: 'a failed refresh must state the doubt');
      expect(find.byKey(const Key('stale-inbox-line')), findsOneWidget);
    });

    testWidgets('the banner is a header, not a replacement for the list',
        (tester) async {
      await loadThenFailRefresh(tester, afterLoad: (t) async {
        await t.drag(find.text('سمير بن عمر'), const Offset(0, 320));
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
          matching: find.byKey(const Key('stale-inbox')),
        ),
        findsOneWidget,
        reason: 'the banner must be a header inside the list, not the list',
      );
      // And the row is still a child of that same list.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('سمير بن عمر'),
        ),
        findsOneWidget,
      );
    });
  });
}
