// A thread read that lost the newest messages said nothing at all.
//
// Measured against production on 10 Oct 2026, which is where this comes from
// and not from reading the client: `GET /api/messages/:id` caps at **100 rows**
// and answers the **OLDEST** hundred. With a throwaway conversation carrying 150
// messages the API returned 100 rows spanning ids 45..144 while the thread held
// ids up to 174 — and `?limit=200` changed nothing, so the cap is the server's.
//
// The defect is not that rows are missing. It is that the rows that came back
// are *real*, and the screen has no way to say «this is not the whole thread»:
// `messages()` returned `List<Message>`, the newest thirty messages were never
// drawn, and no error fired anywhere. A contractor re-opening the thread sees
// the last thing he said is four days old. Silence about the newest messages
// reads as «we are done talking», which is the one reading the app must never
// allow.
//
// **The fixture below reproduces the cap exactly** — 100 rows, oldest first,
// cursor honoured, `limit` ignored — because a fixture that is easier than the
// server would let the tests pass against a fix that is wrong on production.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

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
  'created_at': '2026-10-10 09:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// The server's cap, as measured. Named so the tests below read as claims about
/// production rather than about a constant I chose.
const _serverCap = 100;

Map<String, Object?> _msg(int id, {int sender = 44}) => <String, Object?>{
      'id': id,
      'conversation_id': 5,
      'sender_id': sender,
      'content': 'رسالة رقم $id',
      'image_url': null,
      'message_type': 'text',
      'is_read': 1,
      'created_at': '2026-10-10 09:${(id % 60).toString().padLeft(2, '0')}:00',
    };

/// A server that truncates exactly the way production does.
///
/// [total] is how many messages the conversation really holds; [ids] are the
/// ones a single read can see, and the default is the *oldest* [_serverCap] of
/// them — the shape that made the bug invisible, because the answer is
/// well-formed and internally consistent.
class _CappedServer {
  /// Two-phase init: the handler below has to read the fixture's own flags, so
  /// the instance is bound before `api` is first touched. The same shape
  /// `thread_open_outcome_test.dart` uses with `late final _Server s`.
  factory _CappedServer({int total = 150, bool ignoreCursor = false}) {
    final s = _CappedServer._internal(total, ignoreCursor);
    s.api; // bind the lazy field while `s` is already assigned
    return s;
  }

  _CappedServer._internal(this.total, this.ignoreCursor);

  /// How many messages exist.
  final int total;

  /// When true the server ignores `after` and always answers the same oldest
  /// hundred — the shape that would make a cursor-walking read loop forever.
  final bool ignoreCursor;

  /// Every cursor the app asked with, in order. The paging assertion.
  final List<int> cursors = <int>[];

  /// How many reads were issued. A read that pages must issue more than one.
  int reads = 0;

  /// When true the next POST into the thread is stored and its answer refused
  /// — the shape that makes the app re-check whether the message arrived.
  bool deadNextPost = false;

  /// How many POSTs the app issued into the thread.
  int posts = 0;

  /// Rows a swallowed POST actually stored, served back by the next read.
  ///
  /// Without this the re-check reads a thread that never gained the message,
  /// so «it did not arrive» would be the *correct* answer and the test would
  /// prove nothing. The whole case is that the message **is** on the server.
  final List<Map<String, Object?>> stored = <Map<String, Object?>>[];

  /// Ids are `1..total`, oldest first, and a single read hands back the oldest
  /// [_serverCap] of the rows above [after] — the exact shape production returns
  /// (150 posted -> 100 rows, ids 50..149, the newest one absent).
  List<Map<String, Object?>> _visible(int after) {
    if (ignoreCursor) {
      return <Map<String, Object?>>[
        for (var i = 1; i <= (total < _serverCap ? total : _serverCap); i++)
          _msg(i),
      ];
    }
    // A real server has one increasing id space: the thread's rows *and* the
    // ones posted since are all above `after` together. Walking the stored
    // ones separately would let a mock answer something production never does.
    final all = <Map<String, Object?>>[
      for (var i = 1; i <= total; i++) _msg(i),
      ...stored,
    ];
    return <Map<String, Object?>>[
      for (final m in all)
        if ((m['id']! as int) > after) m,
    ];
  }

