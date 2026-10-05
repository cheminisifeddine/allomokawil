import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allomokawil/src/core/diagnostics/crash_log.dart';
import 'package:allomokawil/src/core/diagnostics/crash_reporter.dart';

/// A store that keeps the lines in memory, so the reporter can be driven
/// without a platform channel.
class _MemoryStore implements CrashStore {
  _MemoryStore([List<String>? seed]) : lines = <String>[...?seed];

  List<String> lines;

  @override
  Future<List<String>> read() async => List<String>.of(lines);

  @override
  Future<void> write(List<String> next) async {
    lines = List<String>.of(next);
  }
}

/// Storage that answers a read late, so the race between [CrashReporter]'s
/// read and its serialised write is the one that actually happens.
///
/// The read resolves only after [turns] event-loop passes, which is enough for
/// a capture to snapshot the log in between — the ordering a real device hits
/// when the preferences channel is slow on a cold start.
class _LateReadStore implements CrashStore {
  _LateReadStore(this.inner, {this.failRead = false});

  /// Event-loop passes the read waits out before answering.
  static const int turns = 3;

  final CrashStore inner;
  final bool failRead;

  List<String> get lines => (inner as _MemoryStore).lines;

  @override
  Future<List<String>> read() async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (failRead) throw StateError('read failed');
    return inner.read();
  }

  @override
  Future<void> write(List<String> next) => inner.write(next);
}

/// Storage having a worse day than the app: every single call throws.
class _BrokenStore implements CrashStore {
  @override
  Future<List<String>> read() async => throw StateError('read failed');

