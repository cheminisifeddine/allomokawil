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
import 'package:allomokawil/src/data/read_age_ar.dart';
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


  group('staleCatalogueLineWithAgeAr', () {
    test('the age is APPENDED, never substituted for the reason', () {
      // The second rule of the family, and the one that is easiest to write
      // wrong: a band that traded the failure for a timestamp would say the
      // quota is "old" and never say *why*, which reads as a routine label
      // rather than a failed write.
      final line = staleCatalogueLineWithAgeAr(
        S.errOffline,
        DateTime(2026, 9, 29, 9, 0),
        now: DateTime(2026, 9, 29, 9, 40),
      );
      expect(line, contains(S.errOffline),
          reason: 'the diagnosed failure must survive the age: "$line"');
      expect(line, contains('لم نتمكن من تحديث بياناتك'));
      expect(line, contains('قبل 40 دقيقة'));
      expect(line, contains('\nقرأناها قبل 40 دقيقة.'),
          reason: 'the age is a second sentence, not an edit of the first');
    });

    test('a read inside the minute leaves the line byte for byte identical', () {
      // Silence, not "الآن". The catalogue was just read, so there is nothing
      // to doubt, and every assertion the previous tick wrote still holds.
      //
      // **The silent window is the first 60 seconds, and 60 itself speaks.**
      // `readAgeAr` is `diff.inSeconds < 60`, so a read exactly a minute old
      // is already datable and prints «قبل دقيقة». The first version of this
      // test listed 08:59 against a 09:00 clock as a *silent* case, which is
      // 60 seconds — datable — and it failed for exactly that reason. A
      // boundary assertion written from the prose instead of from the code is
      // a test of the writer's memory.
      final base = staleCatalogueLineAr(S.errOffline);
      final now = DateTime(2026, 9, 29, 9, 1);
      for (final at in <DateTime?>[
        DateTime(2026, 9, 29, 9, 0, 30), // 30s old — under the minute
        DateTime(2026, 9, 29, 9, 0, 59), // 1s old — the last silent instant
        DateTime(2026, 9, 29, 9, 30), // 31 MINUTES AHEAD — clock skew
        null, // never read
      ]) {
        expect(
            staleCatalogueLineWithAgeAr(S.errOffline, at, now: now), base,
            reason: 'an undatable or undated read must add nothing: $at');
      }
      // And the other side of the same boundary, asserted rather than assumed:
      // 60 seconds is not silent.
      expect(
          staleCatalogueLineWithAgeAr(S.errOffline, DateTime(2026, 9, 29, 9),
              now: now),
          contains('قبل دقيقة'));
    });

    test('a stamp ahead of the clock is not aged', () {
      // Clock skew is somebody else's broken timestamp; ageing it into a
      // future would have the app blame this contractor's phone for it.
      expect(
          staleCatalogueLineWithAgeAr(S.errOffline,
              DateTime(2026, 9, 29, 9, 30), now: DateTime(2026, 9, 29, 9)),
          staleCatalogueLineAr(S.errOffline));
    });

    test('the age is the shared read-age rule, not a local grammar', () {
      // The rule belongs to `readAgeAr`, so this surface cannot decide for
      // itself what "old enough to mention" means.
      final at = DateTime(2026, 9, 29, 9, 0);
      final now = DateTime(2026, 9, 29, 14, 0);
      expect(staleCatalogueAgeAr(at, now: now), readAgeAr(at, now: now));
    });

    test('a real age reads the way the rest of the app reads it', () {
      // A real value, not a boundary: the whole reason this surface is worth
      // the second sentence is that a price read at 08:00 and a price read
      // twelve minutes ago are not the same decision.
      //
      // The app counts in **whole** hours and has no compound form, so 2h05m
      // is «قبل ساعتين» and not «قبل ساعتين و 5 دقائق». This test first
      // asserted the compound and failed: the point of routing the age through
      // [readAgeAr] is that this surface speaks exactly as the notification
      // list beside it does, so a figure cannot be dated two ways in one app.
      final line = staleCatalogueLineWithAgeAr(
        S.errOffline,
        DateTime(2026, 9, 29, 12, 0),
        now: DateTime(2026, 9, 29, 14, 5),
      );
      expect(line, contains('قرأناها قبل ساعتين.'), reason: 'got "$line"');
      expect(line, isNot(contains('و ')),
          reason: 'the app has no compound relative time, and this surface '
              'must not invent one: "$line"');
    });
  });

  group('SubscriptionScreen — a failed refresh is not silent', () {
    /// Renders the screen against a GET that succeeds once and then fails,
    /// exactly the shape of a pull-to-refresh on a flaky connection. Leaves
    /// the second read failed and the band on screen.
    ///
    /// [now] and [reads] are handed back so a test can age the band past the
    /// minute the clock is injected across — the only way to photograph the
    /// dated case, because a real wall clock can only ever produce the silent
    /// one.
    Future<({int reads, ApiClient api})> loadThenFailRefresh(
        WidgetTester tester, {
      required DateTime Function() now,
    }) async {
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
          home: SubscriptionScreen(clock: now),
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
      return (reads: reads, api: api);
    }

    testWidgets('the banner appears and the plan stays on screen',
        (tester) async {
      await loadThenFailRefresh(tester, now: () => DateTime(2026, 9, 29, 9));

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
    testWidgets('a band on a forty-minute-old read says how old it is',
        (tester) async {
      // The pure half above is the wording; this is the screen obeying it. A
      // correct helper wired to an unchanged screen passes every assertion in
      // the group above clean, which is the mistake the pricing-card tick
      // already made once — so the claim is a NUMBER on the banner, not the
      // band's presence.
      //
      // The failure the read does not catch: the scenario has to let the read
      // SUCCEED once and then fail, and the clock has to cross a whole minute
      // afterwards. A test that pumps frames only, or that fails the first
      // read, photographs the one frame where the age is deliberately silent
      // and passes against a screen that never dated anything.
      var now = DateTime(2026, 9, 29, 9, 0);
      await loadThenFailRefresh(tester, now: () => now);

      expect(find.byKey(const Key('stale-catalogue')), findsOneWidget);
      final atNine = tester
          .widgetList<Text>(find.byKey(const Key('stale-catalogue-line')))
          .map((t) => t.data ?? '')
          .join();
      // The read landed one frame ago, so the age is silence — and the line is
      // the old one, byte for byte. Asserted so a later tick that makes the
      // age speak too eagerly has something to fail against.
      expect(atNine, isNot(contains('قرأناها')),
          reason: 'a read inside the minute must add nothing: "$atNine"');

      // The network went under the phone and he does not touch it for forty
      // minutes. The tick re-dates the band; the screen has to rebuild for
      // that to happen, which is the wiring this test exists for.
      now = DateTime(2026, 9, 29, 9, 40);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));

      final line = tester
          .widgetList<Text>(find.byKey(const Key('stale-catalogue-line')))
          .map((t) => t.data ?? '')
          .join();
      expect(line, contains('قبل 40 دقيقة'),
          reason: 'the band still cannot say how old the price on it is');
      // Asserted by *shape*, not by a constant: a 503 and a dropped connection
      // are two different sentences from `errorCopy`, and pinning the test to
      // one of them makes the assertion a lie the moment the mapping moves.
      // What must survive is the diagnosed failure itself — the age is
      // appended, never substituted for it. The first version of this line
      // asserted `S.errOffline` against a 503, which `errorCopy` renders as
      // «خلل مؤقّت في الخادم», and it failed for exactly that reason.
      expect(line, contains('لم نتمكن من تحديث بياناتك'),
          reason: 'the failure clause must survive the age: "$line"');
      expect(line.split('\n').first, isNot(contains('قرأناها')),
          reason: 'the age is a second sentence, not an edit of the first');

      // The figures themselves are untouched: this is the one surface where
      // the band sits over a price and a quota, and blanking them would
      // discard a plan he has already paid for.
      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget);
    });

    testWidgets('a read that succeeds again drops the date with the doubt',
        (tester) async {
      // The other half of the tick. A band that keeps ageing after the read it
      // was complaining about has been answered is a band that tells the
      // contractor his price is forty minutes old when it was fetched this
      // second. The stamp has to be written on every settled success, not
      // only on the first.
      var now = DateTime(2026, 9, 29, 9, 0);
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var fail = true;
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/api/mobile/subscription')) {
            if (fail) {
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
          home: SubscriptionScreen(clock: () => now),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // First read fails, so there is nothing to age.
      expect(find.byKey(const Key('plan-load-failed')), findsOneWidget);

      fail = false;
      await tester.tap(find.text(S.planRetry));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'a successful read must leave no doubt on screen');

      // Half an hour later the screen is still alive, and the timer must not
      // have resurrected a band out of a stamp that is now current.
      now = DateTime(2026, 9, 29, 9, 30);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'a live catalogue must never grow a staleness band');
      expect(find.byKey(const Key('plan-pro-month')), findsOneWidget);

      // **The half this test missed the first time.** Everything above is
      // invisible to a stale stamp, because the band is hidden whenever the
      // read is healthy — so a stamp written once and never refreshed passes
      // all of it. The sabotage is not theoretical: a screen that stamps only
      // its *first* successful read answers the second outage with the age of
      // the first one, and the contractor is told a price he fetched this
      // second is an hour old. Nothing crashes; the number is simply wrong on
      // the one card the number is money.
      //
      // So the clock moves on, a *second* read succeeds at 09:30, and only
      // then does the network go. The band now has two candidate stamps and
      // they name different reads: 30 minutes, or 90.
      //
      // **This staging is the second thing the test got wrong first.** The
      // obvious version moved the clock and failed the read directly, which
      // set the stamp at 09:00 and looked at 09:30 — the same instant a
      // screen that only ever stamps its *first* read would report. Correct
      // and broken code printed the identical number and the sabotage passed.
      // A test that cannot tell right from wrong is a comment; this one
      // interleaves a second success so it can.
      now = DateTime(2026, 9, 29, 9, 30);
      await tester.tap(find.byTooltip(S.planRetry));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const Key('stale-catalogue')), findsNothing,
          reason: 'the read at 09:30 succeeded; the stamp must move with it');

      fail = true;
      now = DateTime(2026, 9, 29, 11, 0);
      await tester.tap(find.byTooltip(S.planRetry));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.byKey(const Key('stale-catalogue')), findsOneWidget,
          reason: 'the read failed again; there is a doubt to state');

      final aged = tester
          .widgetList<Text>(find.byKey(const Key('stale-catalogue-line')))
          .map((t) => t.data ?? '')
          .join();
      //
      // **The expected string is `«قبل ساعة»`, and that is a defect, not a
      // feature.** It is the *distinctive* value that matters: the sabotage
      // stamps 09:00, which is 120 minutes and reads «قبل ساعتين», so this
      // assertion separates correct from broken even while sitting on a
      // lossy boundary. 90 minutes and 120 minutes are different reads of the
      // catalogue and they say different things.
      //
      // The lossiness is `relativeTimeAr`'s and it is **app-wide**, not this
      // screen's: `diff.inHours < 24` floors, so 60 through 119 minutes all
      // print «قبل ساعة» and the minutes are discarded outright. Verified on
      // this tick by probing `readAgeAr` directly — 1→«قبل دقيقة», 59→«قبل 59
      // دقيقة», 60→«قبل ساعة», 90→«قبل ساعة», 119→«قبل ساعة», 120→«قبل
      // ساعتين». On the notifications list that is cosmetic; on this one it
      // means a price read an hour ago and a price read two hours ago are
      // the same sentence. It is filed as its own item rather than fixed
      // here: `relativeTimeAr` is shared by the chat list, the notification
      // centre and every member of the stale-band family, and a change to it
      // needs the full suite, not one ten-minute tick.
      expect(aged, contains('قبل ساعة'),
          reason: 'the figures on screen were read at 09:30, not at the very '
              'first read at 09:00 — a stamp that is never refreshed dates '
              'the wrong read and states a number nobody can rely on: "$aged"');
      expect(aged, isNot(contains('قبل ساعتين')),
          reason: 'that is the 09:00 stamp talking: 120 minutes from 11:00');
    });
  });
}
