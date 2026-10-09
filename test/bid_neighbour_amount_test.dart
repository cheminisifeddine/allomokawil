// A contractor's bid was reported as arrived because a **rival** bid the same
// amount was already on the job.
//
// Found 4 Oct 2026, the third instance of the family this loop keeps auditing:
// the re-read for an unconfirmed write asked a question the server could answer
// *before the write was sent*. `verificationLanded` asks whether the document
// queue grew; `resolveProjectEditOutcome` asks whether the row carries the
// values the form was sending; the bid path asked
//
//     rows.any((q) => q.amount == amt && (mine <= 0 || q.workerId == mine))
//
// which is answerable from the list the screen was already drawing, because the
// amount a contractor is about to type is a number the market sets. Measured on
// production the same day: workers **148** and **149** both hold a bid for
// **70000** on one project, and the list the re-read reads returns both rows.
//
// **The fallback is what made it reachable, and it is the ordinary case.** An
// unconfirmed write *is* a dead network — that is the definition of
// `errWriteUnconfirmed`. So `myProfile()`, issued microseconds later on the same
// connection, is the request most likely of all to fail, `mine` stays `-1`, and
// the predicate widens to the amount alone. The path that exists to answer a
// question the app cannot answer is the one that stops asking it. What the
// contractor is shown is «وجدناه في القائمة — الطلب وصل بنجاح»: his bid never
// left the phone, and he is told it reached the server.
//
// The rule the fix lands is the one every sibling already uses — a **difference**
// between the list the screen held when he tapped and the one the re-read
// returned, with identity required of both. A bid carrying his own worker id that
// the earlier list did not hold is his write. The rival's identical 70000 row is
// in both lists, so it is evidence of nothing.
//
// Both directions are pinned here. Reporting a rival's bid as a landing is the
// expensive half, but a fix that stops at «never claim a landing» would report
// the genuine one as missing too, and that sentence sends him to press send
// again on a job the Worker refuses a second bid on
// (`لقد قدّمت عرضاً لهذا المشروع بالفعل`, measured) — so the real landing must
// still come back `landed`.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/project/project_detail_screen.dart';

const _mine = 16; // this contractor's worker id
const _rival = 77; // the neighbour's, on the same job, at the same figure
const _amount = 70000;

Map<String, Object?> _project() => <String, Object?>{
      'id': 'p-1',
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
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };

Map<String, Object?> _myProfile() => <String, Object?>{
      'id': _mine,
      'user_id': 16,
      'full_name': 'مقاول تجربة',
      'bio': null,
      'specialties': <String>['painting'],
      'experience_years': 4,
      'price_range_min': null,
      'price_range_max': null,
      'service_radius_km': null,
      'is_available': 1,
      'verification_status': 'verified',
      'verification_pending_docs': 0,
      'is_identity_verified': 1,
      'is_certificate_verified': 0,
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
      'response_time_hours': null,
      'cover_image_url': null,
      'avatar_image_url': null,
      'avatar_url': null,
      'user_wilaya': '16',
      'commune': null,
    };

