// One project lifecycle state, one Arabic name — on every surface that prints
// one, and only ever reachable through the value the server actually stores.
//
// Found on 2 Oct 2026 by reading the two surfaces that print one. The filter
// tab table in `projects_screen.dart` named the four states privately, and the
// `StatusPill.project` factory in `ui.dart` named them again in a private
// `switch`. That is the same shape as the urgency defect shipped the day
// before, and it hid something larger: the pill's switch keyed on
//
//     case 'inprogress':    // the Dart enum name
//
// while **both** of its callers passed `project.status.wire`, which is
// `'in_progress'`. No caller anywhere in the repo ever passed the string that
// arm matched, so it was dead code — no project in this app has ever been
// drawn as «قيد التنفيذ». Every job a contractor was working drew «مفتوح»:
// the claim that other contractors may still bid on it.
//
// So this file pins two things, and the second is the one that would have
// caught it:
//
//   1. the shared words themselves, and
//   2. **every widget that draws a state, driven through the wire string the
//      server sends** — so a factory that is handed `in_progress` and answers
//      «مفتوح» fails here, even though nothing in this file is wrong.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/project_status_copy.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';
import 'package:allomokawil/src/screens/project/projects_screen.dart';
import 'package:allomokawil/src/widgets/project_card.dart';
import 'package:allomokawil/src/widgets/ui.dart';

Project _project(ProjectStatus status, {String id = 'p1'}) => Project(
      id: id,
      customerId: 30,
      title: 'دهان شقة 3 غرف',
      description: 'دهان كامل مع تصليح',
      category: 'painting',
      images: const [],
      wilaya: '16',
      commune: 'حسين داي',
      budgetMin: 60000,
      budgetMax: 90000,
      urgency: UrgencyLevel.withinWeek,
      // Built through `fromJson` on purpose: the server's string goes through
      // the one parser and comes out as the enum the widgets are handed, so
      // this test cannot pass by asserting against a value no read path
      // produces.
      status: Project.fromJson({
        'id': id,
        'customer_id': 30,
        'title': 'دهان شقة 3 غرف',
        'category': 'painting',
        'images': <String>[],
        'wilaya': '16',
        'urgency': 'within_week',
        'status': status.wire,
        'created_at': '2026-10-02 10:00:00',
      }).status,
    );

void main() {
  group('the shared copy', () {
    test('every state has an Arabic name, and none of them is empty', () {
      for (final status in ProjectStatus.values) {
        final name = projectStatusAr(status);
        expect(name, isNotEmpty,
            reason: '${status.name} would print a blank pill');
        expect(name.trim(), name,
            reason: '${status.name} would print padding a reader can see');
      }
    });

    test('the names are distinct, so one state cannot masquerade as another', () {
      final names = ProjectStatus.values.map(projectStatusAr).toList();
      expect(names.toSet().length, names.length,
          reason: 'two states share a name: $names');
    });

    test('a finished job is «منجز», not the word this app uses for a lapsed plan',
        () {
      // «منتهي» is what `subscription_screen.dart` and `_planSummary` print for
      // an EXPIRED PLAN. The pill used it for a completed renovation, so one
      // word meant two different things on screens the reader learned it from.
      expect(projectStatusAr(ProjectStatus.completed), 'منجز');
      expect(projectStatusAr(ProjectStatus.completed), isNot('منتهي'));
    });

    test('the wire value still round-trips through the name', () {
      // The display layer must not become a second, forgiving parser — the
      // exact trap this factory fell into. A state is reached by its stored
      // string and the name is looked up from that.
      for (final status in ProjectStatus.values) {
        expect(ProjectStatus.fromWire(status.wire), status);
        expect(projectStatusAr(ProjectStatus.fromWire(status.wire)),
            projectStatusAr(status));
      }
    });
  });

  group('the pill every project card draws', () {
    testWidgets('a job in progress is drawn «قيد التنفيذ», not «مفتوح»',
        (tester) async {
      // The whole defect in one assertion, driven the way the app reaches it:
      // the server's own `in_progress` string, through the parser, into the
      // card. The old factory keyed on `'inprogress'` and answered «مفتوح».
      await tester.pumpWidget(_wrap(ProjectCard(project: _project(
        ProjectStatus.inProgress,
      ))));

      expect(find.text('قيد التنفيذ'), findsOneWidget);
      expect(find.text('مفتوح'), findsNothing,
          reason: 'a running job was drawn as one still taking offers');
    });

    testWidgets('all four states reach the card with their shared names',
        (tester) async {
      for (final status in ProjectStatus.values) {
        await tester.pumpWidget(_wrap(ProjectCard(project: _project(status))));
        expect(find.text(projectStatusAr(status)), findsOneWidget,
            reason: '${status.name} drew the wrong word on the card');
      }
    });

    testWidgets('the pill and the card agree, because they are the same pill',
        (tester) async {
      // The signature is the second half of the fix: the factory takes a
      // `ProjectStatus`, so a caller cannot hand it a string the parser never
      // produced. Asserted here so re-widening it back to a `String` — the
      // shape that hid the bug — is a compile error in this file.
      for (final status in ProjectStatus.values) {
        expect(StatusPill.project(status).label, projectStatusAr(status),
            reason: '${status.name} was named twice');
      }
    });
  });

  group('the tint, which the fix also changed', () {
    test('a running job is no longer painted as a project taking offers', () {
      // The colour is half of what a pill says, and the old factory gave
      // «قيد التنفيذ» the accent tint of an *open* project — the same amber the
      // feed uses for a job you can still bid on. Asserted here because a
      // screenshot would show the hue and not the reason it was wrong, and
      // because nothing else in the suite looks at a pill's wash.
      final running = StatusPill.project(ProjectStatus.inProgress);
      final open = StatusPill.project(ProjectStatus.open);

      expect(running.color, isNot(open.color));
      expect(running.wash, isNot(open.wash));
      expect(running.icon, isNot(open.icon));
    });

    test('the four states stay distinguishable by colour alone', () {
      // Four pills, four tints: a client scanning «مشاريعي» picks the right tab
      // by colour before he reads it, so two states sharing a wash is a defect
      // the Arabic words cannot repair.
      final washes = ProjectStatus.values
          .map((s) => StatusPill.project(s).wash)
          .toSet();
      expect(washes.length, ProjectStatus.values.length,
          reason: 'two states are painted the same: $washes');
    });
  });

  group('the «مشاريعي» filter tabs name the states the same way', () {
    testWidgets('each tab prints the shared name of the state it filters to',
        (tester) async {
      // The second surface, and the one the defect was invisible in: the tab
      // already said «قيد التنفيذ» while the pill under it said «مفتوح», on
      // the same screen, for the same project. Read back off the real widget
      // tree, so re-introducing a private copy in the tab table fails here.
      final auth = await _bootAuth();
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrapScreen(
        AppScope(
          api: auth.api,
          auth: auth.auth,
          child: ProjectsScreen(repo: Repository(auth.api)),
        ),
      ));
      await _settle(tester);

      // The strip is a horizontal `ListView`, so the last tabs are not built at
      // all until it is scrolled — an off-screen pill is not a wrong pill, and
      // counting without scrolling is how this assertion passes by accident on
      // the three tabs that happen to fit.
      for (final status in ProjectStatus.values) {
        final word = projectStatusAr(status);
        await _scrollTabsUntil(tester, word);
        expect(find.text(word), findsOneWidget,
            reason: 'the ${status.name} tab does not use the shared name');
      }
      // «الكل» is the no-filter tab and has no state, so it stays its own word.
      // Checked after scrolling back: the strip above was left at the far end,
      // and a tab scrolled out of the viewport is unbuilt, not absent.
      await _scrollTabsUntil(tester, 'الكل');
      expect(find.text('الكل'), findsOneWidget);
    });
  });
}

