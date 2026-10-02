// The stale-gallery band and the one thing that makes it lie to a contractor
// deciding whether to spend his evening re-uploading every photo he has.
//
// **[MyPortfolioScreen.clock] was already here**, on the same terms as the other
// nine members of this family: a screen that reads the real clock is a screen
// whose pixels depend on when the test ran, so the seam exists to pin the
// answer. That is all it was ever wired to. The band composes
// `staleGalleryLineWithAgeAr(_error!, _readAt, now: _now())` **at build time**,
// and this screen rebuilds on exactly two things: the first pair of reads, and
// `_load()` when the user presses «تحديث». Neither of those is "a minute
// passed".
//
// So a contractor whose refresh failed on hotel wifi — the whole reason this
// screen exists — sat reading a band that said «الصور المعروضة قبل 12 دقيقة» and
// watched it stay «قبل 12 دقيقة» for as long as he sat there. The band exists to
// tell him how old the photos under it are, and it is the one line on the page
// whose answer gets worse the longer he looks at it.
//
// **This screen is the worst shape of the family's defect, and the shape is why
// the tick is armed where it is.** Nine siblings arm from the lifecycle and guard
// inside the tick. This one cannot: the band is born in a **failure**, not in a
// read. `_stale` is `_error != null && _images.isNotEmpty`, so on the success
// path `_error` is null, there is no band, and a sibling-shaped arm would be
// armed exactly when there is nothing to say and cancelled exactly when there
// is. `_armAgeTick()` is therefore called from *both* ends of `_load` and
// derived from `_stale`, which is the only predicate that answers "is there a
// band on screen right now". Cancel-first, so a «تحديث» that fails and then
// succeeds cannot leave two live timers behind.
//
// The mutation gate matters more than the assertions. A test that only looks for
// «ساعتين» passes just as happily against the old code, because the old code
// printed a *different* sentence rather than no sentence. What is pinned below
// is the behaviour: one fixture, two clocks, and a tick that must move the
// label with nothing else rebuilding it.
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
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/stale_gallery_copy.dart';
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';

/// How a request is answered, so a case can park one read while another lands.
typedef Answer = Future<http.Response> Function(String path);

/// The read the band's age is measured against. Fixed, not wall-clock, so a
/// claim about which sentence is on screen is a claim about words.
final DateTime kReadAt = DateTime(2026, 10, 2, 9, 48);

/// Twelve minutes after [kReadAt] — inside the minute band, so the sentence is
/// «قبل 12 دقيقة» and not the «ساعتين» the clock-moving case lands on. A
/// fixture that made both cases print the same words would pass against a build
/// that aged nothing.
final DateTime kFirst = DateTime(2026, 10, 2, 10);

/// Past the hour band, for the same fixture and the same bytes on the wire.
final DateTime kLater = DateTime(2026, 10, 2, 12, 5);

String _body(String path, {required int photos, required int limit}) {
  if (path.endsWith('/api/login') || path.endsWith('/api/register')) {
    return jsonEncode(<String, Object?>{
      'token': 'tok',
      'user': <String, Object?>{
        'id': 31,
        'phone': '0773000000',
        'full_name': 'مقاول تجربة',
        'type': 'worker',
        'wilaya': '16',
        'created_at': '2026-09-11 20:00:00',
      },
    });
  }
  if (path.contains('/portfolio')) {
    return jsonEncode(<Object>[
      for (var i = 0; i < photos; i++)
        <String, Object>{'image_url': 'https://r2.test/p$i.jpg'},
    ]);
  }
  if (path.contains('/my/profile')) {
    return jsonEncode(<String, Object?>{
      'id': 7,
      'user_id': 31,
      'full_name': 'مقاول تجربة',
      'specialties': <Object?>['دهان'],
      'experience_years': 5,
    });
  }
  if (path.contains('/subscription')) {
    return jsonEncode(<String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'plans': <Object?>[],
      'current': <String, Object?>{
        'plan': 'free_trial',
        'name_ar': 'الخطة المجانية',
        'status': 'active',
        'quote_limit': 3,
        'portfolio_limit': limit,
        'quotes_used_this_month': 0,
      },
    });
  }
  return jsonEncode(<Object>[]);
}

