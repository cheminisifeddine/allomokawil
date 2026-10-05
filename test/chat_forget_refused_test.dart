// A delivered message came back from the dead as a duplicate.
//
// The outbox exists so a message the server refused is not lost: it is written
// to the phone *before* the first attempt and dropped the moment the server
// holds a row. `_deliver`'s success path does that drop — `await _forget(local)`
// — and every word in this file is about the case where the **phone refuses the
// delete**.
//
// The record left on the disk by a successful send is a plain one: `uncertain`
// is null, which is the codebase's word for «the server refused it, safe to
// re-send». `_restoreQueued` asks the fresh thread whether the server already
// holds a record's words — but **only for records marked `unconfirmed`**:
//
//     if (p.uncertain != null) { …ask… }
//     …draw the bubble as SendState.failed…
//
// So a refused delete does not merely leak a row. It leaves a row whose mark
// says «re-send me», the restore branch skips it, `_flushQueued` hands it to
// the wire with no tap from anyone, and the contractor receives the same
// address twice — the duplicate this whole file exists to kill, produced by
// the app itself at the exact moment it *succeeded*.
//
// Nothing reported it either. `ChatOutbox.remove` ended in `_write`, which
// catches the store's refusal and answers `false` — and then returned
// `Future<void>`, throwing the answer away. The one caller that had a sentence
// ready could not have used it, and the other wrote:
//
//     _outbox.remove(id).catchError((Object _) {});
//
// which guards a future that cannot throw. That line looks like storage-failure
// handling and handles nothing; the same census `failure_reported_test.dart`
// asserts over `catch` blocks never sees a `catchError`.
//
// *Shipped:* `remove` answers whether the record is really off the disk, like
// [ChatOutbox.markUncertain] already did. When the answer is false the screen
// writes the «do not send me again» mark onto the row instead — the one word
// that makes `_restoreQueued`'s question answerable on the next cold start, and
// the same mark a swallowed write already uses. The refused forget is not
// papered over: when the mark does not land either, the user is told with the
// sentence that already exists for exactly this (`S.markUnconfirmedNotSaved`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

const _typed = 'العنوان: حسين داي، الطابق الثالث';

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

/// A store that refuses the writes numbered in [refuse] and takes every other
/// one — the shape of a device that would not clear one row and then would.
///
/// **Injected rather than swapped into the platform**, for the reason
/// `chat_mark_not_saved_test.dart` records: the plugin caches its
/// `SharedPreferences` instance, so a store configured after the session was
/// written is not the store the screen reads.
class _SelectiveStore implements OutboxStore {
  _SelectiveStore({this.refuse = const <int>{}, this.raw});

  /// Which write numbers are refused. Counting starts at 1.
  final Set<int> refuse;

  int writes = 0;