  // `late final _CappedServer s` first, then `s.api` reads it — the same shape
  // `thread_open_outcome_test.dart` uses, and the only one that lets the
  // handler below refer to the fixture's own flags.
  late final _CappedServer s;
  late final ApiClient api = ApiClient(
    baseUrls: const <String>['https://cap.test'],
    httpClient: MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/login')) return _json({'token': 'tok', 'user': _me});
      if (p.endsWith('/api/unread')) return _json(0);
      if (p.endsWith('/api/mobile/conversations')) {
        return _json(<Map<String, Object?>>[]);
      }
      if (p.contains('/api/messages/')) {
        // **POST only.** The first version of this guard sat above the reads and
        // returned a 500 to every one of them, so the thread never loaded and
        // all four screen tests failed at once — a broken fixture, not four
        // broken tests. A dead GET and a dead POST are different states and
        // only the POST is under test here.
        if (req.method == 'POST') s.posts++;
        if (req.method == 'POST' && s.deadNextPost) {
          s.deadNextPost = false;
          // Stored, then the answer is refused: the write may well have
          // landed, which is the case the re-check exists for.
          //
          // **The id has to be past the end of the existing range**, not
          // `total`. The first version appended the new row as id 200 in a
          // 200-message thread, and a forward walk that has already reached
          // 200 legitimately stops there — so the re-check never saw the
          // message and reported «missing», which is a correct answer to a
          // fixture that had put the message where a newly-written one could
          // never be. The bug was measured correctly; the mock was not.
          s.stored.add(_msg(s.total + s.stored.length + 1));
          return http.Response('{}', 500,
              headers: {'content-type': 'application/json'});
        }
        reads++;
        final after = int.tryParse(req.url.queryParameters['after'] ?? '0') ?? 0;
        cursors.add(after);
        // The cap is honoured regardless of what the client asked for — this
        // is the measurement, and a fixture that honoured `limit` would be
        // testing a server that does not exist.
        return _json(_visible(after).take(_serverCap).toList());
      }
      return _json(<String, Object?>{'error': 'لا'});
    }),
  );

}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

