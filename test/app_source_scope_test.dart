// The one Dart file the app ships that no source sweep could see.
//
// `lib/main.dart` sits beside `lib/src/`, not inside it, so every rule written
// as `Directory('lib/src')` skipped it — and the file that was skipped is the
// entry point, where the app wires its crash hooks, its clock, its API client,
// its auth state and its location state, and hands two futures to
// `unawaited(...)`. The rules were correct; the *enumeration* was narrower than
// the rule. That distinction is the whole defect, and it is invisible from
// inside any one sweep, because each sweep faithfully checked its own files.
//
// Proven before this file existed, not asserted from reading. A
// `ScaffoldMessenger` call was planted in `lib/main.dart` and the four
// `lib/src`-scoped sweeps were run together:
//
//   +21: All tests passed!
//
// `snack_rule_sweep_test.dart` exists precisely so a tenth copy of the snack
// rule cannot be born quietly, and the copy was planted in the one file it was
// blind to. All three app-wide sweeps were widened to `lib/` in this tick and
// `main.dart` passes every one of them, so nothing was hiding — the hole was
// the finding, and this file is what keeps it shut.
//
// The census below is the durable half. It reads every test that scans source
// and records the *root* each one walks, then asserts two things: that
// `lib/main.dart` is inside the set of files some sweep actually reads, and
// that every Dart file `lib/` ships is read by at least one of them. A new
// sweep that narrows to a directory therefore fails here rather than reading
// green over a file it never opened.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every tracked Dart file under `lib/`, entry point included.
///
/// Through `git ls-files`, not a filesystem glob: `lib/` also holds
/// `.dart_tool`/build output on a dirty checkout, and a rule that polices
/// generated files is a rule whose failures nobody can reproduce.
List<String> shippedDartFiles() {
  final result = Process.runSync(
    'git',
    ['ls-files', '--', 'lib/*.dart'],
    workingDirectory: Directory.current.path,
  );
  expect(result.exitCode, 0,
      reason: 'git ls-files failed (${result.stderr}) — without it this '
          'census would compare an empty set against an empty set and read as '
          'a clean box.');
  final paths = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.endsWith('.dart'))
      .toList()
    ..sort();
  expect(paths, isNotEmpty,
      reason: 'the app ships no Dart, so every sweep below is vacuous');
  return paths;
}

/// The root shapes this census has been taught to recognise.
///
/// A **set**, and deliberately not a list of guards: the failure being guarded
/// against is a root nobody remembered to update. So the census *reads* each
/// sweep's own enumeration and fails on a shape it has not been shown, by name.
const _knownRoots = <String>{
  // Recursive walks of the whole app directory — the only shapes that reach
  // `lib/main.dart`.
  'lib',
  // Recursive walks of the layer tree. **Every one of these is exactly one
  // level short of the entry point**, which is the defect this file records.
  'lib/src',
  'lib/src/screens',
  'lib/src/data',
  'lib/src/models',
  'lib/src/core/format',
  // Whole-file reads of a named source file.
  'lib/src/core/theme/motion.dart',
  'lib/src/core/theme/app_theme.dart',
  // Instrument sweeps over Python: a different language and a different
  // question, listed so the census says so explicitly rather than by omission.
  '*.py',
};

/// The literal roots a source sweep enumerates, read out of its own source.
///
/// Every fix in this file's first draft was a failure of *this* reader rather
/// than of the tree, and both are worth keeping:
///
///   * **Prose shadowed code.** The root was found by taking the first
///     `Directory('…')` in the file — and the first one in `snack_rule_sweep`
///     is the `Directory('lib/src')` quoted in the doc comment explaining this
///     very fix. A reader that counts prose reads the *old* root, so the guard
///     reported the messenger sweep as blind to `main.dart` minutes after it
///     had been widened. Comments are blanked before the search for that
///     reason, and it is why the doc comments in the three widened files spell
///     the old root as a bare `lib/src` rather than as `Directory('lib/src')`.
///   * **First match is not the guard's root.** `tool_clock_seam_test.dart`
///     opens a `Directory(...)` on its fixtures directory *inside a test body*,
///     long after the helper that enumerates the repo's real instruments. So
///     the roots are **all** of them, and only the ones declared before
///     `void main(` — a top-level enumeration helper is a guard's root; a
///     directory a test opens at runtime is not.
List<String> _rootsOf(String source) {
  final code = _blankComments(source);
  final beforeMain = code.indexOf('void main(');
  final scope = beforeMain < 0 ? code : code.substring(0, beforeMain);

  final roots = <String>[];
  for (final m in RegExp(
          r"""Directory\(\s*['"]([^'"]+)['"]""").allMatches(scope)) {
    roots.add(m.group(1)!);
  }
  for (final m in RegExp(
          r"""['"]ls-files['"]\s*,\s*\[\s*['"]([^'"]+)['"]""").allMatches(scope)) {
    roots.add(m.group(1)!);
  }
  return roots;
}

