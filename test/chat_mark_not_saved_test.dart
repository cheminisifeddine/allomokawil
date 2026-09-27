// The «do not send this again» mark could fail to reach the disk, silently.
//
// Everything this app does to stop a chat message being sent twice hangs on
// one stored word. A record the server refused is re-sent on the next thread
// open; a record marked `unconfirmed` is skipped. `ChatOutbox.add` writes the
// record and `markUncertain` writes the mark, and the mark is the *only* thing
// that separates "he refused it" from "nobody knows what happened to it".
//
// `markUncertain` awaited `_write(next)` and threw the answer away — exactly
// what the enqueue path did before `7a15de6`. And the two failures are not
// symmetrical in severity, which is why this file is about the mark:
//
//  * **the mark is refused.** The disk still reads «safe to send». The screen
//    draws the bubble without a retry affordance and believes it has protected
//    the user, then the process dies. Next open, `_flushQueued` hands the words
//    to the wire with no tap from anyone. The server may already hold that
//    row — the mark exists *because* nobody knows — so the contractor receives
//    «العنوان: حسين داي» twice. This is the duplicate Phase 5 exists to kill,
//    reopened by a storage failure the user was never told about.
//  * **the clear is refused.** The re-read proved the words are absent, but
//    the record still reads `unconfirmed`. After a restart that record comes
//    back with no retry affordance and the startup flush skips it: not on the
//    server, not resendable. The user has to retype his own address.
//
// Both are one bool, and neither was reported anywhere.
//
// **The harness note, hard-won:** the platform prefixes every key `flutter.`,
// so seeding a hand-built map in the app's own vocabulary makes the phone come
// back empty — the thread never signs in, never reaches the send, and the test
// *hangs* instead of failing. An earlier version of this file did that. The
// declining store is therefore layered over the values a live instance is
// holding, captured before the swap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

const _typed = 'العنوان: حسين داي، الطابق الثالث';

/// The sentence the app prints when the mark did not land, as literal copy
/// rather than a reference to the constant. A test that cannot compile against
/// the source it is written for has proven nothing, and the only thing that
/// tells you whether this test can fail is the run against the reverted file.
const _markLost = 'انسخ الرسالة الآن قبل إغلاق التطبيق';

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

/// Accepts the first [accept] queue writes and refuses every one after it,
/// answering `false` the way the platform really does on a full disk, a
/// revoked storage grant or a rejected commit. Nothing is thrown.
///
/// **Injected rather than swapped into the platform.** The widget tests install
/// this as the screen's [ChatOutbox] store, and that is not a shortcut: the
/// plugin caches its `SharedPreferences` instance, so swapping
/// `SharedPreferencesStorePlatform` after the session was written leaves the
/// screen reading a *different* store than the one the test just configured.
/// A test that cannot say which write went where is a test that can pass
/// without exercising anything — and this file proved it, twice.
class _GatedOutboxStore implements OutboxStore {
  _GatedOutboxStore({this.accept = 1});

  /// How many queue writes are taken before every one is refused.
  final int accept;

  int writes = 0;

  /// The queue as it is on the disk, so a test can check what the *next* cold
  /// start will read — which is the only thing that decides a duplicate.
  String? raw;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    writes++;
    if (writes > accept) {
      throw StateError('preferences refused to store the queue');
    }
    raw = value;
  }

  /// What a fresh process would restore from this phone.
  List<PendingMessage> stored() => decodeOutbox(raw);
}

/// The thread the Worker holds, plus the two switches that make a write's answer
/// get lost.
class _Thread {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  /// Every message POST that reached the server, whatever its outcome.
  int posts = 0;

  /// Stored on the Worker, then the answer is lost — the shape that produces
  /// `errWriteUnconfirmed`, and so the unconfirmed path in the screen.
  bool swallowAnswer = false;

  /// Counts down rather than switching on, so the thread can be read first
  /// (the composer must be on screen to type) and only then go dark, which is
  /// the real shape: the connection dies *after* the message was sent.
  int refuseReadAfter = -1;

  /// Reads only the rows that existed before the swallowed write, so the
  /// re-read comes back *successfully* and does not contain the message —
  /// which is how a message is proved absent. A read that fails cannot say
  /// that; the two paths need different harnesses and testing one with the
  /// other is how a test passes without exercising anything.
  int hideFromRow = -1;

  /// When true the swallowed write's row is also missing from the re-read, so
  /// the app is told «your message is not on the server» instead of the read
  /// failing.
  bool hideAfterSwallow = false;

  int reads = 0;

  late final ApiClient api;
}

