// A bounded queue must not eat a message in silence.
//
// The outbox exists because this app was once the one that ate messages: a
// failed send lived only inside the open thread, so tap back and the words were
// gone with nothing on the phone, nothing on the server, and no screen that said
// so. `chat_outbox.dart` closed that hole — a record is written *before* the
// first attempt and survives the thread and a cold start.
//
// Then the bound quietly reopened it. `chatOutboxMax` is 60, and `add()` did
// `while (items.length > chatOutboxMax) items.removeAt(0);` — the oldest
// record deleted, with no return value, no log the user sees, and no word
// anywhere on screen. Sixty refused sends is an account problem, not a queue
// problem, so the bound is right; deleting the user's own words because of it is
// not. The line that goes first is very often the line that matters:
// «العنوان: حسين داي». A client whose connection stays dead through the 61st
// message loses his address and never finds out, which is the exact failure the
// outbox was written to prevent — reproduced quietly, one bound higher up.
//
// The fix does not raise the bound (a preferences blob must stay bounded) and it
// does not refuse to write (that would be a send that never happens, worse than
// one that is reported). It *reports*: `add()` hands back the record it had to
// drop, and the thread says which message is gone so it can be retyped.
//
// The unit test below fails on the build before the fix — `lastDropped` did not
// exist, so a dropped record was unobservable at all — and the widget test fails
// because nothing on screen ever said the word «حُذفت».
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

// ── Fixtures ──────────────────────────────────────

final _me = <String, Object?>{
  'id': 30,
  'phone': '0773000000',
  'email': null,
  'full_name': '\u0632\u0628\u0648\u0646 \u062a\u062c\u0631\u0628\u0629',
  'type': 'customer',
  'avatar_url': null,
  'wilaya': '16',
  'commune': null,
  'created_at': '2026-09-11 20:00:00',
};

http.Response _json(Object body) => http.Response(
      jsonEncode(body), 200, headers: {'content-type': 'application/json'});

// ── Harness ──────────────────────────────────────────

class _Fake {
  _Fake(this.api);
  final ApiClient api;
  int posts = 0;
  bool failSend = false;
}

_Fake _buildFake({List<Map<String, Object?>> thread = const []}) {
  late final _Fake fake;
  final client = MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.endsWith('/api/mobile/conversations')) return _json(<Object>[]);
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') return _json(thread);
      fake.posts++;
      if (fake.failSend) {
        return http.Response('{}', 500,
            headers: {'content-type': 'application/json'});
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return _json({
        'id': 900 + fake.posts,
        'conversation_id': 5,
        'sender_id': 30,
        'content': body['content'],
        'image_url': body['image_url'],
        'message_type': body['message_type'] ?? 'text',
        'is_read': 0,
        'created_at': '2026-09-11 21:00:00',
      });
    }
    return _json(<Object>[]);
  });
  return fake = _Fake(ApiClient(baseUrls: ['https://x.test'], httpClient: client));
}

Future<AuthState> _boot(ApiClient api) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.restore();
  await auth.login(phone: '0773000000', password: 'secret123', rememberMe: true);
  expect(auth.role.name, 'customer', reason: 'the fixture must land on a client');
  return auth;
}

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, ApiClient api,
    AuthState auth) async {
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
      home: screen,
    ),
  ));
  await _settle(tester);
}

