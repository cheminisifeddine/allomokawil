// The fixtures no test reads.
//
// `test/fixtures/*.py.fixture` are the committed vectors for the Python reader
// in `tool_clock_seam_test.dart` -- the shapes no tracked instrument contains,
// because they deliberately read the wall clock that the instrument sweep
// forbids. They are kept out of that sweep by their **extension**, and that
// exclusion is load-bearing rather than cosmetic; case 5 below is what keeps it
// load-bearing.
//
// So the fixtures live in a directory the guard sweep deliberately does not
// walk, and they are read one literal name at a time from a test case. Nothing
// ever connected the two ends. A test that is deleted, renamed or moved takes
// its fixture's only reference with it, and the suite stays green while
// `test/fixtures/` quietly accumulates vectors that guard nothing -- the same
// class of hole `app_source_scope_test.dart` was written for on the app side,
// mirrored onto the suite's own test data: there, a Dart file the app ships
// was readable by no source sweep; here, a vector a committed guard depends on
// is readable by no test.
//
// The valid-Python sweep in `tool_clock_seam_test.dart` does not catch this,
// and it cannot be asked to: it enumerates the directory and compiles each
// fixture, so an orphan compiles perfectly. An **empty file** compiles too
// (verified: `python3 -c "compile('', 'f', 'exec')"` exits 0), so a fixture
// truncated to nothing by a bad edit reads green there as well. That guard
// answers "is this vector real Python"; this file answers "does any test read
// it", and only the second question notices a vector nobody is using.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The fixtures the repo actually ships, as `test/fixtures/<name>`.
///
/// Through `git ls-files`, not a directory listing: the valid-Python sweep in
/// `tool_clock_seam_test.dart` enumerates `Directory('test/fixtures')` off the
/// filesystem, so an untracked file left behind by any earlier tick is swept
/// there while this census -- which is about what the repo ships -- must not
/// see it. Case 4 is where the two enumerations are required to agree.
List<String> shippedFixtures() {
  final result = Process.runSync(
    'git',
    ['ls-files', '--', 'test/fixtures/*.py.fixture'],
    workingDirectory: Directory.current.path,
  );
  expect(result.exitCode, 0,
      reason: 'git ls-files failed (${result.stderr}) -- without it this '
          'census would compare an empty set against an empty set and read as '
          'a clean box.');
  final paths = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.endsWith('.py.fixture'))
      .toList()
    ..sort();
  return paths;
}

/// Every tracked test, as `test/...dart`.
///
/// The same enumeration `app_source_scope_test.dart` uses, so a guard living
/// outside `test/` would still be read -- though for this census `test/` is the
/// only place a reference can be, since a fixture name is meaningless to the
/// loop's Python tools.
List<String> trackedTests() {
  final result = Process.runSync(
    'git',
    ['ls-files', '--', 'test/*.dart'],
    workingDirectory: Directory.current.path,
  );
  expect(result.exitCode, 0,
      reason: 'git ls-files failed (${result.stderr})');
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.endsWith('.dart'))
      .toList()
    ..sort();
}

