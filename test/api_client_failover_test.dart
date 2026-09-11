import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';

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
}
