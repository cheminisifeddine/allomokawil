// The regression this file pins, found by the live chat-image round trip:
// every photo the app uploaded arrived at the API labelled
// `application/octet-stream`. `MultipartFile.fromPath` defaults a part's media
// type when it is not told otherwise, and the Worker stores whatever the client
// declares on the R2 object — so the URL for a PNG served a binary blob, which
// makes a browser download the picture instead of showing it.
//
// This test does not go near the network: a loopback `HttpServer` receives the
// real multipart body, so what is asserted is the bytes that leave the device.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/network/api_client.dart';

void main() {
  late HttpServer server;
  late String base;
  late List<String> requests;

  setUp(() async {
    requests = <String>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    // latin1, not utf8: the body carries raw file bytes and must be readable
    // byte for byte without a decode error.
    server.listen((req) async {
      final body = await latin1.decodeStream(req);
      requests.add('${req.method} ${req.uri.path} '
          '${req.headers.contentType}\n$body');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"url":"$base/api/images/images/pinned.png"}');
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  Future<File> write(String name) async {
    final dir = await Directory.systemTemp.createTemp('om_upload_');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List<int>.generate(16, (i) => i));
    return file;
  }

  test('a PNG upload declares image/png on the wire', () async {
    final api = ApiClient(baseUrls: <String>[base]);
    final url = await api.uploadPhoto(await write('photo.png'));

    expect(url, '$base/api/images/images/pinned.png',
        reason: 'the upload must return the URL the server stored');
    expect(requests, hasLength(1));
    final sent = requests.single.toLowerCase();
    expect(sent, contains('post /api/upload'));
    expect(sent, contains('content-type: image/png'));
    expect(sent, contains('filename="photo.png"'));
    expect(sent, isNot(contains('octet-stream')),
        reason: 'a PNG sent as a binary blob is the bug this file exists for');
  });

  test('a JPEG upload declares image/jpeg on the wire', () async {
    final api = ApiClient(baseUrls: <String>[base]);
    await api.uploadPhoto(await write('IMG_2024.JPG'));
    expect(requests.single.toLowerCase(), contains('content-type: image/jpeg'),
        reason: 'the camera writes upper-case extensions');
  });

  test('the extension map covers what the pickers hand over', () {
    expect(photoMediaType('/tmp/a.png').mimeType, 'image/png');
    expect(photoMediaType('/tmp/a.jpeg').mimeType, 'image/jpeg');
    expect(photoMediaType('/tmp/a.webp').mimeType, 'image/webp');
    expect(photoMediaType('/tmp/a.gif').mimeType, 'image/gif');
    expect(photoMediaType('/tmp/a.heic').mimeType, 'image/heic');
    // No extension at all is not a photo — do not claim otherwise.
    expect(photoMediaType('/tmp/noextension').mimeType,
        'application/octet-stream');
  });
}
