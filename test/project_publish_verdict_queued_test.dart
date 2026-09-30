// The verdict on a **published** project was queued behind the recheck line it
// was replacing.
//
// Sixth and last member of a class the loop has now measured on every screen
// that can draw a second line over a first one. `ScaffoldMessenger` **queues**:
// a second `showSnackBar` while one is visible does not replace it, it waits
// for the first to time out — four seconds by default.
//
// This file is the interesting one, because **its own screen was already half
// fixed**. `project_new_screen.dart` learned the `hideCurrentSnackBar` rule on
// the *edit* half of `_submit` — the comment at the `editOutcomeCopy` call says
// so, and it is correct there. The *create* half sits twelve lines below it and
// calls `_toast(writeOutcomeCopy(outcome))`, which is a bare `showSnackBar`.
//
// So one screen, one `catch`, two answers, and only one of them is reachable in
// time. A customer who publishes a project, loses the answer on a slow network,
// and then finds it in «مشاريعي» is told «نتحقّق الآن من القائمة…» — a note about
// a check that has already finished — and then waits out that note's full four
// seconds before the one sentence that says his project is on the server
// arrives. The identical stall on the *edit* half of the same form, one screen
// away in the same file, is answered immediately.
//
// The cost is the one the whole class costs, and here it is the worst the user
// can be: publishing is the single most consequential write a customer makes.
// Everything after it — being called, being sent quotes — depends on the row
// existing. Telling him the state is unknown for four seconds after the app
// knows is not a cosmetic delay on that row; it is four seconds in which the
// obvious next move is to press publish again, and `ApiClient.post` is declared
// `idempotent: false` precisely because a second press would create a *second*
// project. The duplicate-project complaint is the thing the four seconds
// invites.
//
// The rule pinned here: **a line that is about to be replaced must be removed
// first**, so the verdict is on screen the moment the app knows it — on the
// create half exactly as on the edit half, because they are the same sentence
// answering the same question on the same screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:allomokawil/src/screens/project/project_new_screen.dart';
import 'package:allomokawil/src/widgets/ui.dart';

const _pickerChannel = MethodChannel('plugins.flutter.io/image_picker');

/// The title the form is filled with, and the one the recheck asks about.
///
/// The recheck is `myProjects().any((p) => p.title.trim() == sentTitle)`, and
/// [sentTitle] is the value captured before the first `await` — so the fixture
/// puts the row in the list under **this** string and the verdict can only read
/// as «arrived» when the create really did land.
const sentTitle = 'ترميم فيلا';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: <String, String>{'content-type': 'application/json'});

/// One row of `GET /api/mobile/my/projects`.
Object _projectRow(String title) => <String, Object?>{
      'id': 'p-1',
      'customer_id': 30,
      'title': title,
      'description': null,
      'category': 'painting',
      'categories': <String>['painting'],
      'images': <String>[],
      'wilaya': '16',
      'commune': null,
      'budget_min': null,
      'budget_max': null,
      'urgency': 'flexible',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-30 08:00:00',
      'updated_at': '2026-09-30 08:00:00',
    };

/// The upload is stubbed for the reason every file here stubs it:
/// `Repository.uploadDocument` builds a `MultipartRequest`, which constructs its
/// own `HttpClient` instead of the one handed to [ApiClient], so a `MockClient`
/// never sees it and a real loopback socket deadlocks inside the fake-async
/// zone.
///
/// Everything else is the **real** transport, and it is the real transport that
/// produces the `errWriteUnconfirmed` under test: `ApiClient.post` is declared
/// `idempotent: false`, so a POST whose answer never comes back inside the
/// client's own timeout throws exactly the ambiguous error this screen exists
/// to answer. A stubbed 500 would decodes to `errServer` and skip the re-read
/// entirely.
class _RepoWithFakeUpload extends Repository {
  _RepoWithFakeUpload(super.api);

  @override
  Future<String> uploadDocument(File file) async =>
      'https://r2.test/projects/${file.path.hashCode}.jpg';
}