/// Scrolls the horizontal filter strip until [word] is on screen, then stops.
///
/// Bounded on purpose: if the word never appears the loop ends and the
/// expectation that follows reports it as missing, rather than this hanging on
/// a strip that will not move.
Future<void> _scrollTabsUntil(WidgetTester tester, String word) async {
  final strip = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      description: 'the filter strip');
  // Both directions on every attempt, because the strip is already scrolled to
  // wherever the previous lookup left it — a one-way helper only ever finds the
  // tabs to the right of where it starts, which is how «الكل» went missing.
  const steps = [Offset(-260, 0), Offset(260, 0)];
  for (var i = 0; i < 8; i++) {
    if (find.text(word).evaluate().isNotEmpty) return;
    if (strip.evaluate().isEmpty) return;
    await tester.drag(strip, steps[i % steps.length]);
    await tester.pump(const Duration(milliseconds: 220));
  }
}

/// Bounded pumps: the loading skeletons animate forever, so `pumpAndSettle`
/// would never return — the same trap `feed_search_test.dart` documents.
Future<void> _settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// A signed-in customer with an empty project list, so only the tab row and no
/// card is on screen and each name can be counted once.
Future<({ApiClient api, AuthState auth})> _bootAuth() async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return http.Response(
          jsonEncode({
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
              'created_at': '2026-10-02 09:00:00',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (p.contains('/my/profile')) {
        return http.Response(jsonEncode(<String, Object?>{}), 200,
            headers: {'content-type': 'application/json'});
      }
      // Zero rows on purpose: a card on screen would draw a status pill of its
      // own and `findsOneWidget` could not tell the tab's word from the card's.
      return http.Response(jsonEncode(<Object?>[]), 200,
          headers: {'content-type': 'application/json'});
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

/// A phone-sized app for a *widget* (the card). The scroll view is here
/// because a bare card in a Scaffold is fine but a tall one overflows.
///
/// A whole screen must NOT go through this: wrapping [ProjectsScreen] in a
/// scroll view gives it an unbounded height and its own `ListView` throws
/// «infinite size during layout» — a harness failure, not a product one, and
/// one this file already paid for once.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('ar'),
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// A phone-sized app for a whole screen, which lays itself out.
Widget _wrapScreen(Widget screen) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ar'),
    debugShowCheckedModeBanner: false,
    home: screen,
  );
}