  /// The queue as it stands, seeded by the caller when a test needs the phone
  /// to hold a row it is about to be asked to delete.
  String? raw;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    writes++;
    if (refuse.contains(writes)) {
      throw StateError('preferences refused to store the queue');
    }
    raw = value;
  }

  /// What a fresh process would restore from this phone.
  List<PendingMessage> stored() => decodeOutbox(raw);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
  });

  group('remove answers whether the record really left the disk', () {
    test('true when the store took the delete', () async {
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      final record = await outbox.add(conversationId: 5, text: 'أ');
      expect(await outbox.remove(record.id), isTrue);
      expect(await outbox.pendingFor(5), isEmpty);
    });

    test('true when the id was never in the queue, and nothing is written',
        () async {
      // Nothing on the disk can be re-sent for an id that is not there, so the
      // invariant holds without a write. A store that declines every write must
      // still cost nothing here, or a settled thread would report a failure
      // that never happened.
      final store = _SelectiveStore(refuse: <int>{1, 2, 3});
      final outbox = ChatOutbox(store: store);
      expect(await outbox.remove('5.0.0'), isTrue);
      expect(store.writes, 0);
    });

    test('false when the store refuses, and it never throws', () async {
      final warm = _SelectiveStore();
      final record = await ChatOutbox(store: warm)
          .add(conversationId: 5, text: 'أ');
      // Same bytes, but this device refuses its *first* write — the delete.
      final outbox = ChatOutbox(store: _SelectiveStore(
          refuse: <int>{1}, raw: warm.raw));
      expect(await outbox.remove(record.id), isFalse);
      // The record is still there — which is exactly what the answer is for.
      expect((await outbox.pendingFor(5)).single.id, record.id);
    });
  });

  group('a refused delete leaves a record the next launch will not re-send',
      () {
    testWidgets('the landed message is marked, not queued for a second send',
        (tester) async {
      final store = _SelectiveStore(refuse: <int>{2});
      final outbox = ChatOutbox(store: store);
      // Write 1 = the enqueue, 2 = the delete, 3 = the mark.

      final server = _server();
      final auth = await _boot(server.api);
      _size(tester);

      await tester.pumpWidget(_thread(server: server, auth: auth,
          outbox: outbox));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).last, _typed);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);

      // The server stored it: one POST, and the words are on the thread once.
      expect(server.posts, 1);
      expect(find.text(_typed), findsOneWidget);

      // What the phone still holds is the whole defect. Before the fix this
      // row read `uncertain: null` — «the server refused it, re-send me» —
      // which is the worst possible thing to leave behind a *successful* send.
      final rows = store.stored();
      expect(rows, hasLength(1),
          reason: 'the refused delete really did leave the record behind');
      expect(rows.single.uncertain, SendState.unconfirmed,
          reason: 'a delivered message must come back as «do not send me '
              'again», or _flushQueued hands it to the wire on the next open');

      // And the store was asked to write that mark — the answer is not a
      // guess about the disk.
      expect(store.writes, 3, reason: 'enqueue, refused delete, then the mark');
    });

    testWidgets('a refused forget *and* a refused mark is told to the user',
        (tester) async {
      // The device would not delete the row and would not mark it either. Now
      // the duplicate is genuinely coming back on the next cold start, and
      // nothing on the screen or in the log says so. Silence here is the bug:
      // the sentence that exists for it is exactly this case.
      final store = _SelectiveStore(refuse: <int>{2, 3});
      final outbox = ChatOutbox(store: store);

      final server = _server();
      final auth = await _boot(server.api);
      _size(tester);

      await tester.pumpWidget(_thread(server: server, auth: auth,
          outbox: outbox));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).last, _typed);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);

      expect(server.posts, 1, reason: 'the send itself worked');
      expect(find.textContaining(S.markUnconfirmedNotSaved), findsWidgets,
          reason: 'a delivered message that may be sent again must say so');
    });
  });
}

/// The thread the Worker actually holds, and the counters that make a second
/// POST visible.
class _Thread {
  int reads = 0;
  int posts = 0;
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  late final ApiClient api;
}

_Thread _server() {
  late final _Thread thread;
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') {
        thread.reads++;
        return _json(thread.rows);
      }
      thread.posts++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      thread.rows.add({
        'id': 900 + thread.rows.length,
        'conversation_id': 5,
        'sender_id': 30,
        'content': body['content'],
        'image_url': null,
        'message_type': 'text',
        'is_read': 0,
        'created_at': '2026-09-11 20:0${thread.rows.length}:00',
      });
      return _json(thread.rows.last);
    }
    return _json(<Object>[]);
  });
  thread = _Thread();
  thread.api = ApiClient(baseUrls: ['https://x.test'], httpClient: client);
  return thread;
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

Widget _thread({
  required _Thread server,
  required AuthState auth,
  required ChatOutbox outbox,
}) =>
    AppScope(
      api: server.api,
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
        home: ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول',
          repo: Repository(server.api),
          outbox: outbox,
        ),
      ),
    );

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