void main() {
  group('the queue bound must not delete a message quietly', () {
    test('add() reports the record the bound pushed off the end', () async {
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      final first = await outbox.add(conversationId: 5, text: 'العنوان: حسين داي');
      expect(outbox.lastDropped, isNull,
          reason: 'nothing is dropped while the queue is under the bound');

      for (var i = 0; i < chatOutboxMax - 1; i++) {
        await outbox.add(conversationId: 5, text: 'رسالة $i');
      }
      expect(outbox.lastDropped, isNull,
          reason: 'the bound is a ceiling, not a quota: the record that fills it '
              'must still be reported as kept');

      // This one is the 61st, and it is the one that costs the oldest record.
      await outbox.add(conversationId: 5, text: 'الطابق الثالث، بجانب الصيدلية');

      expect(outbox.lastDropped, isNotNull,
          reason: 'a record the bound deletes must be reported, not swallowed');
      expect(outbox.lastDropped!.id, first.id);
      expect(outbox.lastDropped!.text, 'العنوان: حسين داي',
          reason: 'the oldest record is the one that goes');
      expect(await outbox.pendingFor(5), hasLength(chatOutboxMax),
          reason: 'the bound still holds: this is about honesty, not about '
              'letting the queue grow');
    });

    test('the copy names the message that is gone', () {
      final text = droppedMessageCopy(PendingMessage(
        id: '5.1.0',
        conversationId: 5,
        text: 'العنوان: حسين داي، الطابق الثالث',
        createdAt: DateTime.now(),
      ));
      expect(text, contains('حُذفت'), reason: 'the user is told a message went');
      expect(text, contains('العنوان: حسين داي'),
          reason: 'he must be able to see WHICH line was lost, or he cannot '
              'retype it');
    });

    test('a dropped photo is described as a photo, not as empty quotes', () {
      final copy = droppedMessageCopy(PendingMessage(
        id: '5.2.0',
        conversationId: 5,
        imagePath: '/tmp/facade.jpg',
        createdAt: DateTime.now(),
      ));
      expect(copy, contains('صورة'));
      expect(copy, isNot(contains('«»')),
          reason: 'an empty quote is a bug the user would read as a real '
              'message with no text');
    });

    test('a long line is clipped so the toast does not swallow the thread', () {
      final copy = droppedMessageCopy(PendingMessage(
        id: '5.3.0',
        conversationId: 5,
        text: 'عنوان طويل جدا ' * 20,
        createdAt: DateTime.now(),
      ));
      expect(copy.length, lessThan(140),
          reason: 'a toast is not a place for a paragraph');
      expect(copy, contains('…'));
    });
  });

  testWidgets('the thread says which queued message the bound deleted',
      (tester) async {
    // The queue as the app would read it back from the device, one message
    // short of the bound so the next send crosses it and costs a record.
    final rows = <Map<String, Object?>>[
      for (var i = 0; i < chatOutboxMax; i++)
        {
          'id': '5.$i.0',
          'conversation_id': 5,
          'text': i == 0 ? 'العنوان: حسين داي' : 'رسالة $i',
          'created_at': 1700000000000 + i,
        }
    ];
    final fake = _buildFake();
    final auth = await _boot(fake.api);
    // Every send is refused, so nothing drains the queue behind our back.
    fake.failSend = true;
    // Seeded *after* the boot: signing in resets the mock store, so a queue
    // written before it is gone by the time the thread opens. The real store is
    // used deliberately — the screen builds its own outbox over these bytes.
    await const PrefsOutboxStore().write(_encode(rows));

    await _pump(
      tester,
      ChatScreen(
        conversationId: 5,
        otherUserId: 31,
        repo: Repository(fake.api),
      ),
      fake.api,
      auth,
    );
    await _settle(tester);

    // The queue is confirmed from the device rather than from a bubble: the
    // thread is a lazy list, so the oldest record is not built into the tree —
    // which is precisely why its disappearance needs a word of its own.
    final queued = await ChatOutbox().pendingFor(5);
    expect(queued, hasLength(chatOutboxMax));
    expect(queued.first.text, 'العنوان: حسين داي',
        reason: 'the record about to be deleted is the one that matters');

    // The 61st message. It crosses the bound, so the address line above is
    // dropped from the device at this moment.
    await tester.enterText(find.byType(TextField), 'الطابق الثالث');
    await tester.tap(find.byIcon(Icons.send_rounded));

    // The composer re-sends every queued message first, and there are sixty of
    // them, so the new record is written only after all of those fail. The
    // toast is watched rather than waited for: a SnackBar dismisses itself after
    // four seconds, so by the time the 61st send lands the earlier frames are
    // long gone, and a check after the loop would find an empty screen on a
    // build that did say it.
    var seen = <String>[];
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      for (final w in find.byType(SnackBar).evaluate()) {
        final text = (w.widget as SnackBar).content;
        if (text is Text) seen.add((text.data ?? '').toString());
      }
    }

    expect(seen.where((t) => t.contains('حُذفت')), isNotEmpty,
        reason: 'a message was deleted from this device and the user was never '
            'told; the thread must name it');
    expect(seen.where((t) => t.contains('العنوان: حسين داي')), isNotEmpty,
        reason: 'the toast must name WHICH line is gone, or it cannot be '
            'retyped');

    // And the device agrees: the address is off the queue, the new send is on.
    final after = await ChatOutbox().pendingFor(5);
    expect(after, hasLength(chatOutboxMax));
    expect(after.first.text, isNot('العنوان: حسين داي'));
    expect(after.last.text, 'الطابق الثالث');
  });
}

String _encode(List<Map<String, Object?>> rows) =>
    '[${rows.map((r) => '{"id":"${r['id']}",'
            '"conversation_id":${r['conversation_id']},'
            '"text":"${r['text']}",'
            '"created_at":${r['created_at']}}').join(',')}]';
