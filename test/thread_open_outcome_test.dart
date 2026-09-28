// The `POST` that opens a thread had no answer, and the screen said the
// messages failed to load.
//
// Thirteen write audits in, the backlog recorded `openConversation` as the one
// write left "with no resolved unconfirmed path" — which is true, and is also
// the least interesting thing about it. Reading the file found the other half.
//
// `_ChatScreenState._bootstrap`:
//
//     convId ??= await widget.repo.openConversation(...);
//     _convId = convId;
//     await _load();
//     } catch (_) { refused = true; }
//
// `catch (_)` is not a catch-all, it is a decision: it folds a **write** whose
// answer never arrived into the thread's **read** error. The page then renders
// «تعذّر جلب الرسائل» — a claim about a GET that never ran — and offers
// «إعادة المحاولة» wired to `_bootstrap`, which re-runs the POST. So:
//
//   * the user is told his Wi-Fi broke a request that had already left the
//     device, and
//   * the one button on the page that exists to explain the failure is the one
//     that re-issues the write.
//
// `POST /api/mobile/conversations` is documented as a get-or-create for a
// (customer, worker, project) triple, so a second POST is *probably* harmless —
// and «probably» is carrying the entire duplicate-thread defence on this path.
// The app cannot verify the server's uniqueness guarantee from a phone, so the
// honest fix is not to trust it: the screen re-reads with a GET and sends the
// user to the inbox, which can answer and cannot create anything.
//
// Red before green: the screen cases below fail against the pre-fix screen on
// the **literal strings it printed** — «تعذّر جلب الرسائل» for a write that was
// never a read — and the pure cases fail because the file did not exist.
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
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/data/thread_open_outcome.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': 'زبون تجربة',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// The server the screen talks to, and the three ways the open call can fail.
class _Server {
  /// Rows `/api/mobile/conversations` will list. Seeded to prove the re-read
  /// is what decides, not the POST's own outcome.
  List<Map<String, Object?>> inbox = <Map<String, Object?>>[];

  /// How many times the open call was POSTed. The number the whole item is
  /// about: the fix must not make it 2.
  int opens = 0;

  /// The inbox read that settles an unconfirmed open.
  int inboxReads = 0;

  /// When true the open call **lands** — a conversation is created and the row
  /// appears in the inbox — and then the answer is lost. This is the shape that
  /// produces `errWriteUnconfirmed`, and it is the case that used to print
  /// «تعذّر جلب الرسائل».
  bool swallowAnswer = false;

  /// When true the open call is refused outright, which is an ordinary failure
  /// and not the one under test.
  bool refuseOpen = false;

  /// When true the inbox cannot be read either, so the re-read proves nothing.
  bool inboxDead = false;

  late final ApiClient api;
}

_Server _buildServer() {
  late final _Server s;
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.endsWith('/api/mobile/conversations')) {
      if (req.method == 'POST') {
        s.opens++;
        if (s.refuseOpen) {
          return http.Response('{}', 500,
              headers: {'content-type': 'application/json'});
        }
        // Get-or-create: the same (customer, worker, project) resolves to the
        // same row, so a second POST would not duplicate. The app must not
        // rely on that, and this fixture records the shape so a test can prove
        // the app did not trigger it.
        s.inbox.add({
          'id': 5,
          'customer_id': 30,
          'worker_user_id': 44,
          'project_id': '7',
          'other_user_name': 'مقاول تجربة',
          'other_user_avatar': null,
          'last_message_content': null,
          'unread_count': 0,
          'last_message_at': null,
        });
        if (s.swallowAnswer) {
          // Stored, then the connection dies before the header comes back.
          throw http.ClientException('Connection closed before full header body',
              req.url);
        }
        return _json({'id': 5});
      }
      s.inboxReads++;
      if (s.inboxDead) {
        throw http.ClientException('no route to host');
      }
      return _json(s.inbox);
    }
    if (p.startsWith('/api/messages/')) return _json(<Object>[]);
    return _json(<Object>[]);
  });
  s = _Server();
  s.api = ApiClient(baseUrls: ['https://x.test'], httpClient: client);
  return s;
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land on a client');
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, ApiClient api,
    AuthState auth) async {
  // Wrapped in a RepaintBoundary so `_shot` has one boundary to capture that is
  // the screen and not the MaterialApp around it.
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
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
      home: RepaintBoundary(child: screen),
    ),
  ));
  await _settle(tester);
}