_Thread _buildServer() {
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
        if (thread.refuseReadAfter >= 0 && thread.reads > thread.refuseReadAfter) {
          throw http.ClientException('no route to host');
        }
        if (thread.hideFromRow >= 0) {
          return _json(thread.rows.take(thread.hideFromRow).toList());
        }
        return _json(thread.rows);
      }
      thread.posts++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      // Recorded before the row lands, so the read can exclude exactly this
      // one message and no other.
      final rowAt = thread.rows.length;
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
      if (thread.swallowAnswer) {
        if (thread.hideAfterSwallow) thread.hideFromRow = rowAt;
        throw http.ClientException('Connection closed before full header body',
            req.url);
      }
      return _json(thread.rows.last);
    }
    return _json(<Object>[]);
  });
  thread = _Thread();
  thread.api = ApiClient(baseUrls: ['https://x.test'], httpClient: client);
  return thread;
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Mounts the thread, waits for the composer, then lets the thread go dark so
/// the *next* read is the one that fails.
Future<void> _typeThenBreakConnection(
  WidgetTester tester, {
  required _Thread server,
  required AuthState auth,
  required bool unreadable,
  required ChatOutbox outbox,
  String text = _typed,
}) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(AppScope(
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
  ));
  await _settle(tester);

  // The read that has already succeeded is the one that leaves the screen able
  // to send; the mark is written before the re-read, and the re-read after it
  // is what settles the message.
  server.swallowAnswer = true;
  if (unreadable) {
    // The read itself dies. The app cannot say «absent», so it stays
    // unconfirmed — and the mark is the only thing that survives.
    server.refuseReadAfter = server.reads;
  } else {
    // The read comes back, and does not contain the message. That is the proof
    // of absence, and it is the only branch that clears the mark.
    server.hideAfterSwallow = true;
  }

  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Hand the real in-memory store back, so no other file inherits one that
    // declines writes.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
  });

  group('the user is told when the mark did not land', () {
    testWidgets('a lost mark is said out loud when the re-read also fails',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      // The record lands; the mark does not; the re-read cannot be read.
      final store = _GatedOutboxStore();
      server.hideAfterSwallow = false;

      await _typeThenBreakConnection(tester,
          server: server,
          auth: auth,
          unreadable: true,
          outbox: ChatOutbox(store: store));

      // The mark is the app's only defence against a duplicate and it did not
      // land. Silence here is the bug: the screen draws the bubble as settled
      // and the next launch re-sends the words with no tap from anyone.
      expect(find.textContaining(_markLost), findsWidgets,
          reason: 'a mark the phone refused must be reported, because the '
              'thing it protects is invisible and the cost is a duplicate');

      // Not the ordinary sentence, and specifically not «check the list»:
      // this path has just proved the app cannot read the list.
      expect(find.textContaining('تحقّق من القائمة'), findsNothing,
          reason: 'the sentence that sends the user to the list is a lie here — '
              'the list is exactly what just failed to load');
    });

    testWidgets('the duplicate is then actually possible, and the test says so',
        (tester) async {
      // The assertion the previous version of this file faked. With the mark
      // refused, the record on the disk still reads «safe to send», so a cold
      // start re-posts it — and the server *did* store the first one, so the
      // contractor now has the same address twice. Nothing in the app stops
      // this except the sentence above.
      final server = _buildServer();
      final auth = await _boot(server.api);
      final store = _GatedOutboxStore();

      await _typeThenBreakConnection(tester,
          server: server,
          auth: auth,
          unreadable: true,
          outbox: ChatOutbox(store: store));

      // What the phone holds after the failed mark: the words, and no reason
      // not to send them. Read from the same store the screen used, which is
      // the only place the answer can be trusted.
      final rows = store.stored();
      expect(rows, hasLength(1), reason: 'the record itself did land');
      expect(rows.single.uncertain, isNull,
          reason: 'this is the duplicate: the disk says re-send me, and '
              '_flushQueued will do it on the next thread open');
    });

    testWidgets('a lost clear keeps the retry instruction alive, with a '
        'deadline', (tester) async {
      // The other direction. The re-read *succeeded* and did not contain the
      // words, so the message is genuinely unsent and the retry line is real —
      // but the clear that makes it retryable after a restart was refused, so
      // the record on the disk still reads «unconfirmed» and the startup flush
      // will skip it. Without the deadline the user closes the app holding a
      // message that is on neither the server nor the retry list.
      final server = _buildServer();
      final auth = await _boot(server.api);
      // **Two** accepted writes: the enqueue, and the mark. Only the *clear*
      // is refused. With the default one the mark never lands, the record on
      // the disk is already «safe to send», and clearing it is correctly a
      // no-op — there is nothing stranded, which is a fact the app gets right
      // on its own. The stranding case needs the mark to be there first.
      final store = _GatedOutboxStore(accept: 2);

      await _typeThenBreakConnection(tester,
          server: server,
          auth: auth,
          unreadable: false,
          outbox: ChatOutbox(store: store));

      // It really is a normal failure now: the row never landed and the
      // re-read said so.
      expect(server.posts, 1);
      expect(server.rows, hasLength(1),
          reason: 'the Worker stored it, but the re-read must not see it, or '
              'this is the landed case and a different branch entirely');

      // And the stranding is real, not asserted in the abstract: the record on
      // the disk is still marked, so after a restart it comes back with no
      // retry affordance and the startup flush skips it.
      expect(store.stored().single.uncertain, SendState.unconfirmed,
          reason: 'the clear was refused, so the disk still says do-not-send '
              'for a message now known to be absent');

      // The plain «أعد المحاولة» is not enough on its own: the deadline is the
      // part that tells him not to close the app.
      expect(find.textContaining('قبل إغلاق التطبيق'), findsWidgets,
          reason: 'a refused clear strands the message on restart, so the '
              'retry has to be said as *now*');
    });

    testWidgets('a lost mark does not stop the message reaching the server',
        (tester) async {
      // The point of never unwinding: a storage failure must not become a lost
      // message. The words still go on the wire.
      final server = _buildServer();
      final auth = await _boot(server.api);

      await _typeThenBreakConnection(tester,
          server: server,
          auth: auth,
          unreadable: true,
          outbox: ChatOutbox(store: _GatedOutboxStore()));

      expect(server.posts, 1,
          reason: 'a refused mark is a storage failure, not a reason to drop '
              "the user's words");
      expect(server.rows.single['content'], _typed);
    });
  });
}