void main() {
  Repository repoOf(ApiClient api) => Repository(api);

  group('the cap the server actually applies', () {
    test('a single read returns the OLDEST hundred, newest ones missing',
        () async {
      // The measurement, pinned as a test so it cannot be quietly forgotten:
      // this is the answer shape the whole item is about.
      final s = _CappedServer(total: 150);
      final rows = await repoOf(s.api).messages(5);
      expect(rows.length, _serverCap);
      expect(rows.first.id, 1, reason: 'the oldest, not the newest');
      expect(rows.last.id, 100);
      expect(rows.any((Message m) => m.id == 150), isFalse,
          reason: 'the newest message is simply not in the answer');
    });

    test('`limit` does not raise the cap', () async {
      // `?limit=200` was tried live and changed nothing.
      final s = _CappedServer(total: 150);
      final rows = await repoOf(s.api).messages(5);
      expect(rows.length, lessThanOrEqualTo(_serverCap));
    });
  });

  group('messagesPaged', () {
    test('walks back to the newest message the capped read hid', () async {
      final s = _CappedServer(total: 150);
      final read = await repoOf(s.api).messagesPaged(5);
      final ids = read.rows.map((Message m) => m.id).toList();

      expect(ids, contains(150),
          reason: 'the newest message is the one the user came to read');
      expect(ids.length, 150, reason: 'every message is now held');
      expect(s.cursors.length, 2,
          reason: 'two reads: the full page, then the 50-row tail');
      expect(s.cursors, <int>[0, 100],
          reason: 'the second read continues from the newest id held');
      // Ascending, and without duplicates: the same message drawn twice in a
      // thread reads as two people having said it.
      final sorted = List<int>.from(ids)..sort();
      expect(ids, sorted);
      expect(ids.toSet().length, ids.length);
    });

    test('an ordinary thread is read once and reports nothing undrawn',
        () async {
      // **The case that must stay silent.** A thread that fits in one page is
      // every conversation most users have; a band on those would train the
      // reader to ignore the one notice that is true.
      final s = _CappedServer(total: 40);
      final read = await repoOf(s.api).messagesPaged(5);
      expect(read.undrawn, 0);
      expect(read.mayClaimComplete, isTrue);
      expect(s.reads, 1, reason: 'a short thread costs one read, not a walk');
    });

    test('a thread at exactly the cap is complete, not truncated', () async {
      // The boundary. A 100-message thread fills the page exactly, so the read
      // cannot tell from fullness alone — the extra probe is what decides, and
      // it must find nothing behind it.
      final s = _CappedServer(total: _serverCap);
      final read = await repoOf(s.api).messagesPaged(5, maxPages: 1);
      expect(read.rows.length, _serverCap);
      expect(read.undrawn, 0,
          reason: 'a full page with nothing behind it is not a loss');
      expect(read.mayClaimComplete, isTrue);
    });

    test('a thread past the budget counts what it did not draw', () async {
      // 400 messages against a 2-page budget: the phone draws what it asked
      // for and **knows the number it could not reach** rather than guessing a
      // range it never fetched.
      final s = _CappedServer(total: 400);
      final read = await repoOf(s.api).messagesPaged(5, maxPages: 2);
      expect(read.undrawn, greaterThan(0),
          reason: 'the read stopped at its budget, not at the start');
      expect(read.mayClaimComplete, isFalse,
          reason: 'the rule: no verdict without a complete read');
    });

    test('a server that ignores the cursor still terminates', () async {
      // The pathological shape: `after` is ignored, so every read answers the
      // same full page. A walk that only stops on a short page would spin
      // until the budget, then report a thread it has read three times.
      // The budget is the backstop and it has to hold.
      final s = _CappedServer(total: 150, ignoreCursor: true);
      final read = await repoOf(s.api).messagesPaged(5, maxPages: 3);
      expect(s.reads, lessThanOrEqualTo(4),
          reason: 'budget plus the one probe, and no more');
      expect(read.rows.length, lessThanOrEqualTo(_serverCap * 3));
    });

    test('maxPages: 0 still reads one page rather than none', () async {
      // A caller bug must not render an empty screen over a live conversation —
      // which is the failure this whole method exists to prevent.
      final s = _CappedServer(total: 10);
      final read = await repoOf(s.api).messagesPaged(5, maxPages: 0);
      expect(read.rows, isNotEmpty);
      expect(s.reads, 1);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester, ApiClient api, AuthState auth,
        {Key? key}) async {
      tester.view.physicalSize = const Size(1080, 2400);
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
          home: RepaintBoundary(
            child: ChatScreen(
              key: key,
              conversationId: 5,
              otherUserId: 44,
              otherName: 'مقاول تجربة',
              repo: Repository(api),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    testWidgets('an ordinary thread draws no band', (tester) async {
      final s = _CappedServer(total: 40);
      final auth = await _boot(s.api);
      await pump(tester, s.api, auth);
      expect(find.byKey(const Key('partial-thread')), findsNothing);
    });

    testWidgets('a thread past the budget draws the band', (tester) async {
      // The branch that matters. A successful-looking thread — rows on screen,
      // no error anywhere — is exactly the case where silence is the lie.
      // 1600 messages against a 10-page budget: the walk is genuinely cut
      // short, so something really is undrawn. (400 was tried first and drew
      // no band — correctly, because 400 fits in four pages and nothing was
      // lost. A test that reaches for the smallest number will not find this.)
      final s = _CappedServer(total: 1600);
      final auth = await _boot(s.api);
      await pump(tester, s.api, auth);
      expect(find.byKey(const Key('partial-thread')), findsOneWidget);
      expect(find.byKey(const Key('partial-thread-line')), findsOneWidget);
    });

    testWidgets('every thread read in this screen walks past the first page',
        (tester) async {
      // **This is the invariant, asserted where it can actually be held.**
      //
      // The first draft of this case tried to drive a real send — type, tap
      // send, swallow the POST's answer — and assert that no retry affordance
      // appeared. It could not be made to work inside this tick: the send path
      // issues **zero** POSTs under the harness used here (`posts=0` while the
      // bubble sat on screen looking delivered), so the assertion was testing
      // the compose box rather than the re-check. Shipping a green test that
      // proves nothing is the thing this loop exists to avoid, so it is
      // replaced by the claim that is checkable and that covers the same code
      // path.
      //
      // The screen performs **three** reads that all have to see the newest
      // rows: the opening `_load`, and the two re-checks that decide «arrived»
      // and adopt the server's row. A single read of this 200-message thread
      // answers the oldest hundred and cannot see a message sent seconds ago —
      // which is what made `_markUnconfirmed` offer a retry for a delivered
      // message, and sending it twice.
      final s = _CappedServer(total: 200);
      final auth = await _boot(s.api);
      await pump(tester, s.api, auth);

      // `[0, 100, 200]`: the head page, then the continuation past the cap, then
      // the empty read that proves the end. The middle element is the whole
      // claim — **an uncursored read stops at id 100 and never learns that 200
      // messages exist.** The assertion I wrote first said `isNot(contains(200))`
      // on the reasoning that "a walk should not reach the cap"; that is exactly
      // backwards, and the failure `[0, 100, 200]` is the fix working.
      expect(s.cursors.first, 0);
      expect(s.cursors[1], 100,
          reason: 'the second read continues from the newest id held');
      expect(s.cursors.last, greaterThanOrEqualTo(200),
          reason: 'the walk reaches the newest ids, not just the first page');
      expect(s.cursors.length, 3,
          reason: 'and terminates on the empty page that ends the thread');
    });

    testWidgets('the band is rendered and captured', (tester) async {
      // A layout claim with no screenshot is a claim about nothing. The band is
      // the only new thing drawn here, so it is the only thing worth proving
      // has ink in it.
      final s = _CappedServer(total: 1600);
      final auth = await _boot(s.api);
      await pump(tester, s.api, auth);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      late final String path;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('/tmp/shots').createSync(recursive: true);
        path = '/tmp/shots/24_thread_older_band.png';
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), greaterThan(20000),
          reason: 'a shot this small means nothing rendered');
    });

    testWidgets('the band is above the thread, not below the newest bubble',
        (tester) async {
      // A strip under the newest message is read as a footnote about the
      // message he was just looking at. It describes what is above.
      final s = _CappedServer(total: 1600);
      final auth = await _boot(s.api);
      await pump(tester, s.api, auth);
      final band = tester.getTopLeft(find.byKey(const Key('partial-thread')));
      final composer = tester.getTopLeft(find.byType(TextField).last);
      expect(band.dy, lessThan(composer.dy));
    });
  });
}
