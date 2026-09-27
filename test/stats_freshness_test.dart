// When the contractor's own numbers were read.
//
// Found on 27 Sep 2026, immediately after the market tab got its
// pull-to-refresh. That fix closed the transport half of a staleness problem
// and, in doing so, exposed the half it could not close: the header's stats
// line — «4.6 · 4 مشاريع منجزة · 5 سنوات خبرة» — says what the contractor's
// business looked like, and never says *when*. Every number on that line is
// real, so no `null` check would ever have found it, and the app's own pull
// gesture now sits directly under it implying the numbers are current.
//
// A contractor judges how hard to push to win a job off that line. The pull
// made a stale number a choice he was given the means to avoid; nothing said
// he had not made it. So the line now dates itself, and this file is the
// contract for that.
//
// The assertions here are on *what the screen says and when it changes*, not
// on the copy's wording, so rewording «قبل ساعة» into «منذ ساعة» does not
// break them. What would break them is a header that is silent, a header that
// says «الآن» about an hour-old read, or a repair that re-dates numbers it
// just restored.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/stats_freshness_copy.dart';
import 'package:allomokawil/src/screens/worker/worker_home_screen.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, Object?> _user() => {
      'id': 31,
      'phone': '0773000000',
      'email': null,
      'full_name': 'مقاول تجربة',
      'type': 'worker',
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// A contractor with real history, so the stats line renders at all: the
/// header gates it on `hasHistory`, and a fixture with zero jobs and zero
/// reviews measures the *gate* instead of the fix.
Map<String, Object?> _worker() => {
      'id': 16,
      'user_id': 31,
      'bio': 'دهان وديكور',
      'specialties': <String>['painting'],
      'experience_years': 5,
      'price_range_min': 20000,
      'price_range_max': 60000,
      'service_radius_km': 30,
      'is_available': 1,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'verification_status': 'verified',
      'subscription_plan': 'free_trial',
      'avg_rating': 4.6,
      'total_reviews': 12,
      'total_completed_jobs': 4,
      'response_time_hours': 2,
      'cover_image_url': null,
      'created_at': '2026-09-11 20:23:45',
      'updated_at': '2026-09-11 20:23:45',
      'full_name': 'مقاول تجربة',
      'phone': '077442495',
      'user_wilaya': '16',
      'avatar_url': 'https://x.test/a.png',
    };

Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'أعمال جافة',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'باب الوادي',
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

class _Platform {
  int profileReads = 0;
  bool profileFails = false;

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.endsWith('/api/mobile/my/profile')) {
            profileReads++;
            if (profileFails) {
              return http.Response('<html>boom</html>', 500,
                  headers: {'content-type': 'text/html'});
            }
            return _json(_worker());
          }
          if (p.endsWith('/api/mobile/my/subscription')) {
            return _json(<String, Object?>{
              'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
              'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
              'payment': <String, Object?>{'methods': <Object?>[]},
            });
          }
          // Exact equality, for the reason `worker_home_pull_to_refresh_test`
          // records: `req.url.path` excludes the query string, so a
          // `contains` here would serve the shell's own projects tab the
          // market's fixture.
          if (p == '/api/mobile/projects') {
            return _json([_project('p1', 'مشروع'), _project('p2', 'سباكة')]);
          }
          if (p == '/api/mobile/my/projects') return _json(<Object>[]);
          if (p.endsWith('/portfolio')) return _json(<Object>[]);
          if (p.endsWith('/documents')) return _json(<Object>[]);
          return _json(<Object>[]);
        }),
      );
}

