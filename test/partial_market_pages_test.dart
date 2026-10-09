// A search that silently kept only the pages that answered is reporting
// results it does not have.
//
// `Repository.browseProjects` is documented as «if *every* page fails the
// caller still gets the real error instead of a silently empty market». That
// promise is kept for a page that *throws*, and broken for the case that
// actually happens in the field: page 5 of 5 exists only when the platform
// has 81+ open projects. A young marketplace has fewer, so the tail pages
// legitimately answer `[]` — and an empty page is not a failure, so the
// "did every page fail?" check passes and the search silently narrows to
// however many pages happened to be alive. A contractor searching «دهان» sees
// "no results" because 4 of 5 pages never arrived, and the app has no way to
// say so.
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

/// A project row exactly as D1 files it.
Map<String, Object?> _project(String id, String title) => {
      'id': id,
      'customer_id': 30,
      'title': title,
      'description': 'عمل كامل',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'commune': 'حسين داي',
      'latitude': null,
      'longitude': null,
      'budget_min': 60000,
      'budget_max': 90000,
      'urgency': 'within_week',
      'status': 'open',
      'selected_worker_id': null,
      'created_at': '2026-09-11 20:23:44',
      'updated_at': '2026-09-11 20:23:44',
    };


void main() {
  group('browseProjectsPaged carries the loss to the screen', () {
    test('the count arrives, so the screen can refuse a verdict', () async {
      // The defect this closes. `browseProjects` recorded the lost pages to
      // `CrashReporter` — a place only support reads the morning after — and
      // returned a bare list, so the widget that prints «لا نتائج مطابقة» had
      // no way to know it was reading a partial market. Two pages die here and
      // three answer; the result has to carry "2 of 5" or the honest thing the
      // log does has still reached nobody who can act on it.
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 2 || page == 4) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final result = await repo.browseProjectsPaged(pages: 5);

      expect(result.lostPages, 2, reason: 'two pages never answered');
      expect(result.requestedPages, 5);
      expect(result.mayClaimNoResults, isFalse,
          reason: 'the app may not say "nothing matches" over 2 lost pages');
      // The rows still arrive — the loss is additional information, never a
      // reason to throw away a market the contractor can still read.
      expect(result.rows.map((p) => p.id), ['p1', 'p3', 'p5']);
    });

    test('a complete read reports no loss and may claim the verdict', () async {
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          // Page 5 is past the end of the market and answers `[]`. That is a
          // real answer, not a loss — a young marketplace must not be told it
          // could not read a page that correctly had nothing in it.
          if (page >= 5) return _json(<Object>[]);
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final result = await repo.browseProjectsPaged(pages: 5);

      expect(result.lostPages, 0);
      expect(result.mayClaimNoResults, isTrue);
    });

    test('a single-page read is a complete read', () async {
      final repo = Repository(ApiClient(
        httpClient: MockClient((_) async =>
            _json([_project('p1', 'مشروع واحد')])),
        baseUrls: ['https://x.test'],
      ));

      final result = await repo.browseProjectsPaged();

      expect(result.lostPages, 0);
      expect(result.requestedPages, 1);
      expect(result.rows.length, 1);
    });

    test('browseProjects keeps returning rows, unchanged', () async {
      // Six other screens call this and none of them widen. The plain method's
      // contract must not have moved underneath them.
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 3) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);
      expect(rows.map((p) => p.id), ['p1', 'p2', 'p4', 'p5']);
    });
  });
}