/// Boots the real publish form on a Worker that **stores the project and then
/// never answers the POST**.
///
/// [after] chooses what the re-read returns, and it is the whole difference
/// between «arrived» and «send it again» — so the cases below drive the same
/// stall into both classifications rather than asserting one of them.
Future<({ApiClient api, AuthState auth})> _boot(
  WidgetTester tester, {
  required bool rowArrived,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  var posts = 0;
  var lists = 0;

  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (req.method == 'POST' && p.endsWith('/api/mobile/projects')) {
        posts++;
        // Outlasts the client's patience (500 ms, below), so the write is
        // *ambiguous* rather than refused — which is the only shape that
        // reaches the recheck under test.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return _json(_projectRow(sentTitle));
      }
      if (p.contains('/api/mobile/my/projects')) {
        lists++;
        // A real phone's re-read is a network round trip. Answering it
        // synchronously resolves the exchange faster than the recheck line's
        // entrance animation, so the bar is built and removed without ever
        // being painted and the sampler never sees it. Two earlier files paid
        // this as a fixture bug and filed it as "the verdict never appears".
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _json(rowArrived ? <Object>[_projectRow(sentTitle)] : <Object>[]);
      }
      if (p.endsWith('/api/login')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 30,
            'phone': '0773000000',
            'email': null,
            'full_name': 'زبون تجربة',
            'type': 'customer',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-09-30 08:00:00',
          },
        });
      }
      if (p.endsWith('/unread')) return _json(<String, Object?>{'unread': 0});
      return _json(<Object>[]);
    }),
    // 500 ms, and load-bearing twice. The publishing POST stalls 700 ms so it
    // outruns this and the branch under test is reached at all; and the re-read
    // below takes 300 ms of real round trip, which it must **survive** or the
    // verdict classifies as `unknown` and the test measures a different
    // sentence. A sibling file copied 25 ms here and then reported the
    // `unknown` copy for a re-read that had succeeded — on this class of screen
    // the timeout *is* the verdict the user is shown.
    timeout: const Duration(milliseconds: 500),
  );

  final auth = AuthState(api);
  await auth.login(phone: '0773000000', password: 'secret123');
  // Proof the recheck actually ran, so a case cannot pass by measuring nothing.
  expect(posts, 0, reason: 'nothing is published before the tap');
  expect(lists, 0, reason: 'nothing is re-read before the tap');

  return (api: api, auth: auth);
}

/// The sentence the user is actually looking at right now.
///
/// Exactly one [SnackBar] is ever *built*, whether it is the only one or the
/// head of a queue — `ScaffoldMessenger` holds the rest as pending requests and
/// builds them only when their turn arrives. So this returns the line on screen
/// and the timing below is what says whether another one is waiting behind it.
/// Counting SnackBars in the tree cannot see a queue at all.
String? _visibleLine(WidgetTester tester) {
  final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
  if (bars.isEmpty) return null;
  final c = bars.first.content;
  return c is Text ? (c.data ?? '') : null;
}

/// Fake-clock milliseconds from now until [line] is the one on screen.
///
/// Pumped in 10 ms steps and **never** `pumpAndSettle`: settling advances until
/// nothing is scheduled, which drains the still-animating recheck bar before
/// the next sample — so on the fixed screen the very line the case exists to
/// prove becomes invisible to the sampler and the case fails with the app
/// behaving *better*.
Future<int> _millisUntilVisible(
  WidgetTester tester,
  String line, {
  Duration step = const Duration(milliseconds: 10),
  int capMs = 8000,
}) async {
  var elapsed = 0;
  while (elapsed <= capMs) {
    if (_visibleLine(tester) == line) return elapsed;
    await tester.pump(step);
    elapsed += step.inMilliseconds;
  }
  return _visibleLine(tester) == line ? elapsed : -1;
}

/// Fills the three required fields, attaches one photo so `_submit` has an
/// `await` to park in, and taps publish.
///
/// Returns once the **recheck line** is on screen — the branch under test, and
/// no further, because the timing the cases care about is the wait *after* it.
/// Draining the whole queue here would measure nothing.
Future<void> _publishAndWaitForRecheck(
  WidgetTester tester,
  ({ApiClient api, AuthState auth}) boot,
) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pickerChannel, (call) async {
    if (call.method == 'pickMultiImage') return <String>[_pickFile()];
    return null;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pickerChannel, null));

  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
    api: boot.api,
    auth: boot.auth,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      home: ProjectNewScreen(repo: _RepoWithFakeUpload(boot.api)),
    ),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  await tester.enterText(find.byType(TextField).first, sentTitle);
  await tester.tap(find.byType(SelectableTile).first);
  await tester.pump();

  final wilayaField = find.text('اختر الولاية');
  if (wilayaField.evaluate().isNotEmpty) {
    await _reveal(tester, wilayaField);
    await tester.tap(wilayaField);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(TextField)),
      '16',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('الجزائر').first);
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The photo, so `_submit` must upload before it can send.
  await _reveal(tester, find.text('أضف صورة'));
  await tester.tap(find
      .ancestor(of: find.text('أضف صورة'), matching: find.byType(InkWell))
      .first);
  await tester.pumpAndSettle(const Duration(seconds: 2));

  await tester.tap(find.text('نشر المشروع'));

  // A tap is not a run. `_submit` is async — the upload, then a POST that has
  // to outlast the client's own 500 ms patience before the transport gives up —
  // and a pending timer schedules no frame, so nothing above this line advances
  // the clock. Sampling here returns an empty tree and every assertion below
  // measures a screen that never ran. Three files in this class have now paid
  // that exact tax and each filed it as "the verdict never appears".
  for (var i = 0; i < 400; i++) {
    final line = _visibleLine(tester);
    if (line == S.writeUnconfirmedRecheck ||
        line == S.writeUnconfirmedLanded ||
        line == S.writeUnconfirmedMissing) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 260,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

String _pickFile() {
  final dir = Directory.systemTemp.createTempSync('am_publish_queue');
  final f = File('${dir.path}/p0.png');
  f.writeAsBytesSync(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x0A,
    0x49, 0x44, 0x41, 0x54, 0x78, 0x63, 0x60, 0x00, 0x00, 0x00, 0x02, 0x00,
    0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00,
  ]);
  return f.path;
}