/// One bid row as `GET /api/mobile/projects/p-1/quotes` really returns it.
///
/// [id] and [worker] are the two fields the rule turns on, and they are given
/// explicit values so the rival's row and this contractor's row differ in the
/// only way that matters: identity.
Map<String, Object?> _quote({
  required int id,
  required int worker,
  int amount = _amount,
}) =>
    <String, Object?>{
      'id': id,
      'project_id': 'p-1',
      'worker_id': worker,
      'amount': amount,
      'message': 'يمكنني البدء غداً',
      'estimated_days': 5,
      'worker_full_name': 'مقاول تجربة',
      'worker_avatar_url': null,
      'worker_avg_rating': 0,
      'worker_total_reviews': 0,
      'worker_verification_status': 'verified',
      'status': 'pending',
      'created_at': '2026-09-11 20:30:00',
    };

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// Boots a signed-in **contractor** on someone else's open project, against a
/// Worker that answers the POST with a bid and then loses its reply.
///
/// [rivalBeforeSend] is the decoy: a bid by [_rival] for the *same* amount that
/// is already on the job before this contractor taps. It is in the list both
/// before and after, which is exactly why an amount test cannot tell the two
/// apart.
///
/// [myBidLands] decides whether this contractor's own bid is in the list the
/// re-read reads. It is the second direction: a fix that only ever refuses to
/// claim a landing would pass the false-landing test and misreport a real one.
///
/// [profileReadDies] makes `myProfile()` outrun the timeout, which is what
/// forces the identity fallback — the shape an unconfirmed write makes likely,
/// since both are the same dead connection.
Future<({ApiClient api, AuthState auth})> _boot({
  required bool rivalBeforeSend,
  required bool myBidLands,
  bool profileReadDies = true,
  Duration timeout = const Duration(milliseconds: 40),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  const slow = Duration(milliseconds: 400);
  var bids = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    timeout: timeout,
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 16,
            'phone': '0550000000',
            'email': null,
            'full_name': 'مقاول تجربة',
            'type': 'worker',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-01-01 00:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p == '/api/mobile/my/profile') {
        // The identity read. On the path under test it dies with the network,
        // which is what widens the old predicate to the amount alone.
        if (profileReadDies) await Future<void>.delayed(slow);
        return _json(_myProfile());
      }
      if (p == '/api/mobile/projects/p-1/quotes' && req.method == 'POST') {
        bids++;
        // The row lands. The answer does not. This is the only failure shape
        // that makes the recheck path exist at all.
        await Future<void>.delayed(slow);
        return _json(_quote(id: 501, worker: _mine));
      }
      if (p == '/api/mobile/projects/p-1/quotes') {
        final rows = <Map<String, Object?>>[];
        if (rivalBeforeSend) rows.add(_quote(id: 900, worker: _rival));
        // **Only after the POST.** `bids` counts the writes this Worker took, so
        // the screen's first read — the list it is drawing when the contractor
        // taps — cannot already hold his bid. Returning it on that read too
        // would leave no delta to measure, and the rule (correctly) reports a
        // bid that was in the list *before* the write as evidence of nothing.
        if (myBidLands && bids > 0) rows.add(_quote(id: 501, worker: _mine));
        return _json(rows);
      }
      if (p == '/api/mobile/projects/p-1') return _json(_project());
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0550000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'worker',
      reason: 'the fixture must land on a contractor, or no bid button is drawn');
  return (api: api, auth: auth);
}

Future<void> _pump(WidgetTester tester, ApiClient api, AuthState auth,
    {GlobalKey? rootKey}) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  Widget app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppScope(
        api: api,
        auth: auth,
        child: ProjectDetailScreen(projectId: 'p-1', repo: Repository(api)),
      ),
    );
  // The boundary wraps the **whole** MaterialApp, not its `home:`.
  //
  // A bid sheet is a bottom sheet: it lives in the Navigator's Overlay, which
  // is a sibling of the home route, so a boundary drawn around `home` captures
  // the project page and misses the sheet entirely. Wrapping the app captures
  // the overlay too. Getting this wrong is not a silent no-op — it produced two
  // byte-identical PNGs of the page behind the sheet, which is exactly the
  // failure the shot exists to rule out.
  // Wrapped **once**, on the first pump: a GlobalKey handed to a second
  // `pumpWidget` for the same subtree leaves `currentContext` null, because the
  // first tree is already unmounted by the time anything reads it.
  if (rootKey != null) app = RepaintBoundary(key: rootKey, child: app);
  await tester.pumpWidget(app);
  // Bounded pumps: the loading skeleton animates forever, so `pumpAndSettle`
  // would never return.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Fills the sheet and sends the bid, which is the path that reaches the
