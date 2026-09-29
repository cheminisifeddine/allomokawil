// Proves a failed *refresh* on «اشتراكي» is no longer silent.
//
// The screen keeps the previous catalogue when a re-read fails, and that is the
// right call: blanking the screen would throw away a plan this contractor has
// already paid for. The half that was missing is the other one — `_load()`
// recorded the failure in `_error`, and `_error` was read in exactly one place,
// the `catalogue == null` branch. So a failed *first* load was reported and
// every failed *refresh* was not: the refresh button, the pull-to-refresh, and
// the reload that follows every payment request and every redeemed code all
// left his real price, his pending payment and his remaining quota on screen
// with no statement that a newer read had failed.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean — the mistake the pricing-card tick already made once.
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
import 'package:allomokawil/src/data/stale_catalogue_copy.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _catalogue() => {
      'currency': 'DZD',
      'note_ar': 'الاشتراك فقط: بدون عمولة',
      'auto_renew': false,
      'plans': [
        {
          'id': 'pro',
          'name_ar': 'محترف',
          'price_month': 3000,
          'price_year': 30000,
          'quote_limit': -1,
          'portfolio_limit': 60,
          'features': ['ترتيب متقدّم في نتائج البحث'],
        }
      ],
      'current': {'plan': 'free_trial', 'status': 'active'},
      'pending_request': null,
      'payment': {
        'methods': [
          {'id': 'baridimob', 'label_ar': 'بريدي موب (تحويل)'}
        ],
        'support_phone': null,
      },
};

void main() {
  group('staleCatalogueLineAr', () {
    test('names the failure AND the survival of the last good read', () {
      final line = staleCatalogueLineAr(S.errOffline);
      // Both halves are load-bearing. The failure alone is the state the
      // screen is already in; what was missing is the second clause, which is
      // the only thing that tells the reader the figures in front of him are
      // real but not current.
      expect(line, contains(S.errOffline));
      expect(line, matches(RegExp(_arabic)));
      expect(line, contains('لم نتمكن من تحديث'));
    });

    test('a failure with no sentence still says the data may be old', () {
      // `errorCopy` always returns a sentence, so this arm is unreachable in
      // the app. It exists so a bare failure cannot produce a banner that
      // explains nothing at all.
      expect(staleCatalogueLineAr('   '), 'هذه البيانات قد لا تكون محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line = staleCatalogueLineAr('  ${S.errOffline}  ');
      expect(line, contains('لم نتمكن من تحديث بياناتك — هذه أرقام آخر قراءة ناجحة. '));
      expect(line, endsWith(S.errOffline),
          reason: 'the reason is embedded verbatim and trimmed: "$line"');
    });
  });

  group('SubscriptionScreen — a failed refresh is not silent', () {
    /// Renders the screen against a GET that succeeds once and then fails,
    /// exactly the shape of a pull-to-refresh on a flaky connection. Returns
    /// every string on screen once the second read has failed.
    Future<void> loadThenFailRefresh(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            reads++;
            if (reads == 1) {
              return http.Response(jsonEncode(_catalogue()), 200,
                  headers: {'content-type': 'application/json'});
            }
            // A read that fails, the way a dropped cell connection fails.
            return http.Response('', 503,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(AppScope(
        api: api,
        auth: AuthState(api),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const SubscriptionScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The first read worked: the plan is on screen and there is no banner,
      // because there is nothing to doubt yet.
      expect(reads, 1);
      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'a successful first read must not warn about anything');
      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget);

      // The gesture the app itself offers: the refresh action in the AppBar.
      await tester.tap(find.byTooltip(S.planRetry));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(reads, greaterThanOrEqualTo(2),
          reason: 'the refresh never re-read the server');
    }

    testWidgets('the banner appears and the plan stays on screen',
        (tester) async {
      await loadThenFailRefresh(tester);

      expect(find.byKey(const Key('stale-catalogue')), findsOneWidget,
          reason: 'a failed refresh is being swallowed: the screen is showing '
              'this man a price, a quota and a pending-payment slot with no '
              'statement that the re-read he just performed failed');

      // The data is NOT thrown away. Blanking it would be the worse defect:
      // it discards a plan he has already paid for, and it teaches people that
      // refreshing is destructive.
      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget,
          reason: 'a failed refresh must not destroy the catalogue on screen');

      final line = tester
          .widgetList<Text>(find.byKey(const Key('stale-catalogue-line')))
          .map((t) => t.data ?? '')
          .join();
      expect(line, matches(RegExp(_arabic)),
          reason: 'the banner must be readable Arabic, got "$line"');
    });

    testWidgets('a successful refresh clears the banner again',
        (tester) async {
      // The other half: a banner that outlives its cause is just as wrong as
      // one that never appears. The retry is the AppBar action again, this time
      // against a read that succeeds.
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var reads = 0;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            reads++;
            if (reads == 1) {
              return http.Response('', 503,
                  headers: {'content-type': 'application/json'});
            }
            return http.Response(jsonEncode(_catalogue()), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
        timeout: const Duration(milliseconds: 200),
      );

      await tester.pumpWidget(AppScope(
        api: api,
        auth: AuthState(api),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const SubscriptionScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The very first read failed, so there is no catalogue to be stale: this
      // is the `_LoadFailed` dead-read state, and a banner would be a lie
      // about data that was never there.
      expect(find.byKey(const Key('plan-load-failed')), findsOneWidget);
      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'there is no last good read to describe');

      await tester.tap(find.text(S.planRetry));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'a successful read must leave no doubt on screen');
      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget);
    });
  });
}
