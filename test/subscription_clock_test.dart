// The subscription clock: a UTC timestamp the app read as local wall-clock.
//
// Found on 26 Sep by a read-only audit of the billing model, not from a wish
// list. D1 writes `expires_at` the way SQLite's `CURRENT_TIMESTAMP` does —
// `YYYY-MM-DD HH:MM:SS`, UTC, **no zone marker** — and the app already has
// `parseServerTime` for exactly this, documented in `models/chat.dart`:
//
//     Timestamps come from D1 as `YYYY-MM-DD HH:MM:SS` in UTC with no zone
//     marker, so they go through `parseServerTime` … which would read them as
//     local wall-clock and print every message an hour off in Algiers.
//
// Three places did not go through it. `isExpired` parsed the string bare, and
// so did the two places that print the end date. On a phone set to
// Africa/Algiers that is a one-hour error, and one hour is the entire width of
// the day an expiry lands on:
//
//   * a plan ending `2026-10-01 00:00:00` UTC ends on the **30th** for the
//     contractor paying for it, and the card said the 1st;
//   * `isExpired` therefore fires an hour early — a man loses his paid plan
//     while his money still has 59 minutes to run;
//   * and, the worst of the three, the account row printed the server's raw
//     string and said «نشط» whatever the date was, so a subscription that
//     lapsed in 2020 still read "أساسي — نشط حتى 2020-01-01" on the row whose
//     only job is to send him to the renewal screen.
//
// A test that only runs in this box's `Etc/UTC` cannot see any of it: there
// the two parses are identical, which the last test in the first group asserts
// as its own premise. The real app runs on Algerian phones in UTC+1, so the
// assertions here run in a subprocess with `TZ=Africa/Algiers` — an actual
// timezone-database lookup, not a faked `DateTime` and not a shifted fake clock.
//
// The probe file is written into `build/` rather than the system temp dir: a
// Dart file outside the package cannot resolve `package:allomokawil/...`, and
// `dart run` on one does not fail fast — it hangs until the test's 30 s timeout
// fires three times over. `build/` is git-ignored, so nothing is ever committed
// and the directory is already the one the build itself owns.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:allomokawil/src/screens/worker/subscription_screen.dart';

/// The plan a contractor actually buys, with the server's own timestamp shape.
SubscriptionStatus paid({
  String? expiresAt = '2026-10-01 00:00:00',
}) =>
    SubscriptionStatus.fromJson(<String, dynamic>{
      'plan': 'basic',
      'name_ar': 'أساسي',
      'status': 'active',
      'starts_at': null,
      'expires_at': expiresAt,
      'quote_limit': -1,
      'portfolio_limit': 30,
      'quotes_used_this_month': 2,
      'renews_in_days': null,
    });

/// Runs [body] in a real Dart VM under `TZ=<zone>` and returns its stdout.
///
/// The drift is between two *interpretations* of one string, and this box is
/// `Etc/UTC`, where those interpretations coincide. Reading a
/// `DateTime.now().timeZoneOffset` in-process cannot produce the bug, so the
/// only honest way to pin it is a second process with a different zone.
/// The Dart VM, not `Platform.resolvedExecutable`.
///
/// Under `flutter test` that resolves to `flutter_tester`, which does not take
/// a script path: it starts, loads nothing, and sits there until the test's
/// 30 s timeout kills it. The first version of this file used it and three
/// tests died on `TimeoutException` with no output at all, which looks exactly
/// like a machine problem and is not one.
///
/// Same resolution `design_shots_test.dart` uses, and for the same reason —
/// an absolute path hardcoded to one host dies with the host. `FLUTTER_ROOT` is
/// exported by `flutter test`; the fallback hops six `.parent`s out of
/// `flutter_tester` back to the SDK root, then takes `bin/dart`.
String _dartVm() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    return '$root/bin/dart';
  }
  final cache = File(Platform.resolvedExecutable)
      .parent // <plat>
      .parent // engine
      .parent // artifacts
      .path; // <root>/bin/cache
  return '$cache/dart-sdk/bin/dart';
}

