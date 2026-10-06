// Proves the runner's whole-run deadline is DERIVED from the shard plan rather
// than a constant sitting next to it.
//
// The gate was handed a hand-picked `DEFAULT_DEADLINE = 1800.0`, while the plan
// it has to cover grew to 11 batches x 300s cap x (1 + 1 retry) = 6600s of
// permitted worst case. The global clock therefore SIGTERM'd batches that had
// not come close to breaking *their own* cap — three ticks in a row, one of
// them started with `deadline 1s` — and every one of those batches passes when
// run properly. All three died in `Bad state: Cannot close sink while adding
// stream`, the signature of a killed `flutter_tester`, not of a defect.
//
// A bound that fires on the plan it is supposed to bound measures the bound,
// not the tree. So the number is now a function of the plan. These tests pin
// that function, because a constant that has to be re-tuned by hand is exactly
// the thing that silently decays as the suite grows.
//
// Pure arithmetic on the runner's own module, plus one stubbed CLI run. The
// process-management half — does the deadline still fire, still report HUNG,
// still name the culprit — belongs to `run_tests_deadline_test.dart` and
// `run_tests_shard_test.dart`, which test it against real children. Splitting it
// this way keeps this file cheap enough to sit in a shard without adding a
// `sleep 600` to every gate.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String get _repo => Directory.current.path;
String get _runner => '$_repo/tool/run_tests.py';

/// A gate that always answers CLEAR.
///
/// Necessary, not a convenience: the real gate is *supposed* to refuse while
/// `flutter test` is running, and this file is a test that runs. Same reasoning,
/// and the same stub shape, as the other two runner test files.
Future<String> _clearGate(Directory dir) async {
  final gate = File('${dir.path}/gate_clear.py');
  await gate.writeAsString('import sys\nsys.exit(0)\n');
  return gate.path;
}

/// The runner's constants and its budget curve, read from the module itself.
///
/// Imported in a child process rather than inlined, because the point is that
/// `default_deadline` is the runner's own function and not a copy of it that
/// happens to agree today.
Future<Map<String, dynamic>> _readRunner() async {
  final r = await Process.run(
    'python3',
    [
      '-c',
      '''
import sys, json
sys.path.insert(0, "tool")
import run_tests
_files = len(run_tests.discover_tests())
# Index n is the budget for n shards, so the table must reach the tree's OWN
# batch count or the test below reads one past its own data. It was written as
# range(0, 13) and held for exactly as long as the tree produced 12 shards;
# the 289th test file made it 13 and failed with `expected <13> actual <13>` —
# an off-by-one in the harness, not a runner that stopped covering its plan.
# Derived now, with headroom, so the next shard boundary does not red this.
_batches = -(-_files // run_tests.SHARD_SIZE)
print(json.dumps({
    "shard_deadline": run_tests.SHARD_DEADLINE,
    "retries": run_tests.RETRIES,
    "warmup": run_tests.SHARD_WARMUP,
    "shard_size": run_tests.SHARD_SIZE,
    "real_files": _files,
    "batches": _batches,
    "budget": [run_tests.default_deadline(n) for n in range(0, _batches + 2)],
}))
'''
    ],
    workingDirectory: _repo,
  );
  expect(r.exitCode, 0,
      reason: 'the runner must stay importable: ${r.stdout}${r.stderr}');
  return jsonDecode('${r.stdout}'.trim()) as Map<String, dynamic>;
}

double _at(List<dynamic> budget, int n) => (budget[n] as num).toDouble();

