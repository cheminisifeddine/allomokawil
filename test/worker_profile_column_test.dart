// The contractor profile's two columns, measured.
//
// `worker_profile_screen.dart` held the **most** off-grid literals of any file
// left in the 8pt sweep (9, across 8 `EdgeInsets`), and like the last three
// slices the count was the least interesting part of it. Two of the eight were
// `fromLTRB(18, 8, 18, 28)` — **byte-identical to `AppTheme.pagePad`**, a
// token `project_detail_screen.dart` and `skeletons.dart` have been calling by
// name all along. Two screens agreed by coincidence: one had spelled out the
// token, the other had written it out a second time.
//
// The part that made this worth a guard rather than a rename: the second
// `pagePad` spelling was `_ProfileSkeleton` — the frame the reader watches while
// this page loads, and the thing that is *removed* the moment the answer lands.
// So the two columns are one column in two states, and sweeping one would have
// shifted every card on the screen 2 dp at the exact moment the network
// answered: the "one band moved, its neighbours left behind" shape that three
// earlier slices had to undo. The same pairing is at `:1102`, where
// `_ReviewsSkeleton` previews the gap between review cards before they exist.
//
// So the columns are pinned here by geometry, read off the widget tree rather
// than transcribed from source: the loaded body and the skeleton it replaces
// must agree on **one** number, and the skeleton is asserted against the loaded
// state directly rather than against a constant, because a pair of hand-typed
// constants drift apart silently.
//
// The measurement traps are inherited from `customer_home_column_test.dart`,
// and both fire here:
//   * a `Padding` lays out at its parent's full width, so its own rect is the
//     **outer** edge and asserting on it compares the screen to itself — the
//     inset is `rect + padding`, never `rect`;
//   * a `ListView` hands its `padding` to an internal `SliverPadding`, so
//     `ListView.padding` is null and the naive read answers 0.0. Every column
//     measured here is a list.
import 'dart:async';
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
import 'package:allomokawil/src/screens/worker/my_portfolio_screen.dart';
import 'package:allomokawil/src/screens/worker/worker_profile_screen.dart';
import 'package:allomokawil/src/widgets/skeletons.dart';

/// Worker 5, «رشيد خليفي» — the live payload
/// `reviews_section_short_list_test.dart` already uses, because a worker this
/// app never actually receives would prove nothing about the wire.
const _worker = <String, Object?>{
  'id': 5, 'user_id': 31, 'bio': 'حرفي في الطلاء الخارجي والعام',
  'specialties': ['painting'], 'experience_years': 5,
  'price_range_min': 20000, 'price_range_max': 60000, 'service_radius_km': 30,
  'is_available': 1, 'is_identity_verified': 1, 'is_certificate_verified': 0,
  'verification_status': 'verified', 'subscription_plan': 'free_trial',
  'avg_rating': 4.7, 'total_reviews': 30, 'total_completed_jobs': 7,
  'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// [reviews] null answers **never** — which is how the skeleton is held on
/// screen long enough to be measured. A mock that returns immediately would let
/// the skeleton paint for a single frame and be gone before a pump could read
/// it, and the assertion would pass for a band that was never drawn.
Future<void> _pumpProfile(
  WidgetTester tester, {
  required Object worker,
  Object? reviews,
  Completer<http.Response>? reviewsGate,
  Completer<http.Response>? profileGate,
}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 30, 'phone': '0773000000', 'email': null,
            'full_name': 'زبون تجربة', 'type': 'customer', 'avatar_url': null,
            'wilaya': '16', 'commune': null,
            'created_at': '2026-09-11 20:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      // Two independent gates, because the two pairings below need to hold
      // *different* halves: the page one holds `/workers/5` and the reviews
      // one holds `/reviews`. A single gate that covered every request - the
      // first draft - meant the body never arrived either, so the page pairing
      // measured a skeleton against nothing, and the reviews pairing measured
      // a skeleton against a page with no cards in it.
      if (p.endsWith('/reviews') && reviewsGate != null) {
        return reviewsGate.future;
      }
      if (p.endsWith('/reviews')) return _json(reviews ?? const <Object>[]);
      if (p.endsWith('/portfolio')) return _json(const <Object>[]);
      if (p == '/api/mobile/workers/5' && profileGate != null) {
        return profileGate.future;
      }
      if (p == '/api/mobile/workers/5') return _json(worker);
      return _json(const <Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);

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
      home: const WorkerProfileScreen(workerId: 5),
    ),
  ));
  // Bounded, never pumpAndSettle: `Shimmer` animates forever on this screen,
  // so a settle would wait out the timeout and report a failure that is not
  // this file's.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The x at which a horizontal `ListView`'s **rows** start.