Future<http.Response> _ok(String body) => Future.value(http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    ));

/// The gallery read that fails, by **request count** rather than by a flag, so a
/// case can park one read while the other lands. Counting is the two harness
/// faults from earlier members of this family, designed out again: a case that
/// fails both reads has no cache to mislabel, and one that shares the 200 ms
/// timeout converts a parked read into a failed read.
Answer _failingOn(Set<int> readNumbers,
    {int photos = 3, int limit = 5}) {
  var reads = 0;
  return (path) {
    if (path.contains('/portfolio')) {
      reads++;
      if (readNumbers.contains(reads)) {
        return Future.value(http.Response('boom', 500));
      }
    }
    return _ok(_body(path, photos: photos, limit: limit));
  };
}

/// Frames, never `pumpAndSettle`.
///
/// The loading skeleton animates forever, so settling would never return — and
/// once the age tick is armed there is a periodic timer to boot. Bounded pumps
/// are the only correct shape for this screen, and this repo has lost three
/// ticks to the other one.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Mounts the screen against [answer], with [clock] as its wall clock.
Future<void> _mount(
  WidgetTester tester, {
  required Answer answer,
  required DateTime Function() clock,
}) async {
  tester.view.physicalSize = const Size(392, 2400) * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async => answer(req.url.path)),
  );
  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');

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
      home: MyPortfolioScreen(clock: clock),
    ),
  ));
  await _pumpFrames(tester);
}

/// Counts the frames drawn while it is counting.
///
/// The only **public** observable that separates "the tick was cancelled on the
/// success path" from "the tick is still armed and harmlessly rebuilding
/// nothing": `fakeAsync` is private on this binding, and the pixels are
/// identical either way, because the tick's body is a `setState` with no fields
/// changed and the band is simply not in the tree. A live tick dirties the tree
/// once a minute, so the frames it causes are the leak, measured rather than
/// argued.
///
/// Re-registers itself every frame, so a run that draws three frames counts
/// three and not one.
class _FrameWatch {
  _FrameWatch(this.tester);

  final WidgetTester tester;
  int frames = 0;
  bool _counting = true;

  void _watch() {
    tester.binding.addPostFrameCallback((_) {
      if (!_counting) return;
      frames++;
      _watch();
    });
  }

  void start() {
    frames = 0;
    _counting = true;
    _watch();
  }

  void stop() => _counting = false;
}

/// The band's own sentence, read off the keyed `Text` so the claim is about
/// the tree rather than about a `find.text` guess.
String _bandLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('stale-gallery-line'))).data!;