/// The source with every comment blanked to spaces, offsets preserved.
///
/// String bodies are kept, because the thing being read *is* a string literal:
/// the directory a sweep walks is written `Directory('lib')`. Only comments go,
/// and only because a doc comment can quote the very code it documents.
String _blankComments(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    final isRaw = (c == 'r' || c == 'R') &&
        i + 1 < n &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        !(i > 0 && _isIdentChar(src[i - 1]));
    if (isRaw) {
      // Step over the marker, then let the string branch below handle the body.
      out.write(src[i]);
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
      var depth = 1;
      while (i < n && depth > 0) {
        if (src.startsWith('/*', i)) {
          out.write('  ');
          i += 2;
          depth++;
        } else if (src.startsWith('*/', i)) {
          out.write('  ');
          i += 2;
          depth--;
        } else {
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = src.startsWith(c * 3, i);
      final term = c * (triple ? 3 : 1);
      out.write(term);
      i += term.length;
      while (i < n) {
        if (src.startsWith(term, i)) {
          out.write(term);
          i += term.length;
          break;
        }
        if (!triple && src[i] == '\n') break; // unterminated: do not run away
        if (src[i] == r'\' && !isRaw) {
          out.write(src[i]);
          i++;
          if (i < n) {
            out.write(src[i] == '\n' ? '\n' : src[i]);
            i++;
          }
          continue;
        }
        out.write(src[i]);
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

bool _isIdentChar(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

/// One source-scanning guard and every root it declares.
class _Root {
  _Root(this.file, this.roots);

  /// The guard, as `test/…dart`.
  final String file;

  /// The literal directories/specs it enumerates. Empty when the shape was not
  /// recognised, which is reported by name rather than guessed at.
  final List<String> roots;

  bool get reads => roots.isNotEmpty;
}

/// A sweep is any test that reads another file's source text.
///
/// `Directory('/tmp/shots').createSync()` is a screenshot directory and is not
/// this; the test must call `readAsStringSync`/`readAsLinesSync`, and it must
/// also name a root that looks like app source. Both halves are required so
/// that neither a screenshot suite nor a pure unit test is counted as a guard.
bool _isSourceSweep(String path, String source) {
  if (!source.contains('readAsStringSync') &&
      !source.contains('readAsLinesSync')) {
    return false;
  }
  return RegExp(r"""\blib(?:/src)?[/"']""").hasMatch(source);
}

void main() {
  group('the app source every sweep claims to cover', () {
    late List<String> shipped;
    late Map<String, _Root> sweeps;

    setUpAll(() {
      shipped = shippedDartFiles();

      // Every tracked test, read through the same enumeration the rest of this
      // file uses, so a guard that lives outside `test/` would still be seen.
      final ls = Process.runSync(
        'git',
        ['ls-files', '--', 'test/*.dart'],
        workingDirectory: Directory.current.path,
      );
      expect(ls.exitCode, 0, reason: 'git ls-files failed (${ls.stderr})');

      sweeps = {};
      for (final rel in (ls.stdout as String).split('\n')) {
        final path = rel.trim();
        if (path.isEmpty) continue;
        final src = File(path).readAsStringSync();
        if (!_isSourceSweep(path, src)) continue;
        sweeps[path] = _Root(path, _rootsOf(src));
      }
    });

    test('this file found the app-wide sweeps to census', () {
      // The coverage half. Without it the census below compares two empty sets
      // and passes, which is how a source guard that watches nothing is
      // indistinguishable from one that watches everything.
      expect(sweeps.length, greaterThanOrEqualTo(8),
          reason: 'only ${sweeps.length} test files read app source: this '
              'file stopped recognising the shape of a source sweep, so the '
              'census below is measuring nothing.\n'
              'seen: ${sweeps.keys.join(', ')}');
    });

    test('every Dart file the app ships is read by some sweep', () {
      // The contract, stated as a fact about files rather than about rules.
      // A sweep whose own rule is narrow is not wrong for being narrow; a
      // *file* nothing reads is the hole, because every rule about the app
      // can be true while the entry point answers to none of them.
      final read = <String>{};
      for (final sweep in sweeps.values) {
        for (final spec in sweep.roots) {
        // A glob spec: `*.py` covers no Dart file, which is the point.
        if (spec.contains('*')) continue;
        final dir = Directory(spec);
        final scope = dir.existsSync()
            ? dir
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .map((f) => f.path)
            : <String>[];
        for (final p in scope) {
          if (p.endsWith('.dart')) read.add(p);
        }
        }
      }

      final unwatched = shipped
          .where((f) => !read.contains(f))
          .toList()
        ..sort();
      expect(unwatched, isEmpty,
          reason: 'these Dart files ship in the app and NO source sweep reads '
              'them, so every rule this repo holds about its own source is '
              'silent about them:\n${unwatched.join('\n')}\n'
              'The fix is to widen the guard\'s root — `Directory(\'lib\')` '
              'recursive, not `Directory(\'lib/src\')` — not to relax the rule.');
    });

    test('the entry point is in the set, by name', () {
      // The file the defect was found on, named explicitly so that moving or
      // deleting it is a loud failure rather than a silent drop in coverage.
      // A blanket "is every file watched" rule passes just as happily when the
      // entry point moves to a directory nobody walks.
      final roots = sweeps.values.expand((s) => s.roots).toSet().toList()..sort();
      expect(roots, contains('lib'),
          reason: 'no sweep walks `lib/` itself, so `lib/main.dart` — beside '
              'lib/src/, not inside it — is readable by no guard at all.\n'
              'roots seen: ${roots.join(', ')}');
    });

    test('every root a sweep declares is a shape this census knows', () {
      // The positive contract, and the reason the constants above are a set
      // rather than a list. A sweep that invents a third enumeration shape
      // fails here by name, so the census cannot quietly stop reading it and
      // then report coverage it never measured.
      final unknown = <String>[];
      for (final sweep in sweeps.values) {
        for (final spec in sweep.roots) {
          if (!_knownRoots.contains(spec)) {
            unknown.add('${sweep.file} -> $spec');
          }
        }
      }
      expect(unknown, isEmpty,
          reason: 'these sweeps enumerate files in a shape this census does '
              'not model, so their coverage is neither measured nor claimed. '
              'Teach it the shape in `_rootsOf` and add the root to '
              '_knownRoots.\n${unknown.join('\n')}');
    });

    test('the census would have caught the blind spot it was written for', () {
      // Pin the fix at the level it was made: assert the *sweep reaches the
      // file*, not that the tree is clean. Planting `ScaffoldMessenger` in
      // `lib/main.dart` before this tick left
      // `snack_rule_sweep_test.dart` green at 21/21 — this case is the one
      // that names that shape, and it fails if the entry point is ever moved
      // out of every enumerated root again.
      final mainSrc = File('lib/main.dart');
      expect(mainSrc.existsSync(), isTrue,
          reason: 'the entry point moved; every root that did not move with '
              'it is now blind, and this census cannot see a file it cannot '
              'find.');

      final watchesIt = sweeps.values
          .where((s) => s.roots.contains('lib'))
          .map((s) => s.file)
          .toList()..sort();
      expect(watchesIt, isNotEmpty,
          reason: 'no sweep walks `lib/` recursively, so nothing reads '
              'lib/main.dart.');
      // And at least one of them is the messenger rule that was bypassed, so
      // the specific hole cannot be re-opened by that guard alone.
      expect(
          watchesIt.any((f) => f.contains('snack_rule_sweep')),
          isTrue,
          reason: 'the messenger sweep must keep walking `lib/`: that is the '
              'exact guard a ScaffoldMessenger planted in main.dart bypassed '
              '(21/21 green before this fix).\nwatches lib/: '
              '${watchesIt.join(', ')}');
    });
  });
}
