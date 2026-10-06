// The client home's left column, measured.
//
// Why this file exists. This is the **fourth** screen where the question "is it
// one column or several?" had to be asked before editing, and the answer here
// is the inverse of the last three. On `chat_screen` and `project_new_screen` a
// slice had moved one band and left its neighbours behind, so the column ended
// up with two or three edges 2 dp apart. On this screen the column **agrees** —
// every band sits at 18, the page gutter — but it agreed by *coincidence*: six
// writers had each typed their own `18`, and the one band that already used the
// token (`AppTheme.gutter`, the stale-market strip) agreed with the five that
// did not.
//
// That is the failure R4 is blind to in both directions. It counts literals, so
// it cannot tell agreement from disagreement, and by the time a sweep replaces
// the six spellings with one identifier every one of them stops counting — at
// which point a later half-sweep would move the band nobody re-reads and this
// screen would drift into the exact state the last two slices had to undo.
//
// So the column is pinned here by geometry: every band a reader sees stacked on
// the same left edge is asserted against **one** number, `AppTheme.gutter`, and
// the number is read off the widget tree rather than transcribed from source.
// A later sweep cannot move one band without this file going red.
//
// The measurement traps are inherited from `chat_column_edges_test.dart`, which
// paid for both of them:
//   * a `Padding` lays out at its parent's full width, so its `RenderBox.left`
//     is the **outer** edge and the inset is interior — asserting on the rect
//     compares the screen against itself and passes for any inset;
//   * a `ListView` hands its `padding` to an internal `SliverPadding`, so
//     `ListView.padding` is null and the naive read answers 0.0.
// Three of this screen's bands are lists, so both traps are load-bearing here.
//   * and `SectionTitle` carries its own `fromLTRB(2, …)`, so a title's *text*
//     is 2 dp inside the band that holds it. The band is what is measured; the
//     text is an icon offset wearing a heading's clothes.
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
import 'package:allomokawil/src/screens/customer/customer_home_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';

const _worker = <String, Object?>{
  'id': 16, 'user_id': 31, 'bio': 'دهان وديكور', 'specialties': ['painting'],
  'experience_years': 5, 'price_range_min': 20000, 'price_range_max': 60000,
  'service_radius_km': 30, 'is_available': 1, 'is_identity_verified': 1,
  'is_certificate_verified': 0, 'verification_status': 'verified',
  'subscription_plan': 'free_trial', 'avg_rating': 4.5, 'total_reviews': 3,
  'total_completed_jobs': 7, 'response_time_hours': 2, 'cover_image_url': null,
  'created_at': '2026-09-11 20:23:45', 'updated_at': '2026-09-11 20:23:45',
  'full_name': 'مقاول تجربة', 'phone': '077442495', 'user_wilaya': '16',
  'avatar_url': null,
};

final _project = <String, Object?>{
  'id': 'p1', 'customer_id': 30, 'title': 'دهان شقة 3 غرف',
  'description': 'دهان كامل مع تصليح', 'category': 'painting',
  'images': <String>[], 'wilaya': '16', 'commune': 'حسين داي',
  'latitude': null, 'longitude': null, 'budget_min': 60000, 'budget_max': 90000,
  'urgency': 'within_week', 'status': 'open', 'selected_worker_id': null,
  'created_at': '2026-09-11 20:23:44', 'updated_at': '2026-09-11 20:23:44',
};

const _me = <String, Object?>{
  'id': 30, 'phone': '0773000000', 'email': null, 'full_name': 'زبون تجربة',
  'type': 'customer', 'avatar_url': null, 'wilaya': '16', 'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

/// One conversation, so the returning user is *not* a first run: the guide is
/// derived from both lists, and a user with projects but no threads would still
/// get it.
const _conversation = <String, Object?>{
  'id': 5, 'customer_id': 30, 'worker_user_id': 31, 'project_id': 'p1',
  'other_user_name': 'مقاول تجربة', 'other_user_avatar': null,
  'last_message_content': 'مرحبا', 'unread_count': 0,
  'last_message_at': '2026-09-11 21:00:00',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Pumps the home screen. [firstRun] is driven through the **fixture**, not a
/// constructor flag, because the screen has none: whether the guide shows is
/// derived from what the account already has
/// (`clientNeedsFirstRunGuideFor`), so a new user is one whose projects and
/// conversations both come back empty.
Future<void> _pumpHome(WidgetTester tester, {required bool firstRun}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{'token': 'tok', 'user': _me});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.contains('/workers/top')) return _json([_worker]);
      if (p.endsWith('/api/mobile/my/projects')) {
        return _json(firstRun ? <Object>[] : [ _project ]);
      }
      if (p.endsWith('/api/mobile/conversations')) {
        return _json(firstRun ? <Object>[] : [ _conversation ]);
      }
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land customer');

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
      // The `Key` is load-bearing. This helper is called twice in one test and
      // `pumpWidget` **reuses** the `State` when the widget type matches — so a
      // second `CustomerHomeScreen` would keep the first one's `_firstRun`, its
      // futures and its `initState`, and the guide would never re-decide. That
      // is not a theory: the first cut of this file asserted the guide appears
      // for the empty account and it did not, because the screen under it was
      // a year-old visitor's.
      home: CustomerHomeScreen(key: ValueKey('home-$firstRun')),
    ),
  ));
  // Bounded pumps, not `pumpAndSettle`: the shimmer skeletons and the widen
  // progress bar animate forever on this screen.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