/// unconfirmed branch.
Future<void> _sendBid(WidgetTester tester) async {
  await tester.tap(find.text('قدّم عرضك'));
  await tester.pumpAndSettle();
  expect(find.text('إرسال العرض'), findsOneWidget,
      reason: 'the sheet must be on screen for this to measure anything');
  await tester.enterText(find.byType(TextField).at(0), '$_amount');
  await tester.enterText(find.byType(TextField).at(1), '5');
  await tester.tap(find.text('إرسال العرض'));
  await tester.pumpAndSettle();

  // `pumpAndSettle` returns as soon as no frame is scheduled, and a pending
  // timer schedules none — so it returns while the POST is still waiting for an
  // answer that will never come. The recheck only starts once the transport
  // gives up, so this pump has to outlast the timeout (40 ms) *and* the answer
  // that never lands (400 ms) before any verdict can exist. The identity read
  // dies on the same clock and is awaited inside the recheck, so the budget
  // covers it too.
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

/// The sentence the user is actually looking at right now.
///
/// Exactly one [SnackBar] is ever *built*, whether it is the only one or the
/// head of a queue — `ScaffoldMessenger` holds the rest as pending requests and
/// builds them only when their turn arrives. So this returns the line on screen.
String? _visibleLine(WidgetTester tester) {
  final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
  if (bars.isEmpty) return null;
  final c = bars.first.content;
  return c is Text ? (c.data ?? '') : null;
}


/// Boots a contractor on `p-1` with a Worker that **answers** the POST, so the
/// send under test is an ordinary successful one.
///
/// Deliberately unlike [_boot], whose POST never answers: that fixture exists
/// to reach the unconfirmed-write branch, and this file's new case is about
/// what happens *before* any write is attempted.
Future<({ApiClient api, AuthState auth})> _bootResponsive() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  var posts = 0;
  final api = ApiClient(
    baseUrls: const ['https://x.test'],
    timeout: const Duration(seconds: 2),
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
        return _json(<String, Object?>{
          'token': 'tok',
          'user': <String, Object?>{
            'id': 16,
            'phone': '0550000000',
            'email': null,
            'full_name': 'مقاول تجربة',
            'type': 'worker',
            'avatar_url': null,
            'wilaya': '16',
            'commune': null,
            'created_at': '2026-01-01 00:00:00',
          },
        });
      }
      if (p.endsWith('/api/unread')) return _json(0);
      if (p == '/api/mobile/my/profile') return _json(_myProfile());
      if (p == '/api/mobile/projects/p-1/quotes' && req.method == 'POST') {
        posts++;
        return _json(_quote(id: 501, worker: _mine));
      }
      if (p == '/api/mobile/projects/p-1/quotes') {
        return _json(posts > 0 ? <Map<String, Object?>>[_quote(id: 501, worker: _mine)] : <Map<String, Object?>>[]);
      }
      if (p == '/api/mobile/projects/p-1') return _json(_project());
      return _json(<Object>[]);
    }),
  );
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(
      phone: '0550000000', password: 'secret123', rememberMe: true);
  return (api: api, auth: auth);
}

/// Opens the bid sheet and leaves it open.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('قدّم عرضك'));
  await tester.pumpAndSettle();
  expect(find.text('إرسال العرض'), findsOneWidget,
      reason: 'the sheet must be on screen for this to measure anything');
}

/// True when [text] is drawn inside the sheet's own subtree rather than on the
/// screen behind it.
///
/// This is the assertion that makes the test a regression test and not a
/// description: a snackbar on the project page also satisfies
/// `find.text(...)`, and that snackbar is exactly the bug — the message
/// reaches a widget whose controllers have already been disposed.
bool _drawnInsideSheet(WidgetTester tester, String text) {
  final sheet = find.ancestor(
    of: find.text(text),
    matching: find.byType(Column),
  );
  if (sheet.evaluate().isEmpty) return false;
  return find
      .descendant(of: find.byType(BottomSheet), matching: find.text(text))
      .evaluate()
      .isNotEmpty;
}

