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
import 'dart:async';
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
import 'package:allomokawil/src/data/stale_market_copy.dart';
import 'package:allomokawil/src/data/stale_projects_copy.dart';
import 'package:allomokawil/src/screens/browse/browse_screen.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _me() => {
      'id': 391,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

/// [wilaya] is a parameter so a filter case can put a contractor in a
/// different wilaya from [mainWorker], which is what makes "the wrong city's
/// contractors under this chip" something a test can see rather than argue
/// about.
Map<String, dynamic> _workerIn(
        int id, String name, String wilaya, String specialty) =>
    _worker(id, name)
      ..['wilaya'] = wilaya
      ..['specialties'] = <String>[specialty];

/// Taps a trade chip, **scrolling it into the strip first**.
///
/// The strip is a horizontal [SingleChildScrollView] over sixteen pills, so a
/// chip past the fold is built but not hittable. `tap` on it derives an offset
/// outside the root and prints a warning instead of failing, so a case that
/// taps one without this **passes for the wrong reason**: the filter never
/// changed, and the assertion then proves something about the unfiltered list.
/// The first version of the two filter cases did exactly that and one of them
/// failed against the unfixed screen for a reason that had nothing to do with
/// the defect. `warnIfMissed: false` is deliberately NOT used: this returns
/// only once the chip is genuinely on screen.
Future<void> tapChip(WidgetTester tester, String slug) async {
  final chip = find.byKey(ValueKey('trade-$slug'));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  expect(tester.getCenter(chip).dx,
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
      reason: 'the chip must be on screen for the tap to mean anything');
  await tester.tap(chip);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

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

  /// Renders the directory against a search that succeeds once and then
  /// fails: the exact shape of a pull-to-refresh on a dropped connection.
  Future<void> loadThenFailRefresh(
    WidgetTester tester, {
    required Future<void> Function(WidgetTester) afterLoad,

    /// The clock the band is dated against, when a test needs to move time.
    /// Defaults to the real one, so every existing case is unchanged.
    DateTime Function()? clock,

    /// The rows the FIRST read answers with. The default list is the one the
    /// pull cases have always asserted on; a filter case passes a second
    /// contractor in another wilaya so "the other filter's rows" means
    /// something that could be seen on screen.
    List<Map<String, dynamic>>? firstRead,

    /// Decides what every read **after the first** answers, which is the only
    /// part of this screen a case needs to steer: read 1 is the first filter
    /// tap, read 2 the second.
    ///
    /// Returning null is the default 503. A case that returns a future it
    /// does not complete **parks** that read, which is the only way to
    /// reproduce a tap-tap-tap with the second read still open — a screen that
    /// cannot be observed in that state cannot be tested in it.
    Future<http.Response?> Function(int read)? respond,

    /// The client timeout. The default 200 ms is there so a 503 settles
    /// inside `pumpAndSettle`; a case that parks a read on purpose cannot use
    /// it, because it fires while the read is parked and converts the case
    /// into a failed-read case it is not. See the race case for what that
    /// did the first time this case was written.
    Duration timeout = const Duration(milliseconds: 200),
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
          final index = reads++;
          if (index == 0) {
            return http.Response(
                jsonEncode(<dynamic>[
                  ...firstRead ?? <Map<String, dynamic>>[
                    _worker(1, 'مقاول أول')
                  ],
                ]),
                200,
                headers: {'content-type': 'application/json'});
          }
          final custom = respond == null ? null : await respond(index);
          return custom ??
              http.Response('', 503,
                  headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode(<String, Object?>{}), 200,
            headers: {'content-type': 'application/json'});
      }),
      timeout: timeout,
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
        home: BrowseScreen(clock: clock),
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

  group('staleDirectoryAgeAr — the band says HOW old, not just that it is old',
      () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('a read inside the minute is not a number worth printing', () {
      // A pull that failed on a slow connection while the list is twenty
      // seconds old is a hiccup. «قبل 20 ثانية» under it is a reassurance
      // dressed as a measurement, and the band already said everything there
      // is to say.
      expect(staleDirectoryAgeAr(base.subtract(const Duration(seconds: 20)),
          now: base), isEmpty);
    });

    test('a minute and older is counted in the app\'s own words', () {
      // Same grammar the market and the project band print, asserted on this
      // surface so the three cannot drift into dating one read two ways.
      expect(staleDirectoryAgeAr(base.subtract(const Duration(minutes: 12)),
          now: base), 'قبل 12 دقيقة');
      expect(staleDirectoryAgeAr(base.subtract(const Duration(minutes: 2)),
          now: base), 'قبل دقيقتين');
      expect(staleDirectoryAgeAr(base.subtract(const Duration(hours: 3)),
          now: base), 'قبل 3 ساعات');
      expect(staleDirectoryAgeAr(base.subtract(const Duration(hours: 2)),
          now: base), 'قبل ساعتين');
    });

    test('a read that crossed midnight is yesterday, not N hours', () {
      // 28 Sep 10:00 read, 29 Sep 14:00 now: **28 hours**, but it crossed one
      // midnight, so the calendar day count is 1. Asserted here because
      // `relativeTimeAr` counts **calendar** days and a future "simplification"
      // of this file into a 24-hour period count is the exact defect that made
      // one message read two ways in the chat list.
      expect(staleDirectoryAgeAr(DateTime(2026, 9, 28, 10), now: base), 'أمس');
    });

    test('a read older than a year is dated, not counted in months', () {
      expect(staleDirectoryAgeAr(DateTime(2024, 3, 9), now: base), contains('/'));
    });

    test('clock skew is not the future', () {
      // A stamp ahead of the phone is a broken clock between the server and
      // the handset. Ageing it would print «قبل -3 دقيقة» and blame the
      // reader\'s phone for somebody else\'s clock.
      expect(staleDirectoryAgeAr(base.add(const Duration(minutes: 3)), now: base),
          isEmpty);
    });

    test('a read that never happened has no age', () {
      expect(staleDirectoryAgeAr(null, now: base), isEmpty);
    });
  });

  group('staleDirectoryLineWithAgeAr — the age is added, the reason is kept',
      () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('an undatable read produces the OLD line, byte for byte', () {
      // The contract that protects this screen\'s existing screenshot. A
      // shorter "variant" here would re-open a defect on a screen that is
      // already correct, so the fallback is equality, not resemblance.
      expect(staleDirectoryLineWithAgeAr(S.errOffline, null, now: base),
          staleDirectoryLineAr(S.errOffline));
      expect(
          staleDirectoryLineWithAgeAr(
              S.errOffline, base.subtract(const Duration(seconds: 5)),
              now: base),
          staleDirectoryLineAr(S.errOffline));
    });

    test('an old read gains a second sentence, and keeps the reason', () {
      // Both halves are load-bearing: the reason says *why* the list is not
      // newer, the age says how wrong it can be. On the directory the age is
      // the one that decides whether the man in front of the reader is still
      // free today.
      final line = staleDirectoryLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(minutes: 12)),
          now: base);
      expect(line, contains(S.errOffline));
      expect(line, contains('لم نتمكن من تحديث القائمة'));
      expect(line, contains('قبل 12 دقيقة'));
      expect(line, matches(RegExp(_arabic)));
    });

    test('the age is its own sentence, so the band stays two lines tall', () {
      final line = staleDirectoryLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(hours: 3)),
          now: base);
      expect(line, contains('\n'));
      expect(line.split('\n'), hasLength(2));
      expect(line.split('\n').last, 'قرأناها قبل 3 ساعات.');
    });

    test('the failure with no sentence still ages', () {
      final line = staleDirectoryLineWithAgeAr(
          '   ', base.subtract(const Duration(minutes: 5)), now: base);
      expect(line, startsWith(staleDirectoryLineAr('   ')));
      expect(line, contains('قبل 5 دقائق'));
    });

    test('the same read dates the same way on all three surfaces', () {
      // The family exists because three files re-derived the same grammar. A
      // future edit that hardens one threshold and not another is the defect
      // this assertion is for: one read, one age, three surfaces.
      final read = base.subtract(const Duration(minutes: 12));
      final here = staleDirectoryAgeAr(read, now: base);
      expect(staleMarketAgeAr(read, now: base), here);
      expect(staleProjectsAgeAr(read, now: base), here);
    });
  });

  group('BrowseScreen — a failed refresh is not a blank directory', () {
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
  group('BrowseScreen — the band dates the read it is qualifying', () {
    testWidgets('a failed refresh says how old the surviving rows are',
        (tester) async {
      // The band already said «هذه آخر نتيجة قرأناها». What it could not say is
      // how long ago that was, and on *this* screen it is the half that decides
      // the next action: the directory holds the supply, and a contractor's
      // availability and price band change with no push the app can send. A
      // client standing in a shop with one bar, reading a list that failed to
      // refresh, is asking whether the man in front of him is still free
      // today — and «the refresh failed» does not answer that.
      var now = DateTime(2026, 9, 29, 9, 0);
      await loadThenFailRefresh(tester, clock: () => now, afterLoad: (t) async {
        // Twelve minutes later the directory fails to re-read.
        now = DateTime(2026, 9, 29, 9, 12);
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      final text =
          tester.widget<Text>(find.byKey(const Key('stale-directory-line')))
              .data!;
      // Both halves: the reason says why the list is not newer, the age says
      // how wrong it can be. A band that traded one for the other is worse
      // than the band it replaces.
      expect(text, contains('لم نتمكن من تحديث القائمة'));
      expect(text, contains('قبل 12 دقيقة'));
      // And the rows are still there, dated. The age is an annotation on the
      // list, never a replacement for it.
      expect(find.text('مقاول أول'), findsOneWidget);
    });

    testWidgets('a fresh read is not dated, and the old wording is untouched',
        (tester) async {
      // The contract that protects this screen's existing screenshot: a read
      // inside the minute produces the OLD line, byte for byte. A shorter
      // "variant" would silently re-open a defect on a screen already correct.
      var now = DateTime(2026, 9, 29, 9, 0);
      await loadThenFailRefresh(tester, clock: () => now, afterLoad: (t) async {
        // Before the pull, a good read has nothing to qualify.
        expect(find.byKey(const Key('stale-directory-line')), findsNothing,
            reason: 'a successful first read must not print an age');
        now = DateTime(2026, 9, 29, 9, 0, 20); // 20 seconds later
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      final text =
          tester.widget<Text>(find.byKey(const Key('stale-directory-line')))
              .data!;
      expect(text, staleDirectoryLineAr(S.errServer),
          reason: 'a read still inside the minute must read exactly as it did '
              'before the age existed — «قبل 20 ثانية» would be a reassurance '
              'dressed as a measurement');
    });

    testWidgets('the age advances on its own, without a re-read',
        (tester) async {
      // The tick is the half a stamp alone does not give. Without it the age is
      // frozen at whatever it said when the failure landed: a client who
      // leaves the directory open while he prices a job keeps reading
      // «قبل 12 دقيقة» on a list that is now an hour old — the same lie in a
      // slower costume.
      var now = DateTime(2026, 9, 29, 9, 0);
      await loadThenFailRefresh(tester, clock: () => now, afterLoad: (t) async {
        now = DateTime(2026, 9, 29, 9, 12);
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });
      expect(find.textContaining('قبل 12 دقيقة'), findsOneWidget);

      // Fifty minutes pass with no request issued at all. Nothing is pulled,
      // nothing is refetched — the only thing that moves is the clock.
      now = DateTime(2026, 9, 29, 9, 50);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('قبل 12 دقيقة'), findsNothing,
          reason: 'a frozen age is the same confidently-wrong claim this file '
              'was opened for, in slower motion');
      // Counted from the **successful read at 09:00**, not from the failure at
      // 09:12 — the age describes when the contractors were really on the
      // server, which is the whole point of it.
      expect(find.textContaining('قبل 50 دقيقة'), findsOneWidget,
          reason: 'the tick must age the band without a re-read');
    });
  });

  // ── The cross-filter half ──────────────────────────────────────────────
  //
  // Added 30 Sep, after the sibling defect in `projects_screen` shipped the
  // day before. The directory was the seventh screen in this family and the
  // only one still holding a **bare** `List<WorkerProfile>?`: it has no record
  // of which filters it was read for, so `shown` — a failed *or* waiting read
  // falls back to the cache — answered any question with the last one's rows.
  // Tap «البليدة» on one bar of signal and the all-wilaya directory is drawn
  // under the chip that says Blida.
  //
  // `_matchesQuery` cannot catch it: it narrows on the typed word and the
  // taxonomy name, and a contractor in the wrong city with the wrong trade
  // matches neither — he is simply drawn, correctly formatted, in the wrong
  // row of the wrong list.
  group('BrowseScreen — a failed FILTER switch is not answered by the last '
      'filter', () {
    testWidgets('a failed trade switch does not answer with ALL trades',
        (tester) async {
      await loadThenFailRefresh(
        tester,
        firstRead: <Map<String, dynamic>>[
          _workerIn(1, 'مقاول أول', '16', 'painting'),
          // A second contractor who is NOT a painter. Under the fix this row is
          // on screen only while no trade filter is lit, so drawing him under
          // a lit «السباكة» chip is the defect made visible.
          _workerIn(2, 'مقاول السباكة', '16', 'plumbing'),
        ],
        afterLoad: (t) async {
          await tapChip(t, 'plumbing');
        },
      );

      // The defect, stated as the user meets it: the chip he just tapped is
      // answering with rows that are not that chip's rows.
      expect(find.text('مقاول السباكة'), findsNothing,
          reason: 'the plumber must not be drawn as the answer to a plumbing '
              'read that failed — that is precisely what he is');
      expect(find.text('تعذّر جلب المقاولين'), findsOneWidget,
          reason: 'a failed switch with nothing of its own must say so rather '
              'than borrow another filter\'s rows');
      expect(find.byKey(const Key('stale-directory')), findsNothing,
          reason: 'the band qualifies rows; with no rows for THIS question '
              'there is nothing to qualify');
    });

    testWidgets('a pull inside one filter still keeps its rows', (tester) async {
      // The half that was already right, pinned so the fix cannot take it away
      // with the cross-filter half. The same question asked twice is not the
      // same as a different question, and on this screen the pull is the gesture
      // a client reaches for first.
      await loadThenFailRefresh(tester, afterLoad: (t) async {
        await t.drag(find.text('مقاول أول'), const Offset(0, 340));
        await t.pumpAndSettle(const Duration(seconds: 3));
      });

      expect(find.text('مقاول أول'), findsOneWidget,
          reason: 'a pull changes nothing about the question, so the rows stay');
      expect(find.byKey(const Key('stale-directory')), findsOneWidget);
    });

    testWidgets('two taps in a row: neither read is filed under the wrong '
        'filter', (tester) async {
      // The race the parameter-passing in `_arm` exists for. Tagging the rows
      // inside the `then` callback with the *current* filters is the naive fix
      // for the defect above and reproduces it one layer down: tap painting,
      // tap plumbing while painting is still in flight, and the painting rows
      // land filed under plumbing.
      //
      // Read 1 must SUCCEED or there is no cache to mislabel and the case is
      // vacuous — which is the first fault in this case's history, recorded
      // because the output looked identical (`+1` and green) either way.
      //
      // 20 s client timeout, not the shared 200 ms: a read that is MEANT to
      // hang cannot use a timeout short enough for a 503 to settle inside
      // `pumpAndSettle`, because it fires while the read is parked and turns
      // this into the failed-read case it is not. That is the second fault.
      final parked = Completer<void>();
      final released = Completer<void>();
      await loadThenFailRefresh(
        tester,
        timeout: const Duration(seconds: 20),
        respond: (index) async {
          if (index != 1) return null; // read 2 fails: 503
          // Read 1 (the painting tap) is held open until read 2 has been
          // issued, which is the overlap the defect needs.
          parked.complete();
          await released.future;
          return http.Response(
              jsonEncode(<dynamic>[_worker(1, 'مقاول الصباغ')]),
              200,
              headers: {'content-type': 'application/json'});
        },
        afterLoad: (t) async {
          await tapChip(t, 'painting');
          await parked.future;
          // The screen has moved on while read 1 is still open.
          await tapChip(t, 'plumbing');
          released.complete();
          await t.pumpAndSettle(const Duration(seconds: 3));
        },
      );

      // Read 1 succeeded and read 2 failed, so the honest screen is: plumbing
      // could not be read. The painter's row is not the answer to the plumbing
      // question, and the record must not let it be.
      expect(find.text('تعذّر جلب المقاولين'), findsOneWidget,
          reason: 'the second read failed and had no rows of its own');
      expect(find.text('مقاول الصباغ'), findsNothing,
          reason: 'read 1 landed while the screen was asking for plumbing — '
              'those rows are not the plumbing answer');
    });
  });
}
