// A message the server refused must not be able to disappear.
//
// The thread used to be the only place a failed send existed: a list in memory
// inside the open ChatScreen. Tap back, or let Android kill the app in the
// background, and the words were gone — nothing on the phone, nothing on the
// server, and not one screen in the app that said so. The user believes the
// contractor has his address; the contractor never heard of him.
//
// This file pins the outbox that closes that hole:
//   1. a send is written down *before* the first attempt, so it survives the
//      thread closing and a cold start;
//   2. a queued message is drawn as failed (with its retry line) on the next
//      open, is sent automatically when the network is back, and leaves the
//      queue only after the server confirms the row;
//   3. an unreadable queue degrades to "nothing queued" instead of throwing;
//   4. a thread that cannot be fetched still shows the queued message and the
//      composer instead of an error page that hides both;
//   5. the inbox marks the conversations that are still owed messages, because
//      that is the last screen where the user can notice.
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
import 'package:allomokawil/src/screens/chat/chat_list_screen.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

// ── Fixtures ───────────────────────────────────────────────────────────────

String _utcStamp(DateTime local) {
  final t = local.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, Object?> _conversationRow({
  int id = 5,
  String name = 'مقاول تجربة',
  int unread = 0,
  String? last = 'مرحبا، متى نبدأ؟',
}) =>
    {
      'id': id,
      'customer_id': 30,
      'worker_user_id': 31,
      'project_id': null,
      'other_user_name': name,
      'other_user_avatar': null,
      'last_message_content': last,
      'unread_count': unread,
      'last_message_at': null,
    };

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

// ── Harness ────────────────────────────────────────────────────────────────

class _Fake {
  _Fake(this.api);
  final ApiClient api;

  /// How many message POSTs reached the server.
  int posts = 0;
  bool failSend = false;
  bool offline = false;
}

_Fake _buildFake({
  List<Map<String, Object?>> thread = const [],
  List<Map<String, Object?>> conversations = const [],
}) {
  late final _Fake fake;
  final client = MockClient((req) async {
    if (fake.offline) throw http.ClientException('no route to host');
    final p = req.url.path;
    if (p.endsWith('/api/login') || p.endsWith('/api/register')) {
      return _json({'token': 'tok', 'user': _me});
    }
    if (p.endsWith('/api/unread')) return _json(0);
    if (p.endsWith('/api/mobile/conversations')) {
      return req.method == 'POST' ? _json({'id': 5}) : _json(conversations);
    }
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
        'created_at': _utcStamp(DateTime.now()),
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

/// Paints the widget under [key] with the real engine and writes a PNG, so a
/// claim about what the user sees is backed by pixels and not by reading code.
Future<String> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
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

/// The queue as the app would read it back from the device.
Future<List<PendingMessage>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return decodeOutbox(prefs.getString(chatOutboxKey));
}

const String _typed = 'العنوان: حسين داي، الطابق الثالث';
const String _retryLine = 'لم تُرسل — أعد المحاولة';

void main() {
  group('the outbox queue', () {
    test('round-trips a message through the store', () async {
      final store = MemoryOutboxStore();
      final outbox = ChatOutbox(store: store);
      final record = await outbox.add(conversationId: 5, text: 'العنوان: حسين داي');

      final readBack = await outbox.pendingFor(5);
      expect(readBack.single.id, record.id);
      expect(readBack.single.text, 'العنوان: حسين داي');
      // Millisecond precision by design: the stored stamp is epoch millis, so a
      // sub-millisecond tick is not expected to survive the write.
      expect(readBack.single.createdAt.millisecondsSinceEpoch,
          record.createdAt.millisecondsSinceEpoch);
      expect(await outbox.pendingFor(7), isEmpty,
          reason: 'another thread owes nothing');

      // The same bytes the next cold start would read.
      final decoded = decodeOutbox(store.raw);
      expect(decoded.single.text, 'العنوان: حسين داي');
      expect(decoded.single.conversationId, 5);
    });

    test('a corrupt queue degrades to empty, never throws', () {
      expect(decodeOutbox(null), isEmpty);
      expect(decodeOutbox(''), isEmpty);
      expect(decodeOutbox('{not json at all'), isEmpty);
      expect(decodeOutbox('{"a":1}'), isEmpty);

      // A broken row beside a good one costs only the broken row.
      final raw = jsonEncode(<Object>[
        {'id': 'a', 'conversation_id': 5, 'created_at': 1, 'text': 'مرحبا'},
        {'id': 'b', 'conversation_id': 'five', 'created_at': 1, 'text': 'x'},
        {'id': 'c', 'conversation_id': 5, 'created_at': 1, 'text': ''},
        {'id': 'd', 'conversation_id': 5, 'text': 'no stamp'},
        {'conversation_id': 5, 'created_at': 1, 'text': 'no id'},
      ]);
      expect(decodeOutbox(raw).map((m) => m.id).toList(), <String>['a']);
    });

    test('holds sixty messages and drops the oldest past that', () async {
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      for (var i = 0; i < chatOutboxMax + 5; i++) {
        await outbox.add(conversationId: 5, text: 'رسالة $i');
      }
      final pending = await outbox.pendingFor(5);
      expect(pending.length, chatOutboxMax);
      expect(pending.first.text, 'رسالة 5');
      expect(pending.last.text, 'رسالة ${chatOutboxMax + 4}');
    });

    test('forgets exactly the message the server stored', () async {
      final outbox = ChatOutbox(store: MemoryOutboxStore());
      final first = await outbox.add(conversationId: 5, text: 'أ');
      final second = await outbox.add(conversationId: 6, text: 'ب');

      await outbox.remove(first.id);
      expect(await outbox.pendingFor(5), isEmpty);
      expect((await outbox.pendingFor(6)).single.id, second.id);
      expect(await outbox.countsByConversation(), <int, int>{6: 1});

      await outbox.clear();
      expect(await outbox.all(), isEmpty);
    });

    test('two messages written in the same microsecond get different ids',
        () async {
      final frozen = DateTime(2026, 9, 13, 10, 30);
      final outbox =
          ChatOutbox(store: MemoryOutboxStore(), clock: () => frozen);
      final first = await outbox.add(conversationId: 5, text: 'أ');
      final second = await outbox.add(conversationId: 5, text: 'ب');
      expect(first.id, isNot(second.id));
      expect(first.createdAt, frozen);
      expect((await outbox.pendingFor(5)).length, 2);
    });

    test('counts a queue the way Arabic counts', () {
      expect(queuedCountLabel(0), '');
      expect(queuedCountLabel(1), 'لم تُرسل بعد');
      expect(queuedCountLabel(2), 'رسالتان لم تُرسلا');
      expect(queuedCountLabel(5), '5 رسائل لم تُرسل');
      expect(queuedCountLabel(10), '10 رسائل لم تُرسل');
      expect(queuedCountLabel(11), '11 رسالة لم تُرسل');
    });
  });

  group('a message the server refuses', () {
    testWidgets('is on the device before the attempt is even made',
        (tester) async {
      final fake = _buildFake();
      final auth = await _boot(fake.api);
      fake.failSend = true;

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
      await tester.enterText(find.byType(TextField), _typed);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);

      // On screen it is exactly what it was before this change: the words plus
      // the line that says they have not left.
      expect(find.text(_typed), findsOneWidget);
      expect(find.text(_retryLine), findsOneWidget);

      // And now it is also on the phone.
      final stored = await _stored();
      expect(stored.single.text, _typed);
      expect(stored.single.conversationId, 5);
      expect(fake.posts, 1);
    });

    testWidgets('is still there after the thread is closed and reopened, then '
        'sends itself once the network is back', (tester) async {
      final fake = _buildFake();
      final auth = await _boot(fake.api);
      fake.failSend = true;

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
      await tester.enterText(find.byType(TextField), _typed);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _settle(tester);
      expect(await _stored(), hasLength(1));

      // The user leaves the thread: the screen is disposed, its memory is gone.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Next morning, with the network back.
      fake.failSend = false;
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

      expect(find.text(_typed), findsOneWidget,
          reason: 'the words come back with the queue, not the server');
      expect(find.text(_retryLine), findsNothing,
          reason: 'the automatic retry succeeded, so the line is gone');
      expect(await _stored(), isEmpty,
          reason: 'the server has the row, so the phone owes nothing');
      expect(fake.posts, 2);
    });
  });

  group('a thread that cannot be fetched', () {
    testWidgets('still shows the queued message and the composer',
        (tester) async {
      final fake = _buildFake();
      final auth = await _boot(fake.api);

      // Written yesterday on a connection that died; never confirmed.
      await ChatOutbox().add(conversationId: 5, text: _typed);
      fake.offline = true;

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

      expect(find.text(_typed), findsOneWidget);
      expect(find.text(_retryLine), findsOneWidget);
      expect(find.text('لا يوجد اتصال — ستُرسل رسائلك المحفوظة عند عودة الشبكة'),
          findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget,
          reason: 'a user with no connection must still be able to write');
      expect(find.text('تعذّر جلب الرسائل'), findsNothing,
          reason: 'the error page would hide the message he already wrote');
    });

    testWidgets('falls back to the error page when there is nothing queued',
        (tester) async {
      final fake = _buildFake();
      final auth = await _boot(fake.api);
      fake.offline = true;

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

      expect(find.text('تعذّر جلب الرسائل'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('the rendered queued state', () {
    testWidgets('paints the offline strip, the count and the inbox badge',
        (tester) async {
      final fake = _buildFake(conversations: [_conversationRow(id: 5)]);
      final auth = await _boot(fake.api);
      final outbox = ChatOutbox();
      await outbox.add(conversationId: 5, text: _typed);
      await outbox.add(conversationId: 5, text: 'الطابق الثالث، بجانب الصيدلية');
      fake.offline = true;

      final threadKey = GlobalKey();
      await _pump(
        tester,
        ChatScreen(
          conversationId: 5,
          otherUserId: 31,
          otherName: 'مقاول تجربة',
          repo: Repository(fake.api),
          outbox: outbox,
        ),
        fake.api,
        auth,
        boundary: threadKey,
      );
      final thread = await _shot(tester, threadKey, 'chat_queued_offline');
      // ignore: avoid_print
      print('SHOT $thread');

      // Back online for the inbox: the badge is what is under test here, and the
      // list itself must render as a real conversation row.
      fake.offline = false;
      final inboxKey = GlobalKey();
      await _pump(
        tester,
        ChatListScreen(repo: Repository(fake.api), outbox: outbox),
        fake.api,
        auth,
        boundary: inboxKey,
      );
      expect(find.byTooltip('رسالتان لم تُرسلا'), findsOneWidget,
          reason: 'the badge must be on screen for the shot to mean anything');
      final inbox = await _shot(tester, inboxKey, 'inbox_queued');
      // ignore: avoid_print
      print('SHOT $inbox');
    });
  });

  group('the inbox', () {
    testWidgets('marks the conversations that still owe a message',
        (tester) async {
      final fake = _buildFake(conversations: [_conversationRow(id: 5)]);
      final auth = await _boot(fake.api);
      final outbox = ChatOutbox();
      await outbox.add(conversationId: 5, text: 'أ');
      await outbox.add(conversationId: 5, text: 'ب');

      await _pump(
        tester,
        ChatListScreen(repo: Repository(fake.api), outbox: outbox),
        fake.api,
        auth,
      );

      expect(find.byTooltip('رسالتان لم تُرسلا'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('marks nothing when the phone owes nothing', (tester) async {
      final fake = _buildFake(conversations: [_conversationRow(id: 5)]);
      final auth = await _boot(fake.api);

      await _pump(
        tester,
        ChatListScreen(repo: Repository(fake.api)),
        fake.api,
        auth,
      );

      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });
}
