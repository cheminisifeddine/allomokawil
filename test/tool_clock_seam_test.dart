// The wall-clock family was closed in `lib/` and then in `test/`, and this file
// closes it in **`tool/`** — the level above, which until this tick had never
// been asked the question.
//
// `tool/build_gate.py` and `tool/run_tests.py` are the instruments the tick
// itself runs on. They bound waits, and a wait bounded on the wrong clock is
// not a slower wait, it is a *wrong answer*.
//
//   * **`time.time()` is the wall clock.** NTP steps it in both directions and
//     `settimeofday` can move it either way, and neither is the program's to
//     observe. Forward past the grace window and `while time.time() < deadline`
//     is already false on the **first** comparison, so the wait is skipped
//     outright.
//   * **`time.monotonic()` is not.** It cannot go backwards and it is not
//     affected by sync, so an elapsed-interval question asked of it is
//     answered by elapsed intervals.
//
// The defect was `build_gate.reap()`'s post-SIGTERM wait — the one wait in
// that function whose whole job is to make the return value trustworthy, and
// whose own docstring says so:
//
//     "The wait is what makes the exit code mean something. Without it the
//      call returns while the memory is still held, the caller re-runs the
//      gate, reads NO ROOM on the same browser it was told it had just killed,
//      and concludes the gate is broken."
//
// A forward clock step of more than `grace` is precisely that failure, reached
// without any bug: `reap()` returns, the browser is still alive holding its
// memory, `--reap` prints "reaped leaked browser", and the caller is told a
// fact that is not yet true. `run_tests.py` bounds its identical SIGTERM grace
// on `time.monotonic()` already — the two instruments disagreed about what a
// wait is, one directory apart.
//
// The rule enforced here is **"no wall-clock read anywhere in `tool/`"**, not
// "don't measure waits on the wall clock": the loop's instruments must never
// read the wall clock at all, so there is no shape in which one of them can
// come to depend on the host's time sync. Reads are located with a real
// tokenizer rather than a regex, because the file that documents this bug
// quotes `time.time()` in its own comment, and a regex would count prose as
// code — the same mistake the `test/` half of this family made twice.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.py` under `tool/` — the loop's own instruments.
List<File> _instruments() {
  final dir = Directory('${Directory.current.path}/tool');
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.py'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Remove comments and string literals, keeping line numbering intact.
///
/// A `re.sub(r'#.*')` would also shorten lines and desynchronise [Line]s, so
/// every removed span is replaced with spaces of equal length and newlines are
/// left alone. This is what keeps the guard from firing on the comment *above*
/// the fix, which quotes `time.time()` on purpose.
String _stripCommentsAndStrings(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '#') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '"' || c == "'") {
      final quote = c;
      // Keep the quotes themselves so `'''` and `"""` docstrings, which contain
      // any code at all, are handled as one unit.
      out.write(quote);
      i++;
      while (i < src.length) {
        if (src[i] == '\\') {
          out.write('  ');
          i += 2;
          continue;
        }
        if (src.startsWith(quote * 3, i)) {
          out.write(quote * 3);
          i += 3;
          break;
        }
        if (src[i] == quote) {
          out.write(quote);
          i++;
          break;
        }
        // Newlines inside a triple-quoted docstring must survive or every
        // following line number is wrong.
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

class _Read {
  _Read(this.file, this.line, this.text);
  final File file;
  final int line;
  final String text;
}

/// A wall-clock read: `time.time()`, `datetime.now()`, `date.today()`, ...
///
/// Recognised by shape — the attribute/call pair — so an alias or an import
/// that is not spelled this way is not silently claimed to be covered. The
/// check is deliberately blind to the *module*: `time.time()` is the wall
/// clock and `time.monotonic()` is not, and the distinction that matters is
/// the function, not where it came from.
List<_Read> _wallClockReads(File f) {
  final lines = _stripCommentsAndStrings(f.readAsStringSync())
      .split('\n');
  final hits = <_Read>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final readsWallClock = RegExp(
        r'\b(?:time\.time|datetime\.now|datetime\.utcnow'
        r'|datetime\.today|date\.today|time\.localtime|time\.mktime'
        r'|time\.time_ns|time\.perf_counter)\b');
    if (readsWallClock.hasMatch(line)) {
      hits.add(_Read(f, i + 1, line.trim()));
    }
  }
  return hits;
}

/// `reap()`'s own source, comments and docstrings removed.
///
/// Added because the first version of the case below sliced the raw source,
/// and immediately failed on the **comment explaining the fix** -- this file
/// quoting `time.time()` back at the reader was counted as the defect it
/// describes. That is the same prose-counts-as-code error the `test/` half of
/// this family made twice, and it is worth the three lines to never make it a
/// third time in the same repo.
String _reapCode() => _stripCommentsAndStrings(
      File('${Directory.current.path}/tool/build_gate.py')
          .readAsStringSync(),
    ).split('def reap(').last;

void main() {
  test('no loop instrument reads the wall clock', () {
    final files = _instruments();
    expect(files, isNotEmpty,
        reason: 'the sweep must fail loudly if it ever stops seeing tool/.');

    final hits = <_Read>[];
    for (final f in files) {
      hits.addAll(_wallClockReads(f));
    }

    final why = StringBuffer();
    {
      final b = StringBuffer('A loop instrument reads the wall clock.\n\n');
      for (final h in hits) {
        b.write('  ${h.file.path}:${h.line}: ${h.text}\n');
      }
      b.write('\n'
          'Why it matters: `time.time()` is set by NTP and by `settimeofday`, '
          'and a program cannot observe either. In `build_gate.reap()` a '
          'forward step larger than the grace window makes '
          '`while time.time() < deadline` false on the first comparison, so '
          'the wait is skipped and the function returns while the process it '
          'just announced as reaped is still holding its memory -- exactly '
          'what that function\'s own docstring says it exists to prevent. '
          'A backward step makes the wait outlast its budget.\n\n'
          'Use `time.monotonic()`. It cannot go backwards, it is immune to '
          'sync, and it is the right clock for every elapsed-interval '
          'question. `run_tests.py` already bounds its SIGTERM grace on it, '
          'one directory over.');
      why.write(b.toString());
    }
    expect(hits, isEmpty, reason: why.toString());
  });

  test('the sweep still reads files, so a broken sweep is not a clean box', () {
    // A guard with no positive control passes for free the day it stops
    // matching anything. Proved by handing the reader a file that DOES read
    // the wall clock and requiring it to be found.
    final probe = File('${Directory.systemTemp.path}/clock_probe_$pid.py');
    probe.writeAsStringSync('''
import time
"""Docstring mentioning time.time() is prose, not code."""
# a comment naming time.time() is also prose
x = time.time()
''');
    try {
      final hits = _wallClockReads(probe);
      expect(hits.length, 1,
          reason: 'the real code line must be found, and only it.\n'
              '${hits.map((h) => '${h.line}: ${h.text}').join('\n')}');
      expect(hits.single.line, 4,
          reason: 'the docstring and the comment must not count.');
    } finally {
      probe.deleteSync();
    }
  });

  test('reap() bounds its wait on a clock that cannot be stepped', () {
    // The named case. A file-level sweep is the rule; this is the specific
    // defect it was written for, pinned on the *function*, so deleting the
    // wait entirely — the other way this breaks — is also caught.
    final body = _reapCode();
    expect(body, contains('time.monotonic()'),
        reason: 'reap() must bound the post-SIGTERM wait on a monotonic '
            'clock; a wall clock there makes a forward step skip the wait '
            'entirely and return while the browser is still alive.');
    final cut = body.split('deadline =').first;
    expect(cut.contains('time.time()'), isFalse,
        reason: 'the deadline must not be measured on the wall clock.');
  });

  test('reap() still waits for the process to actually be gone', () {
    // The other direction, and this case was wrong as first written: it
    // re-asserted the *clock*, so a mutation that deleted the /proc poll
    // outright still passed it 4/4 green -- a test that named a contract it
    // did not check. It now pins the poll itself, which is what the docstring
    // says the wait is for ("the pid is gone from /proc before this
    // returns"). Mutation-verified: delete the poll, this goes red.
    final body = _reapCode();
    // Anchored on CODE, not on the path string: the stripper removes string
    // literals by design, so `'/proc/%d'` is not in the body to match. What
    // is there is the probe that uses it and the cadence it runs at.
    //
    // Counted, not merely present. `os.path.exists` appears twice in a
    // correct `reap()` -- once in the "already gone, nothing to reap" guard
    // and once in the poll -- and a bare `contains` would still pass if the
    // poll were deleted and only the guard survived. Two is the floor.
    final probes = RegExp(r'os\.path\.exists').allMatches(body).length;
    expect(probes, greaterThanOrEqualTo(2),
        reason: 'reap() must poll /proc for the process to be gone -- a '
            'correct clock on an empty wait bounds nothing.\n'
            'found $probes probe(s), expected >= 2 (guard + poll).');
    expect(body, contains('time.sleep(poll)'),
        reason: 'the poll must pace itself, not spin the box this gate exists '
            'to protect.');
  });
}