Future<({ApiClient api, AuthState auth, _Platform platform})> _boot(
  _Platform platform,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = platform.build();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth, platform: platform);
}

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The header, mounted directly, with a clock the test owns.
///
/// [MarketplaceView] alone is not usable here: the shell is an `IndexedStack`
/// that builds all three tabs, and the freshness tick is a real `Timer` that
/// `testWidgets` will complain about at teardown if it is still armed.
Future<void> _pumpHeader(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  required DateTime Function() clock,
}) async {
  tester.view.physicalSize = const Size(1176, 2550);
  tester.view.devicePixelRatio = 3.0;
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
      // `MarketplaceView` is a tab *body*, not a page: `WorkerHomeScreen`
      // supplies the Scaffold it sits in, so the test does the same. Without
      // it the feed's TextField has no Material ancestor and the first
      // failure is a missing widget rather than a missing assertion.
      home: Scaffold(
        body: RepaintBoundary(
          key: const Key('header-capture'),
          child: MarketplaceView(repo: Repository(api), clock: clock),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Finder get _freshness => find.byKey(const Key('stats-read-at'));

/// The text the header currently claims its numbers were read.
String? _claimed(WidgetTester tester) =>
    tester.widget<Text>(_freshness).data;

/// Rasterises the header into `/tmp/shots`, the way `design_shots_test.dart`
/// does, so the freshness clause can be checked in pixels rather than argued
/// about.
///
/// The design shots cannot answer this on their own: they pin the wall clock
/// (unpinned, they would diff on every run), so every shot in `goldens/` has a
/// header that was read seconds ago and correctly renders **no** clause. The
/// aged state is the one that ships copy, and it is the one nobody would have
/// a picture of.
Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('header-capture')).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// The whole point, on the success path.
void main() {
  test('a read this minute says nothing; an hour-old one says so', () {
    final now = DateTime(2026, 9, 27, 12);
    // Under a minute is **silence**, not «الآن». The clause exists to report a
    // read that has gone off; a fresh read is not an event, and printing the
    // clause on every fresh header is how a contractor learns to skip past it.
    expect(statsFreshnessAr(now.subtract(const Duration(seconds: 20)), now: now),
        '');
    expect(statsFreshnessAr(now.subtract(const Duration(seconds: 59)), now: now),
        '');
    expect(statsFreshnessAr(now.subtract(const Duration(minutes: 3)), now: now),
        isNot('الآن'));
    expect(statsFreshnessAr(now.subtract(const Duration(hours: 1)), now: now),
        isNot('الآن'));
    // A read that never happened has no age at all, and must not claim to be
    // fresh.
    expect(statsFreshnessAr(null, now: now), '');
    // Exactly one minute crosses into a real count — the boundary is the
    // resolution [relativeTimeAr] itself reports at, not a number picked here.
    expect(statsFreshnessAr(now.subtract(const Duration(minutes: 1)), now: now),
        isNotEmpty);
  });

  test('stale starts at an hour and ignores a clock that runs backwards', () {
    final now = DateTime(2026, 9, 27, 12);
    expect(statsAreStale(now.subtract(const Duration(minutes: 59)), now: now),
        isFalse);
    expect(statsAreStale(now.subtract(const Duration(hours: 1)), now: now),
        isTrue);
    // Skew is the phone's fault, not the data's. Ageing it into a warning
    // would blame the contractor for a server timestamp.
    expect(
        statsAreStale(now.add(const Duration(hours: 3)), now: now), isFalse);
    // Forward skew reads as fresh, which renders as silence — never as an age
    // the app cannot compute and never as a warning it cannot justify.
    expect(statsFreshnessAr(now.add(const Duration(hours: 3)), now: now), '');
  });

  testWidgets('the header dates its own numbers, and is silent when fresh',
      (tester) async {
    final now = DateTime(2026, 9, 27, 12);
    final b = await _boot(_Platform());
    await _pumpHeader(tester, b.api, b.auth, clock: () => now);

    expect(find.textContaining('4.6'), findsWidgets,
        reason: 'the stats line must be on screen for this to mean anything');
    expect(_freshness, findsNothing,
        reason: 'a read seconds old must not print a fourth clause');
    // The baseline for the pixel diff below. Two captures of the *same* tree,
    // one minute old and one hour old, differing by exactly the clause — so
    // "the clause is on screen" is something a diff shows rather than
    // something the widget test asserts about its own finder.
    await _capture(tester, '18_worker_header_fresh');
  });

  testWidgets('an hour-old header says so, in the loud tone', (tester) async {
    final start = DateTime(2026, 9, 27, 12);
    // The clock advances, the screen does not. Nothing re-reads the profile
    // here — that is the point: the header is settled, correct as of an hour
    // ago, and it says which.
    var now = start;
    final b = await _boot(_Platform());
    await _pumpHeader(tester, b.api, b.auth, clock: () => now);

    now = start.add(const Duration(hours: 1, minutes: 5));
    // **A minute of fake-async, not a second.** Nothing rebuilds this row on a
    // clock tick of its own accord: the freshness line is computed in `build`
    // from a stamp, so the only thing that can change what it says is a
    // `setState`, and the only thing that issues one is the periodic tick the
    // screen arms. Pumping a second is the trap — the first run of this file
    // did exactly that and the assertion failed for a reason that had nothing
    // to do with the fix under test.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(_freshness, findsOneWidget);
    expect(_claimed(tester), isNot('الآن'));
    expect(_claimed(tester), isNotEmpty);
    await _capture(tester, '18_worker_header_stale');
    // Loud, not muted: this is the tone the app already uses on this line.
    final style = tester.widget<Text>(_freshness).style!;
    expect(style.color, AppTheme.accent);
    expect(statsAreStale(now), isTrue);
  });

  testWidgets('the tick re-renders the age with no re-read', (tester) async {
    final start = DateTime(2026, 9, 27, 12);
    var now = start;
    final b = await _boot(_Platform());
    await _pumpHeader(tester, b.api, b.auth, clock: () => now);
    final reads = b.platform.profileReads;

    now = start.add(const Duration(hours: 2));
    // The periodic tick is a wall-clock minute; `pump` alone advances no
    // timers, so the fake-async clock has to be stepped past one.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(_freshness, findsOneWidget,
        reason: 'the header must age on its own, not only on a re-read');
    expect(b.platform.profileReads, reads,
        reason: 'ageing the line must not re-issue the request');
  });

  testWidgets('a failed refresh does not re-date a header it restored',
      (tester) async {
    // The subtle one. A failed pull puts the *previous* profile back so the
    // contractor keeps his name, his stats and his plan. It must put the
    // previous profile's *age* back too — otherwise a header he has been
    // looking at for an hour is stamped as if it had just arrived, and the
    // repair that was meant to protect him is what makes the line a lie.
    final start = DateTime(2026, 9, 27, 12);
    var now = start;
    final platform = _Platform();
    final b = await _boot(platform);
    await _pumpHeader(tester, b.api, b.auth, clock: () => now);

    now = start.add(const Duration(hours: 1));
    await tester.pump(const Duration(minutes: 1));
    final before = _claimed(tester);
    expect(_freshness, findsOneWidget);

    // The pull now: profile read fails, so the header must be restored intact.
    platform.profileFails = true;
    for (var i = 0; i < 3; i++) {
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 320));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _settle(tester);

    expect(find.text('تعذّر جلب ملفك'), findsNothing,
        reason: 'a failed refresh must not cost him the header');
    expect(_freshness, findsOneWidget,
        reason: 'the restored header keeps its freshness line');
    expect(_claimed(tester), before,
        reason: 'restored numbers must keep the age they already had');
  });
}
