// The one page a customer picks a tradesman from could not say how old its
// evidence was.
//
// Found on 29 Sep 2026. `Review.fromJson` dropped `created_at` — the field the
// Worker really sends (it is in the production payload captured in
// `live_payload_models_test.dart`) — and `_ReviewCard` drew stars, a name and
// a comment with no time on any of them. Every other dated list in this app
// says how old its rows are; the reviews, on the page that exists to be
// evidence, were the exception.
//
// Two defects, and the second only becomes visible once the first is fixed:
//
//   1. **the row was undated** — a review from last week and one from eight
//      months ago drew identically, which is the difference between a man
//      whose work kept being good and a man who was good once;
//   2. **the list was in whatever order the Worker sent.** The moment the
//      cards carry dates, an unsorted list reads «قبل 3 أشهر» directly above
//      «الآن» — the page dating its own evidence inconsistently, which is the
//      one thing this app's copy layer exists to prevent.
//
// This file pins the model (the wire value survives, read as UTC), the order
// (newest first, undated last and never dropped, stable on a shared stamp),
// and the **real screen** driven end to end against a fake API — a list that is
// sorted and a list that is drawn in the wrong order are the same defect seen
// from two sides, so the widget case is the one that would have caught it.
import 'dart:convert';
import 'dart:io';

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
import 'package:allomokawil/src/data/review_order.dart';
import 'package:allomokawil/src/models/quote_review.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';

/// The review payload exactly as the API sends it: UTC, no zone marker, and
/// `images` as a JSON **string** rather than an array.
const _wire = '{"id":5,"project_id":"p1","customer_id":30,"worker_id":16,'
    '"rating":5,"comment":"\u0639\u0645\u0644 \u0645\u0645\u062a\u0627\u0632",'
    '"images":"[]","is_visible":1,"created_at":"2026-09-11 20:23:50",'
    '"customer_full_name":"\u0632\u0628\u0648\u0646 \u062a\u062c\u0631\u0628\u0629",'
    '"customer_avatar_url":null}';

/// A review with a day-of-month stamp, or none at all.
Review _r(int id, {int? day}) => Review(
      id: id,
      projectId: 'p1',
      workerId: 16,
      rating: 5,
      comment: null,
      images: const [],
      customerFullName: 'زبون',
      createdAt: day == null ? null : DateTime.utc(2026, 9, day),
    );

