// Proves the suite runner shards, retries inside its own shard, and refuses to
// print a grand total unless every shard is green.
//
// The 35th tick ran the whole suite in one process and it died at +1792 of
// ~2121 with `Bad state: Cannot close sink while adding stream` from Flutter's
// own `flutter_platform.dart`, at 182 MB free of 7.9 GB with no swap. Nothing
// was wrong with the tree; the harness lost a memory race. But the truncated
// run ended on a line shaped like a suite result, so the tick could not tell
// green from dying and had to re-run the remaining 38 files by hand.
//
// This file is the fix's evidence. Real child processes, not a mock: the thing
// that failed was process management and output parsing, and a stubbed
// subprocess would pass while the real summary stayed wrong.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String get _runner => '${Directory.current.path}/tool/run_tests.py';

/// A gate that always answers CLEAR.
///
/// Necessary, and not a convenience: the real gate is *supposed* to refuse
/// while a suite is running, and this file is a suite. Stubbing it is what lets
/// the runner be exercised at all.
Future<String> _clearGate(Directory dir, {String name = 'gate'}) async {
  final gate = File('${dir.path}/${name}_${dir.hashCode}.py');
  await gate.writeAsString('import sys\nsys.exit(0)\n');
  return gate.path;
}

/// Run the runner against a stub `flutter` script, in a directory holding
/// `files` fake test paths so discovery and sharding both have something real
/// to work on.
Future<ProcessResult> _runStubbed(
  Directory dir, {
  required String stubBody,
  required List<String> files,
  String shardSize = '2',
  String deadline = '120',
  int shardDeadline = 30,
}) async {
  final gate = await _clearGate(dir);
  final fake = Directory('${dir.path}/test')..createSync(recursive: true);
  for (final f in files) {
    File('${fake.path}/$f').writeAsStringSync('// fake\n');
  }

  final flutter = File('${dir.path}/flutter');
  await flutter.writeAsString('#!/usr/bin/env bash\n$stubBody');
  await Process.run('chmod', ['+x', flutter.path]);

  return Process.run(
    'python3',
    [
      _runner,
      '--deadline', deadline,
      '--shard-size', shardSize,
      '--shard-deadline', '$shardDeadline',
      '--', ...files,
    ],
    environment: {
      'RUN_TESTS_FLUTTER': flutter.path,
      'RUN_TESTS_GATE': gate,
      'PATH': Platform.environment['PATH'] ?? '',
      'HOME': Platform.environment['HOME'] ?? '/tmp',
    },
    // cwd is the repo (the runner resolves REPO from its own path), so the
    // stub's output has to name files itself; discovery is covered separately.
    workingDirectory: Directory.current.path,
  );
}

