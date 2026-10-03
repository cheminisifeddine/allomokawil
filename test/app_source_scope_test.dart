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

import 'support/source_text.dart';

/// Every Dart file the app ships under `lib/`, entry point included.
///
/// **The two sides of the coverage contract must enumerate the same set**, and
/// for most of this file's life they did not. The reader below returned
/// `git ls-files` output; the case that consumes it walked `Directory(root)`
/// on the **filesystem**. So the census compared *tracked* files against
/// *on-disk* roots, and a Dart file under `lib/` that was never `git add`-ed
/// was invisible to the question "does any sweep read this?" -- the same
/// silent-guard hole the previous tick closed for `test/`, still open here for
/// the half of the tree that matters most.
///
/// Neither enumeration is right on its own, so both are read and the difference
/// is a hard failure in *both* directions:
///
///   * on disk, untracked -> the file exists, the rules apply to it, and nothing
///     is enforcing them. This is a guard nobody is running, not a file nobody
///     wrote.
///   * tracked, not on disk -> a green run on this box cannot have compiled it,
///     so the census was crediting coverage to a file that does not exist here.
///
/// The on-disk walk excludes `.dart_tool/` for the reason the doc comment above
/// gives: generated output is not source, and a rule that polices generated
/// files is a rule whose failures nobody can reproduce.
List<String> shippedDartFiles() {
  final onDisk = _dartFilesUnder('lib');
  expect(onDisk, isNotEmpty,
      reason: 'no Dart under lib/ on disk, so every sweep below is vacuous '
          'against a tree that was never read');

  final result = Process.runSync(
    'git',
    ['ls-files', '--', 'lib/*.dart'],
    workingDirectory: Directory.current.path,
  );
  expect(result.exitCode, 0,
      reason: 'git ls-files failed (${result.stderr}) — the census can no '
          'longer tell a tracked file from an untracked one, so "no file is '
          'unwatched" would be the only answer it could give.');
  final tracked = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && l.endsWith('.dart'))
      .toList()
    ..sort();

  // Direction 1 — shipped but untracked. The exact moment a new screen or model
  // is written is the moment it is least likely to be added, and until it is,
  // this census would cheerfully report that every file is watched while the
  // file itself is not in the set being judged.
  final untracked = onDisk.where((p) => !tracked.contains(p)).toList()..sort();
  expect(untracked, isEmpty,
      reason: 'these Dart files sit under lib/ but are not tracked by git, so '
          'the coverage census cannot judge them: a file nobody `git add`-ed is '
          'a file no source sweep is asserted to read, however many guards walk '
          'lib/.\n${untracked.join('\n')}\n'
          'Either the file belongs in the app (git add it) or it does not '
          '(delete it). Do not fix this by relaxing the census.');

  // Direction 2 — tracked but absent. The mirror, and the one that used to be
  // the only direction anyone thought to check. A file git lists that this
  // checkout does not have is a file no local run compiled, so crediting it as
  // "read by some sweep" is a claim about a tree that does not exist here.
  final missing = tracked.where((p) => !onDisk.contains(p)).toList()..sort();
  expect(missing, isEmpty,
      reason: 'git tracks these Dart files under lib/ but they are not on disk '
          'in this checkout, so the census would credit them to a sweep that '
          'cannot open them:\n${missing.join('\n')}\n'
          'This is normally a dirty or partial checkout; `git status --short` '
          'says which.');

  return onDisk;
}

/// Every `.dart` file on disk under [dir], repo-relative and sorted.
///
/// Shared by the shipped-set reader and the untracked-guard case so the two
/// cannot drift apart again — the defect being fixed is precisely that two
/// readers of "the Dart in this directory" disagreed about what they saw.
List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  expect(root.existsSync(), isTrue, reason: '$dir/ does not exist');
  return root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .where((p) => p.endsWith('.dart') && !p.contains('/.dart_tool/'))
      .toList()
    ..sort();
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
  'lib/src/widgets',
  'lib/src/core/format',
  // Whole-file reads of a named source file. Nothing declares these *today* --
  // `contrast_tokens_test.dart` holds them in a `const String`, a shape the
  // reader does not model -- so they are kept as a modelled shape rather than
  // pruned as dead: a guard that walks one of them is understood, not flagged.
  'lib/src/core/theme/motion.dart',
  'lib/src/core/theme/app_theme.dart',
  // The suite reading its own test directory: `wall_clock_seam_site_test.dart`
  // walks `Directory('test')` to police other guards. It holds no shipped Dart,
  // so it contributes no coverage -- it is listed so the census *names* the
  // shape instead of tripping over it.
  'test',
  // git pathspecs. `lib/*.dart` and `test/*.dart` are the `ls-files` reads that
  // find the shipped app and the guards themselves -- a census that flagged its
  // own enumeration as unmodelled would be refusing to describe how it finds
  // the files it judges.
  'lib/*.dart',
  'test/*.dart',
  // Instrument sweeps over Python: a different language and a different
  // question, listed so the census says so explicitly rather than by omission.
  '*.py',
};

