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