void main() {
  testWidgets(
      'a rival bid at the same amount is never reported as this bid arriving',
      (tester) async {
    // The decoy is on the job before the tap and is still there after, and the
    // identity read died with the network — so the app cannot tell whose 70000
    // this is, and must not claim it.
    final boot =
        await _boot(rivalBeforeSend: true, myBidLands: false);

    await _pump(tester, boot.api, boot.auth);
    await _sendBid(tester);

    // Proof the screen reached the branch under test at all, asserted BEFORE the
    // verdict so this test cannot pass by measuring nothing.
    expect(
        _visibleLine(tester),
        anyOf(S.writeUnconfirmedRecheck, S.writeUnconfirmedLanded,
            S.writeUnconfirmedUnknown),
        reason: 'the bid must outrun its timeout and enter the recheck path');

    expect(_visibleLine(tester), isNot(S.writeUnconfirmedLanded),
        reason: 'the rival holds the same 70000 in the list both before and '
            'after. Nothing about this contractor\'s write landed, so '
            '«وجدناه في القائمة» is false — it tells him to leave a bid the '
            'server never received.');
    expect(_visibleLine(tester), isNot(S.writeUnconfirmedMissing),
        reason: 'the identity read died, so the app cannot prove his bid is '
            'absent either. Claiming «did not arrive» would send him to press '
            'send again on a job the Worker refuses a second bid on '
            '(«لقد قدّمت عرضاً لهذا المشروع بالفعل»), so the honest answer is '
            'the one that claims nothing.');
  });

  testWidgets('a bid of his own that really landed is still reported as sent',
      (tester) async {
    // The rival is still on the job at the same figure, so the fix cannot be
    // "ignore the amount" — the row that arrives carries his worker id and is
    // not in the list he tapped against.
    //
    // The identity read succeeds here, and it has to: the rule requires the
    // phone to know whose bid it is looking at. The scenario where it cannot
    // is pinned separately below, because it is the *other* half of the same
    // decision and not a variation of this one.
    final boot = await _boot(
        rivalBeforeSend: true, myBidLands: true, profileReadDies: false);

    await _pump(tester, boot.api, boot.auth);
    await _sendBid(tester);

    expect(_visibleLine(tester), S.writeUnconfirmedLanded,
        reason: 'his own bid, absent from the list before the tap and present '
            'in it after, is the write. Refusing this would report a bid that '
            'did arrive as one that did not, and the sentence it prints tells '
            'him to send it a second time.');
  });

  testWidgets(
      'a bid that did land is reported as unknown, not missing, when the '
      'identity read died with it', (tester) async {
    // His bid genuinely reached the server — it is in the list the re-read
    // returns. What is missing is the phone's ability to tell his row from the
    // rival's identical one, because `myProfile()` died on the same dead
    // connection.
    //
    // This is the third outcome, and it is the one a careless fix erases. A
    // predicate that cannot resolve identity has two ways left to answer:
    // report `missing` and send him to press send again on a job the Worker
    // refuses a second bid on, or widen to the amount and report the rival's
    // bid as his. Both are lies, and they are the two failures this whole file
    // exists to close — so the honest third answer has to be reachable, and it
    // is: [WriteOutcome.unknown], which claims nothing about a write the app
    // cannot read back.
    final boot = await _boot(
        rivalBeforeSend: true, myBidLands: true, profileReadDies: true);

    await _pump(tester, boot.api, boot.auth);
    await _sendBid(tester);

    expect(_visibleLine(tester), S.writeUnconfirmedUnknown,
        reason: 'the bid is in the list and the phone cannot prove whose it '
            'is. «الطلب لم يصل» would be a false claim about a write that is on '
            'the server, and it tells him to send a second bid the Worker will '
            'refuse («لقد قدّمت عرضاً لهذا المشروع بالفعل»).');
    expect(_visibleLine(tester), isNot(S.writeUnconfirmedLanded),
        reason: 'the rival holds the same figure, so a widened match would '
            'report a bid that arrived while the identity is unread as proof '
            'it arrived — which is the bug, not the fix.');
  });

  testWidgets(
      'a bid under 1000 DZD is refused with the sheet still open and the '
      'message he wrote still on screen', (tester) async {
    // The defect this file's new case pins: validation ran in
    // `_showBidSheet`, one screen outward, *after* the sheet popped and
    // disposed the three controllers. So «المبلغ يجب أن يكون 1000 دج على
    // الأقل» appeared on the project page while the amount, the duration and
    // the persuasive message were already gone.
    final boot = await _bootResponsive();
    await _pump(tester, boot.api, boot.auth);
    await _openSheet(tester);

    const copy = 'جاهز للبدء غداً،materials شاملة';
    await tester.enterText(find.byType(TextField).at(0), '500');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.enterText(find.byType(TextField).at(2), copy);
    await tester.pumpAndSettle();

    await tester.tap(find.text('إرسال العرض'));
    await tester.pumpAndSettle();

    expect(find.text('إرسال العرض'), findsOneWidget,
        reason: 'the sheet must NOT close on an invalid amount. Closing it is '
            'the bug: it disposes the controllers holding the amount, the '
            'duration and the message the contractor wrote to win the job, and '
            'leaves him three empty fields.');

    expect(find.text(S.bidAmountMin), findsOneWidget,
        reason: 'the rule must be stated, not merely enforced');
    expect(_drawnInsideSheet(tester, S.bidAmountMin), isTrue,
        reason: 'the error belongs under the field that is wrong, inside the '
            'sheet. A snackbar on the project page satisfies find.text and is '
            'the exact regression this test exists to catch.');

    // The text is still there. This is the half that costs him real work if
    // it is wrong: a paragraph of persuasive copy, gone with no way back but
    // retyping from memory.
    expect(find.text(copy), findsOneWidget,
        reason: 'the message must survive a refused send');

    // And nothing was sent: a refused bid that already POSTed would leave a
    // bid the contractor cannot see or withdraw.
    final noPost = find.text('تم إرسال عرضك');
    expect(noPost, findsNothing,
        reason: 'an amount under the minimum must not reach the server');
  });

  testWidgets(
      'the error clears live as he corrects the digit, and the bid then sends',
      (tester) async {
    // The second half of the fix, and the one that separates it from a form
    // that simply refuses everything: a fix which blocks the send and never
    // sends is not a fix. `70000` is one keystroke past the refused `500`.
    final boot = await _bootResponsive();
    await _pump(tester, boot.api, boot.auth);
    await _openSheet(tester);

    await tester.enterText(find.byType(TextField).at(0), '500');
    await tester.pumpAndSettle();
    expect(find.text(S.bidAmountMin), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '70000');
    await tester.pumpAndSettle();

    expect(find.text(S.bidAmountMin), findsNothing,
        reason: 'the error must clear as he types, not wait for a second tap');

    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال العرض'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();

    expect(find.text('تم إرسال عرضك'), findsOneWidget,
        reason: 'a valid bid must still reach the server and say so');
  });

  testWidgets('a zero-day duration is refused while the sheet stays open',
      (tester) async {
    // `0` is what the duration field shows the moment he clears it to type a
    // fresh number, so `min: 1` refusing it is a case ordinary typing reaches
    // — and it must not cost him the message either.
    final boot = await _bootResponsive();
    await _pump(tester, boot.api, boot.auth);
    await _openSheet(tester);

    const copy = 'أعملMaterial två dagar';
    await tester.enterText(find.byType(TextField).at(0), '70000');
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.enterText(find.byType(TextField).at(2), copy);
    await tester.pumpAndSettle();

    await tester.tap(find.text('إرسال العرض'));
    await tester.pumpAndSettle();

    expect(find.text('إرسال العرض'), findsOneWidget,
        reason: 'a bid cannot be finished in zero days, and refusing it must '
            'not close the sheet');
    expect(find.text(S.bidDaysNotNumber), findsOneWidget);
    expect(find.text(copy), findsOneWidget,
        reason: 'the message survives a refused duration too');
  });

  testWidgets('SHOT: bid sheet holding the error, typed copy intact',
      (tester) async {
    // The visual half of this fix, and the reason a layout claim needs it.
    // The defect was not "a red line appeared" — it was that the sheet was
    // GONE and the message with it. A screenshot of the project page after a
    // refused send is a screenshot of an empty form; this one has to show the
    // sheet still up, the error band under the amount, and the prose still in
    // the box.
    final boot = await _bootResponsive();
    final rootKey = GlobalKey();
    await _pump(tester, boot.api, boot.auth, rootKey: rootKey);
    await _openSheet(tester);

    await tester.enterText(find.byType(TextField).at(0), '500');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.enterText(find.byType(TextField).at(2),
        'جاهز للبدء غداً،materials شاملة وكل الأدوات على نحو');
    await tester.pumpAndSettle();
    await tester.tap(find.text('إرسال العرض'));
    await tester.pumpAndSettle();

    expect(find.text('إرسال العرض'), findsOneWidget,
        reason: 'the shot must be of the HELD sheet, not a closed one');

    final boundary =
        rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.75);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('/tmp/shots').createSync(recursive: true);
      File('/tmp/shots/bid_sheet_error_light.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    // And the second state, the one that proves the error is live and not
    // sticky: correct the digit, and the band goes away without a second tap.
    await tester.enterText(find.byType(TextField).at(0), '70000');
    await tester.pumpAndSettle();
    expect(find.text(S.bidAmountMin), findsNothing);

    final b2 = rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await b2.toImage(pixelRatio: 2.75);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/shots/bid_sheet_clear_light.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