/// The app rules that are only enforced because a named guard walks the source.
///
/// **Names, not a count.** The census used to answer "are enough sweeps here?"
/// with `sweeps.length >= 8`, and that number cannot say *which* guard went
/// dark. Proven on the tick that wrote this: renaming every `readAsStringSync`
/// in `no_empty_text_site_test.dart` — the empty-text rule, an app-wide rule
/// with no other enforcer — left the whole census **green at +5**, because 13
/// other sweeps still satisfied `>= 8` and no case named that file. A rule that
/// is silently unregistered is worse than one that is absent, because the tree
/// still looks policed.
///
/// So the positive half is now a fact about the repo: each guard that carries
/// one of the app's own rules must be *recognised* and must declare a root this
/// census can model. Both failure directions are reported by name.
///
/// The messenger guard was already pinned by the blind-spot case below; it is
/// listed here too because that pin is about the entry point specifically and
/// this is about the guard existing at all.
const _appRuleGuards = <String, String>{
  'test/snack_rule_sweep_test.dart':
      'the snack rule: no second messenger outside the allowed wrappers',
  'test/no_empty_text_site_test.dart':
      'the empty-text rule: no user-visible Arabic string left blank',
  'test/wall_clock_seam_site_test.dart':
      'the wall-clock seam: no app widget reading the clock at build time',
  'test/tool_clock_seam_test.dart':
      'the instrument seam: the Python tools that read the clock',
  'test/layering_test.dart': 'the import layering rule',
  'test/type_scale_test.dart': 'the type-scale rule',
  'test/card_recipe_test.dart': 'the card recipe rule',
  // `motion_test.dart` was absent from this map on 3 Oct (24th) even though it
  // enforces one of the app's own rules -- no screen may type its own duration
  // -- and even though the blind-spot case below already named it. It was in the
  // `appWide` list and nowhere else, which is the whole defect: a rule enforced
  // in every build and described in no by-name list.
  'test/motion_test.dart': 'the motion rule: no screen types its own duration',
  // Named for what they hold, not for where they point: these are the guards
  // whose root was invisible to this census until the reader was taught the
  // shapes below. Before this tick `contrast_tokens`, `failure_reported`,
  // `header_trust_wiring`, `payload_coverage` and `quote_count_copy` declared
  // no root at all -- every one of them walking `lib/` -- so a rule added to
  // any of them could go dark without a word here.
  'test/contrast_tokens_test.dart': 'the contrast-token rule',
  'test/failure_reported_test.dart': 'the failure-reported rule: every caught '
      'failure reaches the user in Arabic',
  'test/header_trust_wiring_test.dart': 'the header trust-signals rule',
  'test/payload_coverage_test.dart': 'the payload-coverage rule',
  'test/quote_count_copy_test.dart': 'the quote-count copy rule',
};

