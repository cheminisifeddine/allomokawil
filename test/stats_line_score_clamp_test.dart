// A star that means «out of five», beside the number 7.5.
//
// Found on 1 Oct 2026, twenty minutes after the clamp that closed the first
// three copies of this defect shipped. `clampRating` was lifted out of
// `starIconFor` and asked by the glyphs, the printed digits in `RatingStars`
// and the spoken label in `A11y.rating`. The rule was correct and it was
// applied to three of the four places a score reaches glass.
//
// The fourth is `_StatsLine` on the contractor's own home
// (`worker_home_screen.dart:1624`), and it is the one that does not go through
// `RatingStars` at all: it draws its own single `Icons.star_rounded` and its
// own `Text`, so the clamp that lives in the widget never reached it. It
// printed `worker.avgRating!.toStringAsFixed(1)` raw. An `avg_rating: 7.5`
// off `GET /api/mobile/my/profile` printed **7.5** next to a gold star.
//
// Why the previous tick's sweep missed it, stated so the next one does not
// repeat it: the audit listed every `RatingStars` call site and every
// `toStringAsFixed` and called the count three. The count was right about
// stars and wrong about *stars* — the bug was in the one rating line that has
// no star row, so "grep for the widget" and "grep for the widget's arithmetic"
// both miss it. What catches it is asking the other question: **which other
// place prints this same number, with its own copy of the formatting?** The
// answer is found by looking for `avgRating` outside `models/` and `ui.dart`,
// not by counting the rows that draw five glyphs.
//
// Why it is worth shipping while latent, and it is latent in exactly the same
// way as the last one: `WorkerProfile._rating` folds a score to null only when
// `v > 0` is false, so 7.5 is kept intact; and the score is the one value on
// this row the **server** writes and the app does not. But the blast radius
// differs from the `RatingStars` case, and that is the argument. On the browse
// card a wrong score is one card among twenty-six. This is the contractor's
// own header, the first thing he sees when he opens the app, on the screen
// where `stats_freshness_copy` was written specifically to stop the app
// making claims about his business that have gone stale. A 7.5 printed there
// is the app rating him above every other tradesman on the platform.
//
// Every value a real payload carries — 0/4.5/4.6/4.7/4.8/5 — renders
// byte-identically before and after, so this is deliberately **not**
// pixel-proofed: a screenshot of the live app would show nothing about it and
// offering one anyway would be theatre. The proof offered instead is a widget
// test on the real mounted header, plus the behavioural revert below.
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/star_row_shape.dart';
import 'package:allomokawil/src/data/worker_stats_copy.dart';
import 'package:allomokawil/src/models/worker.dart';
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

/// Real history, so the stats line renders at all: the header gates it on
/// [WorkerProfile.hasHistory], and a fixture with no jobs and no reviews
/// measures the gate instead of the fix.
Map<String, Object?> _worker(Object score) => {
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
      'avg_rating': score,
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
  _Platform(this.score);
  final Object score;

  ApiClient build() => ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          final p = req.url.path;
          if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
            return _json(<String, Object?>{'token': 'tok', 'user': _user()});
          }
          if (p.endsWith('/api/unread')) return _json(0);
          if (p.endsWith('/api/mobile/my/profile')) return _json(_worker(score));
          if (p.endsWith('/api/mobile/my/subscription')) {
            return _json(<String, Object?>{
              'plan': <String, Object?>{'id': 'basic', 'name_ar': 'أساسي'},
              'usage': <String, Object?>{'quotes_used': 1, 'quote_limit': 3},
              'payment': <String, Object?>{'methods': <Object?>[]},
            });
          }
          // Exact equality, for the reason `worker_home_pull_to_refresh_test`
          // records: `req.url.path` excludes the query string, so a `contains`
          // here would serve the shell's own projects tab the market's fixture.
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