/// Closes the bar the way a user closes it, then drains the overlay.
///
/// Without this the teardown assertion `!timersPending` fires with every
/// assertion above it already green: the fix makes the verdict arrive while the
/// *old* bar's timer is still counted, so the tree can be disposed with the new
/// bar's four-second timer live. The sentence is correct — the bar is simply
/// still up — and it reads like an app bug. `pumpAndSettle` alone drains the
/// very bar under assertion.
Future<void> _closeBar(WidgetTester tester) async {
  final messenger =
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
  messenger.hideCurrentSnackBar();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(SnackBar).evaluate().isEmpty) break;
  }
}

void main() {
  testWidgets(
      'the verdict on a published project is drawn without waiting out the '
      'line it replaces', (tester) async {
    final boot = await _boot(tester, rowArrived: true);
    await _publishAndWaitForRecheck(tester, boot);

    // Proof the screen reached the branch under test at all. Asserted *before*
    // the timing, so the case cannot pass by measuring nothing: the POST outran
    // its timeout, so either the recheck line is up or — once the fix is in — it
    // has already been replaced by the verdict.
    expect(
        _visibleLine(tester),
        anyOf(S.writeUnconfirmedRecheck, S.writeUnconfirmedLanded),
        reason: 'the publish must outrun its timeout and enter the recheck '
            'path, or the timing below measures a screen that never got there');

    final took = await _millisUntilVisible(tester, S.writeUnconfirmedLanded);

    expect(took, isNot(-1),
        reason: 'the Worker stored the project, so the app must say so');
    expect(
        took,
        lessThan(2000),
        reason: 'the verdict waited $took ms to reach the screen. Publishing '
            'is the most consequential write a customer makes — every call and '
            'every quote depends on the row existing — and it must not sit '
            'behind a progress note about a check that had already finished for '
            'that note\'s full default four seconds. Four seconds of "we do not '
            'know" is four seconds in which pressing publish again is the '
            'obvious next move, and that POST is not idempotent.');

    await _closeBar(tester);
  });

  testWidgets('the recheck line is removed, so one verdict is ever on screen',
      (tester) async {
    final boot = await _boot(tester, rowArrived: true);
    await _publishAndWaitForRecheck(tester, boot);

    final took = await _millisUntilVisible(tester, S.writeUnconfirmedLanded);
    expect(took, isNot(-1), reason: 'the verdict must exist to judge this');

    // One failure, one line: once the verdict arrives the progress note about a
    // check that has already finished must not be on screen, and nothing may be
    // queued behind the answer either.
    expect(_visibleLine(tester), S.writeUnconfirmedLanded,
        reason: 'the answer replaces the recheck line; it does not join it');
    expect(_visibleLine(tester), isNot(S.writeUnconfirmedRecheck));

    await _closeBar(tester);
  });

  testWidgets('the not-arrived verdict is answered the same single line',
      (tester) async {
    // The list came back without the row, so the honest sentence is the
    // retryable one — «the request did not arrive, send it again». It is still
    // the verdict, and it must replace the recheck line exactly as the landing
    // does. Otherwise the customer is told to resend a project the app has
    // already finished checking, and waits four seconds for the instruction
    // that tells him to.
    final boot = await _boot(tester, rowArrived: false);
    await _publishAndWaitForRecheck(tester, boot);

    final took = await _millisUntilVisible(tester, S.writeUnconfirmedMissing);
    expect(took, isNot(-1),
        reason: 'an empty list must classify as missing, never landed');
    expect(took, lessThan(2000),
        reason: 'the retry instruction waited $took ms behind a recheck line '
            'about a check that had already finished');
    expect(_visibleLine(tester), S.writeUnconfirmedMissing);

    await _closeBar(tester);
  });
}
