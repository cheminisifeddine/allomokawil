// LIVE end-to-end proof for the backlog item "Chat image round-trip, live".
//
// The point of the item is that nothing short of the real thing counts: a
// bubble can render a URL that the server never stored and still look fine
// until a user on another phone opens the thread. So this file drives the app's
// own code path — `Repository.sendImage`, i.e. multipart `POST /api/upload`
// into R2 and then `POST /api/messages/:id` — and then asks the API, not the
// app, what it kept:
//
//   1. `GET /api/messages/:id` returns the same `image_url` that sendImage was
//      handed back by the upload, so the row the other party reads carries it;
//   2. that URL serves content byte-identical to what went up (status 200,
//      `image/png`, same length, same bytes), so R2 kept the picture and not an
//      error page or a truncated body;
//   3. the real `ChatScreen` builds a `NetworkImage` pointing at exactly that
//      URL — the claim in the item is about the bubble, and only the widget
//      tree can prove what the bubble asks for.
//
// The PNG is built byte by byte in `_pngBytes` (signature, IHDR, IDAT, IEND)
// rather than shipped as a fixture, so the bytes that come back are compared
// against bytes produced by the same encoder that runs here. `file(1)` reads
// the file it writes as `PNG image data, 64 x 64, 8-bit/color RGB`.
//
// Run with:  flutter test test/live_chat_image_e2e_test.dart
//
// It needs the network. A network-level failure here is not a code regression —
// the file names the call that failed and the loop reports it as such. Every
// run creates two real accounts and a few KB in R2, the same way
// `live_register_e2e_test.dart` already does.
// Tagged `live`: this file drives the REAL API, and a run registers real
// accounts on production. The default gate skips it — run it on demand with
// `flutter test --tags live --run-skipped live_chat_image_e2e_test.dart`.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/app_scope.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/core/security/auth_state.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/chat.dart';
import 'package:allomokawil/src/models/enums.dart';
import 'package:allomokawil/src/screens/chat/chat_screen.dart';

/// The customer-facing API host (not the workers.dev fallback), so the URL the
/// upload hands back is the one a real install produces.
const _live = 'https://allomokawil.colisify.com';

// ---------------------------------------------------------------------------
// A real PNG, generated in Dart
// ---------------------------------------------------------------------------

Uint8List _u32(int v) => Uint8List.fromList(
    <int>[(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _chunk(String type, List<int> data) {
  final body = <int>[...ascii.encode(type), ...data];
  return Uint8List.fromList(
      <int>[..._u32(data.length), ...body, ..._u32(_crc32(body))]);
}

/// A 64x64 8-bit RGB PNG. Every pixel is a function of its coordinates, so two
/// runs of this function never produce the same picture twice by accident and a
/// truncated upload cannot pass the byte comparison by luck.
Uint8List _pngBytes(int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter type 0 for this scanline
    for (var x = 0; x < w; x++) {
      raw.addByte((x * 4) & 0xff);
      raw.addByte((y * 4) & 0xff);
      raw.addByte(128);
    }
  }
  final ihdr = BytesBuilder()
    ..add(_u32(w))
    ..add(_u32(h))
    ..add(const <int>[8, 2, 0, 0, 0]); // bit depth 8, colour type 2 (RGB)
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, // PNG signature
    ..._chunk('IHDR', ihdr.takeBytes()),
    ..._chunk('IDAT', ZLibEncoder(level: 9).convert(raw.takeBytes())),
    ..._chunk('IEND', const <int>[]),
  ]);
}

