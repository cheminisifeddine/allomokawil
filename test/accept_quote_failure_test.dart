// Accepting a quote: the one write in the product that cannot be undone, and
// the only one that was shipping with no failure handling at all.
//
// Found on 27 Sep 2026, hunting the class the previous ticks had closed
// ("a failed read published as a settled state" — now fully closed, all four
// candidates already gate on `hasError`). The new class is the write side.
//
// `_accept` on the project detail screen:
//
//   Future<void> _accept(Quote q) async {
//     await widget.repo.acceptQuote(widget.projectId, q.id);
//     if (mounted) { showSnackBar('تم قبول العرض…'); _reload(); }
//   }
//
// Three defects in six lines, all on the highest-stakes button in the app:
//
//  1. **No `catch`.** `_complete` and `_cancel`, the two sibling owner actions
//     twenty lines away, both wrap their call and show `errorCopy(e)`. `_accept`
//     does not. A failed accept — 409 because the web app already accepted a
//     different bid, 500, a dropped connection on hotel wifi — escapes as an
//     *unhandled* async error. In release that is a red screen and a crash
//     report; the owner never learns whether the contractor he just hired is
//     hired. The button looks tapped and nothing happens, forever.
//
//  2. **No busy guard.** The quotes are a `ListView`, and the accept button
//     stays enabled for the whole round-trip. Tapping «قبول العرض» twice — which
//     is what everyone does when a phone is slow, and what a lost connection
//     provokes — fires two POSTs. The backend rejects every other quote on the
//     first one, so the second lands on a now-inconsistent project.
//
//  3. **The confirmation lies about timing.** The snackbar says the other
//     quotes *will* be rejected, then `_reload()` re-reads. If that read fails,
//     the list on screen is still the pre-accept one — every other quote still
//     shows its own «قبول العرض» button, which the server will now refuse.
//
// `_complete` and `_cancel` were repaired in earlier ticks. This is the third
// screen in that family, and the last one.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

Map<String, Object?> _user(String type) => {
      'id': type == 'worker' ? 31 : 30,
      'phone': '0773000000',
      'email': null,
      'full_name': type == 'worker' ? 'مقاول تجربة' : 'زبون تجربة',
      'type': type,
      'avatar_url': null,
      'wilaya': '16',
      'commune': null,
      'created_at': '2026-09-11 20:00:00',
    };

/// The owner's own open project — `customer_id` 30 matches the signed-in user,
/// so `_isOwner` is true and the accept button under test is the one he sees.
Map<String, Object?> _project({String status = 'open'}) => <String, Object?>{
      'id': 'p1',
      'customer_id': 30,
      'title': 'دهان شقة 3 غرف',
      'description': 'دهان كامل مع تصليح',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': status,
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

Map<String, Object?> _quote(int id) => <String, Object?>{
      'id': id,
      'project_id': 'p1',
      'worker_id': 16,
      'amount': 70000,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

http.Response _boom([int status = 500]) => http.Response(
    '<html>Internal Server Error</html>', status,
    headers: {'content-type': 'text/html'});

/// Boots a signed-in project owner against a fake API, recording every request
/// so a test can count how many accepts the app actually fired.
///
/// [onAccept] is awaited *before* the response, so a test can hold the POST open
/// with a completer and tap twice while the first is still in flight — the only
/// honest way to prove the double-submit guard.
Future<({ApiClient api, AuthState auth, List<String> log})> _boot({
  required http.Response Function() quotes,
  FutureOr<http.Response> Function()? onAccept,
  String projectStatus = 'open',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final log = <String>[];
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      log.add('${req.method} $p');
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object>{'token': 'tok', 'user': _user('customer')});
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.startsWith('/api/mobile/projects/p1/quotes/') &&
          p.endsWith('/accept')) {
        return onAccept == null ? _json(<String, Object>{'ok': true}) : onAccept();
      }
      if (p.startsWith('/api/mobile/projects/p1/quotes')) return quotes();
      if (p == '/api/mobile/projects/p1') {
        return _json(_project(status: projectStatus));
      }
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land on the owner');
  return (api: api, auth: auth, log: log);
}

Future<void> _pump(
  WidgetTester tester,
  ApiClient api,
  AuthState auth, {
  Size logical = const Size(392, 1900),
  GlobalKey? shotKey,
}) async {
  tester.view.physicalSize = logical * 2.75;
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  final screen = ProjectDetailScreen(projectId: 'p1', repo: Repository(api));
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
      // The boundary lives INSIDE the live tree, so `_capture` photographs the
      // state the test is actually in. Wrapping afterwards would rebuild and
      // reset it.
      home: shotKey == null
          ? screen
          : RepaintBoundary(key: shotKey, child: screen),
    ),
  ));
  await _settle(tester);
}

