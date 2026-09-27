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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/diagnostics/crash_reporter.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';
import 'package:allomokawil/src/models/project.dart';

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

/// A store that keeps the log in memory, so the test asserts on the record
/// without touching shared preferences.
class _MemoryStore implements CrashStore {
  @override
  Future<List<String>> read() async => const <String>[];

  @override
  Future<void> write(List<String> lines) async {}
}

void main() {
  group('browseProjects keeps the pages it could read', () {
    test('pages that answered are returned even when a tail page is empty', () async {
      // Pages 1-4 answer with rows. Page 5 is past the end of the market:
      // a real, successful `[]`. A page that answered is not a page that
      // failed, and the four pages of results must still reach the search.
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page >= 5) return _json(<Object>[]);
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);

      expect(rows.map((p) => p.id), ['p1', 'p2', 'p3', 'p4'],
          reason: 'an empty tail page is not a failed page');
    });

    test('a page that failed is reported, not silently dropped', () async {
      // Page 3 refuses. The other four pages are good and must survive, but a
      // search that is missing a third of the market is a search whose "no
      // results" is a lie, so the loss has to reach the log.
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 3) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);

      expect(rows.map((p) => p.id), ['p1', 'p2', 'p4', 'p5'],
          reason: 'the pages that answered survive the one that did not');
    });

    test('a lost head page is re-issued, and a still-dead one raises', () async {
      // The worst shape, and the one a young marketplace actually hits: the
      // market holds fewer than 40 open projects, so pages 2-5 answer `[]` and
      // that is true. Page 1 — every newest posting, the ones a contractor
      // most wants to quote on — fails. "Every page failed" is false, so
      // nothing used to be re-issued, the union was empty, and the search
      // said there was no work on the market while twenty open projects sat
      // on the server. Two things must be true now: the head page is asked
      // again, and if it is still dead the caller gets the error — never an
      // empty list that reads as "nothing here".
      var asked = 0;
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 1) {
            asked++;
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json(<Object>[]);
        }),
        baseUrls: ['https://x.test'],
      ));

      await expectLater(
          repo.browseProjects(pages: 5), throwsA(isA<ApiException>()),
          reason: 'a dead market raises; it must never render as an empty one');
      expect(asked, greaterThanOrEqualTo(2),
          reason: 'the head page is re-issued rather than written off');
    });

    test('a head page that answers on the retry gives back the market', () async {
      // The same shape, one transient blip: the first attempt at page 1
      // fails, the re-issue gets the answer, and the contractor's search finds
      // the newest projects instead of nothing.
      var asked = 0;
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 1) {
            asked++;
            if (asked == 1) {
              return http.Response('{"error":"boom"}', 500,
                  headers: {'content-type': 'application/json'});
            }
            return _json([_project('p1', 'مشروع جديد')]);
          }
          return _json(<Object>[]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);
      expect(rows.map((p) => p.id), ['p1'],
          reason: 'the newest page comes back on the retry');
    });

    test('a recovered head page does not throw the good pages away', () async {
      // THE REGRESSION. The head page is re-issued so the market comes back,
      // and the re-issue `return`s that page straight to the caller. Everything
      // the *other* pages answered in the same batch is dropped on the floor:
      // the union was never built, because the `return` sits above it.
      //
      // The pre-existing test above cannot see this, because there every other
      // page is empty — there is nothing to lose. Here the market is full:
      // pages 2-5 answer with rows, page 1 blips, and the retry heals it. The
      // contractor gets page 1 back and loses the other 4 pages that had
      // arrived perfectly. A search that healed itself by *dropping* results is
      // worse than the bug it replaced: the widen exists so «دهان» can reach a
      // project on page 3, and the recovery makes that page 3 unreachable.
      var asked = 0;
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 1) {
            asked++;
            if (asked == 1) {
              return http.Response('{"error":"boom"}', 500,
                  headers: {'content-type': 'application/json'});
            }
            return _json([_project('p1', 'مشروع جديد')]);
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);

      expect(rows.map((p) => p.id), ['p1', 'p2', 'p3', 'p4', 'p5'],
          reason: 'a head page that heals must join the union, not replace it');
      expect(asked, greaterThanOrEqualTo(2));
    });

    test('a head page that heals and a lost tail page both report', () async {
      // Two things have to survive the retry: the rows, and the record. The
      // retry heals the head, so a naive fix that simply deletes the re-issue
      // passes the row test above and silently re-opens the empty-market bug.
      // The tail page is still dead, so the log must still say so.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      var asked = 0;
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 1) {
            asked++;
            if (asked == 1) {
              return http.Response('{"error":"boom"}', 500,
                  headers: {'content-type': 'application/json'});
            }
            return _json([_project('p1', 'مشروع جديد')]);
          }
          if (page == 4) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);

      expect(rows.map((p) => p.id), ['p1', 'p2', 'p3', 'p5'],
          reason: 'the healed head joins the pages that answered');
      expect(reporter.log.records, isNotEmpty,
          reason: 'the page that is still dead is still recorded');
      expect(reporter.log.records.last.kind, 'page');
      expect(reporter.log.records.last.message, contains('4'),
          reason: 'the record names the page that never arrived');
    });

    test('every page empty is a real answer, not a failure', () async {
      // A wilaya with no open projects. The tail is empty and so is the head,
      // but nothing failed: this is a genuinely empty market and the screen
      // must show its empty state, not an error card.
      final repo = Repository(ApiClient(
        httpClient: MockClient((_) async => _json(<Object>[])),
        baseUrls: ['https://x.test'],
      ));

      expect(await repo.browseProjects(pages: 5), isEmpty);
    });

    test('every page failing still raises the Arabic sentence', () async {
      // The boundary that must not move: the doc promises the caller gets the
      // real error when the whole batch is down, not an empty list.
      final repo = Repository(ApiClient(
        httpClient: MockClient((_) async =>
            http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'})),
        baseUrls: ['https://x.test'],
      ));

      await expectLater(
          repo.browseProjects(pages: 5), throwsA(isA<ApiException>()));
    });

    test('the pages that were lost are recorded, not swallowed', () async {
      // A short result set is only safe to render if the app can still say
      // what it lost. The record is what turns this from a silent
      // under-search into something support can look at.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 3) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));
      await repo.browseProjects(pages: 5);

      expect(reporter.log.records, isNotEmpty);
      expect(reporter.log.latest!.kind, 'page');
      reporter.uninstall();
    });

    test('a single-page fetch is untouched', () async {
      // pages <= 1 is a different code path and must keep raising on failure.
      final repo = Repository(ApiClient(
        httpClient: MockClient((_) async =>
            http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'})),
        baseUrls: ['https://x.test'],
      ));

      await expectLater(
          repo.browseProjects(), throwsA(isA<ApiException>()));
    });

    test('a lost page records why it died, not just which one', () async {
      // The record used to be a hand-written sentence naming the page: «صفحة 3
      // من بحث السوق لم تصل». That says *which* page, and nothing about *why*,
      // and the `catch (_) { return null; }` in `_safeBrowsePage` threw the
      // `ApiException` away on the way — the status code and the cause, the
      // only two things that distinguish the four failures that actually happen
      // in the field:
      //
      //   * a 500 from the Worker  -> the server, nothing the phone can do
      //   * a 401 while signed in  -> the session died mid-search
      //   * a timeout / socket     -> the network, retrying is the fix
      //   * a 5xx from a bad deploy-> the API shape guard has a lead
      //
      // All four reach the log as the same line. Support gets «صفحة 3 لم تصل»
      // and cannot tell a client with no signal from a Worker that is 500ing,
      // so the question can only be answered by guessing and shipping a guess
      // to a user. The cause has to survive the catch, or the record is a
      // timestamp and nothing else.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

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

      await repo.browseProjects(pages: 5);

      final record = reporter.log.records.last;
      expect(record.kind, 'page');
      expect(record.detail, contains('500'),
          reason: 'the HTTP status has to reach the log, not just the page');
    });

    test('a timeout and a 500 are told apart in the log', () async {
      // One test, two very different worlds. A 500 is the API's problem and
      // the shape guard is the lead; a timeout is the network's and retrying
      // fixes it. A support reply that treats them as the same thing either
      // ships a fix for the wrong system or tells a user with no signal to
      // reinstall an app that is fine.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 3) {
            return http.Response('{"error":"boom"}', 500,
                headers: {'content-type': 'application/json'});
          }
          if (page == 4) {
            throw const SocketException('Failed host lookup');
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      await repo.browseProjects(pages: 5);

      final details = reporter.log.records
          .where((r) => r.kind == 'page')
          .map((r) => r.detail)
          .toList();
      expect(details, hasLength(2),
          reason: 'both lost pages are recorded');
      expect(details.any((d) => d.contains('500')), isTrue,
          reason: 'a server fault names its status');
      expect(details.any((d) => d.contains('SocketException')
              || d.contains('socket')),
          isTrue,
          reason: 'a dead socket is not a 500, and the log must say so');
    });

    test('a lost page that is not an ApiException still gets a reason', () async {
      // `_safeBrowsePage` catches everything with `catch (_)`, not just
      // `ApiException` — a row that will not parse raises a `TypeError` from
      // `_row`, and a bug in the widening loop must not be silently recorded
      // as a dead page. Dropping the error object for *those* too would leave
      // the record empty, which is the failure this whole change is about.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(
              Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          if (page == 2) {
            throw StateError('row shape the parser never saw');
          }
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      await repo.browseProjects(pages: 5);

      final record = reporter.log.records.last;
      expect(record.kind, 'page');
      expect(record.detail, contains('StateError'),
          reason: 'a non-API failure keeps its own type name');
    });

    test('a full market is returned whole', () async {
      // The healthy path: every page answers with rows, the union is
      // de-duplicated by id and the order is preserved.
      final repo = Repository(ApiClient(
        httpClient: MockClient((req) async {
          final page = int.parse(Uri.parse(req.url.toString()).queryParameters['page'] ?? '1');
          return _json([_project('p$page', 'مشروع $page')]);
        }),
        baseUrls: ['https://x.test'],
      ));

      final rows = await repo.browseProjects(pages: 5);
      expect(rows.map((p) => p.id), ['p1', 'p2', 'p3', 'p4', 'p5']);
      expect(rows.every((p) => p.status == ProjectStatus.open), isTrue);
    });
  });
}