/// Every line the screen drew, for a failure message that has to be readable.
List<String> _lines(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((t) => t.isNotEmpty)
    .toList();

/// Drives the screen into the one state it was written for: a first read that
/// **landed**, then a «تحديث» that failed with those photos still on screen.
///
/// [atRefresh] is the clock's value at the moment the *failing* read settles,
/// and it is a parameter rather than something the cases move afterwards,
/// because of one thing about this screen: `_readAt` is stamped when the first
/// read **settled**, so the band's age is `clock at the failed refresh` minus
/// `clock at the successful first read`. A case that raised the band and *then*
/// moved the clock was measuring a build that had already happened — and since
/// nothing dirties this screen between a read and the next, the second clock
/// was never observed at all. Setting it before the tap is what makes the
/// second clock the one the band is actually composed against.
Future<void> _raiseBand(
  WidgetTester tester, {
  required Answer answer,
  required DateTime Function() clock,
  required void Function(DateTime) setClock,
  required DateTime atRefresh,
}) async {
  await _mount(tester, answer: answer, clock: clock);
  expect(find.byKey(const Key('stale-gallery')), findsNothing,
      reason: 'a first read that landed has nothing to warn about');
  setClock(atRefresh);
  await tester.tap(find.byTooltip('تحديث'));
  await _pumpFrames(tester);
  expect(find.byKey(const Key('stale-gallery')), findsOneWidget,
      reason: 'the failed re-read did not raise the band, so the case under '
          'test is not the state it claims:\n${_lines(tester)}');
  expect(find.byType(GridView), findsOneWidget,
      reason: 'the photos under the band are the point of the band');
  // The count on screen is still the count the server sent — that is the thing
  // the band exists next to, and the thing a blanked gallery used to destroy.
  expect(find.textContaining(portfolioCountLineAr(3)), findsOneWidget,
      reason: 'the header still counts the photos the server sent');
}

void main() {
  group('the stale band ages while the gallery sits open', () {
    testWidgets('a read 12 minutes old is labelled 12 minutes', (tester) async {
      var now = kReadAt;
      await _raiseBand(
        tester,
        answer: _failingOn(<int>{2}),
        clock: () => now,
        setClock: (v) => now = v,
        atRefresh: kFirst,
      );

      // Asserted against the app's **own** composer rather than against Arabic
      // typed into this file: a test that names words the app never prints fails
      // for a reason unrelated to the defect, which is the flakiest possible
      // way to write one. `stale_gallery_test.dart` recorded this the hard way.
      expect(
        _bandLine(tester),
        staleGalleryLineWithAgeAr(S.errServer, kReadAt, now: kFirst),
        reason: 'the band must be the composer\'s whole sentence — the reason '
            'with the age appended — and nothing else',
      );
      expect(_bandLine(tester), contains('12 دقيقة'),
          reason: 'the band must report the age it was handed, not a '
              'timestamp: ${_bandLine(tester)}');
      expect(
        _bandLine(tester),
        contains(staleGalleryLineAr(S.errServer)),
        reason: 'the age is appended, never substituted for the reason',
      );
    });

    testWidgets('the SAME gallery reads as two hours old once the clock moves',
        (tester) async {
      // The measurement, not a tautology: **one fixture, two clocks.** The
      // payload is byte-identical to the case above and the only difference is
      // when the injected clock stood as the failed refresh settled — 10:00 vs
      // 12:05, with `_readAt` pinned at 09:48 by the first read either way.
      // Before the fix the label was whatever the first frame composed, so this
      // difference was not observable at all, which is the definition of the
      // fuse.
      var now = kReadAt;
      await _raiseBand(
        tester,
        answer: _failingOn(<int>{2}),
        clock: () => now,
        setClock: (v) => now = v,
        atRefresh: kLater,
      );

      expect(_bandLine(tester), contains('ساعتين'),
          reason: 'a 12-minute read was labelled two hours old: '
              '${_bandLine(tester)}');
      expect(_bandLine(tester), isNot(contains('12 دقيقة')),
          reason: 'the band did not move with the clock it was handed');
    });

    testWidgets('the minute tick re-labels the band without anything rebuilding it',
        (tester) async {
      // The half no screenshot can show, and the half the two cases above
      // cannot reach: both of those raise the band with the clock already where
      // they want it, so the tick is never the thing under test. A contractor
      // does not do that. He raised the band on hotel wifi, put the phone down,
      // and came back to it later with nothing happening in between — so this
      // case hands the screen a clock that is **still** at the instant the band
      // was first drawn, and then lets a real minute reach it through the tick,
      // with no `pumpWidget`, no key change and no `setState` from the test.
      //
      // Before the fix there was no timer at all, so this pump was a no-op and
      // the band kept the first frame's sentence for as long as the screen sat
      // open.
      var now = kReadAt;
      await _raiseBand(
        tester,
        answer: _failingOn(<int>{2}),
        clock: () => now,
        setClock: (v) => now = v,
        atRefresh: kFirst,
      );
      expect(_bandLine(tester), contains('12 دقيقة'),
          reason: 'setup did not reach the minute sentence: '
              '${_bandLine(tester)}');

      // Only the clock moves, the way a real minute moves while the phone sits
      // in a pocket and the contractor is deciding whether to re-upload.
      now = kLater;
      await tester.pump(const Duration(minutes: 1, milliseconds: 100));

      expect(_bandLine(tester), contains('ساعتين'),
          reason: 'the band did not age with the clock it was handed. This '
              'screen rebuilds only on its first read and on `_load()`, so '
              'nothing else can move the age: ${_bandLine(tester)}');
    });

    testWidgets('a «تحديث» that succeeds withdraws the band AND the tick',
        (tester) async {
      // The arm-site claim, and the reason `_armAgeTick` is not copied from a
      // sibling. Read 2 fails and raises the band; read 3 lands and withdraws
      // it. A tick left armed here would rebuild a perfectly healthy gallery
      // once a minute for the rest of the session — the leak the family keeps
      // creating, with the timer sitting inside the contractor's own hands.
      //
      // **This case was written wrong twice and the mutation gate caught it
      // both times.** First version asserted the band stayed gone after two
      // minutes — which a leaked tick satisfies too, since the band is absent
      // from the tree either way and the pixels are identical. Deleting the
      // `!_stale` guard from the arm site left all five cases green.
      //
      // Second version reached for `fakeAsync.periodicTimerCount`, the obvious
      // probe, and did not compile: `_currentFakeAsync` is private on
      // `AutomatedTestWidgetsFlutterBinding` in this Flutter version, so there
      // is no public accessor and the framework only surfaces the count in an
      // assert that fails the whole file at teardown.
      //
      // What is left is the frame watch, and **it was measured before it was
      // trusted.** Deleting the `!_stale` guard alone still leaves all five
      // green: the tick's own body guards on `_stale`, so a leaked timer wakes
      // once a minute, finds no band, and returns without dirtying the tree —
      // which is *why* the shipped code is correct and exactly why the leak
      // cannot be seen from the outside. The frame watch only fails when the
      // arm-site guard **and** the body guard are both gone (1 frame across
      // three minutes). So: it is a real probe and it is a weak one. It pins the
      // double-arm — fail then success — because that is the state where two
      // live timers would exist, which is the leak this family keeps creating.
      // The `_stale` guard on its own is not pinned by any case here, and that
      // limit is recorded rather than dressed up.
      var now = kReadAt;
      await _raiseBand(
        tester,
        answer: _failingOn(<int>{2}),
        clock: () => now,
        setClock: (v) => now = v,
        atRefresh: kFirst,
      );
      expect(_bandLine(tester), contains('12 دقيقة'));
      // Proof the tick is live **before** the success path runs, measured the
      // same way the leak is measured below, so the two are comparable numbers
      // rather than two different kinds of claim.
      final armed = _FrameWatch(tester)..start();
      await tester.pump(const Duration(minutes: 2, milliseconds: 100));
      armed.stop();
      expect(armed.frames, greaterThan(0),
          reason: 'setup did not arm the tick, so the assertion below is '
              'vacuous: a cancelled tick and a missing tick look identical '
              'from the success path');

      await tester.tap(find.byTooltip('تحديث'));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('stale-gallery')), findsNothing,
          reason: 'a read that landed has nothing to warn about');
      expect(find.byType(GridView), findsOneWidget,
          reason: 'the successful re-read replaced the photos, it did not '
              'blank them');

      // Everything the successful read still had to say is settled by now — the
      // allowance read lands after the photos — so a frame counted from here is
      // one the timer caused and nothing else.
      final watch = _FrameWatch(tester)..start();
      await tester.pump(const Duration(minutes: 3, milliseconds: 100));
      watch.stop();

      expect(
        watch.frames,
        0,
        reason: 'a «تحديث» that succeeded withdrew the band and left its tick '
            'armed. The gallery on screen is current, so the tick rebuilds it '
            'once a minute for the rest of the session, holding the screen and '
            'its images alive for nothing: ${watch.frames} frames drawn across '
            'three minutes.',
      );
    });

    testWidgets('the ageing timer is cancelled when the screen leaves the tree',
        (tester) async {
      // A `Timer.periodic` left armed after `dispose` keeps a live handle and
      // fails the very next test with "A Timer is still pending", which is how
      // one author's widget test becomes everybody's. Three callers push this
      // route, so the cancel is part of the feature rather than hygiene.
      var now = kReadAt;
      await _raiseBand(
        tester,
        answer: _failingOn(<int>{2}),
        clock: () => now,
        setClock: (v) => now = v,
        atRefresh: kFirst,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      // And elapsing past the boundary must not resurrect anything: reaching
      // here without "A Timer is still pending even after the widget tree was
      // disposed" *is* the second half of the assertion.
      await tester.pump(const Duration(minutes: 2, milliseconds: 100));
    });
  });
}