void main() {
  late Map<String, dynamic> r;

  setUpAll(() async {
    r = await _readRunner();
  });

  test('the budget covers every batch the runner is allowed to spend', () {
    final shard = (r['shard_deadline'] as num).toDouble();
    final retries = (r['retries'] as num).toInt();
    final warmup = (r['warmup'] as num).toDouble();
    final budget = r['budget'] as List<dynamic>;

    // Index n is the budget for n batches. The property that matters: for every
    // plan the runner can produce, the whole-run budget is at least the sum of
    // what each batch may individually spend, plus its warm-up.
    for (var n = 2; n < budget.length; n++) {
      final worst = n * shard * (1 + retries) + n * warmup;
      final got = _at(budget, n);
      expect(got, greaterThanOrEqualTo(worst),
          reason: '$n shard(s): budget $got cannot cover worst case $worst');
    }
  });

  test('a grown plan gets a bigger budget — the decay this fixes', () {
    final budget = r['budget'] as List<dynamic>;

    // The exact shape of the regression: 9 batches fit inside 1800s, 11 do not.
    // Under the old constant both answered 1800, so the eleventh batch was
    // promised 1800s to spend up to 6600s of and got SIGTERM'd mid-file.
    expect(_at(budget, 11), greaterThan(_at(budget, 9)),
        reason:
            'adding batches must raise the budget, not silently not raise it');

    // And the concrete number the three failed ticks needed: the plan this tree
    // actually produces must clear the old 1800s constant outright.
    expect(_at(budget, 11), greaterThan(1800.0),
        reason: '11 batches at 6600s worst case cannot be bounded by 1800s');
  });

  test('one batch is bounded but not derived from a plan', () {
    final budget = r['budget'] as List<dynamic>;

    // `--shard-size 0` is the pre-sharding case: a single process with no plan
    // to multiply. The function returns None so the caller falls back to the
    // per-batch cap rather than inventing a number.
    expect(budget[1], isNull,
        reason: 'no plan, no derived budget — None means "caller decides"');
    expect(budget[0], isNull, reason: 'zero batches cannot be budgeted');
  });

  test('the real suite is budgeted from its real batch count', () {
    final files = (r['real_files'] as num).toInt();
    final shardSize = (r['shard_size'] as num).toInt();
    final batches = (files / shardSize).ceil();
    final budget = r['budget'] as List<dynamic>;

    expect(shardSize, greaterThan(0),
        reason: 'sharding stays on — raising concurrency on 2 cores with no '
            'swap was measured and answered: no');
    expect(batches, lessThan(budget.length),
        reason: 'the curve must reach this tree\'s own batch count ($batches)');
    expect(_at(budget, batches), greaterThan(1800.0),
        reason: '$files files -> $batches batches must clear the old 1800s');
  });

  test('the CLI says which budget it ran under', () async {
    // A tick reading the log has to be able to tell a derived budget from a
    // caller-set one, or the number above is unverifiable from the report.
    final dir = await Directory.systemTemp.createTemp('budget_cli');
    final gate = await _clearGate(dir);
    final fake = Directory('${dir.path}/test')..createSync(recursive: true);
    for (final f in ['a', 'b', 'c', 'd']) {
      File('${fake.path}/${f}_test.dart').writeAsStringSync('// fake\n');
    }
    final flutter = File('${dir.path}/flutter');
    await flutter.writeAsString(
        '#!/usr/bin/env bash\necho "00:01 +1: All tests passed!"\nexit 0\n');
    await Process.run('chmod', ['+x', flutter.path]);

    Future<ProcessResult> run(List<String> extra) => Process.run(
          'python3',
          [
            _runner,
            '--shard-size',
            '2',
            '--shard-deadline',
            '30',
            ...extra,
            '--',
            'a',
            'b',
            'c',
            'd'
          ],
          environment: {
            'RUN_TESTS_FLUTTER': flutter.path,
            'RUN_TESTS_GATE': gate,
            'PATH': Platform.environment['PATH'] ?? '',
            'HOME': Platform.environment['HOME'] ?? '/tmp',
          },
          workingDirectory: _repo,
        );

    final derived = await run([]);
    final derivedOut = '${derived.stdout}${derived.stderr}';
    expect(derived.exitCode, 0, reason: derivedOut);
    expect(derivedOut, contains('derived from 2 shard(s)'),
        reason: 'the derived budget must be visible in the log.\n$derivedOut');
    // 2 batches x 30s cap x 2 attempts + 2 x 20s warm-up = 160s, and it must
    // be derived — not the old 1800 constant leaking through.
    expect(derivedOut,
        contains('deadline: 160s whole run (derived from 2 shard(s))'),
        reason: 'budget must follow the plan the caller actually asked for.'
            '\n$derivedOut');

    // An explicit --deadline still wins, and says so, so an operator can always
    // tighten the bound by hand when they know the box is busy.
    final fixed = await run(['--deadline', '90']);
    final fixedOut = '${fixed.stdout}${fixed.stderr}';
    expect(fixed.exitCode, 0, reason: fixedOut);
    expect(fixedOut, contains('deadline: 90s whole run (caller-set)'),
        reason:
            'a caller-set budget must be honoured and labelled.\n$fixedOut');
  });

  test('one batch is capped at the per-batch deadline, and says so', () async {
    // The note is how a tick tells a derived budget from a fallback one. If the
    // single-batch path claimed "derived from 1 shard(s)" while actually
    // handing out the per-batch cap, the log would misdescribe its own number
    // — and a log nobody can trust is not evidence, it is decoration.
    final dir = await Directory.systemTemp.createTemp('budget_single');
    final gate = await _clearGate(dir);
    final fake = Directory('${dir.path}/test')..createSync(recursive: true);
    for (final f in ['a', 'b']) {
      File('${fake.path}/${f}_test.dart').writeAsStringSync('// fake\n');
    }
    final flutter = File('${dir.path}/flutter');
    await flutter.writeAsString(
        '#!/usr/bin/env bash\necho "00:01 +1: All tests passed!"\nexit 0\n');
    await Process.run('chmod', ['+x', flutter.path]);

    final r = await Process.run(
      'python3',
      [_runner, '--shard-size', '0', '--shard-deadline', '30', '--', 'a', 'b'],
      environment: {
        'RUN_TESTS_FLUTTER': flutter.path,
        'RUN_TESTS_GATE': gate,
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '/tmp',
      },
      workingDirectory: _repo,
    );
    final out = '${r.stdout}${r.stderr}';
    expect(r.exitCode, 0, reason: out);
    // 2 files, no sharding -> one batch -> bounded by the 30s per-batch cap.
    expect(
        out,
        contains(
            'deadline: 30s whole run (single shard, capped at the per-batch deadline)'),
        reason:
            'the single-batch fallback must be bounded AND labelled.\n$out');
    expect(out, isNot(contains('derived from 1 shard(s)')),
        reason: 'nothing was derived from a one-batch plan.\n$out');
  });
}
