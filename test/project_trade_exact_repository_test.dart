// The market's trade filter has to be wired, not merely written.
//
// `project_trade_exact.dart` is a rule and rules rot: a helper nobody calls is
// the exact hole `rows_partial_test.dart` and the census sweeps exist to keep
// shut. These tests drive `Repository.browseProjects` over a real `MockClient`
// and feed it the **verbatim** body `GET /api/mobile/projects?category=wallpaper`
// answered with on 4 Oct 2026 — seventeen rows, sixteen of them painters.
//
// Pre-fix this file answers 17 and prints painters under «ورق جدران».
//
// The two shapes matter and are both covered below: `pages: 1` (the plain read)
// and `pages: 5` (the search widen, which merges five pages through a
// different code path) must both narrow, or the widening a contractor does on
// his first keystroke would undo the filter he tapped.
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

/// One row of that live answer: the trades are the ones the server sent.
Map<String, Object?> _row(String id, String cat, List<String> cats) => {
      'id': id,
      'customer_id': 1,
      'title': 'مشروع $id',
      'category': cat,
      'categories': cats,
      'wilaya': '16',
      'urgency': 'within_week',
      'status': 'open',
    };

/// The seventeen rows of `category=wallpaper`, verbatim.
const _liveWallpaperAnswer = <Map<String, Object?>>[
  {'id': '961072ac', 'cat': 'painting', 't': ['painting']},
  {'id': '3d918ee7', 'cat': 'painting', 't': ['painting']},
  {
    'id': '3a915d88',
    'cat': 'plumbing',
    't': ['plumbing', 'electrical', 'painting']
  },
  {'id': '32fa3e1f', 'cat': 'painting', 't': ['painting', 'plumbing']},
  {'id': 'bf2a66f3', 'cat': 'painting', 't': ['painting']},
  {'id': '2d94081c', 'cat': 'painting', 't': ['painting']},
  {'id': '21fb59cf', 'cat': 'painting', 't': ['painting']},
  {'id': '2a929f52', 'cat': 'painting', 't': ['painting']},
  {
    'id': '25ef91d0',
    'cat': 'construction',
    't': ['construction', 'renovation', 'plaster_drywall', 'painting']
  },
  {'id': '90dc9045', 'cat': 'painting', 't': ['painting', 'electrical']},
  {
    'id': '8cee95af',
    'cat': 'general_finishing',
    't': [
      'general_finishing',
      'painting',
      'renovation',
      'construction',
      'plumbing',
      'carpentry_aluminum'
    ]
  },
  {'id': '5700e663', 'cat': 'painting', 't': ['painting']},
  {'id': 'b5e739eb', 'cat': 'painting', 't': ['painting']},
  {'id': 'b37a6feb', 'cat': 'painting', 't': ['painting']},
  {'id': '70a8c03b', 'cat': 'painting', 't': ['painting']},
  {'id': 'proj_006', 'cat': 'wallpaper', 't': ['wallpaper']},
  {'id': 'proj_005', 'cat': 'painting', 't': ['painting']},
];

List<Map<String, Object?>> _body() => _liveWallpaperAnswer
    .map((r) => _row(r['id']! as String, r['cat']! as String,
        (r['t']! as List).cast<String>()))
    .toList();

Repository _repo(Future<http.Response> Function(http.Request) h) =>
    Repository(ApiClient(httpClient: MockClient(h), baseUrls: ['https://x.test']));

void main() {
  test('browseProjects(category: wallpaper) drops the sixteen painters',
      () async {
    final repo = _repo((req) async => _json(_body()));
    final rows = await repo.browseProjects(category: 'wallpaper');
    expect(rows.map((p) => p.id).toList(), ['proj_006']);
    // The count the market used to draw, written down as a measurement.
    expect(_body().length, 17);
  });

  test('the search widen narrows too, or the filter undoes itself', () async {
    // `pages: 5` is the path a contractor's first keystroke takes. It merges
    // five pages and de-duplicates by id; if the filter were applied only in
    // the single-page read, the widen would re-fill the market with painters
    // the moment he typed anything.
    final repo = _repo((req) async => _json(_body()));
    final rows = await repo.browseProjects(category: 'wallpaper', pages: 5);
    expect(rows.map((p) => p.id).toList(), ['proj_006']);
  });

  test('browseProjects(category: null) hands back every row the server sent',
      () async {
    final repo = _repo((req) async => _json(_body()));
    final rows = await repo.browseProjects();
    expect(rows.length, 17);
  });

  test('a category with no live project answers empty, not every row',
      () async {
    // `hvac_heating` answered 0 live rows on 4 Oct. The app must not "help" by
    // falling back to the unfiltered market — the screen already says
    // «لا نتائج مطابقة» with a «مسح البحث والفلاتر» button, which is the truth.
    final repo = _repo((req) async => _json(_body()));
    expect(await repo.browseProjects(category: 'hvac_heating'), isEmpty);
  });

  test('the request still carries the category, and server order survives',
      () async {
    final asked = <Uri>[];
    final repo = _repo((req) async {
      asked.add(req.url);
      return _json(_body());
    });
    final rows = await repo.browseProjects(category: 'painting');
    // The app narrows what the server returned; it does not stop asking — the
    // filter is the server's job too, and a narrower question returns a
    // narrower page on a large market.
    expect(asked.single.queryParameters['category'], 'painting');
    expect(rows.length, 16);
    // Survivors keep the server's relative order: the two painters that were
    // asked for by name stay in the order the server sent them.
    expect(rows.first.id, '961072ac');
    expect(rows.last.id, 'proj_005');
  });
}