double _rectLeft(WidgetTester tester, Finder f) =>
    tester.renderObject<RenderBox>(f).localToGlobal(Offset.zero).dx;

/// The x at which a horizontal `ListView`'s **rows** start.
///
/// Not `ListView.padding` — a list hands its padding to an internal
/// `SliverPadding` and the widget's own field is null, so the naive read
/// answers 0.0 and the assertion passes for any inset at all.
double _listRowLeft(WidgetTester tester, Finder list) {
  final pads = tester
      .widgetList<SliverPadding>(find.descendant(
          of: list, matching: find.byType(SliverPadding)))
      .map((e) => e.padding.resolve(TextDirection.rtl).left)
      .where((l) => l > 0);
  return _rectLeft(tester, list) + (pads.isEmpty ? 0.0 : pads.first);
}

/// The x at which a `Padding`'s **content** starts — `rect + padding`, never
/// `rect`. A `Padding` is laid out at its parent's full width, so its own rect
/// is the outer edge and asserting on it compares the screen to itself.
double _padContentLeft(WidgetTester tester, Finder pad) {
  final w = pad.evaluate().first.widget as Padding;
  return _rectLeft(tester, pad) + w.padding.resolve(TextDirection.rtl).left;
}

void main() {
  group('the client home has ONE left column', () {
    testWidgets('every band on it sits on AppTheme.gutter', (tester) async {
      await _pumpHome(tester, firstRun: false);

      // The page gutter is 18 and is **named** — it is the one value in the
      // theme that is deliberately off the 4 dp grid, because it is a page
      // margin and not a component gap. Asserting the literal 18 would be
      // asserting the grid against a value the codebase documents as off-grid;
      // asserting the token means a band that retypes the number cannot pass.
      expect(AppTheme.gutter, 18.0);

      // ── The publish banner: the first block on the page. ──
      final cta = find.byKey(const Key('client-post-cta'));
      expect(cta, findsOneWidget,
          reason: 'the publish action is the screen; nothing to compare');
      expect(_padContentLeft(tester, bandAbove(tester, cta)), AppTheme.gutter,
          reason: 'the banner\'s own band must start on the page gutter');

      // ── The three `SectionTitle`s. ──
      // Measured through the *band*, not the heading text: `SectionTitle`
      // carries `fromLTRB(2, …)`, so its text is 2 dp inside its band and a
      // text-based assertion here reads an icon offset and calls it alignment
      // — the mistake `project_new_edges_test.dart` made first.
      for (final heading in const ['التخصصات', 'أفضل المقاولين', 'مشاريعي الأخيرة']) {
        final t = find.text(heading);
        expect(t, findsOneWidget, reason: 'the band «$heading» must be on screen');
        expect(_padContentLeft(tester, bandAbove(tester, t)), AppTheme.gutter,
            reason: 'the heading «$heading» must start on the page gutter');
      }

      // ── The category strip and the contractor strip: two `ListView`s. ──
      expect(find.byType(ListView), findsNWidgets(2),
          reason: 'the categories strip and the contractor strip are the two '
              'horizontal lists on this screen; a third means the screen grew a '
              'band this file has not measured');
      final lists = find.byType(ListView);
      expect(_listRowLeft(tester, lists.at(0)), AppTheme.gutter,
          reason: 'the category strip rows must start on the page gutter');
      expect(_listRowLeft(tester, lists.at(1)), AppTheme.gutter,
          reason: 'the contractor strip cards must start on the page gutter');

      // ── «مشاريعي الأخيرة»: the three most recent project cards. ──
      expect(find.byType(ProjectCard), findsWidgets,
          reason: 'the fixture returns a project; if it does not draw, this '
              'case is measuring the other bands and calling it the column');
      final card = find.byType(ProjectCard).first;
      expect(_padContentLeft(tester, bandAbove(tester, card)), AppTheme.gutter,
          reason: 'the project cards must start on the page gutter');
    });

    testWidgets('the first-run card and the banner share that gutter',
        (tester) async {
      // The two are **mutually exclusive**: `firstRun` swaps the publish
      // banner for the three-step guide, one above the other in the same slot.
      // A single case cannot measure both, and the lesson from the chat column
      // is that a case asserting a set of bands it can only see some of is a
      // case asserting the ones it happens to find.
      await _pumpHome(tester, firstRun: false);
      expect(find.byKey(const Key('client-post-cta')), findsOneWidget);
      expect(find.byKey(const Key('client-start-card')), findsNothing,
          reason: 'returning user: the guide must stand down');

      await _pumpHome(tester, firstRun: true);
      expect(find.byKey(const Key('client-start-card')), findsOneWidget,
          reason: 'first-run user: the guide replaces the banner');
      expect(find.byKey(const Key('client-post-cta')), findsNothing);

      expect(_padContentLeft(
              tester, bandAbove(tester, find.byKey(const Key('client-start-card')))),
          AppTheme.gutter,
          reason: 'the first-run guide must start on the same gutter as the '
              'banner it replaces, or the column steps in for new users only');
    });
  });
}

/// The nearest ancestor `Padding` of [inner] — the node that owns the edge.
Finder bandAbove(WidgetTester tester, Finder inner) =>
    find.ancestor(of: inner, matching: find.byType(Padding)).first;