Future<String> _underZone(String zone, String body) async {
  // `build/` is inside the package (so the import resolves) and git-ignored
  // (so the probe is never committed). Created under the package root rather
  // than a system temp dir, which is outside it.
  final dir = Directory('${Directory.current.path}/build/_tz_probe')
    ..createSync(recursive: true);
  final file = File('${dir.path}/probe.dart');
  try {
    file.writeAsStringSync("""
import 'package:allomokawil/src/models/plan.dart';
void main() {
  $body
}
""");
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

void main() {
  group('subscription expiry is read in the phone timezone', () {
    test('a plan ending at 00:00 UTC expires on the day Algiers is in', () async {
      final out = await _underZone('Africa/Algiers', r'''
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'basic', 'name_ar': 'x', 'status': 'active',
        'starts_at': null, 'expires_at': '2026-10-01 00:00:00',
        'quote_limit': -1, 'portfolio_limit': 1,
        'quotes_used_this_month': 0, 'renews_in_days': null,
      });
      final end = s.expiresAtLocal!;
      print('END=${end.year}-${end.month.toString().padLeft(2, "0")}-'
          '${end.day.toString().padLeft(2, "0")}');
      print('HOUR=${end.hour}');
''');
      // 2026-10-01 00:00 UTC is 01:00 on the 1st in Algiers, so the day the
      // contractor's money actually runs out is the 1st here. Read as bare
      // wall-clock it is 00:00 on the 1st too — but `HOUR` is what proves the
      // string was pinned to UTC and not read as a local wall clock, and a
      // `DateTime` that *looks* the same can still be an hour wrong.
      expect(out, contains('END=2026-10-01'));
      // The bug's real shape, stated on its own: the instant D1 wrote is 01:00
      // in Algiers. Bare parsing yields 00:00 and is an hour early.
      expect(out, contains('HOUR=1'));
    });

    test('a plan ending at 23:00 UTC is still the next day in Algiers', () async {
      final out = await _underZone('Africa/Algiers', r'''
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'basic', 'name_ar': 'x', 'status': 'active',
        'starts_at': null, 'expires_at': '2026-09-30 23:00:00',
        'quote_limit': -1, 'portfolio_limit': 1,
        'quotes_used_this_month': 0, 'renews_in_days': null,
      });
      final end = s.expiresAtLocal!;
      print('DAY=${end.day}');
''');
      // The sharper half of the same defect, and the one that files a day under
      // the wrong date. 23:00 UTC on the 30th is 00:00 on the 1st in Algiers:
      // bare parsing calls the 30th the last day of the plan and takes a paid
      // day off him.
      expect(out, contains('DAY=1'));
    });

    test('isExpired does not fire an hour early', () async {
      final out = await _underZone('Africa/Algiers', r'''
      // D1 says this plan runs until 00:30 UTC. In Algiers that is 01:30, so
      // at 01:00 local the plan is still paid for. The old parse read the
      // string as 00:30 local and declared it dead 30 minutes early.
      final s = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'basic', 'name_ar': 'x', 'status': 'active',
        'starts_at': null, 'expires_at': '2099-01-01 00:30:00',
        'quote_limit': -1, 'portfolio_limit': 1,
        'quotes_used_this_month': 0, 'renews_in_days': null,
      });
      print('END_HOUR=${s.expiresAtLocal!.hour}');
''');
      // 00:30 UTC -> 01:30 Algiers. A parse that left this at 0 is the defect,
      // stated as the number that changes.
      expect(out, contains('END_HOUR=1'));
    });

    test('this box is UTC, which is why an in-process test cannot see it', () {
      // Guards the premise of the three tests above. If a future machine runs
      // in UTC+1 by default, the subprocess probes stop being the only way to
      // see the bug and someone can delete them as redundant.
      expect(DateTime.now().timeZoneOffset.inMinutes, 0,
          reason: 'this test assumes a UTC box; the subprocess probes are what '
              'cover the drift');
    });
  });

  group('a plan whose expiry cannot be read is not declared over', () {
    test('an unreadable date is not expired', () {
      expect(paid(expiresAt: 'not-a-date').isExpired, isFalse);
      expect(paid(expiresAt: null).isExpired, isFalse);
      expect(paid(expiresAt: null).expiresAtLocal, isNull);
    });

    test('the free plan has no expiry to read', () {
      final free = SubscriptionStatus.fromJson(<String, dynamic>{
        'plan': 'free_trial',
        'name_ar': 'مجاني',
        'status': 'active',
        'starts_at': null,
        'expires_at': '2020-01-01 00:00:00',
        'quote_limit': 3,
        'portfolio_limit': 5,
        'quotes_used_this_month': 0,
        'renews_in_days': null,
      });
      expect(free.isExpired, isFalse);
      expect(free.expiresAtLocal, isNull);
    });
  });

  group('the end date the user reads', () {
    test('is the Algiers day, zero-padded, from the already-local instant', () {
      final s = paid(expiresAt: '2026-09-13 12:04:11');
      expect(subscriptionEndDateLabel(s.expiresAtLocal), '2026-09-13');
    });

    test('is null when there is nothing to format', () {
      expect(subscriptionEndDateLabel(null), isNull);
    });
  });

  group('the copy on the real subscription screen', () {
    testWidgets('a plan that expired in 2020 is not announced as active',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/mobile/subscription')) {
            return http.Response(jsonEncode(_catalogue('2020-01-01 00:00:00')),
                200, headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(<String, Object?>{}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      final auth = AuthState(api);

      await tester.pumpWidget(AppScope(
        api: api,
        auth: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          locale: const Locale('ar'),
          home: const SubscriptionScreen(),
        ),
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The half of the defect a model test cannot see: it happened in a
      // `build`. A plan whose date passed must not render as the live, verified
      // card, whatever `status` still says in the row.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.any((t) => t.contains('مفعّل')), isFalse,
          reason: 'a 2020 plan is rendered as active: $texts');
      expect(texts.any((t) => t.contains('منتهي')), isTrue,
          reason: 'the card never says the plan is over: $texts');
    });
  });
}

/// A paid `basic` subscription in the shape the Worker sends it.
Map<String, Object?> _catalogue(String expiresAt) => <String, Object?>{
      'currency': 'DZD',
      'commission_percent': 0,
      'commission_per_order': 0,
      'note_ar': 'الاشتراك فقط',
      'plans': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'basic',
          'name_ar': 'أساسي',
          'name_fr': 'Basique',
          'price_month': 1500,
          'price_year': 15000,
          'quote_limit': -1,
          'portfolio_limit': 30,
          'search_boost': 1,
          'wilaya_span': 1,
          'features': <String>[],
        },
      ],
      'current': <String, Object?>{
        'plan': 'basic',
        'name_ar': 'أساسي',
        'status': 'active',
        'starts_at': null,
        'expires_at': expiresAt,
        'quote_limit': -1,
        'portfolio_limit': 30,
        'quotes_used_this_month': 2,
        'renews_in_days': null,
      },
      'pending_request': null,
      'payment': <String, Object?>{
        'methods': <Map<String, Object?>>[],
        'support_phone': null,
      },
};
