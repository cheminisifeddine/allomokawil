// The suite runner's total is the number this loop gates on, and for as long as
// the reporter emitted a skip marker the runner could not read one of its own
// lines.
//
// **What it was.** `_PROGRESS` matched `\+(\d+)(?: -\d+)?:` -- taught the
// FAILURE form (` -N`) and nothing else. `test_core`'s `compact.dart`
// `_progressLine` writes `+passed` then, each **only when non-empty**, ` ~skipped`
// and ` -failed`. So the four shapes a shard can end on are:
//
//     00:00 +3: All tests passed!            green, nothing skipped
//     00:00 +2 ~3: All tests passed!         green, 3 skipped
//     00:00 +3 -1: Some tests failed.        red, nothing skipped
//     00:00 +2 ~1 -1: Some tests failed.     red, both
//
// and the reader understood the first and third only.
//
// **The symptom was worse than "prints 0".** The backlog filed it as two
// shards scoring zero. What actually happened is subtler and harder to catch:
// `passed_count` returns the LAST line it could parse, and on a shard whose
// skips begin before its last pass-count change that is a *partial* — a small
// plausible number. A 5-test file reported 1. A shard that lost its whole
// first file would report the count of whatever ran after, which is exactly
// what a healthy shard looks like.
//
// **Every line below is a real reporter line**, captured on this box from
// `flutter test --reporter expanded` runs, not written from memory: the first
// two from a file with `skip:` on three tests, the red two from a file with
// two deliberate failures. A regex asserted against invented input proves
// only that the regex matches the string it was written for.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Load the real runner module. Not reimplemented: the thing that broke is a
/// compiled-by-the-interpreter artifact, and a copy of its regex in Dart would
/// be a second answer to the same question.
ProcessResult _probe(Map<String, List<String>> tails) {
  final res = Process.runSync(
    'python3',
    ['-c', '''
import json, sys
sys.path.insert(0, "tool")
import run_tests as r
out = {}
for name, tail in json.loads(sys.argv[1]).items():
    t = list(tail)
    out[name] = {
        "counts": r.progress_counts(t),
        "passed": r.passed_count(t),
        "ran": r.ran_count(t),
    }
print(json.dumps(out))
''', jsonEncode(tails)],
    workingDirectory: Directory.current.path,
  );
  expect(res.exitCode, 0,
      reason: 'the runner must import cleanly: ${res.stderr}');
  return res;
}

Map<String, dynamic> _counts(Map<String, List<String>> tails) {
  final res = _probe(tails);
  return (jsonDecode((res.stdout as String).trim()) as Map)
      .cast<String, dynamic>();
}

void main() {
  // The four shapes the reporter really emits, one map key each.
  const green = '00:00 +3: All tests passed!';
  const greenSkip = '00:00 +2 ~3: All tests passed!';
  const red = '00:00 +3 -1: Some tests failed.';
  const redSkip = '00:00 +2 ~1 -1: Some tests failed.';

  test('all four reporter shapes yield a count, not a partial and not None',
      () {
    final got = _counts({
      'green': [green],
      'greenSkip': [greenSkip],
      'red': [red],
      'redSkip': [redSkip],
    });

    // The passed-only reading, which is what the old regex managed.
    expect(got['green']!['passed'], 3, reason: 'the shape it already knew.');
    expect(got['red']!['passed'], 3, reason: 'and the failure form.');

    // The shape it did not. `None` here is the bug, and so is a small number.
    expect(got['greenSkip']!['passed'], 2,
        reason: 'a 5-test green file reported 2 passes and 3 skips; the '
            'pre-fix reader could not see this line at all.\n$got');
    expect(got['redSkip']!['passed'], 2,
        reason: 'same shape on a red run.\n$got');

    // And what each shard actually ran -- the figure the suite total is built
    // from, which is not the same as the passed count whenever anything was
    // skipped or failed.
    expect(got['green']!['ran'], 3);
    expect(got['greenSkip']!['ran'], 5,
        reason: '2 passed + 3 skipped is 5 tests that ran. Reporting 2 would '
            'make a smaller file look like a regression.\n$got');
    expect(got['red']!['ran'], 4, reason: '3 passed + 1 failed.\n$got');
    expect(got['redSkip']!['ran'], 4, reason: '2 + 1 + 1.\n$got');

    // And the triple, so the split is recoverable rather than summed blind.
    expect(got['greenSkip']!['counts'], [2, 3, 0],
        reason: 'the runner must be able to SAY that 3 were skipped; a total '
            'that silently folds them into "passed" is the lie this file is '
            'about.\n$got');
    expect(got['redSkip']!['counts'], [2, 1, 1], reason: '$got');
  });

  test('a tail is read at its LAST progress line, not its first', () {
    // The monotonicity assumption the docstring leans on, against a tail that
    // also carries the failure detail lines the expanded reporter interleaves.
    final got = _counts({
      'walk': [
        '00:00 +0: loading test/x_test.dart',
        '00:00 +1: alpha passes',
        '00:01 +2 ~1: beta skipped here',
        '  Skip: probe skip shape',
        '00:01 +2 ~2: gamma skipped here',
        '  Skip: probe skip shape',
        '00:01 +2 ~3: All tests passed!',
      ],
    });
    expect(got['walk']!['counts'], [2, 3, 0],
        reason: 'the last progress line wins, and the `Skip:` detail lines in '
            'between are not progress lines at all.\n$got');
    expect(got['walk']!['ran'], 5);
  });

  test('a reporter that wrote no count says so rather than reporting zero', () {
    // `None` is kept distinct from 0 on purpose. If this ever returns 0, a
    // shard that ran nothing is indistinguishable from a shard whose count
    // could not be read, which is the same confusion this file exists to end
    // -- one level down.
    final got = _counts({
      'silent': ['the process died before writing a line',
        'Killed', 'Error: no such file'],
    });
    expect(got['silent']!['passed'], isNull, reason: '$got');
    expect(got['silent']!['ran'], isNull,
        reason: 'and the suite total must be able to refuse it, which it '
            'cannot do with a 0.\n$got');
  });

  test('the pre-fix regex is proven to fail here, so the guard is not idle',
      () {
    // A guard that cannot fail is a guard that proves nothing. The old pattern
    // is exercised directly against the very lines this file claims are read
    // now: it must return None on both skip shapes. If a future tick "fixes"
    // this by widening the pattern elsewhere, this case still names the
    // regression it came from.
    final res = Process.runSync('python3', [
      '-c',
      'import re,sys\n'
          'old = re.compile(r"\\+(\\d+)(?: -\\d+)?:")\n'
          'for line in sys.argv[1:]:\n'
          '    m = old.search(line)\n'
          '    print(line, "->", m.group(1) if m else "None")\n',
      green,
      greenSkip,
      red,
      redSkip,
    ]);
    expect(res.exitCode, 0, reason: '${res.stderr}');
    final lines = (res.stdout as String).trim().split('\n');
    expect(lines[0], contains('-> 3'), reason: lines.join('\n'));
    expect(lines[1], contains('-> None'),
        reason: 'this is the defect, on a line this box really produced.\n'
            '${lines.join('\n')}');
    expect(lines[2], contains('-> 3'), reason: lines.join('\n'));
    expect(lines[3], contains('-> None'), reason: lines.join('\n'));
  });
}
