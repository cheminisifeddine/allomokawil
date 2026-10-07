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

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
  // ...and these four are declared in the *literal* spelling, taught to
  // `_rootsOf` on 8 Oct: `File('…').readAsStringSync()`. Two of them are read
  // by guards this file already names for other roots
  // (`layering_test.dart`, `quote_count_copy_test.dart`); the other two are
  // the point of the change, because `lib/src/widgets/ui.dart` was the root of
  // a guard that declared **none** and was therefore invisible to every case
  // in this file while reading a shared kit the whole app draws from.
  'lib/src/core/format/calendar_day.dart',
  'lib/src/data/chat_time.dart',
  'lib/src/models/plan.dart',
  'lib/src/widgets/ui.dart',
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
  // Added 3 Oct (32nd). The monogram tick fixed the invisible-RLM first
  // character for the avatar and explicitly refused to call the rest of the
  // app clean; this is the rest of the app. Its evidence token is the
  // prefilter's own `[0]` index, because that is what the file selects on.
  'test/first_char_measurement_test.dart':
      'the first-character rule: no string is measured by its first '
      'character except the avatar',
  // Added 4 Oct (40th). `phone_field.dart:30` tells every future screen to post
  // `DzPhone.canonical(controller.text)`, and nothing read the number off the
  // wire to check it: the test that looked closest defined it instead
  // (`postedFor()` is `DzPhone.canonical` with a comment claiming otherwise).
  // Measured on that tick -- posting `_phone.text` raw, so the sign-in path sent
  // `05 50 12 34 56` with its spaces, left all 58 tests in the three existing
  // phone files green. The rule was documented and unenforced at the same time.
  'test/phone_posted_value_test.dart':
      'the posted-phone rule: a phone reaches the API canonicalised, or not at '
      'all',
  // Added 8 Oct with the `File('…')` root shape. This guard enforced a real
  // rule about app source -- every taxonomy label fits the tile the app draws
  // -- and `lib/src/widgets/ui.dart` was its only root. The reader could
  // *resolve* a file spec and had never *read* one, so the guard declared
  // nothing and answered to none of the by-name lists here. Its evidence token
  // is the pattern it applies to `ui.dart` to read the inset back.
  'test/tile_label_fit_test.dart':
      'the tile-label rule: every Arabic label the app ships fits its tile at '
      'every width the app claims',
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
  'test/motion_test.dart': [r'\w*[Dd]uration\s*:\s*(?:const\s+)?Duration\('],
  'test/contrast_tokens_test.dart': [r'wash: Color\(0xFF'],
  'test/failure_reported_test.dart': [r'\bcatch\b'],
  'test/header_trust_wiring_test.dart': [r'NotificationCountTrust\s*\('],
  'test/payload_coverage_test.dart': ['/api/mobile/workers/top'],
  'test/quote_count_copy_test.dart': ['quoteLimit|quotesUsedThisMonth'],
  'test/first_char_measurement_test.dart': [r'substring\s*\(\s*0'],
  // `phone:` was the first token tried and it is wrong: it also matches
  // `seen.add(...)` and every other bookkeeping call in this guard, so the
  // applier reader credited enforcement through an undeclared name and the
  // census went red on the guard that was being registered. The token has to
  // be one only a real call site can carry -- the named argument itself, with
  // the colon and the label spelled the way a call spells it.
  'test/phone_posted_value_test.dart': [r'phone:\s*(.+?),?\s*$'],
  'test/tile_label_fit_test.dart': [r'symmetric\(\s*horizontal:'],
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

  // A whole-file read: `File('lib/src/widgets/ui.dart').readAsStringSync()`.
  // **Taught this tick, and the hole it closes is the one the previous tick
  // left as work.** `tile_label_fit_test.dart` declared its only root in this
  // shape. The reader could *resolve* a file spec (that is what `_resolveRoot`
  // has always done) but had never *read* one, so the guard declared nothing:
  // absent from the root census, from the coverage set, and from the by-name
  // rule lists -- a rule about app source this file could not see.
  //
  // Three things are required of a spec before it is read as a root, and each
  // one is a shape this tree actually contains:
  //
  //   * **A read.** The pattern is anchored on `.readAsStringSync` /
  //     `.readAsLinesSync`, not on the constructor, so
  //     `File('lib/…').existsSync()` -- an assertion about a path, not an
  //     enumeration of it -- is not credited. Same exclusion `Directory`
  //     gets one level down, for the same reason.
  //   * **A literal.** `'${Directory.current.path}/tool/build_gate.py'` is a
  //     file `tool_clock_seam_test.dart` really reads, and it is built at
  //     runtime. It cannot go into `unresolved`, because the pin table beside
  //     that list is keyed by guard and `tool_clock_seam_test.dart` already
  //     spends its one entry on its fixtures directory -- a second root per
  //     guard has nowhere to be written down. So it is reported in `skipped`
  //     with its reason, and the case below refuses a skipped spec that points
  //     at the app. Pinning it silently is what the reader must not do.
  //   * **A root shape.** `lib/…` or `test/…`, exactly the filter the
  //     `<String>[…]` reader above applies, for its reason: a string in a file
  //     is not a root, and a string that *is* a path is.
  //
  // Reads held in a variable -- `File(_reviewPath)` in
  // `contrast_tokens_test.dart` -- are a fourth shape this reader still does
  // not model. That is pre-existing and stated in `_knownRoots`; it is not
  // widened here, because a const-holding guard is a different reader again
  // and this tick's claim is only about the literal spelling.
  final skipped = <String, String>{};
  // One pattern in one literal: two adjacent raw strings do not concatenate
  // in Dart, which parsed as a broken argument list rather than as anything
  // about the reader, so the mistake was invisible in the failure.
  final wholeFileRead = RegExp(
      r"""File\(\s*['"]([^'"]+)['"]\s*\)\s*\.\s*(?:readAsStringSync|readAsLinesSync)""");
  for (final m in wholeFileRead.allMatches(code)) {
    final spec = m.group(1)!;
    if (spec.contains(r'$')) {
      skipped[spec] = 'built at runtime by interpolation, so it is not a '
          'literal this census can resolve';
    } else if (!spec.startsWith('lib') && !spec.startsWith('test/')) {
      skipped[spec] = 'not root-shaped: it names neither `lib/` nor `test/`';
    } else {
      roots.add(spec);
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
      unresolved,
      skipped);
}

/// The two answers a root reader can give, kept apart on purpose.
class _Read {
  _Read(this.roots, this.unresolved, this.skipped);

  /// Roots that are literal paths this census can model.
  final List<String> roots;

  /// Roots written as a runtime expression. Not a modelled root, not a failure
  /// on its own — a fact for the caller to pin by name.
  final List<String> unresolved;

