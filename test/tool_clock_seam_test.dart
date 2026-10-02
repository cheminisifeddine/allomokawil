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
// The rule enforced here is **"no wall-clock read in any tracked Python"**, not
// "don't measure waits on the wall clock": the loop's instruments must never
// read the wall clock at all, so there is no shape in which one of them can
// come to depend on the host's time sync. Reads are located with a real
// tokenizer rather than a regex, because the file that documents this bug
// quotes `time.time()` in its own comment, and a regex would count prose as
// code — the same mistake the `test/` half of this family made twice.
//
// The sweep was scoped to `tool/*.py` when it was born, and that scope was the
// defect it could not see: `test/build_gate_test.py` — the suite every tick
// runs against real processes — bounded the same kind of wait on `time.time()`
// and sat outside it. A rule over a *directory* is a claim about where
// instruments are supposed to live, not a fact about where they live, so it
// was green and incomplete at the same time. The sweep now enumerates every
// tracked `.py`, and a second case asserts that the directories the loop
// actually runs out of are still inside it, so an incomplete sweep fails
// instead of passing for a clean box.
//
// The reader itself was the next layer, and it had two defects, both
// **false negatives** -- the direction that hides bugs. A rule that reports
// prose as code is noisy; a rule that erases real code is silent. Neither shape
// existed in any tracked `.py`, which is exactly why a census over the corpus
// could not find them: the corpus was clean and the reader was still wrong.
// They are fixtures now, committed under `test/fixtures/` as `*.py.fixture`.
//
//   * **A backslash-newline inside a string deleted the newline.** It is a
//     Python line continuation -- the string continues, the physical line ends
//     -- and the reader emitted two spaces, shifting every later line number
//     down by one. A defect would be reported against the wrong source line.
//   * **An f-string replacement field was erased with its literal.**
//     `f"{time.time() - t0}"` reads the wall clock at runtime and the sweep
//     reported the file clean.
//
// Both were checked against Python's own `tokenize`, not against intuition:
// for `r"a\` + newline + `b"` the tokenizer reports ONE STRING token spanning
// (1,4)-(2,2), which is why the continuation branch is not gated on the
// `r` prefix. An earlier draft of this fix added a raw-string escape rule and
// the oracle killed it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `.py` the repository actually tracks — the loop's own instruments.
///
/// This was `tool/*.py` only, and that was the whole point of this case: the
/// guard proved a rule over a *directory*, which is a decision about where
/// instruments are supposed to live, not a fact about where they live. A
/// runner outside `tool/` was invisible to it. `test/build_gate_test.py` is
/// one — the suite every tick runs against real processes, carrying the same
/// `deadline = time.time() + 5` wait the guard existed to prevent, 400 lines
/// past the last file it watched.
///
/// Enumerated through `git ls-files`, not by globbing the filesystem, because
/// a glob also collects `ios/Flutter/ephemeral/flutter_lldb_helper.py` — SDK
/// scaffolding the repo does not own and must not police (it is gitignored).
/// And it is a positive contract, not a filter: the set must still be
/// non-empty, and the directories the loop actually runs must still be in it.
List<File> _instruments() {
  final result = Process.runSync(
    'git',
    ['ls-files', '--', '*.py'],
    workingDirectory: Directory.current.path,
  );
  expect(result.exitCode, 0,
      reason: 'git ls-files failed (${result.stderr}) — without it the sweep '
          'would silently watch nothing and read as a clean box.');
  final paths = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.endsWith('.py'))
      .toList()
    ..sort();
  return paths.map((rel) => File('${Directory.current.path}/$rel')).toList();
}