/// Bounded pumps: the loading skeleton animates forever, so pumpAndSettle
/// would never return.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Scrolls the accept button into view and taps it, once. `tapCount` taps it
/// again without an intervening rebuild so a double-tap is genuinely a
/// double-tap — the gesture a slow phone produces on its own.
Future<void> _tapAccept(
  WidgetTester tester, {
  int tapCount = 1,
  Duration between = Duration.zero,
}) async {
  // A project with two quotes renders two accept buttons; the first is the one
  // under test and `ensureVisible` needs exactly one.
  final finder = find.text('قبول العرض').first;
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < tapCount; i++) {
    if (i > 0) {
      if (between > Duration.zero) await tester.pump(between);
      await tester.tap(finder, warnIfMissed: false);
    } else {
      await tester.tap(finder);
    }
  }
  await _settle(tester);
}

int _acceptPosts(List<String> log) => log
    .where((e) => e.startsWith('POST') && e.endsWith('/accept'))
    .length;

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

/// Captures the boundary the test pumped, to a PNG.
///
/// It takes a [GlobalKey] attached in [_pump] rather than building its own
/// widget, because the state worth photographing — a commit POST held open by
/// a [Completer], the card spinning and its sibling greyed — only exists inside
/// the test's live tree. Two earlier versions got this wrong and both produced
/// two byte-identical PNGs (md5 `c95a1979…`, then `1a83eb74…`) while every
/// assertion in the test still passed: one pumped a fresh screen, the next
/// grabbed the root render view, which is not the repainted subtree. A
/// screenshot helper that cannot fail is worse than no screenshot, so the test
/// now also asserts the two captures differ.
Future<String> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(data);
    return data.length;
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a $name shot this small means nothing rendered');
  return path;
}

