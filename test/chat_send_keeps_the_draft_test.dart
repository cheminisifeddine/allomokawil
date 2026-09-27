// Sending must not lose a message, in any order.
//
// Three defects shared the composer's send — and all three are reachable in a
// single gesture, «tap send, tap back», which is exactly what a man does after
// typing his address into the chat. Tapping back is the most ordinary way to
// end a conversation, so the window between «he pressed send» and «the screen
// is gone» is not an edge case; it is the normal one.
//
//  1. `_sendText` built the bubble with `_localBubble` *after* an await. That
//     call asks the session who the user is, and that is a `context` lookup —
//     on a State he has already left, it throws "This widget has been unmounted".
//
//  2. The retries ran *before* the queue write, so a throw anywhere in them
//     unwound the method and the message he was sending right then was never
//     written down at all. A crash that ate a second message on top of the red
//     screen.
//
//  3. `_retryUnsent` — the loop over everything the server refused — called
//     `setState` with no `mounted` check. It is the one `setState` in the file
//     without one, and it is the one most likely to land on a dead State.
//
// The last tick fixed two `setState`s on this path. These are the same gesture
// reaching the same method, and what it left behind.

import 'dart:async';
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
import 'package:allomokawil/src/data/chat_outbox.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

/// Holds the `await` inside the outbox write open for as long as the test
/// needs. That window is the whole subject here: it is the interval in which a
/// user taps back, and in which the words are neither on screen nor on disk.
class _GatedStore implements OutboxStore {
  final gate = Completer<void>();
  Object? raw;

  /// Every value handed to the store, in order. The first one is the interesting
  /// one: it is the send being written down, and the last is usually the record
  /// being forgotten once the server confirms — so counting writes proves
  /// nothing on its own.
  final List<String> written = <String>[];

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    await gate.future;
    raw = value;
    written.add(value);
  }
}

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

String _json(Object? body) => jsonEncode(body);

/// [refusePost] answers every send with a refusal, which is what puts a bubble
/// into [SendState.failed] — the state `_retryUnsent` exists to clear.
///
/// [hold] is a one-slot box the test fills with a `Completer` *after* the thread
/// has opened. The retry loop's crash lives *between* two attempts, so an
/// attempt has to still be on the wire when he taps back; a mock that answers
/// instantly finishes the whole loop inside one frame and the pop never lands
/// in the window. Arming it later matters too: the thread's own open-time flush
/// must run to completion, or the bubbles are still mid-send when he types.
ApiClient _api({bool refusePost = false, List<Completer<void>?>? hold}) {
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return http.Response(_json({'token': 'tok', 'user': _me}), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.endsWith('/api/unread')) {
      return http.Response(_json(0), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.endsWith('/api/mobile/conversations')) {
      return http.Response(_json({'id': 5}), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') {
        return http.Response(_json(<Object>[]), 200,
            headers: {'content-type': 'application/json'});
      }
      await hold?.first?.future;
      if (refusePost) {
        // 400 is a settled refusal, not an unknown outcome: the server answered
        // and said no, so the bubble is `failed` and the queue keeps it.
        return http.Response(_json({'error': 'مرفوض'}), 400,
            headers: {'content-type': 'application/json'});
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          _json({
            'id': 900,
            'conversation_id': 5,
            'sender_id': 30,
            'content': body['content'],
            'image_url': body['image_url'],
            'message_type': 'text',
            'is_read': 0,
            'created_at': '2026-09-27 10:00:00',
          }),
          200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 404,
        headers: {'content-type': 'application/json'});
  });
  return ApiClient(baseUrls: ['https://x.test'], httpClient: client);
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  return auth;
}

/// Mounts the thread behind a route the user can pop — the only honest way to
/// reproduce «he tapped back».
Future<ChatOutbox> _openThread(
  WidgetTester tester, {
  required ApiClient api,
  required AuthState auth,
  required Repository repo,
  required ChatOutbox outbox,
}) async {
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatScreen(
                    conversationId: 5,
                    otherUserId: 31,
                    otherName: 'مقاول',
                    repo: repo,
                    outbox: outbox,
                  ),
                ),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.tap(find.text('افتح'));
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
  return outbox;
}