/// The directories the loop protocol actually runs Python out of.
///
/// The point of a positive contract is that it fails when the rule stops
/// describing the box. If the loop ever grew an instrument outside these two,
/// the sweep would still be green and still be incomplete.
const _watchedDirs = ['tool', 'test'];

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
      // The one prefix flag that changes how this literal is read: `f` makes
      // the `{...}` fields real code, evaluated at runtime. Read from the
      // character immediately before the quote so `foo(bar)"` does not
      // inherit an unrelated `f` from a nearby word.
      final isF = _prefixFlags(src, i).contains('f');
      // Keep the quotes themselves so `'''` and `"""` docstrings, which contain
      // any code at all, are handled as one unit.
      out.write(quote);
      i++;
      while (i < src.length) {
        if (src[i] == '\\') {
          // A backslash immediately before a newline is a LINE CONTINUATION:
          // the string does not end, and the physical line does. The reader
          // used to emit two spaces here, which deleted the newline and
          // shifted every later line number down by one -- so a wall-clock
          // read was reported against the wrong line, or missed outright.
          // Verified against Python's own tokenizer: a raw string does NOT
          // exempt this case (`r"a\` + newline + `b"` is one STRING token
          // spanning two lines), so the rule stays unconditional.
          if (i + 1 < src.length && src[i + 1] == '\n') {
            out.write(' ');
            out.write('\n');
          } else {
            out.write('  ');
          }
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
        if (isF && src[i] == '{') {
          if (src.startsWith('{{', i)) {
            // `{{` is an escaped brace: literal text, not code.
            out.write('  ');
            i += 2;
            continue;
          }
          // A replacement field is CODE. `f"{time.time() - t0}"` reads the
          // wall clock, and erasing the span made this guard blind to it --
          // the exact class of defect it exists to catch. The field is copied
          // through verbatim so the sweep can see the call.
          final end = _fFieldEnd(src, i);
          out.write(src.substring(i, end));
          i = end;
          continue;
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

/// The Python string-prefix flags on the literal whose opening quote is at
/// [quote].
///
/// Read backwards over the identifier run that ends at the quote, lowercased.
/// Only those characters count: `foo(bar)"` must not inherit the `f` of an
/// unrelated earlier word. Raw (`r`) and bytes (`b`) prefixes need no
/// handling here -- a backslash does not end a raw string's quote, which is
/// exactly what the escape branch above already does.
String _prefixFlags(String src, int quote) {
  var j = quote - 1;
  final end = j + 1;
  while (j >= 0 && _isIdentChar(src[j])) {
    j--;
  }
  return src.substring(j + 1, end).toLowerCase();
}

bool _isIdentChar(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x41 && code <= 0x5a) || // A-Z
      (code >= 0x61 && code <= 0x7a) || // a-z
      code == 0x5f; // _
}

/// Index just past the `}` closing the f-string replacement field at [open].
///
/// Brace nesting is counted and a nested string is skipped whole, so neither
/// `d["}"]` nor a `}` inside a nested literal can end the field early. An
/// unterminated field runs to end-of-input rather than looping forever.
int _fFieldEnd(String src, int open) {
  var j = open + 1;
  var depth = 0;
  while (j < src.length) {
    final c = src[j];
    if (c == '{') {
      depth++;
      j++;
    } else if (c == '}') {
      if (depth == 0) {
        return j + 1;
      }
      depth--;
      j++;
    } else if (c == '"' || c == "'") {
      final quote = c;
      j++;
      while (j < src.length) {
        if (src[j] == '\\') {
          j += 2;
          continue;
        }
        if (src[j] == quote) {
          j++;
          break;
        }
        j++;
      }
    } else {
      j++;
    }
  }
  return src.length;
}

/// A committed Python **fixture** -- a shape no tracked instrument contains.
///
/// These are vectors for the reader, not instruments the loop runs: they
/// deliberately read the wall clock, which is exactly what the sweep above
/// fails on. So they are named `*.py.fixture`, and the `git ls-files '*.py'`
/// enumeration cannot collect them. A fixture written as `*.py` would make the
/// guard red on its own test data.
File _fixture(String name) {
  final f = File('${Directory.current.path}/test/fixtures/$name');
  expect(f.existsSync(), isTrue,
      reason: 'fixture $name must exist under test/fixtures/ as a committed '
          'file. Inline strings would not exercise the reader against a real '
          'file read, which is how the defect was originally hidden.');
  return f;
}

class _Read {
  _Read(this.file, this.line, this.text);
  final File file;
  final int line;
  final String text;
}

/// A wall-clock read, as the **dotted attribute path that reaches it**.
///
/// Modelled as a path instead of a regex so that the three ways Python lets
/// you spell the same read land on the same entry:
///
///     import time                        time.time()
///     import time as t                   t.time()
///     from time import time              time()
///     from time import time as wall      wall()
///
/// The last two were invisible: the guard recognised clocks by *literal
/// spelling*, so `from time import time as wall` followed by `wall()` was a
/// real wall-clock read the sweep reported as clean. Same false-negative
/// direction as the two reader defects above -- the guard finding nothing.
///
/// `time.perf_counter` was in this list and is not any more. It is not a wall
/// clock: `time.get_clock_info('perf_counter')` reports `monotonic=True,
/// adjustable=False`. Banning it pushes the *fix* for a wall-clock bug onto
/// the wall clock. A case below checks this table against the Python on this
/// box, so the table is pinned by the interpreter rather than by this comment.
const _wallClockPaths = <String>{
  'time.time',
  'time.time_ns',
  'time.localtime',
  'time.mktime',
  'datetime.datetime.now',
  'datetime.datetime.utcnow',
  'datetime.datetime.today',
  'datetime.date.today',
};

/// Modules whose functions this guard has an opinion about.
///
/// Bounded on purpose. Resolving an alias from an unrecognised module would
/// mean claiming the guard knows what some third-party `now()` does, and a
/// guard that claims more than it checks is worse than one that admits its
/// edge.
const _clockModules = {'time', 'datetime', 'date'};

/// `moduleAlias` maps `import X as A` to `X`; `nameAlias` maps
/// `from X import Y as A` to the path `X.Y`.
///
/// Collected over the **whole file**, not in order: a function body may call
/// an alias imported below it, and that call resolves at call time, after
/// every module-level import has run. Module-level code that used a name
/// before importing it would be a `NameError` anyway.
({Map<String, String> moduleAlias, Map<String, String> nameAlias})
    _importAliases(String stripped) {
  final moduleAlias = <String, String>{};
  final nameAlias = <String, String>{};
  final fromImport = RegExp(r'^\s*from\s+([A-Za-z_][\w.]*)\s+import\s+'
      r'([A-Za-z_][\w]*)'
      r'(?:\s+as\s+([A-Za-z_][\w]*))?');
  final plainImport = RegExp(
      r'^\s*import\s+([A-Za-z_][\w.]*)\s*(?:as\s+([A-Za-z_][\w]*))?\s*$');
  for (final line in stripped.split('\n')) {
    final m = fromImport.firstMatch(line);
    if (m != null) {
      final module = m.group(1)!;
      final name = m.group(2)!;
      final bound = m.group(3) ?? name;
      if (_clockModules.contains(module)) {
        nameAlias[bound] = '$module.$name';
      }
      continue;
    }
    final i = plainImport.firstMatch(line);
    if (i != null) {
      final module = i.group(1)!;
      if (_clockModules.contains(module)) {
        moduleAlias[i.group(2) ?? module] = module;
      }
    }
  }
  return (moduleAlias: moduleAlias, nameAlias: nameAlias);
}

/// Names bound a second time by something other than an import.
///
/// If a clock alias is also a function parameter, a local, a loop target or
/// any other binding, `wall()` is *that* binding and the guard cannot say
/// what it calls. It must then refuse to claim the file is clean -- see
/// [_clockAliasSuspicion], which is the whole point of computing this.
Set<String> _reboundNames(String stripped) {
  final out = <String>{};
  final param =
      RegExp(r'^\s*def\s+[A-Za-z_][\w]*\s*\(([^)]*)\)', multiLine: true);
  for (final m in param.allMatches(stripped)) {
    for (final raw in m.group(1)!.split(',')) {
      final name = raw.trim().split(RegExp(r'[:=\s]')).first;
      if (name.isNotEmpty && RegExp(r'^[A-Za-z_]\w*$').hasMatch(name)) {
        out.add(name);
      }
    }
  }
  final binders = [
    RegExp(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', multiLine: true),
    RegExp(r'^\s*class\s+([A-Za-z_]\w*)', multiLine: true),
    RegExp(r'^\s*([A-Za-z_]\w*)\s*(?:=[^=]|\+=|-=)', multiLine: true),
    RegExp(r'\bfor\s+([A-Za-z_]\w*)\s+in\b'),
    RegExp(r'\bas\s+([A-Za-z_]\w*)\s*:'),
    RegExp(r'\blambda\b[^:]*\b([A-Za-z_]\w*)\s*[:,)]'),
  ];
  for (final re in binders) {
    for (final m in re.allMatches(stripped)) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

/// Every wall-clock read in [stripped], plus what the guard could not decide.
///
/// A [_ClockScan] carries both because "found nothing" and "could not tell"
/// must not collapse into the same answer: the first is a clean file, the
/// second is a file the sweep is blind to, and reporting the second as the
/// first is how this guard was wrong twice already.
class _ClockScan {
  _ClockScan(this.hits, this.suspicions);
  final List<_Read> hits;
  final List<String> suspicions;

  bool get isClean => hits.isEmpty && suspicions.isEmpty;
}

/// Scan already-stripped source for wall-clock reads, resolving aliases.
_ClockScan _clockScanFrom(String stripped, [File? f]) {
  final file = f ?? File('<source>');
  final aliases = _importAliases(stripped);
  final rebound = _reboundNames(stripped);

  // A clock alias that is also rebound somewhere is not a clock read we can
  // claim -- and neither is it a clean bill of health.
  final blind = <String, String>{};
  for (final entry in aliases.nameAlias.entries) {
    if (rebound.contains(entry.key)) {
      blind[entry.key] = entry.value;
    }
  }

  final lines = stripped.split('\n');
  final hits = <_Read>[];
  final suspicions = <String>[];
  final attr = RegExp(r'\b([A-Za-z_]\w*)((?:\.[A-Za-z_]\w*)+)');
  final call = RegExp(r'\b([A-Za-z_]\w*)\s*\(');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    var matched = false;

    for (final m in attr.allMatches(line)) {
      final root = m.group(1)!;
      final module = aliases.moduleAlias[root] ?? root;
      final path = '$module${m.group(2)!}';
      if (_wallClockPaths.contains(path)) {
        hits.add(_Read(file, i + 1, line.trim()));
        matched = true;
      }
    }

    // Bare `name(` only ever means something for a name we bound above from a
    // module this guard knows -- otherwise every call in the file would be
    // tested against the clock table.
    for (final m in call.allMatches(line)) {
      final name = m.group(1)!;
      if (blind.containsKey(name)) {
        suspicions.add('${file.path}:${i + 1}: `$name` is bound both to '
            '${blind[name]} and to another binding on this file, so '
            '${blind[name]} may be called as `$name()`. Looked at it by hand: '
            '${line.trim()}');
      } else if (aliases.nameAlias[name] != null &&
          _wallClockPaths.contains(aliases.nameAlias[name])) {
        hits.add(_Read(file, i + 1, line.trim()));
        matched = true;
      }
    }
    if (matched) continue;
  }
  return _ClockScan(hits, suspicions);
}

/// Aliases the sweep could not resolve -- never reported as clean.
List<String> _clockAliasSuspicion(File f) =>
    _clockScanFrom(_stripCommentsAndStrings(f.readAsStringSync()), f)
        .suspicions;

/// A wall-clock read: `time.time()`, `datetime.now()`, `date.today()`, ...
///
/// Recognised by the **path that reaches the function**, so an import written
/// as `from time import time as wall` counts exactly like `time.time()`, and
/// the module a name was imported under no longer decides whether the guard
/// can see it.
List<_Read> _wallClockReads(File f) =>
    _clockScanFrom(_stripCommentsAndStrings(f.readAsStringSync()), f).hits;

/// The sweep proper, over already-stripped source.
///
/// Split out from [_wallClockReads] so a case can assert on a *span* the reader
/// produced without going back to disk -- the reader is what is under test
/// here, and routing through a file would make every assertion in this file a
/// test of the filesystem as well.
List<_Read> _wallClockReadsFrom(String stripped, [File? f]) =>
    _clockScanFrom(stripped, f).hits;

/// `reap()`'s own source, comments and docstrings removed.
///
/// Added because the first version of the case below sliced the raw source,
/// and immediately failed on the **comment explaining the fix** -- this file
/// quoting `time.time()` back at the reader was counted as the defect it
/// describes. That is the same prose-counts-as-code error the `test/` half of
/// this family made twice, and it is worth the three lines to never make it a
/// third time in the same repo.
String _reapCode() => _stripCommentsAndStrings(
      File('${Directory.current.path}/tool/build_gate.py').readAsStringSync(),
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

  test('the sweep covers every directory the loop runs Python out of', () {
    // The rule above is "no instrument reads the wall clock". A rule with no
    // statement of *which* files it governs cannot tell an incomplete sweep
    // from a clean box — which is exactly how the defect this case was written
    // for survived: `tool/*.py` was a complete-looking answer to a question
    // nobody asked, and `test/build_gate_test.py` sat outside it for a month.
    final files = _instruments();
    expect(files, isNotEmpty,
        reason: 'the sweep must fail loudly if it ever stops seeing Python.');

    for (final dir in _watchedDirs) {
      final any = files.any((f) => f.path.contains('/$dir/'));
      expect(any, isTrue,
          reason: 'no tracked .py under $dir/ — the loop runs instruments '
              'from there, so the sweep is no longer describing the box it '
              'is meant to police.\nfound: '
              '${files.map((f) => f.path).join(', ')}');
    }

    // And the specific file that hid the defect is in the sweep's set, named
    // so that moving or deleting it is a loud failure rather than a silent
    // reduction in coverage.
    expect(
        files.any((f) => f.path.endsWith('/test/build_gate_test.py')), isTrue,
        reason: 'the gate suite must stay under the sweep: it is the runner '
            'every tick drives against real processes.');
  });

  test('the sweep would have caught the wall-clock read outside tool/', () {
    // Pin the fix at the level it was made. `build_gate_test.py` bounded its
    // argv-read wait on the wall clock; the defect is gone, so this case
    // asserts the *sweep reaches it* rather than asserting the clock, which
    // would go green the moment the fix landed and stop proving anything.
    //
    // Mutation-verified: reverting the two lines to `time.time()` puts this
    // red with `test/build_gate_test.py:829` named, even though the file is
    // outside `tool/`.
    final f = File('${Directory.current.path}/test/build_gate_test.py');
    expect(f.existsSync(), isTrue, reason: 'the gate suite must exist.');

    final hits = _wallClockReads(f);
    expect(hits, isEmpty,
        reason: 'test/build_gate_test.py reads the wall clock. It is outside '
            'tool/, which is why it survived the tool/ sweep.\n'
            '${hits.map((h) => '  ${h.file.path}:${h.line}: ${h.text}').join('\n')}');

    // Not merely "clean" — the wait must still be there, or a file with the
    // reads deleted entirely would pass this case for the wrong reason.
    final src = _stripCommentsAndStrings(f.readAsStringSync());
    expect(RegExp(r'deadline\s*=\s*time\.monotonic\(\)').hasMatch(src), isTrue,
        reason: 'the argv-read wait must still exist and be bounded on the '
            'monotonic clock; case 13 depends on it.');
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

  test('the reader keeps a line continuation instead of eating the newline',
      () {
    // A backslash immediately before a newline is a Python line continuation:
    // the string continues and the physical line ends. The reader emitted two
    // spaces for it, which DELETED the newline, so every line after it was
    // numbered one too low.
    //
    // The failure this buys is not cosmetic. `_wallClockReads` reports
    // `file:line`, and a sweep that shifts lines reports a defect against the
    // wrong source line -- or, at the end of a file, drops the read entirely.
    // That is the guard being wrong in the direction that hides bugs.
    //
    // Fixtures, not a mutation against real code: no tracked .py in this repo
    // contains a line continuation inside a string literal, so this shape had
    // never been exercised. They are committed as `*.py.fixture` because the
    // instrument sweep enumerates `git ls-files '*.py'` and these deliberately
    // read the wall clock -- a vector, not an instrument.
    final f = _fixture('backslash_newline_in_string.py.fixture');
    final src = f.readAsStringSync();

    expect(src.contains('\\\n'), isTrue,
        reason: 'the fixture must contain a backslash-newline inside a string, '
            'or the case passes without exercising anything.');

    // The property the guard depends on: stripped output has exactly as many
    // lines as the source, so a reported line number is a source line number.
    final stripped = _stripCommentsAndStrings(src);
    expect(stripped.split('\n').length, src.split('\n').length,
        reason: 'line numbers must survive tokenizing:\n'
            'source:\n$src\nstripped:\n$stripped');

    // And the read must be reported at the line it is ACTUALLY on, taken from
    // the source rather than hardcoded: the file's trailing newline makes that
    // line 3, not 2, and an assertion that hardcoded the wrong constant would
    // have failed for a reason that had nothing to do with the reader.
    final realLine =
        src.split('\n').indexWhere((l) => l.contains('time.time()')) + 1;
    expect(realLine, greaterThan(1),
        reason: 'the fixture must put the read AFTER the continuation.');

    final hits = _wallClockReads(f);
    expect(hits.length, 1,
        reason: 'the wall-clock read must be found.\n'
            '${hits.map((h) => '  ${h.line}: ${h.text}').join('\n')}');
    expect(hits.single.line, realLine,
        reason: 'a line continuation inside a string shifted every later line '
            'number down by one: the read is on source line $realLine and was '
            'reported at ${hits.single.line}.');
  });

  test('the reader sees through an f-string field, because it is code', () {
    // `f"{...}"` replacement fields are evaluated at runtime. A field holding
    // `time.time()` IS a wall-clock read -- and the reader erased the entire
    // literal, span and all, so the sweep reported the file clean.
    //
    // This is a false negative in the exact direction that matters: the guard
    // that exists to find wall-clock reads was blind to one written in the
    // most compact form Python has.
    final f = _fixture('fstring_field_runs_code.py.fixture');
    final hits = _wallClockReads(f);
    expect(hits.length, 1,
        reason: 'a wall-clock read inside an f-string field is real code and '
            'must be found.\nfound ${hits.length}.');

    // Not merely "one hit somewhere": the exact line, because a reader that
    // found it on the wrong line would still have been useful but wrong.
    expect(hits.single.line, 1);
    expect(hits.single.text, contains('time.time()'),
        reason: 'the reported text must be the code line, not a blanked span.');

    // `{{` is an escaped brace -- literal TEXT -- and must not be mistaken for
    // the start of a field, or the brace scan runs past the end of the string
    // and eats real code that follows.
    final braced =
        _stripCommentsAndStrings('x = f"{{literal}} {time.time()}"\n');
    final lines = braced.split('\n');
    expect(lines[0], contains('time.time()'),
        reason: 'the real field after an escaped brace must still be seen.');
    expect(_wallClockReadsFrom(braced).length, 1,
        reason: 'exactly one read, not two and not zero.');
  });

  test('a raw string that spans a continuation is still one line-accurate span',
      () {
    // In `r"a\` + newline + `b"` the backslash does NOT escape anything, so
    // the literal runs to the next `"` -- across the physical line break. That
    // was verified against Python's own tokenizer rather than assumed:
    // `tokenize` reports ONE STRING token from (1,4) to (2,2).
    //
    // The reader therefore must keep the newline even in a raw string, which
    // is why the continuation branch is not gated on the prefix. If someone
    // later adds a "raw strings ignore escapes" shortcut here, this goes red.
    final f = _fixture('raw_string_backslash_quote.py.fixture');
    final src = f.readAsStringSync();
    final realLine =
        src.split('\n').indexWhere((l) => l.contains('time.time()')) + 1;
    expect(src.contains('r"a\\"b"'), isTrue,
        reason: 'the fixture must be the raw string that spans a continuation; '
            'if it was edited this case no longer tests what it says.');

    final stripped = _stripCommentsAndStrings(src);
    expect(stripped.split('\n').length, src.split('\n').length,
        reason: 'a raw string spanning a continuation must not lose a line:\n'
            'source:\n$src\nstripped:\n$stripped');

    // The backslash must not have been read as an escape of the closing quote,
    // which would end the string early and leak the rest of the file as code.
    final hits = _wallClockReads(f);
    expect(hits.length, 1,
        reason: 'the read must still be found; ending the '
            'raw string early would either drop it or invent others.');
    expect(hits.single.line, realLine,
        reason: 'the raw string spans the continuation, so the read after it '
            'must keep its own line number.');
  });

  test('every fixture is still valid Python the reader must agree with', () {
    // The fixtures are test vectors, and a vector that no longer parses is a
    // vector describing a language that does not exist. `python3 -c compile`
    // is the oracle: if the Python on this box rejects a fixture, the reader
    // is being asked to agree with fiction.
    final dir = Directory('${Directory.current.path}/test/fixtures');
    final fixtures = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.py.fixture'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(fixtures, isNotEmpty,
        reason: 'the fixtures must be committed files, not strings inline in '
            'this test -- they are the shapes no tracked .py contains.');

    for (final f in fixtures) {
      final tmp =
          File('${Directory.systemTemp.path}/${f.uri.pathSegments.last}');
      tmp.writeAsStringSync(f.readAsStringSync());
      final res = Process.runSync('python3', [
        '-c',
        'compile(open(__import__("sys").argv[1]).read(), "f", "exec")',
        tmp.path
      ]);
      expect(res.exitCode, 0,
          reason: '${f.path} must be valid Python (it is a fixture, not '
              'pseudocode): ${res.stderr}');
      tmp.deleteSync();
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

  test('a clock imported under another name is still a wall-clock read', () {
    // The gap this tick closed. The guard recognised clocks by *literal
    // spelling* -- `time.time`, `datetime.now` -- so these three lines, which
    // are the same reads written the way Python's own docs write them, were
    // invisible to a sweep that reported the file clean.
    //
    // False negative, again. The direction that hides bugs: two ticks running,
    // both on the guard's blind spot rather than on the app.
    //
    // The fixture also carries the two aliases that are CORRECT code --
    // `mono` and `fast` -- because a resolver that simply banned every
    // aliased import would pass this case while making the guard useless. The
    // one read must be found; the two correct ones must not.
    final f = _fixture('aliased_wall_clock.py.fixture');
    final src = f.readAsStringSync();
    final realLine =
        src.split('\n').indexWhere((l) => l.contains('= wall()')) + 1;
    expect(realLine, greaterThan(1),
        reason: 'the read must come after the imports it is bound by.');

    final hits = _wallClockReads(f);
    expect(hits.length, 1,
        reason: 'exactly one real wall-clock read is in this fixture: '
            '`wall()`. `mono()` and `fast()` are monotonic and must NOT count '
            '-- banning them would push the fix for a wall-clock bug onto '
            'another wall clock.\nfound ${hits.length}: '
            '${hits.map((h) => '${h.line}: ${h.text}').join(' | ')}');
    expect(hits.single.line, realLine,
        reason: 'the read must be reported on the line it is actually on.');
    expect(hits.single.text, contains('wall()'));
  });

  test('the module itself, imported under another name, is still seen', () {
    // `import time as t; t.time()` is the same read as `import time;
    // time.time()`, and the guard keyed on the module *spelling*, so the
    // first was a wall-clock read it could not see.
    final f = _fixture('module_aliased_time.py.fixture');
    final src = f.readAsStringSync();
    final hits = _wallClockReads(f);
    expect(hits.length, 2,
        reason: 'both `t.time()` and `dt.datetime.now()` are wall-clock '
            'reads; the module alias must not hide either.\nfound '
            '${hits.length}: '
            '${hits.map((h) => '${h.line}: ${h.text}').join(' | ')}');
    expect(
        hits.map((h) => h.line),
        containsAll(<int>[
          src.split('\n').indexWhere((l) => l.contains('t.time()')) + 1,
          src.split('\n').indexWhere((l) => l.contains('dt.datetime.now()')) +
              1,
        ]),
        reason: 'each read must be named on its own source line.');
  });

  test('a shadowed clock alias is never reported as clean', () {
    // The half that matters. Resolving aliases means the guard can now be
    // wrong in a NEW way: `wall` is a parameter in this fixture, so `wall()`
    // calls whatever was passed in -- the imported clock or not, the guard
    // cannot say. It is therefore not a read, and it is ALSO not a clean file.
    //
    // Reporting it as clean would be a false negative worse than the original:
    // the guard would be asserting coverage of a call it had just decided it
    // could not understand. So a shadowed alias becomes a *suspicion* -- a
    // named, human-checkable line -- instead of silence.
    final f = _fixture('shadowed_clock_alias.py.fixture');
    final hits = _wallClockReads(f);
    expect(hits, isEmpty,
        reason: 'a parameter named `wall` is not the imported clock, so this '
            'is not a read the guard may claim.');

    final blind = _clockAliasSuspicion(f);
    expect(blind.length, 1,
        reason: 'the guard cannot resolve this call and must say so on '
            'exactly one line -- not read as clean.\nfound $blind');
    expect(blind.single, contains('wall'),
        reason: 'the report must name the binding it could not resolve.');
    expect(blind.single, contains('${f.path}'),
        reason: 'a suspicion with no file:line is a feeling, not a finding.');
    // The docstring quotes `wall()` on purpose: prose is not a call.
    expect(blind.where((b) => b.contains('The docstring quotes')), isEmpty);
  });

  test('the clock table agrees with the Python running this test', () {
    // `_wallClockPaths` is a claim about what the wall clock is. Made from
    // memory, it was wrong on the very first entry that could be checked:
    // `time.perf_counter` was in the ban and is not a wall clock --
    // `get_clock_info` reports it monotonic and non-adjustable.
    //
    // That matters in the real direction, not just for tidiness: a guard that
    // bans `perf_counter` pushes the fix for a wall-clock bug onto a monotonic
    // clock (fine) -- and a guard that trusted that list to *find* reads would
    // have been searching for something that is not there.
    //
    // So the table is checked against the interpreter, not against this
    // comment. If a future Python changes what any of these is, this goes red.
    final res = Process.runSync('python3', [
      '-c',
      'import time,json\n'
          'out={}\n'
          'for n in ["time","perf_counter","monotonic","process_time",'
          '"thread_time"]:\n'
          '    ci=time.get_clock_info(n)\n'
          '    out[n]=[ci.monotonic,ci.adjustable]\n'
          'print(json.dumps(out))\n',
    ]);
    expect(res.exitCode, 0, reason: 'python3 probe failed: ${res.stderr}');

    final table =
        (jsonDecode((res.stdout as String).trim()) as Map).cast<String, List>();
    bool isWall(String name) {
      final row = table[name]!;
      return row[0] == false && row[1] == true;
    }

    // A wall clock is neither monotonic nor free of a host that can step it.
    // `time.time` is exactly that; the four below are not.
    expect(isWall('time'), isTrue,
        reason: 'time.time must be the wall clock: '
            'monotonic=${table['time']![0]}, adjustable=${table['time']![1]}. '
            'If this ever reports otherwise the guard is wrong at its root.');

    for (final safe in const [
      'perf_counter',
      'monotonic',
      'process_time',
      'thread_time',
    ]) {
      expect(isWall(safe), isFalse,
          reason: 'time.$safe is not a wall clock (monotonic='
              '${table[safe]![0]}, adjustable=${table[safe]![1]}). '
              '${safe == 'perf_counter' ? 'It WAS on the ban list until this '
                  'tick checked it against the interpreter, and a guard that '
                  'forbids the safe clock pushes the fix for a wall-clock bug '
                  'onto a wall clock.' : ''}');
      expect(_wallClockPaths.contains('time.$safe'), isFalse,
          reason: 'time.$safe must stay off the wall-clock table.');
    }

    // `time_ns` is the same clock as `time` at nanosecond resolution, and
    // `get_clock_info` has no entry under that name -- so it is checked by
    // construction against `time`, not asked about directly.
    expect(_wallClockPaths.contains('time.time_ns'), isTrue,
        reason: 'time_ns is the wall clock at ns resolution and must be in '
            'the table.');
  });
}
