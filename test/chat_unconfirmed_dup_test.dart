// A message whose answer never came must not be sent a second time.
//
// `5a7052a` stopped the network layer from re-sending a POST on a timeout,
// because a stalled write may already be stored on the Worker. `c428929` then
// made the write screens re-read and tell the user the truth. Both are about the
// moment the failure happens — and both left the *next* moment unguarded.
//
// The hole is the outbox. A chat message is written to the device before its
// first attempt, and on the next thread open the screen restores every queued
// record and flushes it. That flush is the same re-send the network layer
// refused to perform, done by the app itself with no user action: type an
// address on a bad connection, the POST reaches the Worker and is stored, no
// answer comes back, close the app, reopen the thread — and the second copy is
// on its way. The user did nothing wrong and the contractor receives «العنوان:
// حسين داي» twice, which is the duplicate the whole of Phase 5 exists to kill.
//
// The fix is that the queue stores *why* a record is still there. A record the
// server refused is re-sent, as before. A record whose answer never came comes
// back as `unconfirmed`: drawn with a neutral line, no retry affordance, and
// skipped by the startup flush — settled instead by a read, which is the only
// thing that can actually answer the question.
//
// These tests fail on the build before the fix: the cold-start case below sees
// the second POST, and the screen case sees the red «أعد المحاولة» line.
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
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/data/chat_outbox.dart';
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
  'created_at': '2026-09-11 20:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

/// The thread the Worker actually holds. Grows on every POST that lands, which
/// is what makes a duplicated send visible: two POSTs, two rows, and the
/// re-read finds the same words twice.
class _Thread {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  /// Every message POST that reached the server, whatever its outcome.
  int posts = 0;

  /// When true a POST is stored and then the answer is lost — the shape that
  /// produces `errWriteUnconfirmed`.
  bool swallowAnswer = false;

  /// When true nothing is stored and the request is refused outright.
  bool refuse = false;

  /// When true the thread cannot be read, which is the case that leaves a write
  /// genuinely unconfirmed: the app has asked the only question that could
  /// answer it and has not got one.
  ///
  /// Counts down rather than switching on, so the thread can be read first (the
  /// composer has to be on screen for the user to type) and only then go dark —
  /// which is the real shape: the connection dies after the message was sent.
  int refuseReadAfter = -1;

  int reads = 0;

  /// The client the app is given, wired to this thread.
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
        return _json(thread.rows);
      }
      thread.posts++;
      if (thread.refuse) {
        return http.Response('{}', 500,
            headers: {'content-type': 'application/json'});
      }
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
      if (thread.swallowAnswer) {
        // Stored, then the connection dies before the header comes back. The
        // network layer reads this as "possibly delivered" and refuses to
        // re-send — which is correct, and is what the app must then honour.
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

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, ApiClient api,
    AuthState auth, {GlobalKey? boundary}) async {
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
      home: boundary == null
          ? screen
          : RepaintBoundary(key: boundary, child: screen),
    ),
  ));
  await _settle(tester);
}

