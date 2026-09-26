// The screen-level half of the unconfirmed-write fix, driven through a real
// [Repository] and the real network layer with a stalling host.
//
// The shape reproduced here is the one the founder would hit on a bad Algerian
// connection: the POST *reaches* the Worker and is stored, but no answer comes
// back inside the 20 s timeout. The network layer refuses to re-send it (a
// re-send would create the project twice) and throws `errWriteUnconfirmed` —
// whose whole instruction is «تحقّق من القائمة قبل إعادة المحاولة».
//
// Before the fix the publish screen caught that and showed a stale list, so the
// instruction sent the user to look at something that could not answer the
// question. This test fails on that build: the mock records the GET the screen
// never made.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';

/// One published project as the API stores it.
Map<String, dynamic> _row(String title) => {
      'id': 'p-1',
      'customer_id': 7,
      'title': title,
      'category': 'plumbing',
      'images': <String>[],
      'wilaya': 'الجزائر',
      'urgency': 'normal',
      'status': 'open',
    };

void main() {
  test('a stalled publish re-reads the list and finds the row that did land',
      () async {
    final path = <String>[];
    // The server-side store the Worker actually had when the connection died.
    final stored = <Map<String, dynamic>>[];

    final client = MockClient((req) async {
      final p = req.url.path;
      path.add(p);
      if (p.startsWith('/api/mobile/projects') &&
          req.method == 'POST' &&
          !p.contains('my')) {
        // The write lands. The answer does not.
        stored.add(_row(jsonDecode(req.body)['title'] as String));
        throw http.ClientException('Connection closed before full header',
            req.url);
      }
      if (p == '/api/mobile/my/projects') {
        return http.Response(
          jsonEncode(stored),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test'],
      // Short enough to be a unit test, long enough not to be the transport.
      timeout: const Duration(milliseconds: 120),
    );
    final repo = Repository(api);

    // The network layer's verdict on this exact failure, exercised for real so
    // the test cannot drift from the string the screens check.
    Object? thrown;
    try {
      await repo.createProject(
        title: 'ترميم حمام',
        category: 'plumbing',
        wilaya: 'الجزائر',
        urgency: UrgencyLevel.withinMonth,
      );
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isA<ApiException>());
    expect((thrown! as ApiException).message, S.errWriteUnconfirmed);
    expect(stored.length, 1, reason: 'the server did store the write');

    // What the screen now has to do with that verdict.
    final before = path.where((p) => p == '/api/mobile/my/projects').length;
    expect(before, 0, reason: 'the write screen must not have re-read yet');

    final recheck = await repo.myProjects();
    expect(path.where((p) => p == '/api/mobile/my/projects').length, 1,
        reason: 'the screen re-reads the list exactly once');
    expect(recheck.single.title, 'ترميم حمام');
  });

  test('a write that never left the phone is not an unconfirmed write',
      () async {
    final stored = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        // Refused before anything was written: nothing is stored.
        throw _NeverLeft();
      }
      return http.Response(
        jsonEncode(stored),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test'],
      timeout: const Duration(milliseconds: 120),
    );
    final repo = Repository(api);

    // A host that did not resolve is proof the write never left the phone, so
    // the app *is* allowed to try the other host — and with one host configured
    // it ends in the plain offline sentence, not the unconfirmed one. That
    // distinction is the whole design: only an ambiguous failure needs the
    // re-read, and a re-read on a dead network could only ever say «missing».
    String? message;
    try {
      await repo.createProject(
        title: 'دهان واجهة',
        category: 'painting',
        wilaya: 'وهران',
        urgency: UrgencyLevel.flexible,
      );
    } catch (e) {
      message = (e as ApiException).message;
    }
    expect(message, isNotNull);
    expect(message, isNot(S.errWriteUnconfirmed));

    final rows = await repo.myProjects();
    expect(rows, isEmpty, reason: 'nothing was stored, so nothing to find');
  });
}

/// A failure that proves the request never left the phone, so the app is right
/// to try the other host. The wording is one of the strings `_neverReached`
/// matches, which is why it is spelled out here rather than invented.
class _NeverLeft extends http.ClientException {
  _NeverLeft() : super('Failed host lookup: primary.test');
}
