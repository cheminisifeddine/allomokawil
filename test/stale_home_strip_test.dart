// Proves a failed *re-read* on the client home keeps both strips and states the
// doubt on the strip that failed.
//
// The seventh screen in the family the subscription bug opened, and the first
// one that is not just another member: the other six each hold **one** list.
// This screen holds **two** behind **one** gesture, they can fail
// independently, and the supply strip is duplicated («ابحث عن مقاول» is one tap
// away) while the projects strip is not — nothing else in the app lists the
// user's own jobs. So the two halves need different words, which is why the
// copy module takes a `StaleHomeStrip` rather than one more string argument.
//
// Pull-to-refresh is where it bites. `_refresh` re-arms all three reads behind
// the gesture a user reaches for first, and each strip's failure branch drew a
// full `EmptyView` — so a network that blinked during a pull told a client
// there were no contractors on the home screen he opens first, and hid the
// three jobs he had posted.
//
// The pure half is the wording; the widget half is the screen obeying it,
// because a correct helper wired to an unchanged screen passes the first half
// clean.
import 'dart:async';
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
import 'package:allomokawil/src/data/stale_home_strip_copy.dart';
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

const String _arabic = r'[\u0600-\u06FF]';

Map<String, dynamic> _user() => {
      'id': 30,
      'phone': '0773000000',
      'email': null,
      'full_name': 'سمية',
      'type': 'customer',
    };

Map<String, Object?> _worker(int id, String name) => {
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

Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'دهان كامل',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

Map<String, Object?> _conversation(int id) => {
      'id': id,
      'customer_id': 30,
      'worker_user_id': 31,
      'project_id': null,
      'last_message_at': '2026-09-11 20:23:47',
      'created_at': '2026-09-11 20:23:47',
      'other_user_name': 'مقاول تجربة',
      'other_user_avatar': null,
      'last_message_content': 'مرحبا',
      'unread_count': 0,
    };

http.Response _json(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

/// The explore tab's reads, with a threshold for when each starts failing.
///
/// A threshold rather than a per-attempt callback, because a callback has to be
/// told which attempt it is serving and the two strips do **not** agree on what
/// attempt 1 is. That is the trap that cost this file its first run:
///
///  * `/workers/top` is read once at rest, so the explore strip's first read is
///    attempt **1** and a pull makes it **2**.
///  * `/my/projects` is read **twice** at rest, because the shell is an
///    `IndexedStack` and the *projects tab* issues its own read alongside the
///    explore strip's — two requests the phone cannot tell apart. So the explore
///    strip's first read is attempt **2** and a pull makes it **3**.
///
/// Getting that wrong fails the test in a way that looks like a broken fix: the
/// first read dies, the screen correctly shows its first-read error, and the
/// assertion meant to prove «a failed re-read keeps the rows» never gets to
/// test a re-read at all. The counters are public so a test can assert the pull
/// actually re-issued the request rather than assuming it did.
class _Platform {
  // No `guest` switch here: a visitor's pull must not request the two
  // session-only strips, and `customer_home_pull_to_refresh_test.dart` already
  // asserts that on the real screen. Carrying a second, unexercised copy of
  // that knob here is how a harness starts lying about a path it never walks.
  _Platform();

  /// Flipped by a test *after* the first read has been seen on screen, which is
  /// the shape of the real event: the phone rendered fine, then the network
  /// died under it.
  ///
  /// A "fail from attempt N onward" threshold was the first thing tried here
  /// and it is a trap, because the two strips do not agree on what attempt 1
  /// is: `/workers/top` is read once at rest, while `/my/projects` is read
  /// **twice** — the shell is an `IndexedStack`, so the *projects tab* issues
  /// its own request alongside the explore strip's, and the phone cannot tell
  /// the two apart. A wrong threshold fails in a way that looks like a broken
  /// fix: the *first* read dies, the screen correctly shows its first-read
  /// error, and the assertion meant to prove «a failed re-read keeps the rows»
  /// never gets to test a re-read at all. Liveness is set by the test, so the
  /// test does not have to guess how many requests the shell made.
  bool workersDead = false;
  bool projectsDead = false;

  int workerReads = 0;
  int projectReads = 0;

  static Future<http.Response> _okWorkers(int _) async =>
      _json(<Object?>[_worker(1, 'مقاول قديم')]);

  static Future<http.Response> _okProjects(int _) async =>
      _json(<Object?>[_project('p1', 'مشروع قديم')]);

  static Future<http.Response> _dead(int _) async => http.Response('', 503,
      headers: {'content-type': 'application/json'});

  ApiClient client() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.contains('/api/unread')) return _json(<String, Object?>{'unread': 0});
          if (p.contains('/workers/top')) {
            workerReads++;
            return workersDead ? _dead(workerReads) : _okWorkers(workerReads);
          }
          if (p.contains('/my/projects')) {
            projectReads++;
            return projectsDead ? _dead(projectReads) : _okProjects(projectReads);
          }
          if (p.contains('/conversations')) {
            return _json(<Object?>[_conversation(1)]);
          }
          return _json(<String, Object?>{});
        }),
        timeout: const Duration(milliseconds: 200),
      );
}

