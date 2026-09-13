/// Runs the crash-log invariants on the plain Dart VM.
///
/// `crash_log.dart` is deliberately engine-free, so it can be executed when a
/// full test run is unsafe (an orphaned `flutter_tester` holding
/// `build/unit_test_assets` blocks `flutter test`; see the loop protocol).
///
///   dart run tool/crash_log_check.dart
///
/// Prints one PASS/FAIL line per rule and exits non-zero if anything failed.
library;

import 'dart:io';

import 'package:allomokawil/src/core/diagnostics/crash_log.dart';

int failures = 0;

void check(String what, bool ok) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what');
  if (!ok) failures++;
}

void main() {
  final log = CrashLog(limit: 3);
  for (var i = 0; i < 6; i++) {
    log.add(CrashRecord(
      at: DateTime.utc(2026, 1, 1, 0, i),
      kind: 'flutter',
      message: 'e$i',
    ));
  }
  check('cap: 6 added, 3 kept', log.length == 3);
  check('cap: oldest dropped, newest kept',
      log.records.first.message == 'e3' && log.latest?.message == 'e5');

  final lines = log.toLines();
  check('format: one JSON line per record',
      lines.length == 3 && lines.every((line) => line.startsWith('{')));

  final restored = CrashLog(limit: 3)..loadLines(lines);
  check('round-trip: same messages in the same order',
      restored.records.map((r) => r.message).join(',') == 'e3,e4,e5');

  final junk = CrashLog(limit: 5);
  final read = junk.loadLines(<String>[
    '',
    'not json',
    '{"at":"nope"}',
    '{"kind":"flutter","message":"no timestamp"}',
    ...lines,
  ]);
  check('junk: 4 unreadable lines dropped, 3 good ones kept',
      read == 3 && junk.length == 3);

  final hostile = CrashLog()
    ..add(CrashRecord(
      at: DateTime.utc(2026),
      kind: 'flutter',
      message: CrashRecord.trim('x' * 5000, CrashRecord.maxMessage),
    ));
  check('cap: a 5000-char message is clamped to ${CrashRecord.maxMessage}',
      hostile.latest!.message.length == CrashRecord.maxMessage);

  final stamped = CrashRecord.fromJson(<String, Object?>{
    'at': '2026-09-13T12:00:00.000Z',
    'kind': 'async',
    'message': 'm',
  });
  check('schema: a stored UTC stamp parses back',
      stamped != null && stamped.at.toUtc().hour == 12);

  final noKind = CrashRecord.fromJson(<String, Object?>{
    'at': '2026-09-13T12:00:00.000Z',
    'message': 'm',
  });
  check('schema: a missing kind reads as unknown', noKind?.kind == 'unknown');

  final notARecord = CrashRecord.fromJson(<String, Object?>{'message': 'm'});
  check('schema: a record with no timestamp is refused', notARecord == null);

  stdout.writeln(failures == 0 ? 'ALL CHECKS PASS' : '$failures CHECK(S) FAILED');
  exitCode = failures == 0 ? 0 : 1;
}
