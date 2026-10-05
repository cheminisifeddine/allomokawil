// Proves the runner does not leak its suite when the RUNNER ITSELF is killed
// from the outside — the one death `run_tests.py` never handled.
//
// `_kill_group` runs on the runner's *internal* deadline and on a shard that
// fails. It cannot run when the runner is SIGTERM'd or SIGKILL'd by something
// else, because the process that would call it is the thing that died. Two real
// occurrences: on 30 Sep a `flutter test` orphaned that way read as busy forever
// so every later tick skipped its gate, and on 5 Oct the 68th hit it again —
// its full-suite run was cut at shard 47/66 by an external 900 s cap and pid
// 21434 was still alive at PPID 1, in process group 21236, holding 170 MB of a
// 7.8 GB no-swap box, which is why the 69th could not build at all.
//
// **The leak is the grandchild, not the child.** The engine that leaks is
// `flutter_tester`, spawned *by* `flutter test`, so `prctl(PR_SET_PDEATHSIG)`
// on the direct child would kill `flutter test` and orphan the engine anyway —
// which is the bug, reproduced differently. So the stub below is shaped like
// the real thing: a runner child that hangs AND a grandchild of its own that
// must not outlive the runner.
//
// Real processes, no mocks: the defect is process management, and a stubbed
// subprocess cannot prove a kernel signal did the work.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String get _runner => '${Directory.current.path}/tool/run_tests.py';

/// A gate that always answers CLEAR, for the reason spelled out in
/// `run_tests_deadline_test.dart`: the real gate is *supposed* to refuse while
/// a suite is running, and a suite is what is running inside this test.
Future<String> _clearGate(Directory dir) async {
  final gate = File('${dir.path}/gate_clear.py');
  await gate.writeAsString('import sys\nsys.exit(0)\n');
  return gate.path;
}

/// A stub `flutter` that hangs and, like the real tool, leaves an engine of its
/// own behind. `sleep` is copied into the temp dir so `pgrep -f <dir>` matches
/// BOTH the child and the grandchild — matching only the direct child would let
/// this test pass on a fix that still leaks the engine.
Future<File> _hangingFlutterWithGrandchild(Directory dir) async {
  final sleep = File('${dir.path}/sleep');
  await sleep.writeAsBytes((await File('/bin/sleep').readAsBytes()));
  await Process.run('chmod', ['+x', sleep.path]);

  final flutter = File('${dir.path}/flutter');
  await flutter.writeAsString('''#!/usr/bin/env bash
# The "engine": a grandchild of the runner, exactly as flutter_tester is a
# grandchild of flutter test.
${sleep.path} 600 &
echo "00:00 +0: loading test/does_not_matter_test.dart"
${sleep.path} 600
''');
  await Process.run('chmod', ['+x', flutter.path]);
  return flutter;
}

Future<Process> _startRunner(File flutter, String gate) {
  return Process.start(
    'python3',
    [
      _runner,
      '--deadline', '900', // never reached: the runner dies first.
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

/// Everything still alive whose command line names the temp dir: the stub
/// child and the grandchild engine both match.
Future<List<String>> _survivors(Directory dir) async {
  final r = await Process.run('pgrep', ['-af', dir.path]);
  final out = <String>[];
  for (final line in (r.stdout as String).split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.contains('pgrep')) continue;
    out.add(t);
  }
  return out;
}

void main() {
  test('a suite does not outlive a runner that is killed from outside',
      () async {
    final dir = await Directory.systemTemp.createTemp('runner_orphan');
    final gate = await _clearGate(dir);
    final flutter = await _hangingFlutterWithGrandchild(dir);

    final runner = await _startRunner(flutter, gate);

    // Wait for BOTH to exist, so this kills during the run rather than before
    // the spawn — the window is the whole point.
    var waited = 0;
    while (waited < 300) {
      final live = await _survivors(dir);
      if (live.length >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    final atKill = await _survivors(dir);
    expect(atKill.length, greaterThanOrEqualTo(2),
        reason: 'the stub child and its engine must both be up before the kill, '
            'or this test proves nothing.\n$atKill');

    // Kill the runner the way the agent harness kills an overrunning command:
    // SIGTERM to the runner alone, from outside, with no chance to clean up.
    //
    // **The runner's process GROUP, not the runner** — that is the shape the
    // real evidence has. On 5 Oct the 68th's suite was cut by an external cap
    // and its `flutter test` survived at PPID 1, which cannot happen if the
    // group had been signalled too. A group-kill would let this test pass on a
    // fix that only handles group-kills, so the narrower, real signal is the
    // one used, and the watchdog is given its own session anyway so it survives
    // the broader case too.
    await Process.run('kill', ['-TERM', '${runner.pid}']);
    await runner.exitCode
        .timeout(const Duration(seconds: 10))
        .catchError((_) => -1);

    // The engine needs a moment to be torn down; a late reap is still a reap.
    var leaked = <String>[];
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      leaked = await _survivors(dir);
      if (leaked.isEmpty) break;
    }

    expect(leaked, isEmpty,
        reason: 'a suite that outlives its runner leaks a flutter_tester at '
            'PPID 1 that blocks every later tick\'s gate. Killed runner pid '
            '${runner.pid}; still alive:\n${leaked.join('\n')}');
  });

  test('a suite that finishes normally is unaffected and stays green',
      () async {
    final dir = await Directory.systemTemp.createTemp('runner_ok_orphan');
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

    expect(r.exitCode, 0, reason: 'a green suite must stay green.\n$out');
    expect(out, contains('All tests passed!'),
        reason: 'the suite\'s own verdict must survive.\n$out');
  });
}