/// The source with every comment blanked to spaces, offsets preserved.
///
/// The same instrument, and for the same reason, as `app_source_scope_test`:
/// prose shadowed code there, minutes after the fix it documents, because the
/// name being looked for was quoted in the doc comment explaining the fix. A
/// doc comment mentioning a fixture is not a test using it, and a census that
/// counts prose reports coverage it never measured.
///
/// String literals are tracked so a `//` or `/*` **inside** a string cannot be
/// mistaken for a comment and blank away a real reference on the same line --
/// the failure mode here would be a false red, which is worse than useless in
/// a guard.
String blankComments(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  var quote = '';      // '', "'" or '"' while inside a string
  var raw = false;     // r'' / r"" is not escaped by a backslash
  var blockDepth = 0;

  String nextRawMarker() {
    if (i + 1 >= n) return '';
    final c = src[i];
    if ((c == 'r' || c == 'R') && (src[i + 1] == "'" || src[i + 1] == '"') &&
        !(i > 0 && _isIdentChar(src[i - 1]))) {
      return c;
    }
    return '';
  }

  while (i < n) {
    final c = src[i];

    // Inside a string: copy through to its end, honouring escapes unless raw.
    if (quote.isNotEmpty) {
      out.write(c);
      i++;
      if (!raw && c == r'\' && i < n) {
        out.write(src[i]);
        i++;
        continue;
      }
      if (c == quote) quote = '';
      continue;
    }

    // Inside a block comment.
    if (blockDepth > 0) {
      if (src.startsWith('/*', i)) {
        out.write('  ');
        i += 2;
        blockDepth++;
        continue;
      }
      if (src.startsWith('*/', i)) {
        out.write('  ');
        i += 2;
        blockDepth--;
        continue;
      }
      out.write(c == '\n' ? '\n' : ' ');
      i++;
      continue;
    }

    // A raw marker opens a string on the very next character.
    final marker = nextRawMarker();
    if (marker.isNotEmpty) {
      out.write(marker);
      i++;
      raw = true;
      quote = src[i];
      out.write(quote);
      i++;
      continue;
    }

    // A string opens.
    if (c == "'" || c == '"') {
      quote = c;
      raw = false;
      out.write(c);
      i++;
      continue;
    }

    if (c == '/' && i + 1 < n && src[i + 1] == '/') {
      while (i < n && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }

    if (c == '/' && i + 1 < n && src[i + 1] == '*') {
      out.write('  ');
      i += 2;
      blockDepth = 1;
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

bool _isIdentChar(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

/// The 1-based lines of [src] that mention [name] anywhere, comments included.
List<int> linesMentioning(String src, String name) {
  final hits = <int>[];
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(name)) hits.add(i + 1);
  }
  return hits;
}

void main() {
  group('the fixtures every test depends on', () {
    late List<String> fixtures;
    late List<String> tests;

    setUpAll(() {
      fixtures = shippedFixtures();
      tests = trackedTests();
    });

    test('this file found the fixtures to census', () {
      // The positive contract. Without it every case below compares two empty
      // sets and passes, which is exactly how a census that reads nothing is
      // indistinguishable from a repo with nothing to read.
      //
      // 13 is a FLOOR, not a ceiling: adding a vector must not require editing
      // this line. It exists because the orphan check is vacuous if the fixture
      // directory is empty -- a mass `git rm` of every vector would turn this
      // file into a green test that governs no test data at all.
      expect(fixtures.length, greaterThanOrEqualTo(13),
          reason: 'only ${fixtures.length} fixtures are committed under '
              'test/fixtures/, but 13 were shipped on 3 Oct. Either they were '
              'deleted, or this census stopped recognising the shape of a '
              'fixture and is measuring nothing.\n'
              'seen: ${fixtures.join(', ')}');
      expect(tests, isNotEmpty,
          reason: 'no tracked test exists, so no fixture can have a reader');
    });

    test('every committed fixture is read by some test', () {
      // The contract, and the hole this file was written for. Stated as a fact
      // about fixtures rather than about tests: a test with no fixture is
      // normal and fine; a fixture with no test is a vector nobody checks,
      // sitting in a directory the guard sweep deliberately cannot see.
      final orphans = <String>[];
      final detail = <String>[];
      for (final fixture in fixtures) {
        final name = fixture.split('/').last;
        final readers = <String>[];
        for (final t in tests) {
          final src = File(t).readAsStringSync();
          // Comments are blanked first: a doc comment quoting a fixture name
          // is documentation, not a reader.
          if (blankComments(src).contains(name)) readers.add(t);
        }
        if (readers.isEmpty) orphans.add(fixture);
        if (readers.isEmpty) {
          final prose = _proseMentionSites(tests, name);
          detail.add(prose.isEmpty
              ? '$fixture -- read by no test at all'
              : '$fixture -- only mentioned in comments: ${prose.join(', ')}');
        }
      }
      expect(orphans, isEmpty,
          reason: 'these fixtures are committed but NO test reads them, so '
              'each one is a test vector that guards nothing. The valid-Python '
              'sweep still passes them -- it asks "is this real Python", not '
              '"does anything read it", and an empty file is valid Python.\n'
              '${detail.join('\n')}\n'
              'Either the test that used this vector was deleted, in which case '
              'the vector goes with it (`git rm test/fixtures/<name>`), or the '
              'vector is new work that has not been written yet.');
    });

    test('no fixture is held in place by a comment alone', () {
      // The trap that bit `app_source_scope_test.dart`: prose shadowing code.
      // Here it is a real risk rather than a hypothetical one, because these
      // fixture names are exactly the sort of thing a doc comment quotes when
      // it explains which vector a case uses. A census that counted prose
      // would report that vector as covered by the very case whose comment
      // mentions it, while the code below that comment had been deleted.
      //
      // Named separately from the contract above so the failure message can
      // point at the file and line to fix, which is more actionable than
      // "orphan".
      final proseOnly = <String>[];
      for (final fixture in fixtures) {
        final name = fixture.split('/').last;
        var inCode = false;
        for (final t in tests) {
          if (blankComments(File(t).readAsStringSync()).contains(name)) {
            inCode = true;
            break;
          }
        }
        if (!inCode) {
          final prose = _proseMentionSites(tests, name);
          if (prose.isNotEmpty) {
            proseOnly.add('$fixture -- only in comments, at '
                '${prose.join(', ')}');
          }
        }
      }
      expect(proseOnly, isEmpty,
          reason: 'these fixtures are named in comments but in no executable '
              'line, so the comment is the only thing keeping them in the '
              'census:\n${proseOnly.join('\n')}');
    });

    test('the fixture directory and the tracked set are the same set', () {
      // The two enumerations in this repo -- `git ls-files` here,
      // `Directory('test/fixtures').listSync()` in the valid-Python sweep --
      // must agree, in both directions, and this is the only place that says
      // so.
      //
      // A strays-only file is swept as if it were shipped data, so its
      // failures are unreproducible from a clean checkout. A missing-only file
      // is worse: the valid-Python sweep globs the filesystem, so a tracked
      // fixture deleted from disk but not from the index simply stops being
      // checked, with nothing failing.
      final onDisk = Directory('${Directory.current.path}/test/fixtures')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split('/').last)
          .where((n) => n.endsWith('.py.fixture'))
          .toSet();

      final tracked = fixtures.map((f) => f.split('/').last).toSet();

      final strays = onDisk.difference(tracked).toList()..sort();
      final missing = tracked.difference(onDisk).toList()..sort();

      expect(strays, isEmpty,
          reason: 'these files are under test/fixtures/ but are NOT tracked, so '
              'the valid-Python sweep polices them while a clean checkout does '
              'not have them -- a guard whose failures nobody can reproduce:\n'
              '${strays.join('\n')}');
      expect(missing, isEmpty,
          reason: 'these fixtures are tracked but absent from the directory, '
              'so the filesystem-globbing valid-Python sweep silently stops '
              'checking them and no test fails:\n${missing.join('\n')}');
    });

    test('the .py.fixture extension is what keeps the vector sweep blind',
        () {
      // The naming convention IS the isolation mechanism. `_instruments()` in
      // `tool_clock_seam_test.dart` enumerates `git ls-files -- '*.py'`, which
      // does not match `*.py.fixture`; a fixture written as `.py` would be
      // collected as a real instrument and the guard would fail on its own test
      // data, since every fixture reads the wall clock on purpose.
      //
      // Proven rather than assumed, because it is the kind of claim that is
      // true right up until someone "tidies" the extensions:
      //   $ printf 'import time\nS = time.time()\n' > test/fixtures/p.py
      //   $ git add -N test/fixtures/p.py && git ls-files -- '*.py'
      //   test/fixtures/p.py          <-- collected
      final result = Process.runSync(
        'git',
        ['ls-files', '--', '*.py'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0,
          reason: 'git ls-files failed (${result.stderr})');
      final instruments = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // Positive half first: the enumeration must still see real instruments,
      // or "collects nothing" is true for the wrong reason and this test is
      // green on a repo whose guard watches nothing.
      expect(instruments.length, greaterThanOrEqualTo(10),
          reason: 'only ${instruments.length} tracked .py instruments, so the '
              'sweep this fixture names are hidden from has stopped working '
              'and the assertion below proves nothing.');
      expect(instruments.any((p) => p.startsWith('tool/')), isTrue,
          reason: 'the loop tools must stay in the instrument set: '
              '${instruments.join(', ')}');

      final leaked = instruments.where((p) => p.startsWith('test/fixtures/'));
      expect(leaked, isEmpty,
          reason: 'a fixture under test/fixtures/ is tracked with a .py '
              'extension, so the instrument sweep now reads it as real code. '
              'Every fixture deliberately reads the wall clock, so this makes '
              'the guard fail on its own test data:\n${leaked.join('\n')}');
    });
  });
}

/// "file:line" for every **comment** mention of [name].
///
/// A list, not a formatted string: this is compared with `isNotEmpty`, and the
/// first revision returned a display string whose fallback was the literal
/// `'nothing'` -- never empty, so the prose-only case fired for *every* orphan
/// and reported "only in comments, at nothing". A guard that cannot tell
/// "mentioned in a comment" from "mentioned nowhere" is worse than no guard,
/// because the message then contradicts itself and trains the reader to
/// ignore it.
List<String> _proseMentionSites(List<String> tests, String name) {
  final out = <String>[];
  for (final t in tests) {
    final src = File(t).readAsStringSync();
    if (!src.contains(name)) continue;
    if (blankComments(src).contains(name)) continue; // a real reader, not prose
    for (final line in linesMentioning(src, name)) {
      out.add('$t:$line');
    }
  }
  return out;
}