/// The literal each named guard must still carry to be the guard it is
/// registered as.
///
/// **The map above asserts each rule in prose and, until this tick, nothing
/// read those strings back.** So the census could prove a guard exists, reaches
/// Dart the app ships and is listed -- and still could not tell that the rule
/// written beside it is the rule that guard enforces. Rewrite
/// `snack_rule_sweep_test.dart` to police `showDialog` and every case in this
/// file stayed green: the file kept its entry, kept its root and kept the words
/// "the snack rule: no second messenger outside the allowed wrappers" in a map
/// three hundred lines away from the only place the truth lives. A named guard
/// that no longer enforces its name is worse than an unnamed one, because the
/// name is what a later tick reads to decide the rule is covered.
///
/// The fix is one literal per guard, read out of the guard's own **code**: the
/// token its rule is written in. These are not samples chosen to be easy --
/// each is the construct the rule turns on, so losing it means the rule is
/// gone:
///
///   * the messenger rule turns on the one symbol no other screen may call;
///   * the empty-text rule turns on the regex that matches a literal empty
///     return, not on `_emptyReturning`, which is the *table* of function names
///     and would survive a rule that stopped matching empties entirely;
///   * the instrument seam turns on a **Python** path -- a guard reading Dart
///     with the Dart rule is still a wrong rule;
///   * the payload-coverage rule turns on a live endpoint, so renaming the
///     route in the guard without updating the app is a failure.
///
/// Checked against `_blankComments`, never raw source: a guard that keeps the
/// word in its doc comment while enforcing something else is the exact case
/// here, and this file has already been bitten by prose shadowing code once
/// (see `_rootsOf`).
const _ruleEvidence = <String, List<String>>{
  'test/snack_rule_sweep_test.dart': ['ScaffoldMessenger'],
  'test/no_empty_text_site_test.dart': [r'return\s+('],
  'test/wall_clock_seam_site_test.dart': ['DateTime.now()'],
  'test/tool_clock_seam_test.dart': ['time.time_ns'],
  'test/layering_test.dart': ["['data', 'screens', 'widgets']"],
  'test/type_scale_test.dart': [r'fontSize:\s*'],
  'test/card_recipe_test.dart': [r'BorderRadius\.circular'],
  'test/motion_test.dart': [r'duration:\s*(?:const\s+)?Duration\('],
  'test/contrast_tokens_test.dart': [r'wash: Color\(0xFF'],
  'test/failure_reported_test.dart': [r'\bcatch\b'],
  'test/header_trust_wiring_test.dart': [r'NotificationCountTrust\s*\('],
  'test/payload_coverage_test.dart': ['/api/mobile/workers/top'],
  'test/quote_count_copy_test.dart': ['quoteLimit|quotesUsedThisMonth'],
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
_Read _rootsOf(String source) {
  final code = _blankComments(source);
  // `code` is the whole comment-blanked file and **every** pattern below reads
  // all of it rather than `scope`: a guard may enumerate inside a test body --
  // `motion_test.dart` declares its root 290 lines into `main()`, and four
  // more declare theirs there too -- and narrowing to pre-`main` is what hid
  // them. This was the live hole on 3 Oct (21st): the note above used to claim
  // "the two patterns below search all of it" while only the second one did,
  // so a guard whose root was written in a test body read as rootless.

  final roots = <String>[];

  // A bare literal: `Directory('lib')`, `Directory("lib/src")`. Quotes are
  // required, so `Directory lib = Directory('lib')` below is a *different*
  // shape and is read by the next pattern -- both appear in this tree.
  for (final m
      in RegExp(r"""Directory\(\s*['"]([^'"]+)['"]""").allMatches(code)) {
    roots.add(m.group(1)!);
  }

  // The same call behind a type annotation: `final Directory lib =
  // Directory('lib');`. Measured on 3 Oct: 8 of the 14 sweeps this file
  // recognised declared NO root through the pattern above while walking
  // `lib/` all the same, and the coverage half could not tell a guard that
  // walks the app from one that reads a single file. Some of those roots are
  // declared *after* `void main(` -- an enumeration inside a test body is
  // still the guard's root -- hence `code` rather than `scope`.
  for (final m
      in RegExp(r"""Directory\s+\w+\s*=\s*Directory\(\s*['"]([^'"]+)['"]""")
          .allMatches(code)) {
    roots.add(m.group(1)!);
  }

  // `git ls-files` patterns. The *argument list* is what opens with the flag:
  //   Process.runSync('git', ['ls-files', '--', '*.py'])
  // so the pattern to read is the last string in that list, which is why this
  // matches the whole bracket and takes the final quoted run. Demanding the
  // pattern immediately after the flag -- as the first draft did -- could
  // never produce `*.py`, so the root `_knownRoots` has always listed for the
  // instrument sweeps described nothing that any sweep actually declares.
  for (final m
      in RegExp(r"""\[\s*['"]ls-files['"][^\]]*?['"]([^'"]+)['"]\s*\]""")
          .allMatches(code)) {
    roots.add(m.group(1)!);
  }

  // An existence assertion is not an enumeration. Measured on 3 Oct (21st):
  // `payload_coverage_test.dart` holds exactly one `Directory('lib')` literal
  // and it is inside `expect(Directory('lib').existsSync(), isTrue)` -- the
  // reader credits `lib` to it, and a guard that only *asserts a directory
  // exists* then passes for one that reads every file in it. Its real roots are
  // the `<String>[…]` lists below, which are read on their own merits. Crediting
  // a root is a claim about coverage, so a shape that cannot read files is
  // excluded rather than counted as one.
  for (final m
      in RegExp(r"""Directory\(\s*['"]([^'"]+)['"]\s*\)\s*\.existsSync""")
          .allMatches(code)) {
    roots.remove(m.group(1)!);
  }

  // A runtime-built path is not a root this census can resolve, so it is
  // reported as unresolved and never enters `roots`. Carrying it as a literal
  // would put `${Directory.current.path}/test/fixtures` in the coverage set,
  // where it is a directory that does not exist under that name and would
  // contribute nothing while looking like a guard.

  // Roots passed as a list, not written as a `Directory('…')` call:
  // `_dir(<String>['lib'])` and `final roots = <String>['lib/src/screens',
  // 'lib/src/widgets']`. `payload_coverage_test.dart` names all three of its
  // roots this way and none as a literal, which is why the reader above saw an
  // app-wide guard walking nothing. The pattern is anchored on the **typed** list
  // -- `<String>[` -- because an untyped `[…]` is every list in the repo, and a
  // root read out of `['lib', 'lib/src/screens']` in some unrelated set is a
  // false credit in the same way the existence assertion was.
  for (final m in RegExp(r"""<String>\s*\[([^\]]*)\]""").allMatches(code)) {
    for (final item
        in RegExp(r"""['"]([^'"]+)['"]""").allMatches(m.group(1)!)) {
      final spec = item.group(1)!;
      // Only root-shaped entries: a key of a model's field map is a string too.
      if (spec.startsWith('lib') ||
          spec.startsWith('test/') ||
          spec == '*.py') {
        roots.add(spec);
      }
    }
  }

  // A root built at runtime cannot be resolved here and is **not** guessed at.
  // It is returned separately so the caller can tell "this guard walks the app"
  // from "this guard's root is a shape nobody has read", and kept out of `roots`
  // so it cannot enter the coverage set as a literal that names no directory.
  final unresolved = roots.where((r) => r.contains(r'${')).toList()..sort();
  roots.removeWhere((r) => r.contains(r'${'));

  return _Read(
      roots
        ..sort()
        ..toSet().toList(),
      unresolved);
}

/// The two answers a root reader can give, kept apart on purpose.
class _Read {
  _Read(this.roots, this.unresolved);

  /// Roots that are literal paths this census can model.
  final List<String> roots;

  /// Roots written as a runtime expression. Not a modelled root, not a failure
  /// on its own — a fact for the caller to pin by name.
  final List<String> unresolved;
}

/// What one declared root actually resolves to in this checkout.
///
/// The barren-root case and the unnamed-guard case below ask the *same*
/// question -- "does this root reach Dart the app ships?" -- and they were
/// written as two copies until this tick, which is how one of them grew a
/// message the other could not produce. One resolver, so a root that one case
/// calls covered cannot be called barren by the other.
class _RootHit {
  _RootHit({required this.dart, required this.shippedDart, this.reason});

  /// Dart files the root reads. For a pathspec these are the tracked matches,
  /// for a directory they are the files on disk.
  final List<String> dart;

  /// The subset of [dart] that the app actually ships.
  final List<String> shippedDart;

  /// Non-null exactly when [shippedDart] is empty, carrying the sentence the
  /// caller needs. Three causes, named apart because they are three different
  /// mistakes: absent from the checkout, a live directory holding no app Dart,
  /// and a pathspec that matches nothing.
  final String? reason;

  bool get reachesNothing => shippedDart.isEmpty;
}

/// Resolve one declared root. `shipped` is the census's shipped-Dart list.
_RootHit _resolveRoot(String spec, List<String> shipped) {
  if (spec.contains('*')) {
    // A pathspec is answered by git, not by the filesystem: it is not a path.
    final r = Process.runSync(
      'git',
      ['ls-files', '--', spec],
      workingDirectory: Directory.current.path,
    );
    expect(r.exitCode, 0,
        reason: 'git ls-files failed (${r.stderr}) -- this census cannot tell '
            'an empty pathspec from an unreadable one');
    final hits = (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final dart = hits.where((p) => p.endsWith('.dart')).toList();
    final reached = dart.where(shipped.contains).toList();
    if (hits.isEmpty) {
      return _RootHit(
        dart: dart,
        shippedDart: reached,
        reason: 'that pathspec matches no tracked file, so the guard reads '
            'nothing',
      );
    }
    if (reached.isEmpty) {
      return _RootHit(
        dart: dart,
        shippedDart: reached,
        reason: 'matches ${hits.length} tracked file(s) and reaches none that '
            'the app ships, so its coverage is declared but empty',
      );
    }
    return _RootHit(dart: dart, shippedDart: reached);
  }

  if (!Directory(spec).existsSync() && !File(spec).existsSync()) {
    return _RootHit(
      dart: const <String>[],
      shippedDart: const <String>[],
      reason: 'nothing by that name exists in this checkout, so the guard '
          'reads nothing',
    );
  }

  final dart = spec.endsWith('.dart') ? <String>[spec] : _dartFilesUnder(spec);
  final reached = dart.where(shipped.contains).toList();
  if (reached.isEmpty) {
    return _RootHit(
      dart: dart,
      shippedDart: reached,
      reason: 'reads ${dart.length} Dart file(s) and reaches none that the app '
          'ships, so its coverage is declared but empty',
    );
  }
  return _RootHit(dart: dart, shippedDart: reached);
}

/// Roots this reader cannot resolve, pinned by name so one is never guessed at.
///
/// A root is unmodellable when it is **built at runtime** rather than written as
/// a literal -- `Directory('${Directory.current.path}/test/fixtures')`. Measured
/// 3 Oct: `tool_clock_seam_test.dart` is the only sweep in the tree that does
/// this, and it walks `test/fixtures`, not app source, so it carries no app
/// coverage. Left unnamed it would be either silently dropped or silently
/// mis-modelled as the literal `\${Directory.current.path}/test/fixtures`; named
/// here it fails **by name** if a guard adopts that shape for a root that does
/// carry app coverage.
const _knownUnmodelled = <String, String>{
  'test/tool_clock_seam_test.dart': r'${Directory.current.path}/test/fixtures',
};

/// Why each pin exists, kept beside the pin so deleting one is a decision
/// someone can read rather than a diff nobody understands.
const _whyUnmodelled = <String, String>{
  'test/tool_clock_seam_test.dart':
      'runtime-built path, and it walks test data rather than app source — so '
          'it carries no app coverage either way',
};

/// Roots a sweep may declare that reach **no file the app ships**.
///
/// The case above fails when a guard declares a root this census does not model.
/// This is its mirror, and it is the one that lets coverage go dark quietly: a
/// root that resolves to **nothing** still counts as a root. Measured on 3 Oct
/// (23rd), `Directory('lib/src/screens')` on a directory that no longer holds a
/// screen yields `<String>[]` — no crash, no failure, and a guard that watches
/// the empty set while the census reports its coverage as declared.
///
/// So a declared root must either reach at least one shipped Dart file or be
/// exempt **by name, with a reason**. Each exemption below is also checked for
/// staleness in the same case: the day one of these starts reaching shipped
/// Dart, it has outlived its reason and is deleted rather than left waving.
///
/// That check is not decoration. `lib/*.dart` was listed here on the first run,
/// on the reasoning that a pathspec the census uses on itself cannot be allowed
/// to flag itself. The staleness check failed on it immediately: it does reach
/// shipped Dart, so it was never an exempt root but a real one, and exempting
/// it hid a genuine one behind an invented reason.
const _rootsWithoutShippedDart = <String, String>{
  'test': 'the suite reads its own guards; it ships no app Dart, so it '
      'contributes no app coverage and is named so the census says so instead '
      'of by omission',
  'test/*.dart': 'a git pathspec that finds the guards themselves',
  '*.py': 'the Python instruments: a different language and a different '
      'question, so it covers no Dart file and is claimed as none',
};

/// Guards that reach Dart the app ships yet carry no app rule of their own.
///
/// The unnamed-guard case asks for a fact this census can measure rather than
/// a judgement it cannot: a sweep whose root reaches shipped Dart is enforcing
/// something about app source, so it must be named in `_appRuleGuards`. One
/// sweep in the tree is exempt, and the exemption is stated rather than
/// assumed -- each entry is checked for staleness in the same case, so an entry
/// that stops reading app source has to be deleted.
const _guardsCarryingNoAppRule = <String, String>{
  'test/app_source_scope_test.dart':
      'this census itself: it holds the map of the rules and reads app source '
          'only to ask who else reads it. A census listed in the map it reads would '
          'be measuring its own bookkeeping.',
};

/// The source with every comment blanked to spaces, offsets preserved.
///
/// Now delegated to `support/source_text.dart` rather than re-implemented here.
/// This file used to carry its own copy, and a **second** copy of a source
/// reader is a defect waiting for a rule to be written against the one nobody
/// reads: this copy keeps string bodies (the thing being read *is* a string
/// literal -- a guard's root is written `Directory('lib')`, and blanking the
/// body would erase the directory the census is reporting), the motion rule's
/// reader blanks them because an Arabic string holding `Duration(` is copy,
/// not an animation. One implementation with a flag, so the two cannot drift
/// apart the way two copies did.
///
/// The extraction was mechanical and offset-preserving, so both callers are
/// unchanged in behaviour: `_rootsOf` and the evidence case both search
/// comment-blanked source with the comments alone removed.
String _blankComments(String src) => blankComments(src, blankStrings: false);

/// One source-scanning guard and every root it declares.
class _Root {
  _Root(this.file, this.roots, this.unresolved);

  /// The guard, as `test/…dart`.
  final String file;

  /// The literal directories/specs it enumerates. Empty when the shape was not
  /// recognised, which is reported by name rather than guessed at.
  final List<String> roots;

  /// Roots written as runtime expressions, kept out of [roots] so they cannot
  /// pass for coverage.
  final List<String> unresolved;

  bool get reads => roots.isNotEmpty;

  /// True when every root this guard declares is a shape nobody can read, which
  /// is a different problem from declaring no root at all.
  bool get onlyUnresolved => !reads && unresolved.isNotEmpty;
}

/// A sweep is any test that reads another file's source text.
///
/// `Directory('/tmp/shots').createSync()` is a screenshot directory and is not
/// this; the test must call `readAsStringSync`/`readAsLinesSync`, and it must
/// also name a root that looks like app source. Both halves are required so
/// that neither a screenshot suite nor a pure unit test is counted as a guard.
///
/// **The `readAsStringSync` half is read from comment-blanked source**, and
/// only that half. This classifier was the third reader in this file to be
/// bitten by prose shadowing code, and it was bitten by a file this tick
/// wrote: `test/support/source_text.dart` *documents* the per-line motion scan,
/// so its doc comment quotes `readAsLinesSync()`. Read raw, a helper that
/// reads a string and returns offsets was classified as a guard reading app
/// source, and the case below then failed asking it where it walks.
///
/// The `lib` half deliberately stays on **raw** source, because a root may be
/// declared in prose and that is sometimes the only place it appears:
/// `tool_clock_seam_test.dart` says `lib/` in its opening comment and nowhere
/// in code. Blank that half too and a censused guard silently leaves the
/// census — measured here, not assumed: the first version of this fix dropped
/// it from the recognised set and two cases went red.
///
/// So: prose cannot make a reader *look like* a guard, and prose still lets a
/// guard *be* one. Each half is read in the unit where it is true.
bool _isSourceSweep(String path, String source) {
  final code = _blankComments(source);
  if (!code.contains('readAsStringSync') && !code.contains('readAsLinesSync')) {
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

      // Every test file **on disk**, not only the tracked ones. Measured on this
      // tick: a brand-new guard written as a runtime-built root was completely
      // invisible to this census while it sat untracked, because the
      // enumeration below read `git ls-files`. That is the silent-guard hole in
      // its purest form — the exact moment a new app rule is added is the moment
      // nothing would notice it is unmeasured.
      //
      // `.dart` files on disk only. A build artifact left under `test/` would
      // otherwise be censused as a guard, and a *tracked* file missing from disk
      // would be invisible here while still being real to `flutter test`.
      final ls = Process.runSync(
        'git',
        ['ls-files', '--', 'test/*.dart'],
        workingDirectory: Directory.current.path,
      );
      expect(ls.exitCode, 0, reason: 'git ls-files failed (${ls.stderr})');
      final tracked = (ls.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.endsWith('.dart'))
          .toList();
      // The shared reader, so `test/` and `lib/` are enumerated identically.
      // Measured on this tick: the two halves had each grown their own copy of
      // this walk, and `lib/`'s copy was the one that had never been checked
      // against `git ls-files` at all.
      final onDisk = _dartFilesUnder('test');
      final untrackedOnly = onDisk.where((p) => !tracked.contains(p)).toList()
        ..sort();
      expect(untrackedOnly, isEmpty,
          reason:
              'these Dart files sit under test/ but are not tracked by git, '
              'so this census — and every `git ls-files` sweep in the repo — '
              'cannot see them. A guard written but not added is a rule nobody '
              'is enforcing:\n${untrackedOnly.join('\n')}');

      sweeps = {};
      for (final rel in (ls.stdout as String).split('\n')) {
        final path = rel.trim();
        if (path.isEmpty) continue;
        final src = File(path).readAsStringSync();
        if (!_isSourceSweep(path, src)) continue;
        final read = _rootsOf(src);
        sweeps[path] = _Root(path, read.roots, read.unresolved);
      }
    });

    test('every named app-rule guard is censused, by name', () {
      // The coverage half, stated as facts about the repo. The floor it
      // replaced (`sweeps.length >= 8`) could not tell *which* guard stopped
      // being a sweep, only that some count held — and eight of the fourteen
      // sweeps this file recognises declare no root at all, so the raw count
      // was mostly counting files whose coverage is unmeasured.
      final missing = <String>[];
      final blind = <String>[];
      for (final guard in _appRuleGuards.entries) {
        final sweep = sweeps[guard.key];
        if (sweep == null) {
          missing.add('${guard.value}\n    ${guard.key}');
          continue;
        }
        if (!sweep.reads) {
          blind.add('${guard.value}\n    ${guard.key} declares no root this '
              'census can model, so its coverage is not measured');
        }
      }
      expect(missing, isEmpty,
          reason: 'these guards carry the app\'s own rules and this census no '
              'longer recognises them as source sweeps at all — the rules are '
              'now enforced by nothing this file can see:\n'
              '${missing.join('\n')}\n'
              'Recognised sweeps: ${sweeps.keys.join(', ')}');
      expect(blind, isEmpty,
          reason: 'these guards are censused but declare no root, so the '
              'coverage below is not measuring what they actually read:\n'
              '${blind.join('\n')}');
    });

    test('each named guard still enforces the rule it is named for', () {
      // The map is two-way as of the previous tick -- every named guard is
      // censused, and every sweep that reaches shipped Dart is named or
      // exempted. What it could not do is read the words back.
      //
      // `_appRuleGuards` states each rule as a sentence. Every case above
      // checks that sentence's *subject* -- the guard exists, it reaches the
      // app, it is on the list -- and none of them check its *predicate*. So
      // the census could hold a file named "the snack rule" next to prose
      // promising "no second messenger outside the allowed wrappers" while
      // that file policed `showDialog` instead, and every case stayed green.
      // That is the worst failure shape here: the rule is gone AND the tree
      // says it is covered, so the next tick has nothing to notice.
      //
      // Measured against the guard's own comment-blanked code, so a file that
      // *mentions* the token in its doc comment while enforcing something else
      // still fails -- prose shadowing code has already cost this file one
      // reader, and the reader that learned it the hard way is the one this
      // case reuses.
      final unmapped = <String>[];
      final unenforced = <String>[];
      for (final guard in _appRuleGuards.entries) {
        final tokens = _ruleEvidence[guard.key];
        if (tokens == null) {
          unmapped.add('${guard.value}\n    ${guard.key}');
          continue;
        }
        if (!sweeps.containsKey(guard.key)) continue; // named above, by name
        final code = _blankComments(File(guard.key).readAsStringSync());
        final missing = tokens.where((t) => !code.contains(t)).toList()..sort();
        if (missing.isEmpty) continue;
        unenforced.add('${guard.value}\n    ${guard.key}\n'
            '    no longer carries '
            '${missing.map((t) => '`$t`').join(', ')} in its code, so the rule '
            'beside its name is not the rule it enforces.\n'
            '    An entry here is a claim, and this is the case that reads it '
            'back. Either the guard is enforcing the rule again, or the rule '
            'changed and the entry has to be rewritten -- not deleted, because '
            'an unlisted guard fails the case above.');
      }
      expect(unmapped, isEmpty,
          reason: 'these guards are registered as carrying an app rule but '
              'name no token for it in `_ruleEvidence`, so their entry is '
              'checked for existence and never for content:\n'
              '${unmapped.join('\n')}\n'
              'One token per entry: the construct the rule turns on. Not a '
              'sample chosen to be easy -- losing the token must mean losing '
              'the rule.');
      expect(unenforced, isEmpty,
          reason: 'these guards no longer carry the literal their entry in '
              '`_appRuleGuards` claims they enforce. Read from their code with '
              'comments blanked, so a token that survives only in a doc comment '
              'does not count:\n${unenforced.join('\n')}');

      // And the evidence list is checked against the map, so a token cannot be
      // left behind for a guard that was renamed, merged or dropped: it would
      // sit in a map of rules enforcing nothing and reading as proof.
      final orphaned = _ruleEvidence.keys
          .where((g) => !_appRuleGuards.containsKey(g))
          .toList()
        ..sort();
      expect(orphaned, isEmpty,
          reason:
              'these guards have evidence but no entry in `_appRuleGuards`, '
              'so their rule is enforced by nothing this file names, and their '
              'token sits in the evidence list reading as proof:\n'
              '${orphaned.join('\n')}');
    });

    test('enough sweeps model a root for the coverage cases to compare', () {
      // `reads`, not `sweeps.length`: a sweep whose enumeration shape this file
      // does not recognise contributes zero coverage, so counting it as one is
      // how a floor stays satisfied by guards that watch nothing. Without a
      // floor the two cases below compare two empty sets and pass.
      final rooted = sweeps.values.where((s) => s.reads).length;
      // Raised 6 -> 10 on 3 Oct (21st), and deliberately *not* to 14: teaching
      // the reader the list-literal and post-`main` shapes takes every
      // recognised sweep to a root except `tool_clock_seam_test.dart`, whose
      // single root is runtime-built and pinned by name instead. A floor that
      // reached 14 would be satisfied by nothing the reader does not already
      // guarantee, so it would stop being a floor.
      expect(rooted, greaterThanOrEqualTo(10),
          reason: 'only $rooted of ${sweeps.length} recognised sweeps declare '
              'a root this census models, so the coverage below compares two '
              'nearly empty sets and reads as a clean box.\n'
              'with no root: '
              '${sweeps.values.where((s) => !s.reads).map((s) => s.file).join(', ')}\n'
              'A sweep that walks `Directory lib = Directory(\'lib\')` or '
              '`Directory(root)` is a real guard with an unmodelled shape — '
              'teach `_rootsOf` that shape rather than lowering this floor.');
    });

    test('the app-wide guards really walk lib/, by name', () {
      // The hole the previous tick recorded, as a fact about named guards rather
      // than a count. Five recognised sweeps declared no root the census could
      // model while walking `lib/` all the same, so "the census is green" and
      // "the empty-text rule has no guard" were the same box at the same time.
      //
      // Which guards must be app-wide is a claim about each rule, so it is
      // stated per guard rather than inferred from a directory listing: a rule
      // that legitimately reads one screen says so here, and the sweep cannot
      // silently narrow on someone else's say-so.
      const appWide = <String, String>{
        'test/no_empty_text_site_test.dart': 'every user-visible Arabic string',
        'test/snack_rule_sweep_test.dart': 'every messenger call',
        'test/type_scale_test.dart': 'every type style',
        'test/motion_test.dart': 'every duration token',
        'test/contrast_tokens_test.dart': 'every colour token pair',
        'test/header_trust_wiring_test.dart': 'every header trust signal',
      };
      final narrowed = <String>[];
      for (final guard in appWide.entries) {
        final roots = sweeps[guard.key]?.roots ?? const <String>[];
        if (!roots.contains('lib')) {
          narrowed.add('${guard.value} -- ${guard.key}\n'
              '    roots it declares: '
              '${roots.isEmpty ? 'none' : roots.join(', ')}');
        }
      }
      expect(narrowed, isEmpty,
          reason: 'these guards enforce an app-wide rule but no longer walk '
              '`lib/` itself. Beside `lib/src/`, that leaves `lib/main.dart` -- '
              'the entry point -- read by nobody, which is the exact defect this '
              'file exists for:\n${narrowed.join('\n')}');
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

      final unwatched = shipped.where((f) => !read.contains(f)).toList()
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
      final roots = sweeps.values.expand((s) => s.roots).toSet().toList()
        ..sort();
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

    test('every root a sweep declares reaches something the app ships', () {
      // The inverse of the case above, and the one the previous tick could not
      // make: that one asks "does a declared root look like something we
      // model?", which a root that resolves to *nothing* answers yes to. So a
      // guard narrowed onto a directory whose last file was deleted -- or onto a
      // path that no longer exists at all -- reads as coverage here while
      // covering zero files, and the count that guards against an empty census
      // goes *up* when the hole opens rather than down.
      //
      // The fix is not a bigger count, it is a per-root fact: name what the
      // root resolved to, and refuse a root that resolved to nothing the app
      // ships. `_resolveRoot` answers that question and the unnamed-guard case
      // below asks it again per guard -- one resolver, so the two cases cannot
      // drift apart on what "reaches shipped Dart" means.
      final barren = <String>[];
      final exemptUsed = <String>{};
      for (final sweep in sweeps.values) {
        for (final spec in sweep.roots) {
          final hit = _resolveRoot(spec, shipped);
          if (!hit.reachesNothing) continue;
          if (_rootsWithoutShippedDart.containsKey(spec)) {
            exemptUsed.add(spec);
            continue;
          }
          barren.add('${sweep.file} -> $spec\n    ${hit.reason}');
        }
      }
      expect(barren, isEmpty,
          reason:
              'these guards declare a root that resolves to nothing the app '
              'ships. The case above cannot see it -- a root that resolves to '
              'empty still looks like a root -- so the guard reads green while '
              'watching no file at all:\n${barren.join('\n')}\n'
              'Either point the guard at a directory that holds app Dart, or '
              'exempt it by name in `_rootsWithoutShippedDart` with the reason '
              'it covers nothing.');

      // And the exemptions are checked against the tree, so an entry here is
      // not a permanent amnesty: one that has started reaching shipped Dart has
      // outlived its reason and would otherwise hide a guard that *does* cover.
      final stale = _rootsWithoutShippedDart.keys
          .where((r) => !exemptUsed.contains(r))
          .toList()
        ..sort();
      expect(stale, isEmpty,
          reason: 'these exemptions are no longer needed -- the root either is '
              'not declared by any sweep, or now reaches Dart the app ships, '
              'so it is either dead weight or an amnesty for a guard that '
              'really does cover something. Delete the entry:\n'
              '${stale.map((r) => '  $r -- ${_rootsWithoutShippedDart[r]}').join('\n')}');
    });

    test('every sweep that reads app source is named as a rule, by name', () {
      // The reverse direction, and the one the map above could not express. Its
      // doc comment says the half that is checked is "a fact about the repo":
      // each guard carrying an app rule must be *recognised*. Nothing said the
      // converse -- that a guard which reaches app source must be *listed*. So
      // the map was one-way and a new sweep could be born carrying a real rule
      // with no entry here: every case above would credit it, the `rooted >= 10`
      // floor would go **up** with it, and its rule would appear in no by-name
      // list in this file. A tenth unreported rule is indistinguishable from a
      // tenth covered one.
      //
      // The test for "carries an app rule" is therefore not a judgement written
      // down here but a measurement the census can make: a sweep whose root
      // reaches Dart the app ships is enforcing something about app source. If
      // that is not a rule this repo holds about its own source, the sweep has
      // no business reading `lib/` -- and saying so by name is the fix.
      //
      // Proved on this tick by planting, then reverted: a new sweep
      // `test/planted_unnamed_guard_test.dart` that walks `Directory('lib/src')`
      // and fails on a banned token. Every other case in this file stayed green
      // and the `rooted` floor rose from 13 to 14 -- it was the floor moving in
      // the direction that hides the hole.
      final unnamed = <String>[];
      for (final sweep in sweeps.values) {
        if (_appRuleGuards.containsKey(sweep.file)) continue;
        if (_guardsCarryingNoAppRule.containsKey(sweep.file)) continue;

        // Not named -- so it has to earn the exemption by reading no app
        // source at all. One resolver, so "reads app source" means the same
        // thing here as it does in the barren-root case.
        final reached = <String>[];
        for (final spec in sweep.roots) {
          reached.addAll(_resolveRoot(spec, shipped).shippedDart);
        }
        if (reached.isEmpty) continue; // reads nothing shipped: carries no rule

        unnamed.add('${sweep.file}\n'
            '    reads ${reached.length} Dart file(s) the app ships '
            '(${reached.take(3).join(', ')}${reached.length > 3 ? ', ...' : ''})'
            ' through ${sweep.roots.join(', ')}, so it enforces something about '
            'app source -- but no entry in `_appRuleGuards` says which rule, '
            'and it is not exempted in `_guardsCarryingNoAppRule`. Either name '
            'the rule it carries, or exempt the guard with the reason it reads '
            'app source without carrying one.');
      }
      expect(unnamed, isEmpty,
          reason: 'these sweeps read Dart the app ships and are not named in '
              '`_appRuleGuards`, so they are credited with coverage by every '
              'case in this file while the rules they enforce appear in no '
              'by-name list here. That is the same box the count-based floor '
              'was replaced for, reached from the other side:\n'
              '${unnamed.join('\n')}\n'
              'Named guards: ${_appRuleGuards.keys.join(', ')}');

      // The exemptions are facts about the tree, not permanent amnesty: a guard
      // that stops reading app source has outlived its reason and is deleted.
      final stale = _guardsCarryingNoAppRule.keys
          .where((g) =>
              !sweeps.containsKey(g) ||
              sweeps[g]!
                  .roots
                  .every((r) => _resolveRoot(r, shipped).shippedDart.isEmpty))
          .toList()
        ..sort();
      expect(stale, isEmpty,
          reason: 'these exemptions are no longer earned -- the guard is no '
              'longer a recognised sweep, or none of its roots reaches Dart the '
              'app ships any more, so naming it here claims a rule it does not '
              'carry. Delete the entry:\n'
              '${stale.map((g) => '  $g -- ${_guardsCarryingNoAppRule[g]}').join('\n')}');
    });

    test('no guard roots itself in a shape this census cannot read', () {
      // The silent-guard hole, closed by name rather than by count.
      //
      // `_knownUnmodelled` is the whole point of being a map: a root the reader
      // cannot resolve is fine **as long as it is the one root we know about and
      // the guard that uses it is the one guard we know**. The day a *second*
      // guard builds a root at runtime -- or the day this one adopts it for a
      // root that carries app coverage -- it stops being a known unknown and
      // starts being an unmeasured guard, which is the state that lets a rule
      // go dark unnoticed.
      // Direction 1 — a pin that is now stale. The reader grew shapes this
      // tick, so if it can resolve a guard that was registered as unmodellable,
      // the exception has outlived its reason and must be deleted or the next
      // real shape gets waved through behind it.
      // The pin names an exact unresolved root, not merely the guard: a guard
      // can hold one readable root *and* one runtime-built root, and it is the
      // second that needs an exception. Measured 3 Oct (21st): the first draft
      // of this case pinned per guard and went red on the clean tree, because
      // `tool_clock_seam_test.dart` declares `*.py` as well and so reads as
      // resolvable — a stale-pin check that fires on a correct tree is a check
      // nobody keeps running.
      final stale = <String>[];
      for (final pin in _knownUnmodelled.entries) {
        final sweep = sweeps[pin.key];
        if (sweep == null) {
          stale.add('${pin.key} -> ${pin.value}\n'
              '    pinned but the census no longer recognises the file as a '
              'sweep at all — delete the pin');
          continue;
        }
        if (!sweep.unresolved.contains(pin.value)) {
          stale.add('${pin.key} -> ${pin.value}\n'
              '    pinned, but the guard\'s unresolved roots are now '
              '${sweep.unresolved.isEmpty ? 'none' : sweep.unresolved.join(', ')}\n'
              '    ${_whyUnmodelled[pin.key] ?? ''}');
        }
      }
      expect(stale, isEmpty,
          reason: 'these known-unmodelled pins no longer match the tree, so an '
              'exception that outlived its reason is waving through a real '
              'shape:\n${stale.join('\n')}');

      // And nothing may acquire an unresolved root without a pin. This is the
      // direction that closes the hole: a *new* guard that builds its root at
      // runtime is not tolerated on the strength of an old guard's exception.
      final unpinned = <String>[];
      for (final sweep in sweeps.values) {
        for (final spec in sweep.unresolved) {
          if (_knownUnmodelled[sweep.file] != spec) {
            unpinned.add('${sweep.file} -> $spec');
          }
        }
      }
      expect(unpinned, isEmpty,
          reason: 'these guards declare a runtime-built root that no pin in '
              '`_knownUnmodelled` covers, so their coverage is unmeasured and '
              'invisible. Pin it by name if it carries no app coverage; teach '
              '`_rootsOf` the shape if it does:\n${unpinned.join('\n')}');

      // Direction 2 — a guard with no root at all and no pin. This is the hole
      // the previous tick recorded: five recognised sweeps declared nothing the
      // census could model while walking `lib/` all the same, so a rule added
      // to any of them could go dark without a word here.
      final unregistered = sweeps.values
          .where((v) => !v.reads && !v.onlyUnresolved)
          .map((v) => v.file)
          .toList()
        ..sort();
      expect(unregistered, isEmpty,
          reason: 'these guards declare no root this census models and are '
              'not pinned in `_knownUnmodelled`, so they contribute no '
              'coverage and no one can see that:\n'
              '${unregistered.join('\n')}');

      // Direction 3 — the one that actually matters, and the assertion the
      // previous tick could not make: a guard carrying one of the app's own
      // rules must never be one whose root nobody can read. Before this tick
      // that check did not exist *because five of the seven named guards would
      // have failed it.*
      final unreadable = <String>[];
      for (final guard in _appRuleGuards.entries) {
        final sweep = sweeps[guard.key];
        if (sweep == null || sweep.reads) continue;
        unreadable.add('${guard.value}\n    ${guard.key}\n'
            '    ${sweep.onlyUnresolved ? 'root is runtime-built and unmodelled' : 'declares no root at all'}');
      }
      expect(unreadable, isEmpty,
          reason: 'a guard carrying one of the app\'s own rules has a root '
              'this census cannot read, so its coverage is unmeasured and a '
              'rule added there goes dark unnoticed:\n'
              '${unreadable.join('\n')}');
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
          .toList()
        ..sort();
      expect(watchesIt, isNotEmpty,
          reason: 'no sweep walks `lib/` recursively, so nothing reads '
              'lib/main.dart.');
      // And at least one of them is the messenger rule that was bypassed, so
      // the specific hole cannot be re-opened by that guard alone.
      expect(watchesIt.any((f) => f.contains('snack_rule_sweep')), isTrue,
          reason: 'the messenger sweep must keep walking `lib/`: that is the '
              'exact guard a ScaffoldMessenger planted in main.dart bypassed '
              '(21/21 green before this fix).\nwatches lib/: '
              '${watchesIt.join(', ')}');
    });
  });
}
