// The screen-level proof that a photo the server never stored is not deleted.
//
// The predicate tests in `chat_photo_identity_test.dart` pin the rule. This file
// drives the **real `ChatScreen`** with a real `Repository`, a real `ChatOutbox`
// on an in-memory store and a real PNG on disk, and checks the two things a
// user would lose.
//
// The scenario, exactly as it happens on a 3G connection in Algiers: the user
// picks a picture, the upload succeeds and the server hands back an R2 URL, and
// then the POST that would have created the message row never gets an answer.
// The app cannot know whether the row is there, so it re-reads the thread.
//
// Before the fix that re-read compared `content == content` — null on both sides
// — and returned "yes, it is there". The screen then called `_forget`, and the
// queue record was **gone**: the picture was not retried, not redrawn, and no
// sentence anywhere said it had not been sent. The user was left looking at a
// delivered message he had never actually sent, with nothing on the device left
// to send.
//
// The decoy matters: the thread already holds a *different* image from the same
// person, sent earlier. Under the old comparison that row was indistinguishable
// from his lost picture, so the test would have passed for the wrong reason
// had it not been there.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// A 1x1 PNG, so the bubble has a real file to draw and the upload has real
/// bytes to read. Built here rather than shipped as a fixture.
Uint8List _pngBytes() => Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
      0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

/// The server the app is talking to, with a picture already in the thread.
class _Thread {
  /// The rows the Worker holds. Starts with one image from the same person —
  /// the decoy that the old comparison could not tell from our lost picture.
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    {
      'id': 401,
      'conversation_id': 5,
      'sender_id': 30,
      'content': null,
      'image_url': 'https://r2.test/uploads/earlier.jpg',
      'message_type': 'image',
      'is_read': 1,
      'created_at': '2026-09-11 19:00:00',
    }
  ];

  /// Every message POST that reached the server.
  int posts = 0;

  /// The URL the upload handed back — the same opaque key every time, so the
  /// comparison in the test is a real one and not an accident of the harness.
  static const String uploadedUrl = 'https://r2.test/uploads/mine.jpg';

  /// How many uploads the app made.
  int uploads = 0;

  /// Whether the message POST is stored before its answer is lost. False — the
  /// default — is the dangerous case: the picture is on the phone and nowhere
  /// else, and the app has to say so instead of deleting it.
  bool storeTheRow = false;

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
    if (p.endsWith('/api/upload')) {
      thread.uploads++;
      return _json({'url': _Thread.uploadedUrl});
    }
    if (p.startsWith('/api/messages/')) {
      if (req.method == 'GET') return _json(thread.rows);
      thread.posts++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (thread.storeTheRow) {
        thread.rows.add({
          'id': 900 + thread.rows.length,
          'conversation_id': 5,
          'sender_id': 30,
          'content': body['content'],
          'image_url': body['image_url'],
          'message_type': body['message_type'],
          'is_read': 0,
          'created_at': '2026-09-11 20:0${thread.rows.length}:00',
        });
      }
      // Stored — and then the connection dies before the answer comes back. The
      // only shape in which the app must not guess.
      throw http.ClientException('Connection closed before full header body',
          req.url);
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

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// The queue the screen is given, held in memory so the test can read what
/// survived.
class _InspectableStore implements OutboxStore {
  Object? raw;

  @override
  Future<Object?> read() async => raw;

  @override
  Future<void> write(String value) async => raw = value;
}

/// The real screen, the real repository, the real queue — everything but the
/// transport, which is the seam under test.
Future<void> _pumpChat(WidgetTester tester, _Thread thread, AuthState auth,
    ChatOutbox outbox) async {
  tester.view.physicalSize = const Size(1080, 3400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    api: thread.api,
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
        repo: Repository(thread.api),
        outbox: outbox,
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  // The picture is written on the real filesystem, outside FakeAsync: the
  // bubble only needs the file to exist, and real I/O inside a widget test
  // never completes. The file is *not* read by this test — the decision under
  // test is whether the record survives, which happens before any upload.
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat_photo');
    file = File('${dir.path}/shot.png');
    await file.writeAsBytes(_pngBytes(), flush: true);
  });
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets(
      'an unconfirmed photo the thread does not hold is redrawn, not deleted',
      (tester) async {
    final thread = _buildServer();
    final auth = await _boot(thread.api);
    final outbox = ChatOutbox(store: _InspectableStore());

    // The state a cold start finds after the answer to a picture was lost: the
    // record is on the disk, marked «do not send me again», carrying the URL the
    // upload returned. No upload is in flight, so that URL can never be learned
    // again — it is the only identity this picture will ever have.
    final record = await outbox.add(
        conversationId: 5, imagePath: file.path, uncertain: SendState.unconfirmed);
    await outbox.noteUploadedUrl(record.id, _Thread.uploadedUrl);

    await _pumpChat(tester, thread, auth, outbox);

    // THE ASSERTION. The thread holds one image from the same person — the
    // decoy. The old comparison was `content == content`, null on both sides,
    // so that decoy "proved" this picture had arrived and the record was
    // deleted: the picture became unsendable, and no sentence said so.
    final queue = await outbox.pendingFor(5);
    expect(queue, hasLength(1),
        reason: 'the thread holds earlier.jpg, not mine.jpg; the picture is '
            'not on the server and its record must survive');
    expect(queue.single.uploadedUrl, _Thread.uploadedUrl);
    // Twice on purpose: the permanent line under the bubble and the banner over
    // the composer. Both must exist, and neither may offer a blind re-send.
    expect(find.textContaining('لم يتأكّد'), findsWidgets,
        reason: 'the user must be told the outcome is unknown, which is the '
            'only true thing the app can say about it');
    expect(find.textContaining('أعد المحاولة'), findsNothing,
        reason: 'a bubble whose outcome is unknown must not be told to be '
            'pressed: pressing it is the duplicate');
  });

  testWidgets(
      'an unconfirmed photo the server DID hold is settled and forgotten',
      (tester) async {
    final thread = _buildServer();
    // The Worker really does hold this picture: a second row with our URL.
    thread.rows.add({
      'id': 777,
      'conversation_id': 5,
      'sender_id': 30,
      'content': null,
      'image_url': _Thread.uploadedUrl,
      'message_type': 'image',
      'is_read': 1,
      'created_at': '2026-09-11 19:30:00',
    });
    final auth = await _boot(thread.api);
    final outbox = ChatOutbox(store: _InspectableStore());

    final record = await outbox.add(
        conversationId: 5, imagePath: file.path, uncertain: SendState.unconfirmed);
    await outbox.noteUploadedUrl(record.id, _Thread.uploadedUrl);

    await _pumpChat(tester, thread, auth, outbox);

    // The fix must not swing into a duplicate: a picture that really is on the
    // server has to be recognised, so nothing is re-sent on the next launch.
    expect(await outbox.pendingFor(5), isEmpty,
        reason: 'the row is on the server, so the record must be dropped');
    expect(thread.posts, 0, reason: 'an unconfirmed record is never re-sent');
  });
}