///
/// Not `ListView.padding` — a list hands its padding to an internal
/// `SliverPadding` and the widget's own field is null, so the naive read
/// answers 0.0 and passes for any inset at all.
double _listRowLeft(WidgetTester tester, Finder list) {
  final pads = tester
      .widgetList<SliverPadding>(find.descendant(
          of: list, matching: find.byType(SliverPadding)))
      .map((e) => e.padding.resolve(TextDirection.rtl).left)
      .where((l) => l > 0);
  return _rectLeft(tester, list) + (pads.isEmpty ? 0.0 : pads.first);
}

double _rectLeft(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero).dx;

void main() {
  group('the profile page has ONE column, in both of its states', () {
    test('pagePad is the token these lines used to re-type', () {
      // Asserted as a **value**, so the guard below cannot be satisfied by a
      // screen that merely agrees with another literal. `gutter` is 18 and is
      // deliberately off the 4 dp grid — it is a page margin, not a component
      // gap — and the sweep moved *these* lines onto the token without moving a
      // single pixel.
      expect(AppTheme.gutter, 18.0);
      expect(AppTheme.pagePad.resolve(TextDirection.rtl).left, AppTheme.gutter);
      expect(AppTheme.pagePad.resolve(TextDirection.rtl).right, AppTheme.gutter);
    });

    testWidgets('the loaded body sits on AppTheme.pagePad', (tester) async {
      await _pumpProfile(tester, worker: _worker, reviews: const <Object>[]);

      final list = find.byType(ListView).first;
      expect(list, findsOneWidget);
      final rowLeft = _listRowLeft(tester, list);
      // The list is full-bleed, so its own left edge is 0 and every band in
      // the page starts at the gutter inset from it.
      expect(rowLeft - _rectLeft(tester, list), AppTheme.gutter,
          reason: 'the first card of this screen must start on the page '
              'gutter — this is the number the sweep re-typed twice');
    });

    testWidgets('the skeleton that replaces it agrees, to the pixel',
        (tester) async {
      // The skeleton is the column as the reader first sees it, and it is the
      // *same list position*: `_ProfileSkeleton` is what `_body` becomes while
      // the answer is in flight. Asserted against the **loaded** state rather
      // than against a second hand-typed constant, because two constants drift
      // apart silently and that is the whole failure this file exists to
      // prevent.
      final gate = Completer<http.Response>();
      await _pumpProfile(tester,
          worker: _worker, reviews: const <Object>[], profileGate: gate);

      final skeleton = find.byType(Shimmer);
      expect(skeleton, findsWidgets,
          reason: 'the loading frame must actually be on screen, or every '
              'assertion below is measuring a page that never drew');

      final skelList = find
          .descendant(of: skeleton.first, matching: find.byType(ListView))
          .first;
      final skeletonLeft =
          _listRowLeft(tester, skelList) - _rectLeft(tester, skelList);

      // Let the profile answer, then measure the real body in the same test.
      gate.complete(_json(_worker));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      final bodyList = find.byType(ListView).first;
      final bodyLeft =
          _listRowLeft(tester, bodyList) - _rectLeft(tester, bodyList);

      expect(skeletonLeft, bodyLeft,
          reason: 'the page must not shift when the answer lands — the loading '
              'frame and the page it stands in for are one column, and '
              'sweeping only one of them is what this file is here to catch');
      expect(skeletonLeft, AppTheme.gutter);
    });

    testWidgets('the reviews skeleton previews the real card gap',
        (tester) async {
      // Same pairing one section down: `_ReviewsSkeleton` (:1102) draws two
      // placeholder cards in the frame shown while the section loads, and
      // `_ReviewsSection` (:914) draws the real ones. If only the real one
      // moved, the section would visibly re-flow the moment the reviews
      // arrived.
      const one = <String, Object?>{
        'id': 11, 'customer_id': 30, 'worker_id': 5, 'rating': 5,
        'comment': 'عمل ممتاز!', 'created_at': '2026-01-20 10:00:00',
        'customer_full_name': 'زبون تجربة', 'customer_avatar_url': null,
      };
      final gate = Completer<http.Response>();
      await _pumpProfile(tester,
          worker: _worker, reviews: const [one, one], reviewsGate: gate);

      // The reviews section sits below the fold and a `ListView` builds lazily,
      // so at rest **nothing in it exists in the tree** - the first draft failed
      // with "the reviews skeleton must be on screen" for this reason alone,
      // which is a louder failure than the wrong number would have been. Scroll
      // first, then measure, exactly as `reviews_short_list_shot_test` does.
      await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
      await tester.pump(const Duration(milliseconds: 200));

      final skelGap = _skeletonReviewInsets(tester);

      gate.complete(_json(const <Object>[one, one]));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
      await tester.pump(const Duration(milliseconds: 200));
      final realGap = _realReviewInsets(tester);

      expect(skelGap, isNotEmpty,
          reason: 'the skeleton must be drawing rows for this to mean anything');
      expect(realGap, isNotEmpty,
          reason: 'the fixture must draw real rows, or the pairing is vacuous');
      expect(skelGap.toSet(), realGap.toSet(),
          reason: 'the placeholder cards must be inset exactly where the real '
              'ones land - the two were both `10` and are now both `s12`');
      expect(realGap.first, AppTheme.s12,
          reason: 'card-to-card on this screen is s12, the same gap the '
              'project list and the contractor strip use');
    });

    testWidgets('the cover inset and the avatar ring are the tokens',
        (tester) async {
      await _pumpProfile(tester, worker: _worker, reviews: const <Object>[]);

      // `_CoverHeader` paints over the full-bleed cover photo, so its inner
      // `Padding` is the page gutter used *inside a header* — the same reason
      // `StickyCta` in ui.dart is allowed to use it, and the same value the
      // `ui.dart` comment says `worker_profile` already sits on.
      final coverPad = find.descendant(
          of: find.byType(WorkerProfileScreen),
          matching: find.byWidgetPredicate((w) =>
              w is Padding && w.padding == const EdgeInsets.all(AppTheme.gutter)));
      expect(coverPad, findsWidgets,
          reason: 'the cover\'s own inset must be the page gutter by name');

      // The white ring around the avatar. `AppTheme.ring` IS this 3 — it was
      // named for this exact job and `worker_home_screen.dart` already calls it
      // twice. At 4 dp it would eat 1 dp of the icon it frames, so it is a
      // documented exception, not a leftover.
      expect(AppTheme.ring, 3.0);
      expect(AppTheme.ring % 4 != 0, isTrue,
          reason: 'ring is deliberately off-grid; if this ever goes green the '
              'token and its documented reason disagree');
    });
  });

  // Added by the nineteenth slice: the same pairing, one screen over — and the
  // reason it needed saying out loud rather than another rename.
  //
  // `my_portfolio_screen.dart` held the page column in TOKENS —
  // `AppTheme.gutter, AppTheme.s12, AppTheme.gutter, AppTheme.s28` — which
  // reads as the safe way to write it and is why nothing compared it to
  // `pagePad` for a day: `card_recipe_test.dart`'s R5 matches four PLAIN
  // NUMBERS, so a token-spelled column is invisible to the one guard that owns
  // this rule. It sat 4 dp low on the top edge, live since 6 Oct, while the
  // eighteenth slice fixed the identical 4 dp on two screens R5 *could* see.
  //
  // Fixing the screen alone would have been worse than leaving it: the gallery
  // draws `SkeletonGrid()` while the first read is in flight, that skeleton
  // held the same `s12`, and the two are drawn one after the other. Moving one
  // trades a static offset for a 4 dp jump the moment the photographs land.
  // So the pairing is pinned here, by the same method as the three above and
  // for the same reason: two states, one column, measured on the tree.
  group('the gallery opens on the column its photographs land on', () {
    EdgeInsets columnOf(WidgetTester tester, Finder list) {
      final w = tester.widget<ListView>(list);
      return w.padding!.resolve(TextDirection.rtl);
    }

    testWidgets('the loading frame and the gallery agree, to the pixel',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      // The skeleton, mounted as the screen mounts it. Measured directly
      // rather than by holding a read open, because the skeleton is a plain
      // widget with no gate of its own and a gate here would test the mock.
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ar'),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: const SkeletonGrid(),
            ),
          ),
        ),
      ));
      // Bounded, never pumpAndSettle: `Shimmer` animates forever.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      final skeleton = find.byType(SkeletonGrid);
      expect(skeleton, findsOneWidget,
          reason: 'the skeleton must actually be on screen, or the assertion '
              'below is comparing two numbers nothing drew');
      final skelColumn = columnOf(tester, find.descendant(
          of: skeleton, matching: find.byType(ListView)).first);

      // The settled gallery, booted for real against a mock API.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final api = ApiClient(
        baseUrls: const ['https://x.test'],
        httpClient: MockClient((req) async {
          if (req.url.path.contains('/portfolio')) {
            return _json(const <Object>[]);
          }
          if (req.url.path.contains('/subscription')) {
            return _json(<String, Object?>{
              'currency': 'DZD',
              'note_ar': '',
              'commission_percent': 0,
              'commission_per_order': 0,
              'plans': <Object?>[],
              'current': <String, Object?>{
                'plan': 'free_trial',
                'name_ar': 'الخطة المجانية',
                'status': 'active',
                'starts_at': '2026-09-01 00:00:00',
                'expires_at': null,
                'quote_limit': 3,
                'portfolio_limit': 20,
                'quotes_used_this_month': 0,
              },
            });
          }
          if (req.url.path.endsWith('/api/login') ||
              req.url.path.endsWith('/api/register')) {
            return _json(<String, Object?>{
              'token': 'tok',
              'user': <String, Object?>{
                'id': 31, 'phone': '0773000000', 'email': null,
                'full_name': 'مقاول تجربة', 'type': 'worker', 'avatar_url': null,
                'wilaya': '16', 'commune': null,
                'created_at': '2026-09-11 20:00:00',
              },
            });
          }
          return _json(const <Object>[]);
        }),
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
          home: const MyPortfolioScreen(),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      expect(find.byType(SkeletonGrid), findsNothing,
          reason: 'the read answered; the gallery is showing');
      final gallery = columnOf(tester, find.byType(ListView).first);

      expect(skelColumn, AppTheme.pagePad,
          reason: 'SkeletonGrid is drawn in the gallery\'s place while the '
              'first read is in flight, so it is the column the reader sees '
              'first');
      expect(gallery, skelColumn,
          reason: 'the page must not shift when the photographs land — the '
              'loading frame and the gallery it stands in for are one column, '
              'and sweeping only one of them is what this case is here to '
              'catch');
    });
  });
}