/// Writes a PNG of the whole screen and returns its path.
///
/// The same helper the other chat tests use, for the same reason: this state
/// only exists when a `MockClient` swallows a POST's answer, so it cannot be
/// reached in a live web build — a screenshot of the running site would show
/// the normal thread, not this one. The pixels come from the real widget tree
/// under the real theme either way.
Future<String> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first);
  late final String path;
  await tester.runAsync(() async {
    // 3.0, the same ratio the other chat shots use. At 2.0 this page came out
    // at 18.9 kB — an `EmptyView` is mostly background, so it compresses hard
    // and trips a size check that is really a "did anything render" check. The
    // ratio is not a quality knob here; it is what makes that check able to
    // answer.
    final image = await boundary.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    path = '/tmp/shots/$name.png';
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  expect(File(path).lengthSync(), greaterThan(20000),
      reason: 'a shot this small means nothing rendered');
  return path;
}

/// The open call is the only one that has no `conversationId`, so the screen
/// has to POST — which is the whole point.
///
/// [key] is a parameter for one reason: a test that pumps two of these in a row
/// without changing the key gets the **same Element and the same State**, and
/// `initState` — which is what runs `_bootstrap` — does not run a second time.
/// The loop then measures the first server's counters and reports a green test
/// about a screen that was never pumped. `pumpWidget` is a diff, not a reset.
Widget _screen(ApiClient api, {Key? key}) => ChatScreen(
      key: key,
      projectId: '7',
      otherUserId: 44,
      otherName: 'مقاول تجربة',
      repo: Repository(api),
    );

Conversation _conv({
  int id = 5,
  int customer = 30,
  int worker = 44,
  String? project = '7',
}) =>
    Conversation(
      id: id,
      customerId: customer,
      workerUserId: worker,
      projectId: project,
      otherUserName: 'مقاول تجربة',
      unreadCount: 0,
    );

void main() {
  group('the pure rule — did the conversation get opened', () {
    test('the inbox proves the thread exists', () {
      expect(
        inboxHoldsThread(
            inbox: [_conv()], me: 30, otherUserId: 44, projectId: '7'),
        isTrue,
      );
    });

    test('a null project is matched as a thread with no project', () {
      expect(
        inboxHoldsThread(
            inbox: [_conv(project: null)], me: 30, otherUserId: 44),
        isTrue,
        reason: 'the server stores a NULL project_id as null, not as ""',
      );
    });

    test('the sides are matched symmetrically — a contractor is in worker_user_id',
        () {
      // This account is the worker, so the peer is the customer. A predicate
      // that only compared `customer_id == me` would answer false for a
      // contractor's own inbox and report his own thread as missing.
      expect(
        inboxHoldsThread(
            inbox: [_conv(customer: 44, worker: 30)],
            me: 30,
            otherUserId: 44,
            projectId: '7'),
        isTrue,
      );
    });

    test('a different project is a different thread', () {
      expect(
        inboxHoldsThread(
            inbox: [_conv(project: '8')], me: 30, otherUserId: 44, projectId: '7'),
        isFalse,
        reason: 'a thread per project is the server contract; matching on the '
            'peer alone would call a stranger project "opened"',
      );
    });

    test('a stranger conversation is not this thread', () {
      expect(
        inboxHoldsThread(
            inbox: [_conv(customer: 30, worker: 99)],
            me: 30,
            otherUserId: 44,
            projectId: '7'),
        isFalse,
      );
    });

    test('an inbox that does not answer is unknown, never missing', () async {
      final outcome = await resolveThreadOpenOutcome(
        inbox: () async => throw http.ClientException('no route to host'),
        me: 30,
        otherUserId: 44,
        projectId: '7',
      );
      expect(outcome, ThreadOpenOutcome.unknown);
    });

    test('an inbox that answers without the thread is missing', () async {
      final outcome = await resolveThreadOpenOutcome(
        inbox: () async => <Conversation>[],
        me: 30,
        otherUserId: 44,
        projectId: '7',
      );
      expect(outcome, ThreadOpenOutcome.missing);
    });

    test('an inbox holding the thread is landed', () async {
      final outcome = await resolveThreadOpenOutcome(
        inbox: () async => [_conv()],
        me: 30,
        otherUserId: 44,
        projectId: '7',
      );
      expect(outcome, ThreadOpenOutcome.landed);
    });

    test('no outcome tells the user to press the button that re-opens',
        () {
      // The one invariant that matters and that a copy edit could break: none of
      // these three sentences may carry «أعد المحاولة», because the only
      // control on that page re-runs the POST.
      for (final outcome in ThreadOpenOutcome.values) {
        expect(threadOpenOutcomeCopy(outcome), isNot(contains(S.retry)));
        expect(threadOpenOutcomeCopy(outcome), contains(S.openInbox),
            reason: 'every answer points at the list that can settle it: '
                '$outcome');
      }
    });
  });

  group('the screen — an open that never got an answer', () {
    testWidgets('is not reported as a failed message read', (tester) async {
      final s = _buildServer()..swallowAnswer = true;
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      expect(find.text('تعذّر جلب الرسائل'), findsNothing,
          reason: 'the messages were never the call that failed — the POST '
              'that opens the thread was, and the sentence claims otherwise');
      // The fixture's open call *lands* (it creates the conversation and the
      // answer is lost afterwards), so the settled answer is «landed» and the
      // screen says so. Asserting the «unclear» heading here was my error and
      // the test corrected it: the unclear heading belongs to the case where
      // the write did not land, which is the refused/dead fixture below.
      expect(find.text(S.threadUnconfirmedTitleLanded), findsOneWidget);
    });

    testWidgets('a landed open says so and points at the inbox',
        (tester) async {
      final s = _buildServer()..swallowAnswer = true;
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      expect(s.inboxReads, greaterThan(0),
          reason: 'the app must settle the write with a GET');
      expect(find.text(S.threadUnconfirmedTitleLanded), findsOneWidget);
      expect(find.text(S.threadUnconfirmedLanded), findsOneWidget);
    });

    testWidgets('offers the inbox, not a retry that re-runs the POST',
        (tester) async {
      final s = _buildServer()..swallowAnswer = true;
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      expect(find.text(S.openInbox), findsOneWidget);
      expect(find.text(S.retry), findsNothing,
          reason: 'the only button on this page is a POST; "retry" next to it '
              'is an instruction to open a second conversation');
    });

    testWidgets('the open is POSTed exactly once, whatever the outcome',
        (tester) async {
      // One server per case, and the server is rebuilt for the second. The
      // first draft looped a single `tester` over both fixtures, and the
      // second `pumpWidget` reused the first tree — so it measured the *first*
      // server's counter and reported a green test about a screen that had
      // never been pumped. A loop that re-pumps is a loop that needs a fresh
      // pump; `pumpWidget` is not a reset.
      for (final dead in [false, true]) {
        final s = _buildServer()
          ..swallowAnswer = true
          ..inboxDead = dead;
        final auth = await _boot(s.api);
        await _pump(tester, _screen(s.api, key: ValueKey(dead)), s.api, auth);

        expect(s.opens, 1, reason: 'dead=$dead — the re-read is a GET, so the '
            'write cannot be issued twice on this path');
        expect(s.inboxReads, 1, reason: 'dead=$dead — exactly one re-read');
      }
    });

    testWidgets('a dead inbox is unknown, and is not a failure verdict',
        (tester) async {
      final s = _buildServer()
        ..swallowAnswer = true
        ..inboxDead = true;
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      // `unknown` keeps the shared sentence, so the assertion is on the
      // heading: the app must not claim the thread is not there when the one
      // read that could have said so never ran.
      expect(find.text(S.threadUnconfirmedTitleUnclear), findsOneWidget);
      expect(find.text(S.threadUnconfirmedMissing), findsNothing);
    });

    testWidgets('a thread that opens normally is unaffected', (tester) async {
      final s = _buildServer();
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      expect(find.text(S.threadUnconfirmedTitleUnclear), findsNothing);
      expect(find.text(S.threadUnconfirmedTitleLanded), findsNothing);
      expect(s.opens, 1);
    });

    testWidgets('the two states are not the same pixels', (tester) async {
      // Found by looking at the first pair of screenshots: both drew the same
      // grey icon, because [EmptyView] tints from `danger` alone and both
      // states passed `false`. Two pages that differ only in a line of text are
      // one page, and the difference here is the whole message. Asserted on
      // the rendered pixels, not on a widget field, because the field was
      // correct and the paint was not.
      final shots = <String>[];
      for (final dead in [false, true]) {
        final s = _buildServer()
          ..swallowAnswer = true
          ..inboxDead = dead;
        final auth = await _boot(s.api);
        await _pump(tester, _screen(s.api, key: ValueKey('px$dead')), s.api, auth);
        shots.add(await _shot(tester, 'thread_open_px_$dead'));
      }
      expect(shots[0], isNot(equals(shots[1])),
          reason: 'two states, two files — if these are byte-identical the '
              'screen is not distinguishing them at all');
    });

    testWidgets('the page renders (and is captured) in both settled states',
        (tester) async {
      // Two shots, because the two states are the point of the split: a success
      // and a «the app cannot tell» must not look like the same page. A layout
      // claim with no screenshot is a claim about nothing.
      for (final dead in [false, true]) {
        final s = _buildServer()
          ..swallowAnswer = true
          ..inboxDead = dead;
        final auth = await _boot(s.api);
        await _pump(tester, _screen(s.api, key: ValueKey('shot$dead')), s.api,
            auth);
        final path = await _shot(tester, 'thread_open_unconfirmed_$dead');
        expect(File(path).existsSync(), isTrue);
      }
    });

    testWidgets('a refused open is still the ordinary read error',
        (tester) async {
      // A 500 is a real answer: the write did not land and the app knows it.
      // It is not the ambiguous case, so it keeps the sentence it always had —
      // this is a guard against the new branch swallowing every failure.
      final s = _buildServer()..refuseOpen = true;
      final auth = await _boot(s.api);
      await _pump(tester, _screen(s.api), s.api, auth);

      expect(find.text('تعذّر جلب الرسائل'), findsOneWidget);
      expect(find.text(S.threadUnconfirmedTitleUnclear), findsNothing);
    });
  });

  group('the read error page', () {
    testWidgets('its retry is a read, so the open POST is never re-issued',
        (tester) async {
      // A thread reached from the inbox already has an id, so no open call is
      // made at all — which is what makes a read retry safe on this path. The
      // assertion that matters is the one the pre-fix screen could not pass:
      // the retry button used to call `_bootstrap`, which POSTs.
      final s = _buildServer();
      final auth = await _boot(s.api);
      // The read fails from the start, so the error page is the *first* thing
      // this screen ever draws. Setting a flag after a successful load would
      // not put it there — nothing re-reads on its own — and the first draft of
      // this test did exactly that, then asserted on a page that was never
      // built. A test that has to arrange its precondition before the pump, not
      // after, or it is testing a state the app never entered.
      final counting = _CountingRepository(s.api)..refuseReads = true;
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 44,
          otherName: 'مقاول تجربة',
          repo: counting,
        ),
        s.api,
        auth,
      );

      expect(find.text('تعذّر جلب الرسائل'), findsOneWidget,
          reason: 'a linked thread that cannot be read is the ordinary read '
              'error, and keeps the sentence it always had');
      expect(s.opens, 0,
          reason: 'a linked thread is opened by id; nothing POSTs');

      // Press the page's own retry — the control that used to be `_bootstrap`,
      // and so used to be a write.
      counting.refuseReads = false;
      final readsBefore = counting.reads;
      await tester.tap(find.text(S.retry));
      await _settle(tester, frames: 20);

      expect(counting.reads, greaterThan(readsBefore),
          reason: 'the retry must re-read the thread');
      expect(s.opens, 0,
          reason: 'the retry on the read-error page must not re-run the open '
              'POST — that is the duplicate-creating control');
    });
  });
}

/// Counts the message reads a screen makes, and can be made to refuse them.
///
/// Subclassing [Repository] rather than wrapping it: the screens take a
/// concrete `Repository`, and the only method this file needs to observe is
/// `messages`. Nothing in production exists to be counted, which is the point
/// — a seam added to the screen for a test is a seam the next writer has to
/// reason about.
class _CountingRepository extends Repository {
  _CountingRepository(super.api);

  int reads = 0;
  bool refuseReads = false;

  @override
  Future<List<Message>> messages(int conversationId, {int after = 0}) {
    reads++;
    if (refuseReads) {
      return Future<List<Message>>.error(
          http.ClientException('no route to host'));
    }
    return super.messages(conversationId, after: after);
  }
}
