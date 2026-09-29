// Proves a failed *re-read* on «ابحث عن مقاول» keeps the contractors and
// states the doubt.
//
// The fifth screen in the family the subscription bug opened, and the worst of
// them: this one never had a cache at all. Every re-read — a pull, a submitted
// search, clearing the box, a filter chip — re-assigned `_future`, and the
// failure branch painted «تعذّر جلب المقاولين» over the whole feed, so a network
// that blinked mid-pull replaced a warm list of contractors with a page saying
// it could not load them. The directory is the **first** screen a client opens
// and the only read a customer makes who is not here to chat, and it is the
// read most likely to fail where it matters: one bar of signal, in the shop,
// pricing the job he is standing in. Every other screen in this family holds
// the user's own history. This one holds the supply, and supply he cannot see
// does not exist.
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
import 'package:allomokawil/src/data/stale_directory_copy.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _me() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

Map<String, dynamic> _worker(int id, String name) => {
      'id': id,
      'user_id': 1000 + id,
      'full_name': name,
      'bio': 'دهان وتشطيب',
      'specialties': <String>['painting'],
      'experience_years': 9,
      'price_range_min': 20000,
      'price_range_max': 90000,
      'service_radius_km': 15,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_rib_exported': 0,
      'rating_avg': 4.6,
      'rating_count': 12,
      'response_time_hours': 3,
      'commune': 'باب الزوار',
      'wilaya': '16',
      'completed_jobs': 40,
      'avatar_url': null,
    };

void main() {
  group('staleDirectoryLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      final line = staleDirectoryLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is the state the
      // screen was already in; what was missing is the second clause, the only
      // thing that says the contractors in front of the reader are real.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('a failure with no sentence still says the list may be old', () {
      expect(staleDirectoryLineAr('   '), 'هذه القائمة قد لا تكون محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleDirectoryLineAr('  ${S.errOffline}  ');
      expect(line, contains('لم نتمكن من تحديث القائمة — هذه آخر نتيجة قرأناها. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });
  });

  group('BrowseScreen — a failed refresh is not a blank directory', () {
    /// Renders the directory against a search that succeeds once and then
    /// fails: the exact shape of a pull-to-refresh on a dropped connection.
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
          if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
            return http.Response(
                jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
                200,
                headers: {'content-type': 'application/json'});
          }
          if (path.endsWith('/api/mobile/workers/search')) {
            reads++;
            if (reads == 1) {
              return http.Response(
                  jsonEncode(<dynamic>[_worker(1, 'مقاول أول')]),
                  200,
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
          home: const BrowseScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The first read worked: the contractor is on screen and there is no
      // band, because there is nothing to doubt yet.
      expect(reads, 1);
      expect(find.byKey(const Key('stale-directory')), findsNothing,
          reason: 'a successful first read must not warn about anything');
      expect(find.text('مقاول أول'), findsOneWidget);

      await afterLoad(tester);
    }

    testWidgets('a failed pull-to-refresh keeps the rows and says so',
        (tester) async {
      await loadThenFailRefresh(tester, afterLoad: (t) async {
        // The gesture the screen itself offers.
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      // The defect: the contractor was replaced by «تعذّر جلب المقاولين», so on
      // the one screen a client opens to find somebody, a network that
      // blinked mid-pull told him there are none.
      expect(find.text('تعذّر جلب المقاولين'), findsNothing,
          reason: 'a failed refresh must not claim the directory is empty');
      expect(find.text('مقاول أول'), findsOneWidget,
          reason: 'the rows that survived the last good read must stay');
      expect(find.byKey(const Key('stale-directory')), findsOneWidget,
          reason: 'a failed refresh must state the doubt');
      expect(find.byKey(const Key('stale-directory-line')), findsOneWidget);
    });

    testWidgets('the band is a header, not a replacement for the list',
        (tester) async {
      await loadThenFailRefresh(tester, afterLoad: (t) async {
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });
      // The doubt is an annotation *on* the data, so the band is a child of
      // the scrolling list itself. Asserted as a descendant rather than as an
      // item count, because a count would still pass if the band were swapped
      // in for a contractor: the thing that must not happen is the list being
      // replaced, and only the tree shape rules that out.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byKey(const Key('stale-directory')),
        ),
        findsOneWidget,
        reason: 'the band must be a header inside the list, not the list',
      );
      // And the contractor is still a child of that same list.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('مقاول أول'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a first read that fails still gets the full-screen error',
        (tester) async {
      // The fix must not weaken the branch it moves. With no cache there is
      // genuinely nothing to draw, and the retry button is the whole answer —
      // the same split `chat_list_screen` and `subscription_screen` use.
      tester.view.physicalSize = const Size(1080, 2532);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final path = req.url.path;
          if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
            return http.Response(
                jsonEncode(<String, Object?>{'token': 't', 'user': _me()}),
                200,
                headers: {'content-type': 'application/json'});
          }
          if (path.endsWith('/api/mobile/workers/search')) {
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

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
          home: const BrowseScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);
      expect(find.byKey(const Key('stale-directory')), findsNothing,
          reason: 'there is nothing to qualify — the error is the truth here');
    });
  });
}