/// The `EdgeInsets` declared on the reviews-skeleton placeholder rows.
///
/// Asserted from the **declared widget property**, not from rendered rects, and
/// that is a correction rather than a convenience. The rendered measurement
/// came back 12.77 for the skeleton and 12.38 for the real cards — the same
/// declared `12` scaled by **two different factors**, 1.0640 and 1.0320, on two
/// subtrees of one list. Nothing in `lib/` scales anything: the only
/// `Transform` in the app is `motion.dart`'s press animation, nowhere near
/// this tree. So the rects in this harness are not a pure function of the
/// padding value, and a test written against them would encode this host's
/// device configuration instead of the design.
///
/// Which is also the trap `reviews_section_short_list_test.dart` already
/// records: two runs of its harness on identical code differ by ~1400 raster
/// rows of font antialiasing. The layout engine's own numbers could be trusted
/// where they are integers; these are not, and the honest assertion is the
/// one the sweep actually changed — the value the author wrote.
List<double> _skeletonReviewInsets(WidgetTester tester) {
  final out = <double>[];
  for (final el in find.byType(Padding).evaluate()) {
    final w = el.widget as Padding;
    final b = w.padding.resolve(TextDirection.rtl);
    // The reviews skeleton is the only place on this screen with a 12 dp
    // bottom-only inset; everything else here is page pad, gutter or ring.
    if (b.left == 0 && b.top == 0 && b.right == 0 && b.bottom > 0) {
      out.add(b.bottom);
    }
  }
  return out;
}

/// The same measurement over the real review rows.
List<double> _realReviewInsets(WidgetTester tester) {
  final dates = find.byKey(const Key('review-when'));
  final out = <double>[];
  for (var i = 0; i < dates.evaluate().length; i++) {
    for (final el in find
        .ancestor(of: dates.at(i), matching: find.byType(Padding))
        .evaluate()) {
      final b = (el.widget as Padding).padding.resolve(TextDirection.rtl);
      if (b.left == 0 && b.top == 0 && b.right == 0 && b.bottom > 0) {
        out.add(b.bottom);
      }
    }
  }
  return out;
}