void main() {
  setUpAll(() async {
    final reg = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
    await (FontLoader('Cairo')
          ..addFont(Future.value(reg))
          ..addFont(Future.value(bold)))
        .load();
  });

  // ── 1. A failed accept must not vanish ──────────────────────────────────
  //
  // The whole item in one assertion: the owner taps the highest-stakes button
  // in the app, the server says no, and the app must still say something.
  testWidgets('a failed accept tells the owner instead of throwing',
      (tester) async {
    final s = await _boot(
      quotes: () => _json([_quote(1)]),
      onAccept: _boom,
    );
    await _pump(tester, s.api, s.auth);
    await _tapAccept(tester);

    expect(tester.takeException(), isNull,
        reason: 'a failed accept escaped as an unhandled async error — that is '
            'a red screen in release, and the owner never learns whether the '
            'bid he just made is live');
    expect(_acceptPosts(s.log), 1, reason: 'the accept must still be attempted');

    // The curated sentence for this status, not a raw exception: `errorCopy`
    // is the one place a failure becomes Arabic a user can act on, and the
    // two sibling actions already route through it.
    expect(find.text(S.errServer), findsOneWidget,
        reason: 'the 500 must be reported in the app\'s own words: '
            '${_texts(tester)}');

    // And the success claim must NOT be on screen. The old code showed it
    // unconditionally from the `await` returning.
    expect(find.textContaining('تم قبول العرض'), findsNothing,
        reason: 'the app must not tell the owner the bid is accepted when the '
            'server refused it: ${_texts(tester)}');
  });

  // ── 2. The button must not accept a second bid while the first is in
  //       flight ──────────────────────────────────────────────────────────
  //
  // This is the half a `catch` cannot fix. Even with the failure handled, the
  // quotes are a `ListView` whose «قبول العرض» button stays enabled for the
  // whole round-trip, so a second tap on a slow connection fires a second
  // POST. The backend rejects every other quote on the first accept, so the
  // second POST lands on a project that is already committed.
  testWidgets('a second tap cannot accept a second bid', (tester) async {
    final gate = Completer<void>();
    final s = await _boot(
      quotes: () => _json([_quote(1)]),
      // Hold the first POST open so the window is real, not simulated.
      onAccept: () async {
        await gate.future;
        return _json(<String, Object>{'ok': true});
      },
    );
    await _pump(tester, s.api, s.auth);

    // Tap twice, then let the held request finish.
    //
    // The tap is by *screen position*, not by widget: the fix replaces the
    // button's label with a spinner while the POST is in flight, so the finder
    // that located it a moment ago no longer matches anything. That is the
    // fix working — and it is also exactly why a real double-tap has to be
    // aimed at the pixels the user pressed, not at a widget that moved.
    final target = tester.getCenter(find.text('قبول العرض').first);
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('قبول العرض'), findsNothing,
        reason: 'the in-flight card must show a spinner, not a live button');
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 50));

    gate.complete();
    await _settle(tester);

    expect(_acceptPosts(s.log), 1,
        reason: 'two taps must not fire two accepts — the second would hit a '
            'project the backend has already committed to a contractor');
  });

  // ── 2b. The *other* bids must go dead too ──────────────────────────────
  //
  // Guarding the tapped card is not enough. The backend rejects every other
  // quote the moment one is accepted, so while a commit is in flight the
  // sibling «قبول العرض» buttons are already dead on the server — and on a
  // project with five bids there are four of them, all still live, all
  // tappable, all guaranteed to be refused. The owner is left choosing between
  // failures. The first test in this file only ever taps quote 1, so it cannot
  // see this: it needs a second card.
  testWidgets('a bid in flight disables the other bids as well', (tester) async {
    final gate = Completer<void>();
    final s = await _boot(
      quotes: () => _json([_quote(1), _quote(2)]),
      onAccept: () async {
        await gate.future;
        return _json(<String, Object>{'ok': true});
      },
    );
    await _pump(tester, s.api, s.auth);

    // Two quote cards, so two accept buttons.
    expect(find.text('قبول العرض'), findsNWidgets(2),
        reason: 'the fixture must render two bids for this to mean anything');

    // Commit the first.
    final first = find.text('قبول العرض').first;
    await tester.ensureVisible(first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(first);
    await tester.pump(const Duration(milliseconds: 50));

    // Now hit the second one, aimed at its pixels.
    final second = find.text('قبول العرض').last;
    await tester.ensureVisible(second);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tester.getCenter(second));
    await tester.pump(const Duration(milliseconds: 50));

    gate.complete();
    await _settle(tester);

    expect(_acceptPosts(s.log), 1,
        reason: 'the second bid must be refused by the app, not sent to a '
            'server that has already committed the project to somebody else');
  });

  // ── 3. ...and the guard must clear once the call is over ────────────────
  //
  // A guard that never releases is not a fix, it is a second dead button: the
  // owner would have to leave the screen to try again. This is the exact
  // regression a "just add a bool" patch ships.
  testWidgets('the accept button comes back after a failure', (tester) async {
    final s = await _boot(
      quotes: () => _json([_quote(1)]),
      onAccept: _boom,
    );
    await _pump(tester, s.api, s.auth);

    await _tapAccept(tester);
    expect(_acceptPosts(s.log), 1);

    // Second attempt, with the server now accepting. If the guard leaked, this
    // POST never happens and the owner is stuck on a dead screen forever.
    final btn = find.widgetWithText(ElevatedButton, 'قبول العرض');
    await tester.ensureVisible(btn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(btn);
    await _settle(tester);

    expect(_acceptPosts(s.log), 2,
        reason: 'the busy guard must clear in a `finally`, or the owner can '
            'never retry the one action on this screen that commits a '
            'contract');
  });

  // ── 4. A successful accept must not regress ─────────────────────────────
  //
  // The fix must not turn a real accept into an error, nor report failure for
  // a call that landed. The happy path is the product working.
  testWidgets('a successful accept still confirms and reloads', (tester) async {
    final s = await _boot(quotes: () => _json([_quote(1)]));
    await _pump(tester, s.api, s.auth);
    final before = s.log.length;

    await _tapAccept(tester);

    expect(tester.takeException(), isNull);
    expect(_acceptPosts(s.log), 1);
    expect(find.textContaining('تم قبول العرض'), findsOneWidget,
        reason: 'the owner must be told the bid was accepted: ${_texts(tester)}');
    // And the screen must re-read: accepting rejects every other quote, so a
    // stale list is a list of buttons the server will refuse.
    expect(s.log.length, greaterThan(before),
        reason: 'the accept must be followed by a real re-read');
    expect(
      s.log.sublist(before).any((e) => e.startsWith('GET') && e.contains('/p1')),
      isTrue,
      reason: 'expected a re-read of the project after accepting: '
          '${s.log.sublist(before)}',
    );
  });

  // ── 5. The success snackbar must not outlive a failed re-read ───────────
  //
  // The old order was: show «تم قبول العرض، سيتم رفض باقي العروض», then
  // `_reload()`. If that reload fails, the list below still shows every other
  // quote with a live «قبول العرض» button that the server now refuses — the
  // app telling the owner to do the one thing it has just made impossible.
  // The screen already knows how to draw a failed read (that is the
  // `hasError` branch repaired one tick ago), so the reload must be allowed to
  // fail *visibly* rather than silently.
  testWidgets('a failed re-read after a successful accept is not hidden',
      (tester) async {
    var accepts = 0;
    final s = await _boot(
      quotes: () => _json([_quote(1), _quote(2)]),
      projectStatus: 'open',
    );
    // The accept lands; the project re-read then fails. The quotes read still
    // succeeds, so the two sections disagree — which is exactly the state the
    // old code rendered as a normal list.
    final api2 = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        s.log.add('${req.method} $p');
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object>{'token': 'tok', 'user': _user('customer')});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.startsWith('/api/mobile/projects/p1/quotes/') &&
            p.endsWith('/accept')) {
          accepts++;
          return _json(<String, Object>{'ok': true});
        }
        if (p.startsWith('/api/mobile/projects/p1/quotes')) {
          return _json([_quote(1), _quote(2)]);
        }
        if (p == '/api/mobile/projects/p1') {
          if (accepts > 0) return _boom();
          return _json(_project());
        }
        return _json(<Object>[]);
      }),
    );
    final auth = AuthState(api2);
    await auth.restore();
    await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);

    await _pump(tester, api2, auth);
    final acceptBtn = find.text('قبول العرض').first;
    await tester.ensureVisible(acceptBtn);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(acceptBtn);
    await _settle(tester);

    expect(accepts, 1);
    // The project read failed, so the screen must be showing the failed-read
    // state — not a list of quotes that says someone can still be accepted.
    expect(find.text('تعذّر تحميل المشروع'), findsOneWidget,
        reason: 'after a successful accept the project re-read failed; the '
            'screen must show that failure, because the quotes it is still '
            'displaying are no longer accurate: ${_texts(tester)}');
  });

  // ── 6. Guests still get no accept button ────────────────────────────────
  //
  // Guard the guard on the other side: `_isOwner` is a deliberate gate, and the
  // busy plumbing must not weaken it. A visitor has no project to commit.
  testWidgets('a signed-out visitor is offered no accept button', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = ApiClient(
      baseUrls: const ['https://x.test'],
      httpClient: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
          return _json(<String, Object>{'token': 'tok', 'user': _user('customer')});
        }
        if (p.endsWith('/api/unread')) return _json(0);
        if (p.startsWith('/api/mobile/projects/p1/quotes')) {
          return _json([_quote(1)]);
        }
        if (p == '/api/mobile/projects/p1') return _json(_project());
        return _json(<Object>[]);
      }),
    );
    final auth = AuthState(api);
    await auth.restore(); // never logs in

    await _pump(tester, api, auth);
    final texts = _texts(tester);
    expect(texts, isNotEmpty, reason: 'nothing rendered: $texts');
    expect(find.text('قبول العرض'), findsNothing,
        reason: 'a visitor must never see the button that commits a contract; '
            '$texts');
  });

  // ── 7. The in-flight state, rendered ────────────────────────────────────
  //
  // Six widget assertions cannot tell a disabled button from a legible one.
  // This photographs the two states the owner actually sees mid-commit, and —
  // because both earlier helpers silently returned the same picture twice —
  // asserts the two files are genuinely different bytes.
  testWidgets('the accept-in-flight state renders', (tester) async {
    final gate = Completer<void>();
    final s = await _boot(
      quotes: () => _json([_quote(1), _quote(2)]),
      onAccept: () async {
        await gate.future;
        return _json(<String, Object>{'ok': true});
      },
    );
    final shotKey = GlobalKey();
    await _pump(tester, s.api, s.auth, shotKey: shotKey);

    final first = find.text('قبول العرض').first;
    await tester.ensureVisible(first);
    await tester.pump(const Duration(milliseconds: 100));
    final idle = await _capture(tester, shotKey, 'accept_idle');

    await tester.tap(first);
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-flight: the tapped card spins, its sibling is dead.
    expect(find.text('قبول العرض'), findsOneWidget,
        reason: 'the committing card must be spinning, not showing a live '
            'label — this is the state the shot exists to show');
    final mid = await _capture(tester, shotKey, 'accept_in_flight');

    gate.complete();
    await _settle(tester);

    expect(find.text('قبول العرض'), findsNWidgets(2),
        reason: 'after the commit resolves the buttons must be live again');
    expect(File(idle).readAsBytesSync().length,
        isNot(File(mid).readAsBytesSync().length),
        reason: 'the idle and in-flight renders must differ; identical bytes '
            'means the capture is not reading the state under test');
  });
}