  /// Whole-file reads this reader recognised and declined to call a root,
  /// each with the reason it was declined. Kept so the skip is *visible*: a
  /// shape dropped without a reason is the silent hole this file exists for,
  /// and the caller asserts on the reasons rather than trusting the drop.
  final Map<String, String> skipped;
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
  // Added 3 Oct (32nd) with `first_char_measurement_test.dart`. That guard
  // resolves receiver **types**, and the analyzer needs a Dart SDK to do it:
  // under `flutter test` the executing binary is `flutter_tester` in
  // `bin/cache/artifacts/engine/`, which ships no SDK, so the guard walks up
  // from `Platform.resolvedExecutable` looking for `dart-sdk`. It is a path
  // built at runtime and it reaches no app source -- it is the SDK, not `lib/`
  // -- so there is nothing here for this census to model.
  'test/first_char_measurement_test.dart':
      r'${dir.path}${Platform.pathSeparator}dart-sdk',
};

/// Why each pin exists, kept beside the pin so deleting one is a decision
/// someone can read rather than a diff nobody understands.
const _whyUnmodelled = <String, String>{
  'test/tool_clock_seam_test.dart':
      'runtime-built path, and it walks test data rather than app source — so '
          'it carries no app coverage either way',
  'test/first_char_measurement_test.dart':
      'runtime-built path to the Dart SDK the analyzer resolves types '
          'against. The guard reads lib/ through its own `Directory(\'lib\')`, '
          'which this census reads normally; this root only names the SDK the '
          'resolver needs, so it carries no app coverage either way',
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
  _Root(this.file, this.roots, this.unresolved, this.skipped);

  /// The guard, as `test/…dart`.
  final String file;

  /// The literal directories/specs it enumerates. Empty when the shape was not
  /// recognised, which is reported by name rather than guessed at.
  final List<String> roots;

  /// Roots written as runtime expressions, kept out of [roots] so they cannot
  /// pass for coverage.
  final List<String> unresolved;

  /// Whole-file reads [_rootsOf] saw and declined, with the reason. Asserted on
  /// in the case below: a skip is a *decision*, and a decision about app
  /// source that nobody reads back is the silent hole this file exists for.
  final Map<String, String> skipped;

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


/// Method and constructor names whose argument is *read*, not recorded.
///
/// Deliberately a list of names and not "anything that looks like a regex": the
/// map's tokens reach source text through six different readers, and a window
/// that special-cases one of them measures only that one. `RegExp` is *an*
/// applier, not *the* applier -- restricting the check to it was measured at
/// 7 of 13 enforced, which would have gone red on a tree that is correct.
///
/// **Measured, then trimmed to what the tree actually uses (3 Oct).** This
/// list declared **15** names and the census below credited **2** of them --
/// `RegExp` and `contains`. The other 13 (`hasMatch`, `allMatches`,
/// `firstMatch`, `matches`, `isWall`, `split`, `indexOf`, `lastIndexOf`,
/// `startsWith`, `endsWith`, `replaceAll`, `replaceFirst`, `replaceRange`)
/// earned nothing: they were speculative, not measured, which is the same
/// dead-weight shape as an outgrown allow-list.
///
/// **But trimming is not the finding -- *why* they earn nothing is.** All 13
/// are called *constantly* in these guards and **never with a token**:
/// `hasMatch` 28 calls / 0 with a token, `split` 42 / 0, `allMatches` 34 / 0,
/// `endsWith` 27 / 0, `startsWith` 16 / 0, `indexOf` 6 / 0, `replaceAll` 6 /
/// 0. Every one of those is the **downstream half of the same chain**:
/// `RegExp(r'<token>').hasMatch(src)` is one expression, and the token lands in
/// the `RegExp` argument, so the reader credits `RegExp` and the 13 siblings
/// never see a token. A guard written as `src.contains(token)` credits
/// `contains`. There is no third shape in the tree today.
///
/// **So the list is now exactly the two mechanisms the tree uses, and it
/// cannot rot again silently**: the case below asserts that no *declared* applier
/// is dead, and that every applier the tree actually reaches with a token is
/// declared. Adding a guard written with `hasMatch(token)` -- which is the
/// natural thing to write and is why the name was there -- now goes **red**
/// until the name is added back, which is the point: the list is a measured
/// claim about the tree, not a wish list of functions that *could* apply one.
const _tokenAppliers = <String>{
  'RegExp', // the pattern itself
  'contains',
};

/// Guards whose evidence token is held **only** by `expect(...)`, and the
/// shared definition that carries the rule for them.
///
/// This is the one real instance of the hole the 27th tick could not see, found
/// by measuring instead of guessing. `motion_test.dart` does not hold its own
/// pattern: the rule lives once, in `test/support/source_text.dart` as
/// `tempoDurationRule`, and the map's copy of it survives only in
/// `expect(tempoDurationRule.pattern, ...)` at line 473. That `expect` is a
/// *consistency* check between two copies -- if the shared rule changed, both
/// copies move with it -- so it is not enforcement, and no token moved to that
/// file would change the fact. The tree is right; the map could not see why.
const _ruleEvidenceAppliedElsewhere = <String, String>{
  'test/motion_test.dart': 'enforced through `tempoDurationRule` in '
      'test/support/source_text.dart, which `motion_test.dart` reaches via '
      '`tempoRules`',
};

/// Classifies the literals in a unit that carry [token], by what the code
/// around them does with it.
class _TokenUse extends RecursiveAstVisitor<void> {
  _TokenUse(this.token);

  final String token;

  /// The token is handed to something that reads it.
  int applied = 0;

  /// The token is only ever compared back inside an `expect(...)`.
  int expectedOnly = 0;

  /// Every applier found, for the failure message.
  final List<String> appliers = <String>[];

  void _classify(AstNode node) {
    final String? call = _enclosingCall(node);
    if (call != null && _tokenAppliers.contains(call)) {
      applied++;
      if (!appliers.contains(call)) appliers.add(call);
      return;
    }
    if (_insideExpect(node)) expectedOnly++;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final String v = node.value;
    // Containment runs **both ways**, on purpose. The map's token is usually a
    // fragment of a larger pattern -- `return\s+(` inside the guard's own
    // triple-quoted pattern -- and one token is source-shaped rather than
    // regex-shaped, so the other direction matters too. Measured: testing
    // equality only scored 6 of 13 guards as having no applier at all.
    // The empty string is skipped explicitly, and this is a measured bug rather
    // than a tidy-up: `''` is a substring of *every* token, so a guard holding
    // any `''` at all -- `code.contains('')` is common in these sweeps -- was
    // crediting enforcement to every token in the map. The first planted proof
    // of this case came back GREEN because of exactly that, and the two hits it
    // found were both empty literals inside a `.contains(...)`.
    // Containment runs **one way only**, and that is the whole finding of the
    // 30th tick. It used to run both ways (`token.contains(v)` as well) so
    // that a source-shaped token could be found inside a regex-shaped pattern.
    // Measured: the reverse direction credits **a fragment of the token that
    // has nothing to do with the rule**. `payload_coverage_test.dart`'s token
    // is the 23-character route `/api/mobile/workers/top`, and the guard has
    // no literal containing it anywhere -- it was credited by the **one
    // character** `'/'`, handed to `.split('/')` and `.join('/')` in a path
    // helper, and by `'/'` again under `.lastIndexOf('/')`. Any route, any
    // string with a slash in it, would have scored the same.
    //
    // The empty string was the same bug at its limit and was already skipped
    // for exactly this reason: `''` is a substring of *every* token, so
    // `code.contains('')` credited enforcement to every entry in the map.
    //
    // Forward-only costs nothing real: measured across all 13 guards it is
    // **11 of 13**, and the two it loses are `payload_coverage_test.dart`
    // (credited only by the fragment, above -- now a true positive, and its
    // guard was fixed to apply the route it claims to police) and
    // `motion_test.dart` (held by `expect` only, already listed in
    // `_ruleEvidenceAppliedElsewhere`).
    if (v.isNotEmpty && v.contains(token)) _classify(node);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.toSource().contains(token)) _classify(node);
    super.visitStringInterpolation(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    // `layering_test.dart`'s token is the literal `['data', 'screens',
    // 'widgets']`: the rule is "no `models/` file may import one of these",
    // applied later as `_forbidden['models']!.contains(layer)`. That is data
    // the guard *reads*, and a string-literal scan cannot see it at all.
    // Forward-only here too, for the same measured reason as the literals
    // above -- see the note on [visitSimpleStringLiteral].
    final String src = node.toSource();
    if (src.contains(token)) _classify(node);
    super.visitListLiteral(node);
  }
}

/// Every named collection in a unit whose value carries [token].
class _CollectionScan extends RecursiveAstVisitor<void> {
  _CollectionScan(this.token);

  final String token;
  final List<String> owners = <String>[];

  void _record(AstNode node, String source) {
    if (source.isEmpty) return; // '' is a substring of every token
    // Forward-only: see [visitSimpleStringLiteral] for the measurement that
    // removed the reverse direction here as well.
    if (!source.contains(token)) return;
    final String? owner = _collectionOwner(node);
    if (owner != null && !owners.contains(owner)) owners.add(owner);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    _record(node, node.toSource());
    super.visitListLiteral(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    // The map that *holds* the collection, e.g. `_forbidden`.
    _record(node, node.toSource());
    super.visitSetOrMapLiteral(node);
  }
}

/// The name of the variable or field a collection literal belongs to.
///
/// `layering_test.dart` holds its rule as a `const` map of lists and applies it
/// as `_forbidden['models']!.contains(layer)`, so the literal that carries the
/// token is read *through a reference* several lines away. Reading only the
/// literal's own call site finds nothing there and reds a correct guard, which
/// is what happened on the first run of this case.
String? _collectionOwner(AstNode collection) {
  AstNode? p = collection.parent;
  while (p != null) {
    // A local: `final x = [ … ];`
    if (p is VariableDeclarationList && p.parent is VariableDeclarationStatement) {
      return (p.parent as VariableDeclarationStatement)
          .variables
          .variables
          .first
          .name
          .lexeme;
    }
    // A field: `const Map<String, List<String>> _forbidden = { … };`
    if (p is FieldDeclaration) return p.fields.variables.first.name.lexeme;
    // A **top-level** variable. Its parent chain is `TopLevelVariable
    // Declaration -> VariableDeclarationList -> VariableDeclaration`, not a
    // `CompilationUnit` as the first guess assumed, and getting that wrong is
    // what left `layering_test.dart` red on the first two runs of this case.
    if (p is VariableDeclarationList && p.parent is TopLevelVariableDeclaration) {
      return p.variables.first.name.lexeme;
    }
    p = p.parent;
  }
  return null;
}

/// True when [name] is the target of a call in [_tokenAppliers] anywhere in
/// [unit] -- i.e. the collection it names is genuinely read.
class _ReferenceApplied extends RecursiveAstVisitor<void> {
  _ReferenceApplied(this.name);

  final String name;
  bool applied = false;
  String? via;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!applied &&
        _tokenAppliers.contains(node.methodName.name) &&
        (node.target?.toSource().contains(name) ?? false)) {
      applied = true;
      via = node.methodName.name;
    }
    // **The second hop, added by the 30th tick after measuring it.** A rule held
    // as a map and applied by *reading its contents out* --
    // `for (final String route in liveKeys.keys)` -- reaches no applier by name
    // at all, so the call-target branch above misses it and the guard read as
    // one that enforces nothing. Reading `x.keys` or `x.values` hands the
    // collection's own elements to whatever comes next, which is the same
    // reachability the first branch certifies, one syntactic step out.
    //
    // **The stated limit of this branch was removed on the 31st tick, by
    // measuring it.** It used to credit *reading the collection* and said so --
    // "a guard that lists a rule and then does nothing with it is credited
    // here" -- and the census pinned which guards took the branch without ever
    // asking the question that mattered: whether those guards then *use* the
    // element. Answered by `_CountingIds`, below, and it is the only guard in the
    // tree that takes this branch.
    if (!applied && _readsOut(node.target)) {
      applied = true;
      via = node.methodName.name;
    }
    super.visitMethodInvocation(node);
  }

  /// True when [target] reads the contents of the collection this visitor names.
  bool _readsOut(Expression? target) {
    if (target is! PropertyAccess) return false;
    if (target.propertyName.name != 'keys' &&
        target.propertyName.name != 'values') {
      return false;
    }
    return target.target?.toSource().contains(name) ?? false;
  }

  @override
  void visitForStatement(ForStatement node) {
    // `for (final String route in liveKeys.keys)` -- the loop reads the
    // contents out. **The getter is `iterable2`, not `iterable`,** which is not
    // a naming quibble: writing the obvious `node.iterable` does not compile
    // (`The getter 'iterable' isn't defined for the type 'ForStatement'`) and
    // the v1 `iterable` name survives only as a `v1Name` projection in
    // `ForEachPartsWithDeclarationImpl`. A reader that cannot be written cannot
    // be measured, so this is recorded rather than rediscovered.
    final ForLoopParts parts = node.forLoopParts;
    if (applied || parts is! ForEachParts) return;
    // `iterable2` carries `@Experimental` in analyzer 14.4.0, and the v1
    // `iterable` it replaces is a projection that is **not** on the interface,
    // so there is no un-experimental spelling of this read. The warning is
    // scoped to the single line rather than to the file: `flutter analyze` is
    // the loop's gate and it must print "No issues found!", so the choice is
    // between a narrowed suppression with the reason written down and a red
    // gate. It is dev-only test code reading a dev-only AST.
    // ignore: experimental_member_use
    final String src = parts.iterable2.toSource();
    // **The body must use the element, not merely bind it — 31st tick.**
    // This branch used to stop at the loop: reading `liveKeys.keys` out is
    // proof that the collection is reachable, and nothing more. A guard written
    // as `for (final String route in liveKeys.keys) { }` -- empty body, the
    // rule enumerated and then dropped -- was credited as enforcing it. Its own
    // comment admitted that ("it credits reading the collection, not reading
    // each element"), and the census measured *which* guard took the branch
    // without ever asking whether the body acted on the element.
    //
    // **Measured, not assumed:** exactly one guard in the tree takes this branch
    // -- `payload_coverage_test.dart`, whose body reads its loop variable **3**
    // times (`'$sq$route'`, then two `lib.contains` calls). So closing the hole
    // costs nothing, and it closes a hole that was open on the one branch
    // nothing else in the reader covers.
    //
    // `_CountingIds` counts **identifier reads**, not appearances: the loop
    // variable's own declaration is outside the body, so every occurrence in
    // there is a read. It walks statements, not the body source text, so a
    // mention inside a *comment* does not count as use — and a guard cannot buy
    // credit by documenting that it would have used the element.
    if (src.contains('$name.keys') ||
        src.contains('$name.values') ||
        RegExp('$name\\s*\\[').hasMatch(src)) {
      final String? loopVar = _loopVariable(parts);
      final _CountingIds body = _CountingIds(loopVar ?? '<none>');
      node.body.accept(body);
      // The count travels in `via` so the census prints it: `for-in(3)` is a
      // measurement of how hard this branch had to work, and a future tick that
      // sees the guard at `for-in(0)` sees that the rule stopped being applied
      // rather than having to re-derive it.
      if (body.hits > 0) {
        applied = true;
        via = 'for-in(${body.hits})';
      }
    }
    super.visitForStatement(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // A `RegExp(...)` over a reference is the same shape read one hop out.
    if (!applied &&
        node.constructorName.toSource().split('.').last == 'RegExp' &&
        node.argumentList.arguments.any((a) => a.toSource().contains(name))) {
      applied = true;
      via = 'RegExp';
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// The name a `for (final T x in ...)` binds, or `null` when the head is a
/// pattern (`for (final (a, b) in ...)`), which cannot be counted by name.
///
/// Two head forms exist in analyzer 14.4.0 and they do not share a getter:
/// `ForEachPartsWithDeclaration.loopVariable` is a `DeclaredIdentifier`, and
/// `ForEachPartsWithIdentifier` exposes it as the **experimental** token
/// `identifier2` — its `identifier` getter is `@ToBeDeprecated`. A pattern head
/// returns `null` on purpose: a destructuring loop still reads its elements, but
/// "did the body use the element" is then a question about a *pattern
/// variable*, and there is no such loop in the tree to be honest about.
String? _loopVariable(ForEachParts parts) {
  if (parts is ForEachPartsWithDeclaration) {
    return parts.loopVariable.name.lexeme;
  }
  if (parts is ForEachPartsWithIdentifier) {
    // ignore: experimental_member_use
    return parts.identifier2.lexeme;
  }
  return null; // ForEachPartsWithPattern
}

/// How many times [name] is **read** inside a loop body.
///
/// This is the reader that closed the read-out hop's stated weakening, and it
/// counts `SimpleIdentifier` nodes rather than matching the body as text for a
/// reason: in a text match, `for (final route in liveKeys.keys) { /* check
/// route */ }` is identical to a body that checks nothing, because the comment
/// carries the name. Here the visitor only ever reaches expressions that
/// resolved to code, so a guard cannot buy enforcement by documenting the use it
/// did not make.
///
/// It is deliberately a *count* and not a boolean so the failure message can
/// print it: `USED(0)` is a different claim from "no for-in found", and the
/// message in the census case says which.
class _CountingIds extends RecursiveAstVisitor<void> {
  _CountingIds(this.name);

  final String name;
  int hits = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name) hits++;
    super.visitSimpleIdentifier(node);
  }
}

/// Call names that **wrap** a token-carrying call instead of reading it.
///
/// `RegExp(r'token').hasMatch(src)` is one expression with two calls in it, and
/// only one of them is handed the token: the `RegExp` argument. The other is a
/// method on the *result*. Treating those as appliers is the `expect` bug in a
/// new costume -- a name credited with enforcement it never performed -- so they
/// are excluded by name rather than left to the reader to guess.
///
/// This is not a guess either: it is the measured answer to "which calls
/// receive a token", which is why `_CallScan` below passes the token to the
/// **argument** test and not to the callee.
const _nonReaders = <String>{
  'expect', // where a verdict is delivered, not enforced
  'group', 'test', 'setUp', 'setUpAll', 'tearDown', 'tearDownAll', // wrappers
  'hasMatch', 'allMatches', 'firstMatch', 'matches', // on a RegExp *result*
  'isNotEmpty', 'isEmpty', 'toString',
};

/// Every method invocation in a unit that is handed [token] in its **arguments**.
///
/// The asymmetry with `_TokenUse` is deliberate and is the measurement from
/// this tick. `_TokenUse` classifies a *literal* by the call enclosing it; this
/// classifies a *call* by whether the token is among its arguments. Those are
/// not the same question -- `RegExp(token).hasMatch(src)` gives `RegExp` the
/// token and `hasMatch` nothing -- and building the reader around the argument
/// test is what shows the 13 dead names are downstream halves of `RegExp`
/// rather than readers the tree never uses.
class _CallScan extends RecursiveAstVisitor<void> {
  _CallScan(this.token);

  final String token;

  /// Method names this unit calls with [token] among their arguments.
  final List<String> tokenCalls = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final String args =
        node.argumentList.arguments.map((a) => a.toSource()).join('|');
    if (args.isNotEmpty && args.contains(token)) {
      tokenCalls.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final String args =
        node.argumentList.arguments.map((a) => a.toSource()).join('|');
    if (args.isNotEmpty && args.contains(token)) {
      tokenCalls.add(node.constructorName.toSource().split('.').last);
    }
    super.visitInstanceCreationExpression(node);
  }
}

/// The nearest enclosing call name, or null when the literal is not passed into
/// one.
///
/// Reads through an `ArgumentList`, because an argument's parent is the list
/// and the call is *its* parent. Both wrong versions were measured: checking
/// only the immediate parent found **no** appliers anywhere (0 of 13), and
/// checking the grandparent found 7 of 13, red on a correct tree.
String? _enclosingCall(AstNode node, {int maxHops = 4}) {
  AstNode? p = node.parent;
  for (int hops = 0; p != null && hops < maxHops; hops++) {
    if (p is InstanceCreationExpression) {
      return p.constructorName.toSource().split('.').last;
    }
    if (p is MethodInvocation) return p.methodName.name;
    p = p.parent;
  }
  return null;
}

/// True when the node sits inside an `expect(...)` and inside no nearer call.
///
/// An `expect` is where a verdict is *delivered*, not the opposite of enforcing
/// one -- the 27th tick rejected this discrimination for exactly that reason,
/// when it red-lit `header_trust_wiring_test.dart` for applying its token with
/// `RegExp(...).hasMatch(sources)`. Nearest call wins, so an applied site is
/// found before the assertion that reports it.
bool _insideExpect(AstNode node) {
  AstNode? p = node.parent;
  for (int hops = 0; p != null && hops < 6; hops++) {
    if (p is MethodInvocation && p.methodName.name == 'expect') return true;
    p = p.parent;
  }
  return false;
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
        sweeps[path] =
            _Root(path, read.roots, read.unresolved, read.skipped);
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

    test('no rule token can be required to survive the sweep reader', () {
      // **Closes the 27th tick's stated "next step" by measuring it first.**
      // The note said the map still cannot tell a token *enforced in code* from
      // a token *written down*, and proposed closing it by "reading
      // `_ruleEvidence` tokens with the **sweep's** reader (strings blanked) and
      // requiring each token to survive in code, with the handful of tokens
      // that are legitimately strings marked as such".
      //
      // Measured over all 13 entries before writing a line of it:
      //
      // ```
      // STRL  map:yes test/type_scale_test.dart      fontSize:\s*
      // STRL  map:yes test/card_recipe_test.dart      BorderRadius\.circular
      // ...  13 of 13, without exception
      // ```
      //
      // **Every token in this map is a Dart string literal by construction.**
      // `r'fontSize:\s*'` and `'ScaffoldMessenger'` are both *strings*, and
      // `blankComments(src)` blanks string bodies, so it blanks the token
      // itself. There is no exception to mark and no "handful" to allow: the
      // clause as proposed would go red on **every** entry, so it is not a
      // stricter check on this map, it is an unsatisfiable one. Shipping it
      // would have turned this file red on every commit for ever.
      //
      // The second attempt is the instructive one, because it looked shippable.
      // The real hole -- a token held alive only by an `expect(...)` that
      // compares it back to this map -- *was* implemented, and it produced a
      // genuine red:
      //
      // ```
      // carries `NotificationCountTrust\s*\(` only inside `expect(...)`
      // ```
      //
      // on `header_trust_wiring_test.dart`. That red was **the helper being
      // wrong, not the guard**. The guard reads
      // `expect(RegExp(r'NotificationCountTrust\s*\(').hasMatch(sources), isTrue)`
      // -- the token is *applied* to the app's source to decide the assertion.
      // An `expect(...)` is where a rule's verdict is delivered; it is not the
      // opposite of enforcing one. Flagging it would have demanded the app
      // rewrite a correct, deliberately source-based guard.
      //
      // Two of my own mistakes are recorded rather than deleted, because both
      // are the trap this item is about and a later tick will meet them again:
      //
      //   * **The discriminator has to look both ways.** `code.contains(token)`
      //     puts the call *before* the token, so a window that only reads after
      //     the match misses it, and `RegExp(r'''...''')` puts a raw marker
      //     between the paren and the pattern, so a window that only reads
      //     before the match misses that too. A version of this that scored 7
      //     of 13 guards "bare" was measuring its own window, not the tree.
      //   * **`contrast_tokens` and `quote_count_copy` apply their tokens**
      //     through `RegExp(...).allMatches(src)`, where the token sits inside
      //     a *different* raw string than the map's copy. A check that
      //     compares the map's token to a literal in the same file has to
      //     accept that, and my first two plants both failed for exactly this
      //     reason -- one put the token in another raw string, the next in
      //     adjacent string literals. Neither is code.
      //
      // **Why this case asserts a census and not a behaviour.** The obvious
      // shape -- "this token must not appear in code" -- is *unfalsifiable* for
      // 10 of the 13 entries: their tokens are regex-shaped, and regex text in
      // Dart cannot exist outside a string or a comment, both of which this
      // reader blanks. Two plants confirmed it: neither turned the assertion
      // red, because neither produced code at all. An assertion that cannot
      // fail is not a test, so what is asserted instead is the census that the
      // conclusion rests on: **how the map is built**, not what its entries
      // happen to contain today. A map entry that became live code -- a token
      // written as an identifier -- would break the property the next
      // expectation checks, and that property *can* fail.
      //
      // So: the map's tokens are string-shaped, and the 27th tick's proposal is
      // unsatisfiable against it. Closing the "written down" hole properly
      // needs a real parser -- the analyzer AST, not a character window -- which
      // is larger than one cycle and is recorded as such rather than faked with
      // a heuristic that reds a correct tree.
      expect(_ruleEvidence, isNotEmpty,
          reason: 'the census this reasoning rests on is empty, so the '
              'conclusion that every token is a string literal is untested: '
              'the map could have lost every entry and this case would still '
              'pass. It is a non-trivial map -- ${_ruleEvidence.length} '
              'entries, and each is read back above.');

      // The falsifiable half, stated per entry: the token must be reachable
      // **only** as a string, and the sweep reader must therefore be the one
      // that erases it. This is what the two failed plants would have tripped
      // had they produced code, and it is what a real identifier-shaped token
      // would trip.
      for (final entry in _ruleEvidence.entries) {
        final mapCode = _blankComments(File(entry.key).readAsStringSync());
        final sweepCode = blankComments(File(entry.key).readAsStringSync());
        for (final token in entry.value) {
          // The map reader keeps string bodies, so the token is visible there.
          expect(mapCode.contains(token), isTrue,
              reason: 'the read-back above already checks this, and a failure '
                  'here means the two readers disagree about `${entry.key}`.');
          // The sweep reader erases it. For a regex-shaped token this is
          // structural: there is no way to spell it outside a string.
          if (RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$').hasMatch(token)) {
            // An identifier-shaped token *could* appear in live code, so this is
            // the one shape where "survives in code" is a real question, and the
            // sweep reader is the one that answers it.
            expect(sweepCode.contains(token), isFalse,
                reason: '`${entry.key}` carries `$token` as an '
                    'identifier-shaped token, and an identifier can exist in '
                    'live code without passing through a string. It survives '
                    'the sweep reader, so requiring tokens to survive that '
                    'reader would be satisfiable after all and the reasoning '
                    'above is stale. Re-measure the map before acting on it.');
          }
        }
      }
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

    test('no whole-file read that could name app source is dropped quietly',
        () {
      // **The third direction of the case above, and the one that keeps the
      // `File('…')` reader honest.** Teaching `_rootsOf` a new shape is a new
      // place to be wrong in two opposite directions: credit a root that reads
      // nothing, or drop a real one and say nothing. The first is caught by the
      // two cases above. This one is the second.
      //
      // The reader is *allowed* to decline, and it declines two kinds of spec
      // on purpose: one built at runtime (`'${Directory.current.path}/tool/
      // build_gate.py'`, which `tool_clock_seam_test.dart` really reads), and
      // one that is not root-shaped. Neither is a hole. The hole is a spec that
      // **could** name app source being dropped without a word -- which is
      // precisely what happened to `lib/src/widgets/ui.dart` for the tick
      // before this one: a guard enforcing a real rule about a shared kit,
      // declaring no root, and answering to no list in this file.
      //
      // So the assertion is not "nothing was skipped". It is: nothing was
      // skipped that names `lib/` or `test/`, which is the direction that
      // loses coverage, and the reader *can* skip at all, which is what makes
      // the case above falsifiable rather than vacuously true.
      final hidden = <String>[];
      for (final sweep in sweeps.values) {
        sweep.skipped.forEach((spec, why) {
          // A runtime-built prefix can still name the app one level down --
          // `'${dir}/lib/src/models/plan.dart'` -- so the test is containment,
          // not prefix.
          if (spec.contains('lib/') || spec.contains('test/')) {
            hidden.add('${sweep.file} -> $spec\n    dropped as: $why');
          }
        });
      }
      expect(hidden, isEmpty,
          reason:
              'these whole-file reads could name app source and were dropped '
              'rather than read as roots, so the guard\'s coverage is '
              'unmeasured and invisible — the shape '
              '`tile_label_fit_test.dart` hid in for a tick. Teach `_rootsOf` '
              'the spec, or pin it by name with the reason it carries no app '
              'coverage:\n${hidden.join('\n')}');

      // And the reader can decline at all. Without this the case above compares
      // two empty sets and would stay green if the skip branch went dead.
      expect(sweeps.values.expand((s) => s.skipped.keys), isNotEmpty,
          reason:
              'no whole-file read was declined anywhere in the 17 recognised '
              'sweeps, so the case above proved nothing: either the skip '
              'branch is dead or the reader has stopped seeing this shape. '
              'Measure it before believing the green above.');

      // And the shape this tick taught is not decorative: at least one guard
      // must reach a root **through it**, read off the tree rather than
      // asserted from the map -- otherwise the four `.dart` entries now in
      // `_knownRoots` are an amnesty for a shape nothing uses.
      final viaWholeFile = sweeps.values
          .where((s) => s.roots.any((r) => r.endsWith('.dart')))
          .map((s) => s.file)
          .toList()
        ..sort();
      expect(viaWholeFile, contains('test/tile_label_fit_test.dart'),
          reason:
              'no guard declares a whole-file root any more, so the '
              '`File(\'\u2026\')` shape this tick taught is unread — and '
              'a guard whose only root is one file is exactly what it was '
              'written for. Declared through it:\n'
              '${viaWholeFile.isEmpty ? 'none' : viaWholeFile.join(', ')}');
    });

    test('every rule token is applied to source, not just written down', () {
      // **The 27th tick's stated next step, closed with a parser.** The note
      // said the map "still cannot separate *enforced in code* from *written
      // down*", and that closing it needs the analyzer AST rather than a wider
      // character window. This is that: `parseString` per guard, and a literal
      // is ENFORCED when it is passed into a call that *reads* it.
      //
      // The window was measured first and it is why this is an AST. Restricting
      // the applier to `RegExp(...)` -- the shape the tokens mostly take -- was
      // 7 of 13, which would have gone red on a tree that is correct, because
      // `snack_rule_sweep_test.dart` applies its token with `.contains()`,
      // `wall_clock_seam_site_test.dart` with `.indexOf()` and `.startsWith()`,
      // and `payload_coverage_test.dart` with `.lastIndexOf()`. Both earlier
      // wrong versions of the reader are recorded on the helpers above.
      //
      // The map is the thing being asserted, so a reader that is too narrow
      // fails here loudly instead of passing a guard that enforces nothing --
      // which is exactly the failure this case exists to make impossible.
      final applied = <String>[];
      final held = <String>[];
      final missing = <String>[];

      for (final guard in _appRuleGuards.keys) {
        if (_ruleEvidenceAppliedElsewhere.containsKey(guard)) continue;
        final File file = File(guard);
        if (!file.existsSync()) continue;
        // `parseString` returns the wrapper type from the parser library, which
        // is not re-exported here; `var` is deliberate rather than lazy.
        final unit =
            parseString(content: file.readAsStringSync(), throwIfDiagnostics: false);
        for (final String token in _ruleEvidence[guard] ?? const <String>[]) {
          final _TokenUse use = _TokenUse(token);
          unit.unit.accept(use);
          // Second pass, for a rule held as data and applied by reference.
          String? byReference;
          if (use.applied == 0) {
            final _CollectionScan scan = _CollectionScan(token);
            unit.unit.accept(scan);
            for (final String owner in scan.owners) {
              final _ReferenceApplied ref = _ReferenceApplied(owner);
              unit.unit.accept(ref);
              if (ref.applied) {
                byReference = '$owner.${ref.via}()';
                break;
              }
            }
          }
          final String name = '${_appRuleGuards[guard]}\n    $guard\n'
              '    $token';
          if (use.applied > 0 || byReference != null) {
            applied.add(name);
          } else if (use.expectedOnly > 0) {
            held.add(name);
          } else {
            missing.add(name);
          }
        }
      }

      expect(missing, isEmpty,
          reason: 'these rule tokens do not reach any call that reads them, '
              'and are not held by an `expect` either. A token nobody applies '
              'is a claim, so the map entry is documenting a rule this guard '
              'does not enforce:\n${missing.join('\n')}\n'
              'Either the guard applies the token again, or the entry names a '
              'rule that moved -- in which case it belongs in '
              '`_ruleEvidenceAppliedElsewhere` above, with the place it moved '
              'to, not deleted, because an unlisted guard fails the case above.');

      // Not "empty is bad" -- measured. `motion_test.dart` is the one guard whose
      // token is held only by `expect`, and it is listed above with the reason.
      // This case is the thing that would red if a *second* guard got that way,
      // and it is falsifiable: see the planted proof in the commit message.
      expect(held.map((e) => e.split('\n')[1]).toList(),
          everyElement(isNot(anyOf(_ruleEvidenceAppliedElsewhere.keys))),
          reason: 'a guard outside `_ruleEvidenceAppliedElsewhere` now holds its '
              'token only inside `expect(...)`, so the map entry reads as '
              'evidence for a rule the guard no longer applies:\n'
              '${held.join('\n')}\n'
              'Either it applies the token again, or the rule moved and the '
              'guard belongs in `_ruleEvidenceAppliedElsewhere` naming where.');

      // The exemption list is itself read back, so it cannot quietly grow.
      for (final where in _ruleEvidenceAppliedElsewhere.entries) {
        expect(_appRuleGuards.containsKey(where.key), isTrue,
            reason: '`${where.key}` is exempted from the applied-token case '
                'but is not a named guard, so the exemption guards nothing.');
        expect(_ruleEvidence.containsKey(where.key), isTrue,
            reason: '`${where.key}` is exempted from the applied-token case '
                'but names no token, so there is nothing to exempt.');
        expect(where.value, isNotEmpty,
            reason: '`${where.key}` is exempt without saying where its rule '
                'lives, which is the shape that let this hole hide.');
      }

      // And the census the conclusion rests on is not empty.
      expect(applied, isNotEmpty,
          reason: 'no rule token was found applied to source. Either the AST '
              'reader stopped seeing the tree, or every map entry has quietly '
              'become a written-down claim -- which is the failure this case '
              'was written to catch.');
    });

    test('what the AST reader cannot see is a measured list, not a hope', () {
      // The 29th tick shipped the AST reader and left exactly this as its
      // next step: it "knows 16 appliers by name and resolves a rule one hop
      // through a reference", so the honest question is **which guards are
      // carried by an applier it only recognises by name**. Guessing produced
      // three wrong readers in this file already, all of which would have gone
      // red on a correct tree, so the answer is measured here and pinned by
      // name rather than reasoned about.
      //
      // The number that matters is not how many readers exist. It is that
      // **every applier credited is one this file declares**: the census is
      // itself subject to the rule it enforces, and `expect` is the shape that
      // slipped through before -- it is a real call in the AST, so an unlisted
      // name would be credited as enforcement of the thing it only reports.
      final Set<String> credited = <String>{};
      final Map<String, String> byMechanism = <String, String>{};

      for (final guard in _appRuleGuards.keys) {
        final File file = File(guard);
        if (!file.existsSync()) continue;
        // `parseString` returns the wrapper type from the parser library, which
        // is not re-exported here; `var` is deliberate rather than lazy.
        final unit =
            parseString(content: file.readAsStringSync(), throwIfDiagnostics: false);
        for (final String token in _ruleEvidence[guard] ?? const <String>[]) {
          final _TokenUse use = _TokenUse(token);
          unit.unit.accept(use);
          String how;
          if (use.applied > 0) {
            credited.addAll(use.appliers);
            how = use.appliers.join(', ');
          } else {
            final _CollectionScan scan = _CollectionScan(token);
            unit.unit.accept(scan);
            String? via;
            for (final String owner in scan.owners) {
              final _ReferenceApplied ref = _ReferenceApplied(owner);
              unit.unit.accept(ref);
              if (ref.applied) {
                via = '$owner.${ref.via}()';
                break;
              }
            }
            how = via ?? 'NONE';
          }
          byMechanism['$guard\n    $token'] = how;
        }
      }

      expect(credited.difference(_tokenAppliers), isEmpty,
          reason: 'these call names were credited as applying a rule token but '
              'are not in `_tokenAppliers`, so the reader is recognising them '
              'by something other than the declared list -- which is how '
              '`expect` came to be counted as enforcement once:\n'
              '${credited.difference(_tokenAppliers).join(', ')}\n'
              'Every guard was classified:\n'
              '${byMechanism.entries.map((e) => '${e.key} -> ${e.value}').join('\n')}');

      // Pinned by name, and each name is a *different* reachability the reader
      // has to earn. Measured on this tick:
      //   * `payload_coverage_test.dart` reaches its rule only by the read-out
      //     hop added here (`liveKeys.keys` in a for-in). Before the 30th tick
      //     it was credited by the fragment `'/'` and enforced nothing;
      //   * `layering_test.dart` reaches its rule one hop through a `const`
      //     map of lists applied with `.contains()`;
      //   * `motion_test.dart` reaches no applier at all and is the single
      //     listed exemption.
      // A guard silently falling from one mechanism to another is a rule that
      // stopped being enforced without a word here, so the split is asserted
      // rather than described.
      final List<MapEntry<String, String>> referenceApplied =
          byMechanism.entries
              .where((e) =>
                  e.value.endsWith('()') || e.value.startsWith('for-in'))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      // **The expected name is matched with `endsWith`, not written as a
      // `<String>[…]` literal, and that is a fourth reader in this file biting
      // its author.** `_rootsOf` treats any `['lib…']` / `['test/…']` entry in a
      // typed list literal as a declared root, and *this file is itself a
      // sweep*, so writing `containsAll(<String>['test/layering_test.dart'])`
      // made the root census decide this file walks `test/layering_test.dart`
      // -- and two unrelated cases went red on a correct tree. Matched by
      // suffix instead, which is what the assertion means anyway.
      final String layering = _appRuleGuards.keys
          .firstWhere((String k) => k.endsWith('layering_test.dart'));
      // **Index 0 is the guard, not 1** -- the key is `$guard\n    $token`, so
      // the two lines the failure message prints are the guard at `[0]` and the
      // token indented at `[1]`. Guessing the index from the rendered message is
      // what put `[1]` here first, and it compared the *token* against a guard
      // name. Measured, not reasoned.
      expect(referenceApplied.map((e) => e.key.split('\n').first).toList(),
          contains(layering),
          reason: '`layering_test.dart` holds its rule as data and applies it by '
              'reference; if that stopped being read out, its token would fall '
              'back to a literal match that finds nothing:\n'
              '${referenceApplied.map((e) => '${e.key} -> ${e.value}').join('\n')}');

      // And the census is not empty, for the same reason the applied case
      // asserts `applied` is not empty: a reader that sees nothing must not
      // read as a clean bill of health.
      expect(byMechanism, isNotEmpty,
          reason: 'no guard was classified at all, so this census is measuring '
              'nothing and would stay green against a tree it cannot see.');
    });

    test('the read-out hop credits a loop that uses its element, not one that '
        'binds it', () {
      // **The 31st tick's item, and the last unmeasured claim the AST census
      // made about itself.** `_ReferenceApplied` read a collection out with
      // `for (final x in liveKeys.keys)` and called that enforcement, and its
      // comment said the limit out loud: "it credits *reading the collection*,
      // not reading each element, so a guard that lists a rule and then does
      // nothing with it is credited here."
      //
      // A stated weakening in the reader whose entire job is separating applied
      // tokens from written-down ones is not a caveat, it is the one branch that
      // certifies enforcement on its own. Every other hop in this file is
      // falsifiable -- a wrong reader there reds a correct tree, loudly, and
      // three wrong readers here already did. This one failed the *other* way:
      // it stayed green against a guard that enforced nothing.
      //
      // **Measured before changing anything** (throwaway probe over all ten
      // censused guards, deleted after the capture). Exactly one guard reaches a
      // token through this hop:
      //
      //   payload_coverage_test.dart  owner=liveKeys  via=for-in
      //       body reads `route` 3 times  ->  '$sq$route', then two
      //       lib.contains() calls
      //   layering_test.dart          owner=_forbidden via=contains (not this hop)
      //
      // So the tightening costs nothing: the one guard on the branch uses its
      // element three times, and it is now credited *because* it does.
      //
      // Three directions are pinned, because the hole had two mouths:
      //
      //   1. the real guard is still credited, and **with its read count**, so a
      //      body that quietly stopped using the element shows as `for-in(0)`
      //      rather than vanishing;
      //   2. a for-in that reads the collection out with an **empty body** is
      //      NOT credited -- the planted case below;
      //   3. a body that only *mentions* the loop variable inside a **comment**
      //      is not credited either, so a guard cannot buy enforcement by
      //      documenting the use it did not make.
      const String owner = 'liveKeys';
      final File guard =
          File('test/payload_coverage_test.dart');
      expect(guard.existsSync(), isTrue,
          reason: 'the one guard on the read-out hop is gone, so the branch is '
              'unexercised and a passing census would be measuring nothing.');

      // Direction 1 -- the live guard, counted.
      final _ReferenceApplied real = _ReferenceApplied(owner);
      // `parseString` returns the wrapper type from the parser library, which
      // is not re-exported here; `var` is deliberate rather than lazy.
      var realUnit =
          parseString(content: guard.readAsStringSync(), throwIfDiagnostics: false);
      realUnit.unit.accept(real);
      expect(real.applied, isTrue,
          reason: '`payload_coverage_test.dart` reads `liveKeys` out in a '
              'for-in and uses each route three times; if that stopped being '
              'credited the rule would fall back to a literal match that finds '
              'nothing. via=${real.via}');
      expect(real.via, matches(RegExp(r'^for-in\([1-9]')),
          reason: 'the read-out hop now records how many times the loop body '
              'read its element, so `for-in(0)` is visible as a rule that '
              'stopped being applied rather than as a silent pass. Actual: '
              '${real.via}');

      // Directions 2 and 3 -- the two ways the branch used to pass a dead
      // guard, planted as source and read by the same visitor. Both are written
      // here as text rather than as AST so the *reader* is under test, not the
      // parser.
      const String boundOnly = '''
const Map<String, List<String>> liveKeys = {'/api/mobile/workers/top': ['id']};
void main() {
  final List<String> unused = <String>[];
  for (final String route in liveKeys.keys) {
    unused.add('');
  }
}
''';
      const String commentOnly = '''
const Map<String, List<String>> liveKeys = {'/api/mobile/workers/top': ['id']};
void main() {
  final List<String> unused = <String>[];
  for (final String route in liveKeys.keys) {
    // the loop must use route
    unused.add('');
  }
}
''';
      const String genuinelyUsed = '''
const Map<String, List<String>> liveKeys = {'/api/mobile/workers/top': ['id']};
void main() {
  final List<String> unused = <String>[];
  for (final String route in liveKeys.keys) {
    unused.add(route);
  }
}
''';
      for (final (String label, String src) in <(String, String)>[
        ('bound-only', boundOnly),
        ('comment-only', commentOnly),
      ]) {
        var planted =
            parseString(content: src, throwIfDiagnostics: false);
        final _ReferenceApplied probe = _ReferenceApplied(owner);
        planted.unit.accept(probe);
        expect(probe.applied, isFalse,
            reason: 'a for-in that reads a collection out but never reads its '
                'loop variable ($label) is a guard that lists a rule and then '
                'does nothing with it. Crediting it is the false credit this '
                'branch existed to serve; via=${probe.via}');
      }
      var good =
          parseString(content: genuinelyUsed, throwIfDiagnostics: false);
      final _ReferenceApplied ok = _ReferenceApplied(owner);
      good.unit.accept(ok);
      expect(ok.applied, isTrue,
          reason: 'a loop that really uses its element must stay credited -- '
              'the tightening is not a way of making the branch silent.');
      expect(ok.via, 'for-in(1)',
          reason: 'and the read count is the measurement, not a decoration.');
    });

    test('the applier list is what the tree uses, not what it could use',
        () {
      // The 30th tick's next item, measured rather than reasoned about. The
      // list declared 15 names and the census credited 2. Deleting 13 names
      // that earn nothing is only half the job: the danger is that the list
      // becomes **wrong** instead of merely long -- an applier that is declared
      // but never reached, or a guard that reaches a token through a name the
      // list does not declare. Both directions are asserted here.
      //
      // The measurement behind the trim (3 Oct, over all 13 guards):
      //
      //   declared 15, credited 2  ->  RegExp, contains
      //   dead 13  ->  hasMatch(28 calls/0 tokens), split(42/0),
      //                 allMatches(34/0), endsWith(27/0), startsWith(16/0),
      //                 indexOf(6/0), replaceAll(6/0), firstMatch(3/0),
      //                 isWall(2/0), replaceFirst(2/0), lastIndexOf(1/0),
      //                 matches(0/0), replaceRange(0/0)
      //
      // The dead 13 are not noise. Each is the **downstream half** of the same
      // chain: `RegExp(r'token').hasMatch(src)` puts the token in the `RegExp`
      // argument, so the reader credits `RegExp` and the sibling never sees one.
      // That is why trimming is safe *and* why the names were there in the
      // first place: `hasMatch` is the natural spelling, and a guard written as
      // `src.hasMatch(token)` must go red until `hasMatch` is declared -- not
      // be silently credited by a name nobody listed, and not be silently
      // missed.
      //
      // This asserts a **census**, deliberately, and the reason is written down
      // because three readers in this file already guessed wrong: what is being
      // claimed is about the tree, so the only falsifiable form is to derive it
      // from the tree and compare. Two facts are checked, in both directions:
      //
      //   1. no **declared** applier is dead in the current tree, and
      //   2. no applier is reached **with a token** by a name that is not
      //      declared -- which would mean the reader is crediting enforcement
      //      through an unlisted name, the `expect` bug from the 29th tick.

      // Direction 2 first: every method invocation in every censused guard
      // whose *arguments* carry the guard's token. `group`/`test`/`expect` are
      // excluded because they wrap a call rather than read the token -- and
      // `expect` is exactly the name that was once credited as enforcement.
      final Set<String> undeclared = <String>{};
      final List<String> seen = <String>[];
      for (final guard in _appRuleGuards.keys) {
        final File file = File(guard);
        if (!file.existsSync()) continue;
        final unit =
            parseString(content: file.readAsStringSync(), throwIfDiagnostics: false);
        for (final String token in _ruleEvidence[guard] ?? const <String>[]) {
          final _CallScan scan = _CallScan(token);
          unit.unit.accept(scan);
          for (final String call in scan.tokenCalls) {
            if (_nonReaders.contains(call)) continue;
            if (!_tokenAppliers.contains(call)) undeclared.add(call);
            seen.add(call);
          }
        }
      }
      expect(undeclared, isEmpty,
          reason: 'these calls receive a rule token but are not declared in '
              '`_tokenAppliers`, so the reader credits enforcement through a '
              'name nobody listed -- the same shape as `expect` being credited '
              'once:\n${undeclared.join(', ')}\n'
              'Calls seen carrying a token: ${seen.toSet().join(', ')}');

      // Direction 1: every declared name is actually reached. This is what
      // stops the list from rotting back into speculation -- a name added for a
      // guard that was later rewritten goes red here instead of sitting
      // credited to nothing, which is how this list reached 15 names.
      final Set<String> credited = <String>{};
      for (final guard in _appRuleGuards.keys) {
        final File file = File(guard);
        if (!file.existsSync()) continue;
        final unit =
            parseString(content: file.readAsStringSync(), throwIfDiagnostics: false);
        for (final String token in _ruleEvidence[guard] ?? const <String>[]) {
          final _TokenUse use = _TokenUse(token);
          unit.unit.accept(use);
          credited.addAll(use.appliers);
        }
      }
      final Set<String> dead = _tokenAppliers.difference(credited);
      expect(dead, isEmpty,
          reason: 'these appliers are declared but no guard in the tree reaches '
              'a rule token through them any more. Either delete the name or '
              'fix the guard; a declared reader that credits nothing is the '
              'dead weight this item removed:\n${dead.join(', ')}\n'
              'Credited today: ${credited.toList()..sort()..join(', ')}');

      // And the census underneath both directions is not vacuous.
      expect(seen, isNotEmpty,
          reason: 'no call at all received a token, so the two assertions above '
              'would both pass against a tree it cannot read.');
      expect(_tokenAppliers, isNotEmpty,
          reason: 'the applier list is empty, so nothing can be credited and the '
              'difference above is empty for the wrong reason.');
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