/// A local, comparable digest — no `crypto` dependency, and short enough to
/// print in a failure message.
String _digest(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Two accounts on two devices: a project owner and a contractor, both created
/// through the same endpoints the app's own sign-up uses. `% 100000000` keeps
/// the padding honest — a shorter number would be correctly rejected.
String _freshPhone(String prefix) =>
    '$prefix${(DateTime.now().microsecondsSinceEpoch % 100000000).toString().padLeft(8, '0')}';

Future<AuthState> _signUpOwner(ApiClient api) async {
  final auth = AuthState(api);
  final phone = _freshPhone('06');
  await auth.register(
    phone: phone,
    email: '',
    fullName: 'صاحب مشروع (اختبار الصور)',
    password: 'secret123',
    role: UserRole.customer,
  );
  debugPrint('LIVE image round-trip: owner phone=$phone id=${auth.user?.id}');
  return auth;
}

/// The other side of the thread. Registered through the raw endpoint because
/// nothing in this test signs in as him — he only has to exist and be a worker.
Future<int> _signUpWorker(ApiClient api) async {
  final phone = _freshPhone('07');
  final res = await api.post('/api/register', body: <String, Object?>{
    'phone': phone,
    'email': '',
    'full_name': 'مقاول (اختبار الصور)',
    'password': 'secret123',
    'type': 'worker',
  }) as Map<String, dynamic>;
  final id = ((res['user'] as Map<String, dynamic>)['id'] as num).toInt();
  debugPrint('LIVE image round-trip: worker phone=$phone id=$id');
  return id;
}

/// Downloads the stored object the way any other client would: a plain
/// HttpClient, no app code, no auth — the URL has to be public to be usable in
/// a chat bubble.
Future<({int status, String type, Uint8List bytes})> _download(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final bytes = await res
        .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk));
    return (
      status: res.statusCode,
      type: res.headers.contentType?.mimeType ?? '',
      bytes: bytes.takeBytes(),
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  // `TestWidgetsFlutterBinding` installs an HttpOverrides that answers every
  // request with a failure — the app's own client must reach the real API here.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  /// The same 21-second drain `live_register_e2e_test.dart` uses: ApiClient
  /// guards every request with a 20s timeout timer, and a timer still pending
  /// when the body ends is reported as a test failure.
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 21));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('LIVE: an image sent through the app is the image the API serves back',
      () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final api = ApiClient(baseUrls: const <String>[_live]);
    final repo = Repository(api);
    final auth = await _signUpOwner(api);
    final workerId =
        await _signUpWorker(ApiClient(baseUrls: const <String>[_live]));
    expect(auth.isAuthenticated, isTrue,
        reason: 'sign-up must store a session');

    // The picture that will travel. Written to disk because that is what the
    // app uploads: `MultipartFile.fromPath`, a real file.
    final local = _pngBytes(64, 64);
    final dir = await Directory.systemTemp.createTemp('om_img_rt_');
    final file = File('${dir.path}/round_trip.png');
    await file.writeAsBytes(local, flush: true);
    debugPrint('LIVE image round-trip: local ${local.length} bytes '
        'digest=${_digest(local)} path=${file.path}');

    // 1. The app's own send path.
    final convId = await repo.openConversation(otherUserId: workerId);
    final sent = await repo.sendImage(convId, file);
    debugPrint('LIVE image round-trip: conversation=$convId message=${sent.id} '
        'type=${sent.type.name} url=${sent.imageUrl}');

    expect(sent.type, MessageType.image);
    expect(sent.imageUrl, isNotNull);
    expect(sent.imageUrl, startsWith('$_live/api/images/'));
    expect(sent.content, isNull);

    // 2. What the server kept, read back the way the recipient's app reads it.
    final thread = await repo.messages(convId);
    final stored = thread.where((m) => m.id == sent.id).toList();
    expect(stored, hasLength(1),
        reason:
            'the sent image must be one row in the thread, not zero or two');
    expect(stored.single.imageUrl, sent.imageUrl,
        reason: 'the thread must carry the URL the upload produced, not a copy '
            'the app invented');
    expect(stored.single.type, MessageType.image);

    // 3. The stored URL serves the very bytes that went up.
    final got = await _download(stored.single.imageUrl!);
    debugPrint('LIVE image round-trip: GET ${got.status} ${got.type} '
        '${got.bytes.length} bytes digest=${_digest(got.bytes)}');
    expect(got.status, 200);
    expect(got.type, 'image/png',
        reason: 'R2 must hand back the content type the upload declared, or '
            'the bubble decodes as nothing');
    expect(got.bytes.length, local.length);
    expect(got.bytes, orderedEquals(local),
        reason: 'the stored object must be the uploaded file byte for byte');

    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('LIVE: the chat bubble renders the URL the server stored',
      (tester) async {
    HttpOverrides.global = null;
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    final api = ApiClient(baseUrls: const <String>[_live]);
    final repo = Repository(api);
    final auth = await tester.runAsync(() => _signUpOwner(api));
    final workerId = await tester.runAsync(
        () => _signUpWorker(ApiClient(baseUrls: const <String>[_live])));

    final local = _pngBytes(64, 64);
    // dart:io futures do not complete inside the fake-async zone, so the file
    // is written in runAsync alongside the calls that upload it.
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('om_img_ui_')))!;
    final file = File('${dir.path}/thread.png');
    await tester.runAsync(() => file.writeAsBytes(local, flush: true));

    // One image in the thread before the screen mounts, so the assertion is
    // about a row that came from the server, not from this device's queue.
    final result = await tester.runAsync(() async {
      final convId = await repo.openConversation(otherUserId: workerId!);
      final sent = await repo.sendImage(convId, file);
      return (convId: convId, url: sent.imageUrl!);
    });
    final convId = result!.convId;
    final serverUrl = result.url;
    debugPrint('LIVE bubble: conversation=$convId server url=$serverUrl');

    await tester.pumpWidget(
      AppScope(
        api: api,
        auth: auth!,
        child: MaterialApp(
          home: Scaffold(
            body: ChatScreen(
              conversationId: convId,
              otherUserId: workerId!,
              otherName: 'مقاول (اختبار الصور)',
              repo: repo,
            ),
          ),
        ),
      ),
    );

    // Real time has to pass for the thread request to land; `pumpAndSettle`
    // cannot help, the thread's skeleton animates forever.
    var rendered = <String>{};
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 150));
      rendered = tester
          .widgetList<Image>(find.byType(Image))
          .map((w) => w.image)
          .whereType<NetworkImage>()
          .map((p) => p.url)
          .toSet();
      if (rendered.isNotEmpty) break;
    }
    debugPrint('LIVE bubble: rendered image URLs=$rendered');

    expect(rendered, isNotEmpty,
        reason: 'the thread never built an Image at all — the screen was still '
            'loading, so nothing about the bubble is proven');
    expect(rendered, contains(serverUrl),
        reason: 'the bubble must ask for the URL the server stored');

    // The bytes at that URL are the uploaded ones — the same check a second
    // device performs when it opens the thread.
    final got = await tester.runAsync(() => _download(serverUrl));
    expect(got!.status, 200);
    expect(got.bytes, orderedEquals(local));

    await tester.runAsync(() => dir.delete(recursive: true));
    await drain(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