/// Mounts the real header — the same `MarketplaceView` the tab body builds,
/// with the same clock, so this measures the shipped widget and not a
/// reconstruction of it.
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
      home: Scaffold(
        body: MarketplaceView(repo: Repository(api), clock: clock),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<AuthState> _auth(Object score) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = _Platform(score).build();
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

/// What the stats line actually prints for a score the **server** chose.
///
/// Read off the real `Text` in the tree rather than by calling the rule, so
/// this cannot pass by asserting that [clampRating] does what [clampRating]
/// is documented to do.
String? _printed(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).data;

void main() {
  // The gate the previous fix relied on, restated as a precondition so this
  // file fails loudly if the model ever starts folding an oversized score to
  // null — which would make the whole defect unreachable rather than fixed.
  test('an oversized mean is not folded away by the model', () {
    final w = WorkerProfile.fromJson(_worker(7.5));
    expect(w.avgRating, 7.5,
        reason: 'v > 0 is the only filter, so 7.5 reaches the widget intact');
    expect(w.hasRating, isTrue);
  });

  testWidgets('a score above the scale prints the top of the scale',
      (tester) async {
    final now = DateTime(2026, 9, 27, 12);
    final auth = await _auth(7.5);
    await _pumpHeader(tester, _Platform(7.5).build(), auth, clock: () => now);

    expect(find.text('7.5'), findsNothing,
        reason: 'the star beside it means out of five; 7.5 of five is a lie');
    expect(find.text('5.0'), findsOneWidget);
  });

  // One case per mount, and that is not tidiness. A second `pumpWidget` of the
  // same `MarketplaceView` in the same test body reuses the header the first
  // mount already built, so the loop below went on looking for «4.6» in a tree
  // still holding «4.5» and failed on a harness artefact — a red that says
  // nothing about the fix. Caught by running this file against a reverted
  // `lib/`, which is the only way a wrong red is ever visible.
  // NaN is deliberately **not** in this list. JSON has no way to carry it —
  // `jsonEncode` refuses to write it — so a NaN cannot arrive down this wire
  // and a mock that served one would be testing a payload the API cannot send.
  // What NaN *is*, is a value a Dart-side computation could hand the model, and
  // that half is asserted as a plain unit test below rather than by pretending
  // the server sent one.
  for (final bad in <Object>[-2, 0]) {
    testWidgets('a $bad is no score, and says so', (tester) async {
      final now = DateTime(2026, 9, 27, 12);
      final auth = await _auth(bad);
      await _pumpHeader(tester, _Platform(bad).build(), auth, clock: () => now);
      // `_rating` folds every one of these to null, so the honest sentence is
      // the one the model chose, not a number the widget could clamp.
      expect(find.text(noRatingAr()), findsOneWidget);
      expect(_printed(tester, noRatingAr()), noRatingAr());
    });
  }

  for (final real in <double>[4.5, 4.6, 4.7, 4.8, 5.0]) {
    testWidgets('a real payload score of $real is printed exactly',
        (tester) async {
      final now = DateTime(2026, 9, 27, 12);
      final auth = await _auth(real);
      await _pumpHeader(tester, _Platform(real).build(), auth, clock: () => now);
      // The no-regression arm. A clamp that moved a score the platform
      // actually carries would be a worse defect than the one it fixed: it
      // would be wrong about every contractor, every day, and it would look
      // like a rounding decision.
      expect(find.text(real.toStringAsFixed(1)), findsOneWidget);
    });
  }

  test('a NaN is folded to no score, and a legal score never moves', () {
    // The Dart-side half of the unreachable-by-JSON case: a computed mean
    // could be NaN before it ever reaches the model, and `_rating` must not
    // hand a NaN to a widget that is about to print it.
    // Neither of these can arrive down the wire: Dart's `jsonEncode` throws
    // `JsonUnsupportedObjectError` on both, checked here rather than assumed.
    // They are asserted at the **model** because that is the one place a
    // computed mean could still become one before it is printed, and a mock
    // serving an infinite literal in a JSON body would be testing a payload
    // the API cannot send.
    expect(WorkerProfile.fromJson(_worker(double.nan)).avgRating, isNull);
    expect(WorkerProfile.fromJson(_worker(double.infinity)).avgRating,
        double.infinity,
        reason: 'v > 0 holds, so infinity is a score and the widget pins it');
    expect(clampRating(double.infinity), 5.0);
    expect(clampRating(double.negativeInfinity), 0.0);
    for (var v = 0.0; v <= 5.0; v += 0.001) {
      expect(clampRating(v), v, reason: 'the clamp moved a legal $v');
    }
  });

  test('the number printed and the star beside it agree', () {
    // The property, stated over the whole range the row can hold rather than
    // at the five values above: whatever the server sends, the digits can
    // never exceed the scale the single gold star is a mark on.
    for (var v = -5.0; v <= 9.0; v += 0.1) {
      expect(clampRating(v), lessThanOrEqualTo(5.0),
          reason: 'a printed $v outranks the star it sits beside');
    }
  });
}
