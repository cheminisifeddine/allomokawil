// Proves the suite's wall-clock deadline fires, kills the whole process group,
// and names the file that was in flight when it fired.
//
// `flutter test` runs all 201 files in one process with no deadline, so a
// whole-suite deadlock on 30 Sep could not be interrupted and cost ~45 minutes
// of a 10-minute tick; the reporter's last line was buffered mid-test-name, so
// the file could not be named from the output. This test is that deadline, and
// it is tested against real child processes rather than a mock, because the
// thing that failed was process management — a stubbed subprocess would have
// passed while the real runner leaked a tester at PPID 1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String get _runner => '${Directory.current.path}/tool/run_tests.py';

/// Run the runner against a stub `flutter` that prints reporter lines and
/// then hangs forever — the shape of the real failure: output stops mid-suite
/// with no result and the process never exits.
Future<ProcessResult> _runStubbed({
  required String stub,
  required int deadlineSeconds,
}) async {
  final dir = await Directory.systemTemp.createTemp('runner_stub');
  final gate = await _clearGate(dir);
  final flutter = File('${dir.path}/flutter');
  await flutter.writeAsString('''#!/usr/bin/env bash
echo "00:00 +0: loading test/${stub}_first_test.dart"
echo "00:01 +0: loading test/${stub}_second_test.dart"
sleep 600
''');
  await Process.run('chmod', ['+x', flutter.path]);

  return Process.run(
    'python3',
    [
      _runner,
      '--deadline', '$deadlineSeconds',
      '--', 'test/does_not_matter_test.dart',
    ],
    environment: {
      'RUN_TESTS_FLUTTER': flutter.path,
      'RUN_TESTS_GATE': gate,
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': Platform.environment['HOME'] ?? '/tmp',
    },
    workingDirectory: Directory.current.path,
  );
}

/// A gate that always answers CLEAR.
///
/// Necessary, and not a convenience: the real gate is *supposed* to refuse when
/// `flutter test` is running, and a suite is exactly what is running while
/// this test executes. Testing the deadline behind a gate that always says busy
/// tests nothing, and testing it by disabling the gate in the runner would
/// delete the safety property. So the gate is stubbed to clear, and the
/// refusing case is a test of its own below.
Future<String> _clearGate(Directory dir) async {
  final gate = File('${dir.path}/gate_clear.py');
  await gate.writeAsString('import sys\nsys.exit(0)\n');
  return gate.path;
}

void main() {
  test('a hanging suite is killed at the deadline and reported as HUNG', () async {
    final r = await _runStubbed(stub: 'hangs', deadlineSeconds: 2);
    final out = '${r.stdout}${r.stderr}';

    expect(out, contains('HUNG'),
        reason: 'a suite that never returns must not read as a pass.\n$out');
    // 2 is the distinct code: FAIL would let a stall be misread as a red build
    // and "fix" it, HUNG says the harness lost control.
    expect(r.exitCode, 2, reason: 'deadline must be its own exit code.\n$out');
  });

  test('the file in flight at the deadline is named', () async {
    final r = await _runStubbed(stub: 'named', deadlineSeconds: 2);
    final out = '${r.stdout}${r.stderr}';

    expect(out, contains('culprit'),
        reason: 'an unnamed hang is what cost the previous tick its diagnosis.\n$out');
    // The last file the reporter named before it went quiet is the one in
    // flight, and it is recovered from a line the reporter never finished.
    expect(out, contains('test/named_second_test.dart'),
        reason: 'culprit must come from the last line named, not the first.\n$out');
  });

  test('a suite that exits on its own is not reported as hung', () async {
    final dir = await Directory.systemTemp.createTemp('runner_ok');
    final gate = await _clearGate(dir);
    final flutter = File('${dir.path}/flutter');
    await flutter.writeAsString('''#!/usr/bin/env bash
echo "00:00 +0: loading test/quitter_test.dart"
echo "00:01 +2: All tests passed!"
exit 0
''');
    await Process.run('chmod', ['+x', flutter.path]);

    final r = await Process.run(
      'python3',
      [_runner, '--deadline', '60', '--', 'test/does_not_matter_test.dart'],
      environment: {
        'RUN_TESTS_FLUTTER': flutter.path,
        'RUN_TESTS_GATE': gate,
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '/tmp',
      },
      workingDirectory: Directory.current.path,
    );
    final out = '${r.stdout}${r.stderr}';

    expect(out, isNot(contains('HUNG')),
        reason: 'a suite that finishes must never be called hung.\n$out');
    expect(r.exitCode, 0, reason: 'a green suite must stay green.\n$out');
    expect(out, contains('All tests passed!'),
        reason: 'the suite\'s own output has to survive to the tick.\n$out');
  });

  test('a busy gate stops the runner before it starts a second suite', () async {
    final dir = await Directory.systemTemp.createTemp('runner_busy');
    final gate = File('${dir.path}/gate_busy.py');
    await gate.writeAsString('import sys\nprint("BUSY")\nsys.exit(1)\n');

    // A stub that would fail loudly if it were ever reached: the point of the
    // gate is that nothing is spawned at all, so "the stub ran and hung" would
    // be a failure, not a slow pass.
    final marker = File('${dir.path}/flutter');
    await marker.writeAsString('''#!/usr/bin/env bash
touch ${dir.path}/SPAWNED
sleep 600
''');
    await Process.run('chmod', ['+x', marker.path]);

    final r = await Process.run(
      'python3',
      [
        _runner,
        '--deadline', '30',
        '--', 'test/does_not_matter_test.dart',
      ],
      environment: {
        'RUN_TESTS_FLUTTER': marker.path,
        'RUN_TESTS_GATE': gate.path,
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '/tmp',
      },
      workingDirectory: Directory.current.path,
    );

    expect(File('${dir.path}/SPAWNED').existsSync(), isFalse,
        reason: 'a second suite on this 7.8 GB no-swap box is how one gets OOM-killed.');
    expect('${r.stdout}${r.stderr}', contains('BUSY'));
    // 3, not 2. 2 is HUNG -- "a shard I started stopped answering" -- and a
    // refusal is the opposite fact. On 9 Oct the refusal exited 2 and two
    // consecutive ticks wrote it up as a hang in a shard that never ran.
    // Refusing is not passing, not failing, and not hanging.
    expect(r.exitCode, 3,
        reason: 'refusing is not passing, not failing, and not a hang.');
  });
}
