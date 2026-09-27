// Sending a message must survive the user leaving the thread.
//
// `_sendText` writes the message to the device queue first (an `await` on
// SharedPreferences), and only then calls `setState` to draw the bubble. A user
// who taps back in that window — the single most common way to leave a chat —
// disposes the State while the write is still in flight, and the `setState`
// behind it lands on a dead widget. Flutter throws
// "setState() called after dispose()" in debug, which on a real phone is a red
// screen over the message the user just sent.
//
// The screen guards sixteen other post-await `setState` calls with `mounted`.
// These two send paths were the exceptions, and they are the two a user reaches
// in a single tap.
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

/// An outbox store that never answers until the test says so. This is the
/// whole trick: it holds the `await` inside `_enqueue` open for as long as the
/// test needs, which is exactly the window in which a real user taps back.
class _GatedStore implements OutboxStore {
  final gate = Completer<void>();
  Object? raw;
  int writes = 0;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async {
    await gate.future;
    raw = value;
    writes++;
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

ApiClient _api() {
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

void main() {
  testWidgets('tapping back while a send is being written down does not crash',
      (tester) async {
    final store = _GatedStore();
    final outbox = ChatOutbox(store: store);
    final api = _api();
    final auth = await _boot(api);
    final repo = Repository(api);

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
        // The thread sits behind a route the user can pop, which is the only
        // honest way to reproduce "he tapped back".
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

    // Open the thread and let it finish its first load.
    await tester.tap(find.text('افتح'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    await tester.enterText(find.byType(TextField).last, 'سلام');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // The write is now parked inside the gated store.
    await tester.pump(const Duration(milliseconds: 40));

    // He taps back while his own words are still being written down.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Let the write finish onto a disposed State. Before the fix this is where
    // Flutter throws "setState() called after dispose()".
    store.gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(tester.takeException(), isNull,
        reason: 'leaving the thread mid-send must not throw');
    expect(store.writes, 1,
        reason: 'the message must still reach the device queue');
  });
}