  @override
  Future<void> write(List<String> lines) async =>
      throw StateError('write failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FlutterExceptionHandler? outerHandler;
  CrashReporter? reporter;

  setUp(() {
    // The test binding's own `onError` fails the test on any reported error,
    // which is the wrong behaviour for a test that reports one on purpose: park
    // it here and put it back in tearDown.
    outerHandler = FlutterError.onError;
    FlutterError.onError = null;
  });

  tearDown(() {
    reporter?.uninstall();
    FlutterError.onError = outerHandler;
  });

  group('a crash reaches storage', () {
    test('an error reported through FlutterError.onError lands in the store',
        () async {
      final store = _MemoryStore();
      reporter = CrashReporter(store: store)..install();

      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('boom-42'),
        stack: StackTrace.current,
        library: 'crash_reporter_test',
      ));
      await reporter!.flush();

      expect(store.lines, hasLength(1));
      expect(store.lines.single, contains('boom-42'));
      expect(store.lines.single, contains('flutter'));
      expect(reporter!.log.latest?.message, contains('boom-42'));
      expect(reporter!.log.latest?.detail, isNotEmpty);
    });

    test('the next launch reads the previous run back', () async {
      final store = _MemoryStore();
      reporter = CrashReporter(store: store)..install();
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('lost session')),
      );
      await reporter!.flush();

      final next = CrashReporter(store: store);
      await next.restore();

      expect(next.log.length, 1);
      expect(next.log.latest?.message, contains('lost session'));
    });

    test('the handler that was there before still runs', () async {
      var outerSaw = 0;
      FlutterError.onError = (FlutterErrorDetails details) {
        outerSaw++;
      };
      final store = _MemoryStore();
      reporter = CrashReporter(store: store)..install();

      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('chained')),
      );
      await reporter!.flush();

      expect(outerSaw, 1, reason: 'the debug red screen must survive');
      expect(store.lines, hasLength(1));
    });

    test('a store that throws is not a second crash', () async {
      reporter = CrashReporter(store: _BrokenStore())..install();

      await reporter!.restore();
      reporter!.capture(StateError('write will fail'), StackTrace.current,
          kind: 'async', context: 'unit test');
      await reporter!.flush();

      expect(reporter!.log.length, 1);
      expect(reporter!.log.latest?.message, contains('write will fail'));
      expect(reporter!.log.latest?.kind, 'async');
    });

    // ---------------------------------------------------------------------
    // The read that is not in the chain.
    //
    // `_scheduleWrite` serialises every *write* onto `_writes`, and takes the
    // snapshot of the log at the moment it is called — not when the write
    // eventually runs. That snapshot is the whole mechanism, and it is what
    // makes two crashes captured in the same tick land as two ordered writes
    // instead of one list overwriting the other.
    //
    // `restore()` is the read on the same store, and it was the one member of
    // this pair that never went through the chain. It calls `_store.read()`
    // with no ordering against the write queue at all, so on a device where a
    // startup crash beat the restore (the exact case the `earlier:` comment on
    // `loadLines` describes, and the one `Boot.restoreDiagnostics` schedules
    // after the first frame), the two can interleave:
    //
    //   * `restore` reads, then a `capture` snapshots a log that does not
    //     contain the previous run yet, so the write lands **without** the
    //     earlier lines and the previous run's history is gone from disk for
    //     good;
    //   * or the read resolves first and its `earlier:` insert is overwritten
    //     by a write that was already in flight.
    //
    // Both are the same defect chat's `_forgetQuietly` had: a serialised write
    // whose *partner* operation was never serialised with it. Fixed by putting
    // the read on the same queue, which is what the next two tests pin.
    // ---------------------------------------------------------------------

    test('a restore and a capture in the same tick keep the earlier run',
        () async {
      // Seed storage with a previous run's record.
      final previous = CrashReporter(store: _MemoryStore());
      previous.log.loadLines(<String>[
        jsonEncode(<String, Object?>{
          'at': DateTime(2026, 9, 1, 12).toUtc().toIso8601String(),
          'kind': 'flutter',
          'message': 'من التشغيل السابق',
        }),
      ]);

      // A store whose read is slower than the write, so the interleave is the
      // one that actually happens rather than the one the scheduler avoided.
      final store = _LateReadStore(_MemoryStore(previous.log.toLines()));
      reporter = CrashReporter(store: store)..install();

      // Both in flight before either completes — this is what boot does.
      final restoring = reporter!.restore();
      reporter!.capture(StateError('this run'), StackTrace.current);
      await restoring;
      await reporter!.flush();

      // The line on disk must carry BOTH runs.
      expect(store.lines.join('\n'), contains('من التشغيل السابق'),
          reason: 'a write that snapshotted before the read landed erases the '
              'previous run from the device, and it is the only copy');
      expect(store.lines.join('\n'), contains('this run'));
    });

    test('a capture taken before restore finishes is not lost', () async {
      final previous = CrashReporter(store: _MemoryStore());
      previous.log.loadLines(<String>[
        jsonEncode(<String, Object?>{
          'at': DateTime(2026, 9, 1, 12).toUtc().toIso8601String(),
          'kind': 'flutter',
          'message': 'السابق',
        }),
      ]);
      final store = _LateReadStore(_MemoryStore(previous.log.toLines()));
      reporter = CrashReporter(store: store)..install();

      final restoring = reporter!.restore();
      reporter!.capture(StateError('early'), StackTrace.current,
          kind: 'startup');
      await restoring;
      await reporter!.flush();

      final log = CrashReporter(store: _MemoryStore(store.lines));
      await log.restore();
      expect(log.log.length, 2,
          reason: 'both runs must survive the round trip');
    });

    test('a failed read does not strand the write queue', () async {
      final store = _LateReadStore(_MemoryStore(), failRead: true);
      reporter = CrashReporter(store: store)..install();

      await reporter!.restore();
      reporter!.capture(StateError('after the failed read'), StackTrace.current);
      await reporter!.flush();

      expect(store.lines.join('\n'), contains('after the failed read'),
          reason: 'the capture after a failed read must still reach storage');
    });

    test('the real store round-trips through preferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = PrefsCrashStore();
      expect(await store.read(), isEmpty);

      await store.write(<String>['{"message":"stored"}']);
      expect(await store.read(), hasLength(1));
    });
  });

  group('the log itself', () {
    test('keeps only the newest records', () {
      final log = CrashLog(limit: 3);
      for (var i = 0; i < 6; i++) {
        log.add(CrashRecord(
          at: DateTime.utc(2026, 1, 1, 0, i),
          kind: 'flutter',
          message: 'e$i',
        ));
      }
      expect(log.length, 3);
      expect(log.records.first.message, 'e3');
      expect(log.latest?.message, 'e5');
    });

    test('drops unreadable lines but keeps the readable ones', () {
      final good = CrashLog()
        ..add(CrashRecord(
          at: DateTime.utc(2026),
          kind: 'async',
          message: 'kept',
        ));
      final lines = <String>[
        '',
        'not json at all',
        '{"at":"nope"}',
        ...good.toLines(),
      ];

      final log = CrashLog();
      expect(log.loadLines(lines), 1);
      expect(log.length, 1);
      expect(log.latest?.message, 'kept');
    });

    test('clamps a pathological message instead of storing it whole', () {
      final log = CrashLog()
        ..add(CrashRecord(
          at: DateTime.utc(2026),
          kind: 'flutter',
          message: CrashRecord.trim('x' * 5000, CrashRecord.maxMessage),
        ));
      expect(log.latest!.message.length, CrashRecord.maxMessage);
    });

    test('a record without a timestamp is refused', () {
      expect(CrashRecord.fromJson(<String, Object?>{'message': 'm'}), isNull);
      expect(CrashRecord.fromJson('not a map'), isNull);
    });
  });
}