Future<void> _pump(WidgetTester tester, [int times = 8]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {

  // Defect 1 — the composer was emptied before the durable write.
  testWidgets('the draft stays in the composer until the write has landed',
      (tester) async {
    final store = _GatedStore();
    final outbox = ChatOutbox(store: store);
    final api = _api();
    final auth = await _boot(api);
    await _openThread(
        tester, api: api, auth: auth, repo: Repository(api), outbox: outbox);

    await tester.enterText(find.byType(TextField).last, 'العنوان: حسين داي');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 40));

    // The write is parked. The queue has nothing yet, so the *only* copy of
    // his address in the entire app is the composer — and before the fix it
    // had already been emptied, one line above the write. Android killing the
    // app in exactly this window, or the write failing, therefore lost the
    // message outright: not on disk, not on screen, not recoverable.
    expect(store.written, isEmpty, reason: 'the write is still in flight');
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'العنوان: حسين داي',
      reason: 'the draft must survive until the queue has taken it',
    );

    store.gate.complete();
    await _pump(tester, 10);

    // The first write must be the one carrying his address: that write is what
    // makes the words durable, and it happens while the composer still holds
    // them. A later write forgetting the record is correct — the server has it
    // — and must not be confused with this one.
    expect(decodeOutbox(store.written.first).map((m) => m.text).toList(),
        contains('العنوان: حسين داي'),
        reason: 'the first durable write must carry the message');
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
      reason: 'and the composer is cleared once the words are safe',
    );
    // The mock accepted the send, so the record was correctly forgotten again.
    // Asserting it is still queued would pin the opposite of the right thing:
    // what matters is that the words were durable *before* the composer was
    // emptied, which is the previous assertion.
    expect(await outbox.pendingFor(5), isEmpty,
        reason: 'the server stored it, so the queue owes nothing');
  });

  // Defects 2 and 3 — one gesture, both of them.
  testWidgets('tapping back while refused messages are re-sending does not crash',
      (tester) async {
    final store = MemoryOutboxStore();
    final outbox = ChatOutbox(store: store);
    // Two messages the server already refused, so the thread opens holding
    // retryable bubbles and `_sendText` takes the `_retryUnsent` branch. Two,
    // because the unguarded setState is the *second* iteration's — the loop
    // draws one bubble as «sending», waits on the network, then draws the next
    // one onto whatever State is left.
    await outbox.add(conversationId: 5, text: 'العنوان: حسين داي');
    await outbox.add(conversationId: 5, text: 'السعر؟');

    final hold = <Completer<void>?>[null];
    final api = _api(refusePost: true, hold: hold);
    final auth = await _boot(api);
    await _openThread(
        tester, api: api, auth: auth, repo: Repository(api), outbox: outbox);

    // The thread is in exactly the state a user reaches after a morning on a
    // bad connection: bubbles he has already re-tried and that failed again.
    expect(find.text('لم تُرسل — أعد المحاولة'), findsWidgets,
        reason: 'the thread really is holding refused messages');

    // Now park the sends. From here his next send puts an attempt on the wire
    // and leaves it there.
    final gate = Completer<void>();
    hold[0] = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });

    await tester.enterText(find.byType(TextField).last, 'مستعجل');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 40));

    // He taps back while his own send is still working through the refused
    // bubbles — the ordinary gesture, immediately after sending.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await _pump(tester, 5);

    // The parked attempt now answers, onto a State that is gone.
    gate.complete();
    await _pump(tester, 10);

    // Before the fix this is where Flutter throws "setState() called after
    // dispose()" out of `_retryUnsent` — and the throw unwinds `_sendText`
    // itself, so the message he was sending never reaches the queue at all.
    expect(tester.takeException(), isNull,
        reason: 'leaving the thread mid-retry must not throw');

    final kept = (await outbox.pendingFor(5)).map((m) => m.text).toList();
    expect(kept, contains('مستعجل'),
        reason: 'the message he was sending must still reach the queue — the '
            'crash used to abort the send that was in progress');
  });
}