const _worker = {
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.8, 'total_reviews': 2,
  'total_completed_jobs': 12, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Boots a signed-in client whose `/reviews` answers [rows], in **exactly the
/// order given** — deliberately unsorted, which is what the Worker does and
/// what the screen used to draw verbatim.
Future<({ApiClient api, AuthState auth})> _boot(List<Object> rows) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json({
          'token': 'tok',
          'user': {
            'id': 30,
            'phone': '0773000000',
            'email': null,
            'full_name': 'زبون تجربة',
            'type': 'customer',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/portfolio')) return _json(<Object>[]);
      if (p.endsWith('/reviews')) return _json(rows);
      if (p == '/api/mobile/workers/16') return _json(_worker);
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

/// Pumps the real screen and settles the loading shimmer, which animates
/// forever and would never let `pumpAndSettle` return.
Future<void> _pump(
  WidgetTester tester,
  ({ApiClient api, AuthState auth}) s,
  DateTime now,
) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: s.api,
    auth: s.auth,
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
      // The clock is injected for the same reason the notification screen
      // takes one: a date read from `DateTime.now()` ages as the hours pass,
      // which is what drifted the `15_notifications` golden and took the whole
      // suite red with it.
      home: WorkerProfileScreen(workerId: 16, clock: () => now),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// One wire row, with the id and the timestamp the test needs.
Map<String, Object?> _row(int id, {String? at}) => {
      'id': id,
      'project_id': 'p1',
      'customer_id': 30,
      'worker_id': 16,
      'rating': 5,
      'comment': 'عمل ممتاز',
      'images': '[]',
      'is_visible': 1,
      if (at != null) 'created_at': at,
      'customer_full_name': 'زبون تجربة',
      'customer_avatar_url': null,
    };

void main() {
  // ---- the wire --------------------------------------------------------
  group('the model', () {
    test('keeps the timestamp the Worker sends instead of dropping it', () {
      final r = Review.fromJson(jsonDecode(_wire) as Map<String, dynamic>);
      expect(r.createdAt, isNotNull,
          reason: 'every review row carries created_at; the parser threw it '
              'away, so no card could ever say how old it was');
      expect(r.createdAt!.toUtc(), DateTime.utc(2026, 9, 11, 20, 23, 50));
    });

    // **This box is `Etc/UTC`, so the bug it guards against is invisible
    // here.** `DateTime.tryParse('2026-09-11T20:23:50')` and
    // `parseServerTime` of the same string produce the same instant on a UTC
    // host, so an in-process assertion is green either way — I wrote one,
    // sabotaged the parser with the naive `tryParse`, and the suite stayed
    // green. The only honest check is a second process in a real zone, which is
    // what `subscription_clock_test.dart` does for the same drift between two
    // interpretations of one string.
    test('reads it as UTC, not as the phone wall-clock', () async {
      final out = await _underZone('Africa/Algiers', r'''
    final r = Review.fromJson(jsonDecode(_wire) as Map<String, dynamic>);
    print(r.createdAt.toString());
''');
      // 20:23:50 UTC is 21:23:50 in Algiers (+01:00, no DST since 2021). A
      // parser that read the wall-clock string as local would print 20:23:50
      // and put the review an hour before it was written — and a review sent
      // late on the 31st would file itself under the 1st.
      expect(out.trim(), '2026-09-11 21:23:50.000',
          reason: 'the review must be the instant the Worker wrote, in the '
              'reader wall-clock');
    });

    test('a row with no timestamp is an absence, not a crash', () {
      final json = jsonDecode(_wire) as Map<String, dynamic>;
      json.remove('created_at');
      expect(Review.fromJson(json).createdAt, isNull);
    });
  });

  // ---- the order -------------------------------------------------------
  group('the order a customer reads them in', () {
    test('newest first', () {
      final out = newestReviewFirst([
        _r(1, day: 1),
        _r(3, day: 11),
        _r(2, day: 6),
      ]);
      expect(out.map((r) => r.id), [3, 2, 1]);
    });

    test('undated rows go last and are never dropped', () {
      final out = newestReviewFirst([
        _r(1),
        _r(2, day: 11),
        _r(3),
      ]);
      expect(out, hasLength(3), reason: 'nothing is ever deleted');
      expect(out.map((r) => r.id), [2, 1, 3],
          reason: 'a row the server could not date is an absence — kept, and '
              'never floated to the top pretending to be fresh');
    });

    test('rows sharing a stamp fall back to the id inserted last', () {
      // `List.sort` is not stable, so a tie left to it can swap between two
      // reads of the same page.
      final out = newestReviewFirst([
        _r(7, day: 11),
        _r(9, day: 11),
        _r(8, day: 11),
      ]);
      expect(out.map((r) => r.id), [9, 8, 7]);
    });

    test('two reads of the same page are the same page', () {
      final input = [_r(1, day: 1), _r(2, day: 11), _r(3, day: 11)];
      expect(newestReviewFirst(input).map((r) => r.id).toList(),
          newestReviewFirst(input).map((r) => r.id).toList());
    });

    test('an empty or single list is returned, not lost', () {
      expect(newestReviewFirst(const []), isEmpty);
      expect(newestReviewFirst([_r(1, day: 1)]).single.id, 1);
    });
  });

  // ---- the screen ------------------------------------------------------
  group('the profile screen', () {
    testWidgets('a review says how old it is', (tester) async {
      await _pump(
          tester, await _boot([_row(5, at: '2026-09-11 20:23:50')]),
          DateTime.utc(2026, 9, 11, 21, 0).toLocal());
      expect(find.byKey(const Key('review-when')), findsOneWidget);
      // 20:23:50 -> 21:00:00 is 36m10s, and the minute arm floors. My first
      // assertion said 37 and the test caught it: the function was right and
      // the number in the test was not, which is the only direction worth
      // catching in a boundary test.
      expect(find.text('قبل 36 دقيقة'), findsOneWidget);
    });

    testWidgets('an unsorted list is drawn newest first, not as it arrived',
        (tester) async {
      // The Worker sends what it sends. Oldest-first is the natural shape of an
      // upserted table, and the screen used to draw it verbatim.
      await _pump(
          tester,
          await _boot([
            _row(1, at: '2026-09-01 10:00:00'),
            _row(2, at: '2026-09-11 20:23:50'),
          ]),
          DateTime.utc(2026, 9, 11, 21, 0).toLocal());
      final dates = tester
          .widgetList<Text>(find.byKey(const Key('review-when')))
          .map((t) => t.data)
          .toList();
      expect(dates, ['قبل 36 دقيقة', 'قبل 10 أيام'],
          reason: 'a list reading «قبل 10 أيام» above «قبل 36 دقيقة» dates its '
              'own evidence inconsistently — the newest answer to "is he still '
              'good?" has to be the row the customer meets first');
    });

    testWidgets('an undated row prints no date at all', (tester) async {
      // Not «الآن» and not a fallback: the server sent nothing, so the card
      // draws as it always did rather than claiming a recency it cannot back.
      await _pump(tester, await _boot([_row(5)]), DateTime.utc(2026, 9, 11, 21, 0).toLocal());
      expect(find.byKey(const Key('review-when')), findsNothing);
    });

    testWidgets('a genuinely empty list still says so', (tester) async {
      // The date must not make the empty state look like a failure, and must
      // not make «لا تقييمات بعد» appear over reviews that exist.
      await _pump(tester, await _boot(<Object>[]), DateTime.utc(2026, 9, 11, 21, 0).toLocal());
      expect(find.byKey(const Key('profile-reviews-empty')), findsOneWidget);
      expect(find.byKey(const Key('review-when')), findsNothing);
    });
  });
}

/// [raw] as a Dart string literal, so the generated probe embeds the *same*
/// payload the test file parsed above rather than a second copy that could
/// drift from it.
String _jsonString(String raw) {
  final b = StringBuffer();
  b.write("'");
  for (final unit in raw.codeUnits) {
    if (unit == 0x27 || unit == 0x5c || unit == 0x24) b.writeCharCode(0x5c);
    b.writeCharCode(unit);
  }
  b.write("'");
  return b.toString();
}

/// Runs [body] in a real Dart VM under `TZ=<zone>` and returns its stdout.
///
/// Copied from `subscription_clock_test.dart`, and for the same reason: the
/// drift is between two *interpretations* of one string, and this box is
/// `Etc/UTC`, where those interpretations coincide. Reading the offset
/// in-process cannot produce the bug, so the only honest way to pin it is a
/// second process in a real zone.
///
/// The Dart VM, not `Platform.resolvedExecutable`: under `flutter test` that
/// resolves to `flutter_tester`, which does not take a script path — it starts,
/// loads nothing and sits there until the test's timeout kills it, which looks
/// exactly like a machine problem and is not one.
String _dartVm() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/dart';
  final cache = File(Platform.resolvedExecutable)
      .parent // <plat>
      .parent // engine
      .parent // artifacts
      .path; // <root>/bin/cache
  return '$cache/dart-sdk/bin/dart';
}

Future<String> _underZone(String zone, String body) async {
  // `build/` is inside the package (so the import resolves) and git-ignored
  // (so the probe is never committed). Under the package root rather than a
  // system temp dir, which is outside it.
  final dir = Directory('${Directory.current.path}/build/_tz_probe')
    ..createSync(recursive: true);
  final file = File('${dir.path}/probe.dart');
  try {
    file.writeAsStringSync('''
import 'dart:convert';
import 'package:allomokawil/src/models/quote_review.dart';
const _wire = ${_jsonString(_wire)};
void main() {
$body
}
''');
    final result = await Process.run(
      _dartVm(),
      ['run', file.path],
      environment: <String, String>{
        'TZ': zone,
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '',
      },
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0) {
      fail('probe under TZ=$zone failed:\n${result.stdout}\n${result.stderr}');
    }
    return '${result.stdout}';
  } finally {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