void main() {
  test('a green sharded run prints one suite total and the shard plan',
      () async {
    final dir = await Directory.systemTemp.createTemp('shard_ok');
    final r = await _runStubbed(
      dir,
      stubBody: '''
echo "00:00 +0: loading test/\${1}_test.dart"
echo "00:01 +3: All tests passed!"
exit 0
''',
      files: ['a', 'b', 'c', 'd'],
      shardSize: '2',
    );
    final out = '${r.stdout}${r.stderr}';

    // 4 files at 2 per shard is 2 shards, and the plan is printed before any
    // work runs — the reader learns the shape of the run before trusting it.
    expect(out, contains('4 file(s) in 2 shard(s)'), reason: out);
    expect(out, contains('shard 1/2'), reason: out);
    expect(out, contains('shard 2/2'), reason: out);

    // The one number the loop can finally report.
    expect(out, contains('SUITE PASS — 6 tests across 2 shard(s)'),
        reason: '2 shards x 3 tests is the one trustworthy total.\n$out');
    expect(r.exitCode, 0, reason: 'a green suite must stay green.\n$out');
  });

  test('a shard that fails is retried inside its own shard', () async {
    final dir = await Directory.systemTemp.createTemp('shard_retry');
    // Fails on its first attempt, passes on its second. The stub counts
    // attempts in a file so the retry is observable from the runner's output
    // and not merely asserted.
    final marker = File('${dir.path}/attempts');
    final r = await _runStubbed(
      dir,
      stubBody: '''
n=\$(cat ${marker.path} 2>/dev/null || echo 0)
n=\$((n+1))
echo \$n > ${marker.path}
if [ "\$n" -eq 1 ]; then
  echo "00:00 +0: loading test/a_test.dart"
  echo "00:01 +0: test/x [E]"
  echo "Something failed"
  exit 1
fi
echo "00:01 +3: All tests passed!"
exit 0
''',
      files: ['a', 'b'],
      shardSize: '2',
    );
    final out = '${r.stdout}${r.stderr}';

    expect(out, contains('attempt 1/2'), reason: out);
    expect(out, contains('attempt 2/2'), reason: out);
    expect(out, contains('retrying inside its own shard'), reason: out);
    // The retry saved the run: one green shard, and the total is printed.
    expect(out, contains('SUITE PASS'), reason: out);
    expect(r.exitCode, 0, reason: out);
  });

  test('a shard that never passes is reported INCOMPLETE with no total',
      () async {
    final dir = await Directory.systemTemp.createTemp('shard_red');
    final r = await _runStubbed(
      dir,
      stubBody: '''
echo "00:00 +0: loading test/a_test.dart"
echo "00:01 +0: test/x [E]"
echo "Something failed"
exit 1
''',
      files: ['a', 'b'],
      shardSize: '2',
      deadline: '120',
    );
    final out = '${r.stdout}${r.stderr}';

    // The defect: a red run whose last line could be read as a suite number.
    expect(out, isNot(contains('SUITE PASS')),
        reason: 'a failed shard must never print a suite total.\n$out');
    expect(out, contains('not green'), reason: out);
    expect(out, contains('This is NOT a suite result'), reason: out);
    expect(r.exitCode, isNot(0), reason: 'red is not green.\n$out');
  });

  test('a shard that hangs is killed and names the file in flight', () async {
    final dir = await Directory.systemTemp.createTemp('shard_hang');
    final r = await _runStubbed(
      dir,
      stubBody: '''
echo "00:00 +0: loading test/a_first_test.dart"
echo "00:01 +0: loading test/a_second_test.dart"
sleep 600
''',
      files: ['a', 'b'],
      shardSize: '2',
      shardDeadline: 3,
      deadline: '60',
    );
    final out = '${r.stdout}${r.stderr}';

    expect(out, contains('culprit'), reason: out);
    expect(out, contains('test/a_second_test.dart'),
        reason: 'the in-flight file must survive to the report.\n$out');
    expect(out, isNot(contains('SUITE PASS')), reason: out);
    expect(r.exitCode, isNot(0), reason: out);
  });

  test('shards are contiguous, so interacting files stay neighbours', () async {
    // Round-robin would satisfy every other test in this file and hide the
    // 30 Sep interaction, so the plan itself is asserted.
    final dir = await Directory.systemTemp.createTemp('shard_plan');
    final r = await _runStubbed(
      dir,
      stubBody: 'echo "00:01 +1: All tests passed!"\nexit 0\n',
      files: ['a', 'b', 'c', 'd', 'e', 'f'],
      shardSize: '3',
    );
    final out = '${r.stdout}${r.stderr}';

    expect(out, contains('6 file(s) in 2 shard(s)'), reason: out);
    // shard 1 = a,b,c and shard 2 = d,e,f: contiguous, in order.
    // The plan prints the paths it was given: discovery yields
    // `a_test.dart`, an explicit list yields `a`, and both are contiguous.
    expect(out, contains('shard 1/2: 3 file(s) — a .. c'),
        reason: 'shards must be contiguous runs of the sorted list.\n$out');
    expect(out, contains('shard 2/2: 3 file(s) — d .. f'),
        reason: out);
  });
}
