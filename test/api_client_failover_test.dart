import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/l10n/strings.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';

/// Regression tests for the Algerian-network fix: the app must survive a DNS
/// failure on one host by failing over to the other, and it must never surface
/// a raw SocketException to the user.
void main() {
  test('fails over to the secondary host when the primary cannot resolve',
      () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add(req.url.host);
      if (req.url.host == 'primary.test') {
        throw SocketException('Failed host lookup: primary.test');
      }
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
    );

    final res = await api.get('/api/ping');

    expect(res, {'ok': true});
    expect(hits, ['primary.test', 'backup.test']);
    // The healthy host is remembered for subsequent calls.
    expect(api.baseUrl, 'https://backup.test');
  });

  test('turns an unreachable backend into a friendly ApiException', () async {
    final client = MockClient((req) async {
      throw SocketException('Failed host lookup: nope.test');
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://a.test', 'https://b.test'],
    );

    await expectLater(api.get('/api/ping'), throwsA(isA<ApiException>()));
  });

  test('does not retry on a clean HTTP error response', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add(req.url.host);
      return http.Response(jsonEncode({'error': 'بيانات خاطئة'}), 401,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
    );

    await expectLater(api.get('/api/ping'), throwsA(isA<ApiException>()));
    expect(hits, ['primary.test']);
  });

  // ---- Write safety: one tap must never create two rows -------------------
  //
  // Both configured hosts answer from the same Worker, so failing a *write*
  // over is not a retry of a request that failed — it is a second copy of a
  // request that may already have succeeded. These four tests pin the rule:
  // a POST moves to the other host only when the failure proves nothing was
  // delivered, and the user is told the outcome is unknown otherwise.

  test('a write that timed out on the primary is never re-sent', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add('${req.method} ${req.url.host}');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.Response(jsonEncode({'id': 42}), 201,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
      timeout: const Duration(milliseconds: 25),
    );

    await expectLater(
      api.post('/api/mobile/projects', body: {'title': 'ترميم حمام'}),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', S.errWriteUnconfirmed)),
    );
    // The whole point: one request, on one host — the backup never saw it.
    expect(hits, ['POST primary.test']);
  });

  test('a write whose host does not resolve still fails over', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add('${req.method} ${req.url.host}');
      if (req.url.host == 'primary.test') {
        throw SocketException('Failed host lookup: primary.test');
      }
      return http.Response(jsonEncode({'id': 7}), 201,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
      timeout: const Duration(milliseconds: 200),
    );

    final res = await api.post('/api/mobile/projects', body: {'title': 'دهان'});
    expect(res, {'id': 7});
    expect(hits, ['POST primary.test', 'POST backup.test']);
  });

  test('a refused connection is a write that was never delivered', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add('${req.method} ${req.url.host}');
      if (req.url.host == 'primary.test') {
        throw SocketException('Connection refused', osError: OSError('refused'));
      }
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
      timeout: const Duration(milliseconds: 200),
    );

    expect(await api.post('/api/ping', body: const {}), {'ok': true});
    expect(hits, ['POST primary.test', 'POST backup.test']);
  });

  test('a read still fails over on a timeout', () async {
    final hits = <String>[];
    final client = MockClient((req) async {
      hits.add('${req.method} ${req.url.host}');
      if (req.url.host == 'primary.test') {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'content-type': 'application/json'});
    });

    final api = ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
      timeout: const Duration(milliseconds: 25),
    );

    expect(await api.get('/api/ping'), {'ok': true});
    expect(hits, ['GET primary.test', 'GET backup.test']);
  });

  test('the app\'s own publish path posts exactly once when the host stalls',
      () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url}');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.Response(jsonEncode({'id': 1}), 201,
          headers: {'content-type': 'application/json'});
    });

    final repo = Repository(ApiClient(
      httpClient: client,
      baseUrls: ['https://primary.test', 'https://backup.test'],
      timeout: const Duration(milliseconds: 25),
    ));

    await expectLater(
      repo.createProject(
        title: 'بناء فيلا',
        category: 'بناء',
        urgency: UrgencyLevel.withinMonth,
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', S.errWriteUnconfirmed)),
    );
    expect(calls, hasLength(1));
    expect(calls.single, startsWith('POST '));
  });
}