/// Scrolls the explore page down far enough for the projects strip to be built.
///
/// A lazy sliver never builds it, and its `FutureBuilder` never runs — so an
/// assertion on a project title would pass or fail on whether the *viewport*
/// reached it, not on whether the fix works. Same rule the pull-to-refresh
/// suite writes down, reused rather than re-derived.
Future<void> _revealProjects(WidgetTester tester) async {
  await tester.drag(
      find.byType(CustomScrollView).first, const Offset(0, -1600));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The pull gesture itself, anchored on the scroll view under the indicator so
/// a positional finder cannot start aiming at another tab's list.
Future<void> _pull(WidgetTester tester) async {
  final page = find.descendant(
    of: find.byType(RefreshIndicator),
    matching: find.byType(Scrollable),
  );
  expect(page, findsWidgets, reason: 'the explore tab must be pullable');
  await tester.fling(
      find.byType(CustomScrollView).first, const Offset(0, 340), 1200);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<({ApiClient api, AuthState auth})> _boot(_Platform platform) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = platform.client();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    api: api,
    auth: auth,
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
      home: CustomerHomeScreen(clock: clock),
    ),
  ));
  await _settle(tester);
}

void main() {
  group('staleHomeStripLineAr', () {
    test('names the failure AND that these rows are the last ones read', () {
      for (final strip in StaleHomeStrip.values) {
        final line = staleHomeStripLineAr(S.errOffline, strip);
        // Both halves are load-bearing. The failure alone is the state the
        // screen was already in; what was missing is the second clause, the
        // only thing that says the rows in front of the reader are real.
        expect(line, contains(S.errOffline), reason: '$strip');
        expect(line, matches(RegExp(_arabic)), reason: '$strip');
        expect(line, contains('لم نتمكن من تحديث'), reason: '$strip');
      }
    });

    test('a failure with no sentence still says the strip may be old', () {
      expect(staleHomeStripLineAr('   ', StaleHomeStrip.contractors),
          'قد لا تكون هذه المقاولين محدَّثة');
      expect(staleHomeStripLineAr('   ', StaleHomeStrip.projects),
          'قد لا تكون مشاريعك محدَّثة');
    });

    test('the reason is trimmed, not embedded with stray whitespace', () {
      final line =
          staleHomeStripLineAr('  ${S.errOffline}  ', StaleHomeStrip.contractors);
      expect(line, contains('لم نتمكن من تحديث قائمة المقاولين — هذه آخر نتيجة '
          'قرأناها. '));
      expect(line, endsWith(S.errOffline), reason: 'trimmed: "$line"');
    });

    test('the two strips are worded about themselves, not each other', () {
      // The whole reason this module is not one more argument to
      // `staleProjectsLineAr`: the supply is duplicated one tap away, the
      // user's own jobs are not, and a shared sentence would have to be
      // vaguer than either. So each says its own noun.
      final workers =
          staleHomeStripLineAr(S.errOffline, StaleHomeStrip.contractors);
      final projects =
          staleHomeStripLineAr(S.errOffline, StaleHomeStrip.projects);
      expect(workers, contains('المقاولين'));
      expect(workers, isNot(contains('مشاريعك')));
      expect(projects, contains('مشاريعك'));
      expect(projects, isNot(contains('المقاولين')));
    });
  });

  group('staleHomeStripAgeAr — the band says HOW old, not just that it is old',
      () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('a read inside the minute is not a number worth printing', () {
      // A pull that failed on a slow connection while the strip is twenty
      // seconds old is a hiccup. «قبل 20 ثانية» under it is a reassurance
      // dressed as a measurement, and the band already said everything there
      // is to say.
      expect(staleHomeStripAgeAr(base.subtract(const Duration(seconds: 20)),
          now: base), isEmpty);
    });

    test('a minute and older is counted in the app\'s own words', () {
      // Same grammar the market and projects bands print, asserted on this
      // surface so the two cannot drift into dating one read two ways.
      expect(staleHomeStripAgeAr(base.subtract(const Duration(minutes: 12)),
          now: base), 'قبل 12 دقيقة');
      expect(staleHomeStripAgeAr(base.subtract(const Duration(minutes: 2)),
          now: base), 'قبل دقيقتين');
      expect(staleHomeStripAgeAr(base.subtract(const Duration(hours: 3)),
          now: base), 'قبل 3 ساعات');
      expect(staleHomeStripAgeAr(base.subtract(const Duration(hours: 2)),
          now: base), 'قبل ساعتين');
    });

    test('an age past a year is dated, not counted', () {
      // A home left unrefreshed across a whole year is not a latency problem
      // and must not be described in the vocabulary of one.
      final old = DateTime(2024, 3, 15, 9, 30);
      final line = staleHomeStripAgeAr(old, now: base);
      expect(line, isNot(contains('سنة')));
      expect(line, isNot(contains('شهر')));
      expect(line, isNot(isEmpty));
    });

    test('a stamp ahead of the phone is clock skew, not the future', () {
      // Ageing it into «قبل -3 دقيقة» would be the app blaming the reader's
      // phone for somebody else's timestamp, so the skewed read is reported as
      // current and the band keeps its own words.
      expect(
          staleHomeStripAgeAr(base.add(const Duration(minutes: 3)), now: base),
          isEmpty);
    });

    test('a read that never happened has no age to print', () {
      expect(staleHomeStripAgeAr(null, now: base), isEmpty);
    });
  });

  group('staleHomeStripLineWithAgeAr — appended, never substituted', () {
    final base = DateTime(2026, 9, 29, 14, 0);

    test('the failure sentence survives the age', () {
      // The age is an addition, not a replacement. `errorCopy` names the KIND
      // of failure and the timestamp says nothing about it; a band that traded
      // the reason for a number would tell a client his jobs are «قبل 12 دقيقة»
      // without saying why they are not newer.
      for (final strip in StaleHomeStrip.values) {
        final line = staleHomeStripLineWithAgeAr(
            S.errOffline, base.subtract(const Duration(minutes: 12)), strip,
            now: base);
        expect(line, contains(S.errOffline), reason: '$strip');
        expect(line, contains('لم نتمكن من تحديث'), reason: '$strip');
        expect(line, contains('قبل 12 دقيقة'), reason: '$strip');
      }
    });

    test('the age is a second sentence, so the band stays readable when it wraps',
        () {
      final line = staleHomeStripLineWithAgeAr(
          S.errOffline, base.subtract(const Duration(hours: 2)),
          StaleHomeStrip.projects,
          now: base);
      expect(line, contains('\n'));
      expect(line.split('\n').last, contains('قرأناها قبل ساعتين.'));
    });

    test('a read with no age worth printing is the old line, byte for byte', () {
      // Not a shorter variant and not a trailing dash: the wording the
      // existing screenshots of this screen were written against has to survive
      // unchanged, or this quietly re-opens a defect on a screen already
      // correct.
      for (final strip in StaleHomeStrip.values) {
        for (final readAt in <DateTime?>[
          null,
          base,
          base.subtract(const Duration(seconds: 59)),
          base.add(const Duration(minutes: 5)),
        ]) {
          expect(
              staleHomeStripLineWithAgeAr(S.errOffline, readAt, strip,
                  now: base),
              staleHomeStripLineAr(S.errOffline, strip),
              reason: '$strip @ $readAt');
        }
      }
    });

    test('each strip is dated about its own rows', () {
      final old = base.subtract(const Duration(hours: 5));
      final workers = staleHomeStripLineWithAgeAr(
          S.errOffline, old, StaleHomeStrip.contractors, now: base);
      final projects = staleHomeStripLineWithAgeAr(
          S.errOffline, old, StaleHomeStrip.projects, now: base);
      expect(workers, contains('المقاولين'));
      expect(workers, isNot(contains('مشاريعك')));
      expect(projects, contains('مشاريعك'));
      expect(projects, isNot(contains('المقاولين')));
    });
  });

  group('CustomerHomeScreen — the band dates its own rows', () {
    testWidgets('a strip that failed forty minutes ago says so', (tester) async {
      // The pure half already proves the wording. This proves the *screen*
      // hands it a stamp, because a correct helper wired to an unchanged
      // screen passes every pure case in this file clean.
      var now = DateTime(2026, 9, 29, 14, 0);
      final platform = _Platform();
      final b = await _boot(platform);

      await _pump(tester, b.api, b.auth, clock: () => now);
      expect(find.byKey(const Key('stale-workers')), findsNothing);

      // The read lands at 14:00, then the network dies and the phone is not
      // touched again for forty minutes.
      platform.workersDead = true;
      await _pull(tester);
      now = now.add(const Duration(minutes: 40));
      // Crossed by pumping a whole minute, not a frame: the band is re-dated
      // by the once-a-minute age tick, so a test that only pumps frames is
      // asserting on the sentence as it stood when the failure landed. This is
      // the same mechanism that keeps a home left open over a coffee break
      // from reading «قبل 12 دقيقة» forever.
      await tester.pump(const Duration(minutes: 1));
      await _settle(tester, frames: 2);

      expect(find.byKey(const Key('stale-workers')), findsOneWidget);
      expect(
        find.textContaining('قبل 40 دقيقة', findRichText: true),
        findsOneWidget,
        reason: 'a band that cannot say how old is a doubt with no magnitude',
      );
      // The reason must still be there: the age is an addition, not a
      // replacement for the sentence that names the failure. Asserted on the
      // band's OWN composed line rather than on a string constant — the
      // harness returns a 503, so `errorCopy` picks its own two-line sentence
      // and never prints `S.errOffline` at all. Re-deriving the expected text
      // from the same helper the screen uses would be circular, so the check
      // is structural: the band is one Text, and both halves are in it.
      final band = tester.widget<Text>(
          find.descendant(
              of: find.byKey(const Key('stale-workers')),
              matching: find.byType(Text)));
      expect(band.data, contains('لم نتمكن من تحديث'),
          reason: 'the failure sentence must survive the age');
      expect(band.data, contains('قبل 40 دقيقة'),
          reason: 'and the age is appended to it, not swapped in');
    });

    testWidgets('the two strips are dated by their OWN reads, not one stamp',
        (tester) async {
      // The two reads fail independently, so a single shared stamp is how a
      // projects list that refreshed a second ago gets dated by a contractors
      // read that has not landed in an hour.
      //
      // **Two earlier versions of this test could not see that bug at all.**
      // The first asserted the projects band is ABSENT — a band that is not
      // on screen cannot be dated wrongly, so it passed green with one shared
      // stamp wired in. The second rendered the strip but had the projects
      // read stay dead for the whole scenario, and the shared-stamp copy lives
      // in the projects **success** arm, so that arm never re-ran and the
      // corrupted value was never written. Both looked like proof.
      //
      // The scenario that can see it: the projects read has to **succeed at
      // least once after the shared stamp is taken** and then fail again, so
      // the success arm writes and the band is rebuilt on the value it wrote.
      var now = DateTime(2026, 9, 29, 14, 0);
      final platform = _Platform();
      final b = await _boot(platform);

      await _pump(tester, b.api, b.auth, clock: () => now);

      // 14:00 — both reads die. Both strips keep their rows, both admit it,
      // and both are stamped 14:00.
      platform.workersDead = true;
      platform.projectsDead = true;
      await _pull(tester);

      // 15:00 — the projects read recovers and re-stamps **itself**; the
      // contractors read stays dead and keeps its 14:00 stamp.
      now = now.add(const Duration(hours: 1));
      platform.projectsDead = false;
      await _pull(tester);

      // 16:00 — the projects read dies again, so its band comes back standing
      // on rows that were last true at 15:00.
      now = now.add(const Duration(hours: 1));
      platform.projectsDead = true;
      await _pull(tester);

      // 18:00 — the clock is read by the once-a-minute age tick, so the band
      // is dated against a real passage of time rather than a frame.
      now = now.add(const Duration(hours: 2));
      await tester.pump(const Duration(minutes: 1));
      await _settle(tester, frames: 2);
      await _revealProjects(tester);
      await _settle(tester, frames: 2);

      expect(find.byKey(const Key('stale-projects-strip')), findsOneWidget);
      final band = tester.widget<Text>(
          find.descendant(
              of: find.byKey(const Key('stale-projects-strip')),
              matching: find.byType(Text)));
      expect(band.data, contains('مشاريعك'),
          reason: 'the band must still be talking about the projects');

      // Three hours, counted from the read at 15:00. A stamp shared with the
      // contractors read carries 14:00 instead and prints «قبل 4 ساعات» —
      // dating the customer\'s own jobs by a read that never refreshed them.
      expect(band.data, contains('قبل 3 ساعات'),
          reason: 'the projects rows were last true at 15:00, not at whatever '
              'the contractors strip last read');
      expect(band.data, isNot(contains('قبل 4 ساعات')),
          reason: 'and specifically not the contractors read\'s stamp');
    });

    testWidgets('a band on rows read seconds ago prints no age at all',
        (tester) async {
      // A pull that failed on a slow connection while the strip is seconds old
      // is a hiccup. Printing «قبل 4 ثوانٍ» under it would be a reassurance
      // dressed as a measurement.
      final platform = _Platform();
      final b = await _boot(platform);
      final now = DateTime(2026, 9, 29, 14, 0);
      await _pump(tester, b.api, b.auth, clock: () => now);

      platform.workersDead = true;
      await _pull(tester);
      await _settle(tester, frames: 2);

      expect(find.byKey(const Key('stale-workers')), findsOneWidget);
      // «قرأناها قبل …» and not a bare «قرأناها»: the base sentence ends
      // «هذه آخر نتيجة قرأناها», so the shorter needle matches the line that
      // is on screen whether or not the age is there.
      expect(find.textContaining('قرأناها قبل', findRichText: true), findsNothing,
          reason: 'under a minute the honest answer is silence');
    });
  });

  group('CustomerHomeScreen — a failed pull is not a blank home', () {
    testWidgets('a failed contractors read keeps the cards and says so',
        (tester) async {
      final platform = _Platform();
      final b = await _boot(platform);
      await _pump(tester, b.api, b.auth);

      // First read worked, so there is nothing to doubt yet.
      expect(find.text('مقاول قديم'), findsOneWidget);
      expect(find.byKey(const Key('stale-workers')), findsNothing,
          reason: 'a successful first read must not warn about anything');

      final before = platform.workerReads;
      platform.workersDead = true;
      await _pull(tester);

      expect(platform.workerReads, greaterThan(before),
          reason: 'the pull must have re-read the strip');
      // The defect: a blink during the pull told a client the marketplace was
      // empty, on the first screen he opens.
      expect(find.text('تعذّر جلب المقاولين'), findsNothing,
          reason: 'a failed refresh must not claim there are no contractors');
      expect(find.text('مقاول قديم'), findsOneWidget,
          reason: 'the cards that survived the last good read must stay');
      expect(find.byKey(const Key('stale-workers')), findsOneWidget,
          reason: 'a failed refresh must state the doubt');
    });

    testWidgets('a failed projects read keeps the jobs and says so',
        (tester) async {
      final platform = _Platform();
      final b = await _boot(platform);
      // Left at the top of the page for the whole test, because a
      // `RefreshIndicator` fires at scroll offset 0 and nowhere else: the two
      // strips sit ~1100 logical px apart on a 829 px viewport, so proving
      // anything about the projects strip means scrolling, and a pull from
      // halfway down a page is swallowed without re-issuing the read. The
      // request count is asserted rather than trusting the gesture, because a
      // swallowed pull otherwise fails as if the fix were broken.
      await _pump(tester, b.api, b.auth);
      await _pull(tester);
      expect(platform.projectReads, greaterThan(0),
          reason: 'the pull must have re-read the strip');

      platform.projectsDead = true;
      await _pull(tester);
      expect(platform.projectReads, greaterThan(1),
          reason: 'the second pull must have re-read the strip');

      await _revealProjects(tester);

      // Nothing else in the app lists *his own* jobs, so erasing these is the
      // home screen forgetting what he posted — not a temporary nuisance.
      expect(find.text('تعذّر جلب المشاريع'), findsNothing,
          reason: 'a failed refresh must not claim the projects are gone');
      expect(find.text('مشروع قديم'), findsOneWidget);
      expect(find.byKey(const Key('stale-projects-strip')), findsOneWidget);
    });

    testWidgets('only the strip that failed gets a band', (tester) async {
      // The one thing a single-list screen never has to answer: the two reads
      // behind one gesture fail independently, so the bands are per strip. A
      // band on the answering strip would be a doubt about rows the server
      // just confirmed.
      final platform = _Platform();
      final b = await _boot(platform);
      await _pump(tester, b.api, b.auth);

      // Only the contractors read dies. Checked in two passes because the two
      // strips cannot be on screen at once — they sit ~1100 logical px apart on
      // a 829 px viewport — and a lazily built sliver that has scrolled out is
      // not in the tree, so a single pass would assert nothing at all.
      final before = platform.projectReads;
      platform.workersDead = true;
      await _pull(tester);

      expect(find.byKey(const Key('stale-workers')), findsOneWidget);

      await _revealProjects(tester);
      expect(find.byKey(const Key('stale-projects-strip')), findsNothing,
          reason: 'the projects read answered, so nothing is doubtful about it');
      expect(find.text('مشروع قديم'), findsOneWidget);
      expect(platform.projectReads, greaterThan(before),
          reason: 'and it really was re-read, so the absence is not a stale '
              'tree that simply never rebuilt');
    });

    testWidgets('a read that succeeds again clears the doubt', (tester) async {
      // A band that outlives the failure is its own lie.
      final platform = _Platform();
      final b = await _boot(platform);
      await _pump(tester, b.api, b.auth);

      platform.workersDead = true;
      await _pull(tester);
      expect(find.byKey(const Key('stale-workers')), findsOneWidget);

      // The server answers again — the doubt must not outlive the read that
      // settled it.
      platform.workersDead = false;
      await _pull(tester);

      expect(find.byKey(const Key('stale-workers')), findsNothing,
          reason: 'a successful read must clear the doubt');
      expect(find.text('مقاول قديم'), findsOneWidget);
    });

    testWidgets('a first read that fails still gets the full-screen error',
        (tester) async {
      // The fix must not weaken the branch it moves. With no cache there is
      // genuinely nothing to draw, and the retry button is the whole answer.
      // Dead before the first read: this is the case with nothing to qualify,
      // and it must keep the full-screen error.
      final platform = _Platform()..workersDead = true;
      final b = await _boot(platform);
      await _pump(tester, b.api, b.auth);

      expect(find.text('تعذّر جلب المقاولين'), findsOneWidget);
      expect(find.byKey(const Key('stale-workers')), findsNothing,
          reason: 'there is nothing to qualify — the error is the truth here');
    });

    testWidgets('a waiting read shows the skeleton, never the empty strip',
        (tester) async {
      // The regression this shape of fix introduced on the sibling screens and
      // the loop caught: writing `shown` as "cache if we ever got one, else
      // data-or-empty" makes "no cache" and "no rows" the same empty list, so a
      // *waiting* first read falls out of the skeleton into the empty strip
      // and tells a client on a slow connection that there are no contractors
      // before the request has answered. Pinned here for the same reason.
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      // Never answers — a Completer that is never completed is what "still in
      // flight" actually means. A 503 would resolve in a microtask and test the
      // *failed* branch instead, which is the case next door.
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return Future.value(
                _json(<String, Object?>{'token': 't', 'user': _user()}));
          }
          if (p.contains('/api/unread')) {
            return Future.value(_json(<String, Object?>{'unread': 0}));
          }
          return Completer<http.Response>().future;
        }),
      );

      // Session from prefs only, and no `login()`: a dead client would answer
      // neither, so calling it would hang the test instead of testing anything.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth.token': 'test-token',
        'auth.user': jsonEncode(_user()),
      });
      final auth = AuthState(api);
      await auth.restore();
      await _pump(tester, api, auth);

      expect(find.byType(Shimmer), findsWidgets,
          reason: 'a waiting read must show the skeleton, not the empty strip');
      expect(find.text('لا يوجد مقاولون بعد'), findsNothing,
          reason: 'an unanswered request is not an empty marketplace');
      expect(find.text('تعذّر جلب المقاولين'), findsNothing,
          reason: 'an unanswered request is not a failure either');

      // Drain the client's own 20 s timeout so the test does not end with a
      // pending timer.
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}
