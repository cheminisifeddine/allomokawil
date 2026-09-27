// One malformed row must not empty the whole feed.
//
// `Repository._rows` is documented as «parsed row by row so one malformed row
// cannot take the whole screen down», and it is not: the list comprehension
// builds every element eagerly, so the first `TypeError` from a drifted column
// aborts the list and the caller gets the Arabic error sentence with an empty
// screen behind it. The good rows that came back in the same 200 are thrown
// away with the bad one.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:allomokawil/src/core/diagnostics/crash_reporter.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:allomokawil/src/data/repository.dart';

http.Response _json(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

ApiClient _api(Future<http.Response> Function(http.Request) h) =>
    ApiClient(httpClient: MockClient(h), baseUrls: ['https://x.test']);

/// A worker row exactly as D1 files it.
Map<String, Object?> _worker(int id, String name) => {
      'id': id,
      'user_id': id * 10,
      'full_name': name,
      'specialties': ['بناء'],
      'avg_rating': 4.5,
      'total_reviews': 3,
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
  group('_rows keeps the rows it can read', () {
    test('a malformed row in the middle does not empty the feed', () async {
      // Row 2 lost its `id` — the exact TypeError repro the shape guard
      // already pins, except here it sits between two good rows.
      final repo = Repository(_api((_) async => _json([
            _worker(1, 'أحمد البناء'),
            {'full_name': 'مقاول بلا معرّف'},
            _worker(3, 'كريم النجّار'),
          ])));

      final workers = await repo.topWorkers();

      expect(workers.map((w) => w.id), [1, 3],
          reason: 'the two readable rows survive the unreadable one');
      expect(workers.map((w) => w.fullName),
          ['أحمد البناء', 'كريم النجّار']);
    });

    test('a bad row at the head does not swallow the rest either', () async {
      final repo = Repository(_api((_) async => _json([
            {'user_wilaya': 16, 'full_name': 'بلا معرّف ولا رقمي'},
            _worker(7, 'سمير الدهن'),
          ])));

      expect((await repo.topWorkers()).map((w) => w.id), [7]);
    });

    test('every row unreadable still raises the Arabic sentence', () async {
      // The all-broken case is unchanged on purpose: a screen that would show
      // nothing must say so, not render an empty list that reads as «no data».
      final repo = Repository(_api((_) async => _json([
            {'full_name': 'بلا معرّف'},
            {'full_name': 'بلا معرّف'},
          ])));

      await expectLater(repo.topWorkers(), throwsA(isA<ApiException>()));
    });

    test('an empty answer is an empty list, never an error', () async {
      // The boundary that must not move: `[]` is what the Worker sends for a
      // contractor with no projects or a wilaya with no workers. Throwing
      // here would replace every genuinely empty screen in the app with an
      // error card.
      final repo = Repository(_api((_) async => _json(<Object>[])));
      expect(await repo.topWorkers(), isEmpty);
    });

    test('the dropped row is recorded, not swallowed', () async {
      // A partial feed is only safe to render if the app can still say what it
      // lost. The record is what turns this from a silent short-list into
      // something support can look at.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(_api((_) async => _json([
            _worker(1, 'أحمد البناء'),
            {'full_name': 'مقاول بلا معرّف'},
          ])));
      await repo.topWorkers();

      expect(reporter.log.records, hasLength(1));
      expect(reporter.log.latest!.kind, 'row');
      reporter.uninstall();
    });

    test('a well-formed feed is untouched', () async {
      final repo = Repository(_api((_) async => _json([
            _worker(1, 'أحمد البناء'),
            _worker(2, 'كريم النجّار'),
          ])));
      final workers = await repo.topWorkers();
      expect(workers.map((w) => w.id), [1, 2]);
    });

    test('three dropped rows are one record carrying the real count', () async {
      // **The record used to lie about its own size.** The capture sat inside
      // the loop, so every dropped row wrote its own line reading
      // «1 of 5 rows could not be read» — three times over, for a feed that
      // lost three rows. Support reading the log sees "1" and "1" and "1" and
      // concludes a single bad profile, on a feed where a third of the market
      // is missing.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(_api((_) async => _json([
            _worker(1, 'أحمد البناء'),
            {'full_name': 'بلا معرّف'},
            {'full_name': 'بلا معرّف'},
            _worker(4, 'كريم النجّار'),
            {'full_name': 'بلا معرّف'},
          ])));
      final workers = await repo.topWorkers();

      expect(workers.map((w) => w.id), [1, 4],
          reason: 'the readable rows are still returned');
      expect(reporter.log.records, hasLength(1),
          reason: 'one parse, one record — not one line per dropped row');
      final detail = reporter.log.records.single.detail;
      expect(detail, contains('3 of 5 rows could not be read'),
          reason: 'the record states how many rows were actually lost');
      expect(detail, isNot(contains('1 of 5')),
          reason: 'each dropped row used to claim 1 while 3 were gone');
    });

    test('a drifted row is recorded as a type, never as its own value', () async {
      // `_asMap` keeps the value it refused as the cause, and the record used
      // to print that cause as its message: the log line was literally the
      // server's value. What the log is for is naming the shape, not storing
      // whatever the Worker happened to send.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(_api((_) async => _json([
            _worker(1, 'أحمد البناء'),
            'drifted-column-value',
          ])));
      await repo.topWorkers();

      final record = reporter.log.records.single;
      expect(record.detail, contains('String'),
          reason: 'the refused shape is named by type, so the fix is findable');
      expect('${record.message}\n${record.detail}',
          isNot(contains('drifted-column-value')),
          reason: 'a raw server value never reaches the on-device log');
    });

    test('every distinct cause is named, and a repeat is not listed twice',
        () async {
      // Two different defects in one feed must not collapse into one line: a
      // missing `id` and a row that is not an object at all are different
      // columns to go and look at, and they arrive as the same sentence.
      final reporter = CrashReporter(store: _MemoryStore());
      reporter.install();
      addTearDown(reporter.uninstall);

      final repo = Repository(_api((_) async => _json([
            {'full_name': 'بلا معرّف'},
            {'full_name': 'بلا معرّف مرتين'},
            {'id': 3},
            'bare-string',
          ])));

      await expectLater(repo.topWorkers(), throwsA(isA<ApiException>()));
      final detail = reporter.log.records.single.detail;
      expect(detail, contains('4 of 4 rows could not be read'));
      expect(detail, contains('TypeError'),
          reason: 'a column that came back as the wrong type is named');
      expect(detail, isNot(contains('_TypeError')),
          reason: "Dart's private type names must not reach a support log as "
              '`_TypeError` — a class the project has never heard of');
      expect(detail, contains('String'),
          reason: 'a row that is not an object at all is named too');
      expect('TypeError'.allMatches(detail).length, 1,
          reason: 'the same cause three times is one line, not three');
    });
  });
}
