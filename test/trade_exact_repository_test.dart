// The trade filter has to be wired, not merely written.
//
// `trade_exact.dart` is a rule and rules rot: a helper nobody calls is the
// exact hole `rows_partial_test.dart` and the census sweeps exist to keep shut
// (a Dart file no sweep reaches was found on 4 Oct). These tests drive
// `Repository.searchWorkers` over a real `MockClient` and feed it the
// **verbatim** body `GET /api/mobile/workers/search?category=wallpaper`
// answered with on 4 Oct 2026 — nine rows, six of which are painters.
//
// Pre-fix this file answers 9 and prints painters under «ورق جدران».
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';

http.Response _json(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

/// One row of that live answer. The trades are the ones the server sent.
Map<String, Object?> _row(int id, String name, List<String> trades) => {
      'id': id,
      'user_id': id * 10,
      'full_name': name,
      'specialties': trades,
      'experience_years': 5,
      'is_available': 1,
      'verification_status': 'pending',
      'avg_rating': 0,
      'total_reviews': 0,
      'total_completed_jobs': 0,
    };

const _liveWallpaperAnswer = <Map<String, Object?>>[
  {'id': 5, 'name': 'رشيد خليفي', 't': ['painting']},
  {'id': 2, 'name': 'خالد رحماني', 't': ['painting', 'wallpaper', 'tiling_marble']},
  {'id': 7, 'name': 'مراد حميدي', 't': ['tiling_marble', 'painting']},
  {'id': 8, 'name': 'فريد زروالي', 't': ['wallpaper', 'painting']},
  {'id': 68, 'name': 'E2E اختبار', 't': ['painting']},
  {'id': 71, 'name': 'E2E اختبار', 't': ['painting']},
  {'id': 25, 'name': 'best worker', 't': ['painting', 'carpentry_aluminum', 'wallpaper']},
  {'id': 121, 'name': 'كريم بن سالم', 't': ['painting', 'plumbing']},
  {'id': 124, 'name': 'حرفي 1200', 't': ['painting']},
];

List<Map<String, Object?>> _body() => _liveWallpaperAnswer
    .map((r) => _row(r['id']! as int, r['name']! as String, (r['t']! as List).cast<String>()))
    .toList();

Repository _repo(Future<http.Response> Function(http.Request) h) =>
    Repository(ApiClient(httpClient: MockClient(h), baseUrls: ['https://x.test']));

void main() {
  test('searchWorkers(category: wallpaper) drops the six painters', () async {
    final repo = _repo((req) async => _json(_body()));
    final rows = await repo.searchWorkers(category: 'wallpaper');
    expect(rows.map((w) => w.id).toList(), [2, 8, 25]);
    // The count the directory used to draw, written down as a measurement.
    expect(_body().length, 9);
  });

  test('searchWorkers(category: null) hands back every row the server sent',
      () async {
    // The unfiltered directory must keep the untyped rows: 74 of 91 live rows
    // carry no trades at all, and filtering them away would hide most of the
    // marketplace from the client who has not tapped anything.
    final repo = _repo((req) async => _json(_body()));
    final rows = await repo.searchWorkers();
    expect(rows.length, 9);
  });

  test('a category with no live professional answers empty, not every row',
      () async {
    // 6 of the 16 trades in the taxonomy have nobody signed up. The server
    // answers 0 for those already; this asserts the app does not "help" by
    // falling back to the unfiltered list.
    final repo = _repo((req) async => _json(_body()));
    expect(await repo.searchWorkers(category: 'hvac_heating'), isEmpty);
  });

  test('the request itself still carries the category, and order survives',
      () async {
    final asked = <Uri>[];
    final repo = _repo((req) async {
      asked.add(req.url);
      return _json(_body());
    });
    final rows = await repo.searchWorkers(category: 'wallpaper');
    // The app narrows what the server returned; it does not stop asking —
    // the filter is the server's job too, and a narrower question returns a
    // narrower page on a large marketplace.
    expect(asked.single.queryParameters['category'], 'wallpaper');
    // Survivors keep the server's relative order (2 before 8 before 25).
    expect(rows.map((w) => w.fullName).toList(),
        ['خالد رحماني', 'فريد زروالي', 'best worker']);
  });
}