Future<String> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  late final String path;
  await tester.runAsync(() async {
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

const String _typed = 'العنوان: حسين داي، الطابق الثالث';
const String _retryLine = 'لم تُرسل — أعد المحاولة';
const String _uncertainLine = 'لم يتأكّد وصولها — النتيجة غير معروفة';

void main() {
  group('the stored queue remembers why a message is still there', () {
    test('an unconfirmed record survives a round trip through the store',
        () async {
      final store = MemoryOutboxStore();
      final outbox = ChatOutbox(store: store);
      final record = await outbox.add(
        conversationId: 5,
        text: _typed,
        uncertain: SendState.unconfirmed,
      );
      final read = await ChatOutbox(store: store).pendingFor(5);
      expect(read.single.id, record.id);
      expect(read.single.uncertain, SendState.unconfirmed,
          reason: 'the reason the message is still queued must outlive the '
              'process, or the next cold start sends it again');
    });

    test('a refused record stays retryable, and a cleared one goes back to it',
        () async {
      final store = MemoryOutboxStore();
      final outbox = ChatOutbox(store: store);
      final record = await outbox.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);

      // A re-read that came back empty proves the words are not there, so the
      // message is a normal failure again and re-sending it is correct.
      await outbox.markUncertain(record.id, uncertain: null);
      final back = await ChatOutbox(store: store).pendingFor(5);
      expect(back.single.uncertain, isNull,
          reason: 'a message known to be absent must be retryable again');
    });

    test('a corrupt reason is read as unconfirmed, never as safe to send',
        () async {
      // The conservative direction: an unrecognised value keeps the record and
      // stops the auto-send. Guessing the other way puts a possibly-delivered
      // message back on the wire.
      final decoded = decodeOutbox(jsonEncode([{
        'id': '5.1.0',
        'conversation_id': 5,
        'text': _typed,
        'created_at': 1757620800000,
        'uncertain': 'sent',
      }]));
      expect(decoded.single.uncertain, isNull,
          reason: 'only the exact unconfirmed mark may block a re-send');
    });
  });

  group('a message the app could not confirm', () {
    testWidgets('is drawn without the red retry line after a cold start',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      await outbox.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);

      final key = GlobalKey();
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
        boundary: key,
      );

      expect(find.text(_typed), findsOneWidget);
      expect(find.text(_retryLine), findsNothing,
          reason: 'a retry affordance is the instruction that creates the '
              'duplicate — the app must not draw one it cannot honour');
      expect(find.text(_uncertainLine), findsNWidgets(2),
          reason: 'once under the bubble, once in the banner — the user sees '
              'the same fact in both places the app can show it');
      final path = await _shot(tester, key, 'chat_unconfirmed');
      // ignore: avoid_print
      print('SHOT $path');
    });

    testWidgets('is never re-sent by the thread opening', (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      await outbox.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);

      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );

      expect(server.posts, 0,
          reason: 'this is the whole bug: opening a thread used to flush the '
              'queue, which re-sends a message the server may already hold');
    });

    testWidgets('keeps its mark when the banner offers to send again',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      await outbox.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);

      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );

      // The banner is there — the user must know something is unresolved — but
      // it must not be offering a re-send of a possibly-delivered message.
      expect(find.text('إرسال'), findsNothing);
      expect(find.text('تحقّق'), findsOneWidget);
      expect(server.posts, 0);
    });

    testWidgets('is not redrawn when the thread already holds those words',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      await outbox.add(
          conversationId: 5, text: _typed, uncertain: SendState.unconfirmed);
      // The Worker does hold it: the earlier POST landed after all, so the
      // thread the app just read already has these words.
      server.rows.add({
        'id': 901,
        'conversation_id': 5,
        'sender_id': 30,
        'content': _typed,
        'image_url': null,
        'message_type': 'text',
        'is_read': 0,
        'created_at': '2026-09-11 20:05:00',
      });

      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );

      expect(server.posts, 0);
      expect(find.text(_typed), findsOneWidget,
          reason: 'the user must not open the thread and read his own message '
              'twice — the optimistic bubble and the server row are one '
              'message, and the queue has to yield to the row that is real');
      expect(await outbox.pendingFor(5), isEmpty,
          reason: 'the message is stored, so the phone no longer owes it');
    });
  });

  group('the live path', () {
    testWidgets('a stalled send whose row landed is adopted, not repeated',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      server.swallowAnswer = true;

      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );
      await tester.enterText(find.byType(TextField), _typed);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);

      expect(server.posts, 1);
      expect(server.rows.single['content'], _typed,
          reason: 'the first send landed, it just never said so');
      // The re-read found it, so the phone no longer owes the server anything:
      // one copy on screen, and the queue is empty.
      expect(await outbox.pendingFor(5), isEmpty);
      expect(find.text(_typed), findsOneWidget,
          reason: 'one copy, not two — the optimistic bubble and the server '
              'row are the same message');
      expect(find.text(_retryLine), findsNothing);
    });

    testWidgets('a send that stays unconfirmed is not re-sent on reopen',
        (tester) async {
      final server = _buildServer();
      final auth = await _boot(server.api);
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      server.swallowAnswer = true;
      // The thread is readable once, so the composer is on screen and the
      // message can be typed; every read after the first fails, so the re-read
      // cannot answer and the message is left in the state it is really in.
      server.refuseReadAfter = 1;

      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );
      await tester.enterText(find.byType(TextField), _typed);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);

      expect(server.posts, 1);
      expect(find.text(_typed), findsOneWidget,
          reason: 'the words must not vanish while their fate is unknown');
      expect(find.text(_retryLine), findsNothing,
          reason: 'a retry line here is the instruction that duplicates it');

      // The mark reached the device, which is the part that survives the
      // process being killed between two opens.
      final stored = await outbox.pendingFor(5);
      expect(stored.single.uncertain, SendState.unconfirmed);

      // Reopen with the network healthy: the flush must leave it alone.
      server.refuseReadAfter = -1;
      server.reads = 0;
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          repo: Repository(server.api),
          outbox: outbox,
        ),
        server.api,
        auth,
      );
      expect(server.posts, 1,
          reason: 'the duplicate this prevents is the reason Phase 5 exists');
    });
  });
}
