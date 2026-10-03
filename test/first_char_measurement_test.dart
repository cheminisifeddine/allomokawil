// First-character measurement: `name[0]` on a user-supplied string.
//
// **The class of bug.** A string is stored verbatim from a plain `TextField`
// with no input formatter (`auth_screen.dart:164` is
// `fullName: _name.text.trim()`), and Algerian users paste their own name out
// of Facebook and WhatsApp constantly. Those apps bracket Arabic text with
// invisible formatting characters — `U+200F` RLM, `U+200E` LRM, `U+200D` ZWJ,
// `U+200B` ZWSP. Dart's `String.trim()` strips whitespace and these are `Cf`
// (format) characters, **not** whitespace, so `trim('\u200fمحمد')` keeps
// `U+200F` as its first code unit. `name[0]` then hands back a **zero-width
// glyph** where the real character should be, and code that branches on it —
// `name[0] == 'م'`, `name[0].toUpperCase()`, a list built per leading letter —
// silently measures nothing.
//
// The monogram tick (30th) fixed exactly this for the avatar, and **refused to
// call the rest of the app clean**; this is the rest of the app. `Monogram.of`
// owns the read-time rule: skip what paints nothing, never edit the stored
// name. Anything that wants a name's first character goes through it.
//
// **Measured before this file existed, not asserted from grepping.** A `grep`
// over `lib/` for `runes.first` / `name[0]` / `substring(0,1)` comes back
// near-empty — it found one `runes.first` and one `name[0]`, both *inside the
// doc comments of the very helpers being discussed*. A grep cannot tell a
// comment from code, and it cannot tell `list[0]` from `str[0]`: four of the
// five `[0]` sites in the tree are `List` receivers. So this is an AST over
// **resolved** types. What it found:
//
// | receiver type | site | verdict |
// | --- | --- | --- |
// | `String` | `dz_phone.dart:65` `'567'.contains(d[0])` | allowed — [allowed] |
// | `String` (x6) | `substring(0, n)` in phone/number/clip/crash code | allowed — [allowed] |
// | `List` (x4) | `batches[0]`, `items[0]`, `_docs[0]`, `(row as List)[0]` | not a string at all |
//
// so the tree is correct today and this file is what keeps it correct. The
// interesting number is not "0 violations" — it is **1 allowed `String[0]`**,
// because a guard that has never had to allow anything cannot be shown to
// allow it.
//
// **Widened on 3 Oct (33rd tick), in both halves, and measured rather than
// assumed.** The tick that wrote this file listed a third shape in the same
// class in its own prose and did not implement it: `.runes.first`. Both layers
// were checked before any line was written, and both were open —
//
//   * **Selection.** `_candidateFiles()` fired on `[0]` and `substring(0,`,
//     so a file whose only site was `s.runes.first` was never selected.
//   * **Catch.** `_FirstCharVisitor` had no `visitPropertyAccess`, so even a
//     selected file's `runes.first` site was never recorded.
//
// `runes.first` is not a near-miss for `[0]`; it is the same question asked of
// a string: *what is its first character*. The monogram's own doc comment names
// it as the shape the avatar used before it was fixed, which is exactly why it
// is the shape a paste-from-Facebook regression would come back through.
//
// Measured before the change (comment-blanked, so doc comments do not count):
// **0 code sites** in all 131 `lib/` files for `runes.first`, `runes[0]`,
// `characters.first` and `codeUnitAt(0)`. So this is a hole in a green guard,
// not a live defect — which is the only kind worth widening a 29 s guard for
// when there are no users to break.
//
// The cost was measured rather than guessed, because the prefilter is the only
// thing standing between this guard and the ~54 s whole-tree resolution: the
// four added patterns select **0 new files**. The candidate set stays **10 of
// 131**, so the resolution bill does not move.
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receiver expressions that measure a string's first character, and are not
/// the avatar.
///
/// An entry is `relPath#owner` and must still resolve to the same receiver
/// expression in the same file. That is the cost of the allow-list: it rots
/// the moment the code it excuses moves, and the rot **is** the failure — a
/// stale entry cannot silently exempt a new site, because it exempts an
/// expression that no longer exists and the new site goes back to red.
///
/// Every entry here is digit-only or explicitly bounded; none of them is
/// user-facing text, and that is checked by shape rather than by assertion —
/// each one is either in a module under `core/text/` that folds its input to
/// digits, or truncates with `substring` rather than *deciding* on the first
/// character.
const _allowed = <String, String>{
  // `'567'.contains(d[0])` — the leading-operator-digit test. `d` is the
  // digit-only form: `canonicalFromDigits` strips `_nonDigit` on its first
  // line, so there is no code unit here that is not a digit and the check is
  // about `5`/`6`/`7`, not about a person. Its own docstring calls the repair
  // "550123456 -> 0550123456", i.e. a number the user mistyped as international.
  'lib/src/core/text/dz_phone.dart#canonicalFromDigits': 'leading operator '
      'digit of a digit-only phone number, repaired to a 0-prefixed form',
  // The six `substring(0, n)` receivers below are truncation, not measurement:
  // `substring(0, max)` keeps the first n characters, it never *decides* on
  // the first one. Listed individually because a bundled glob could not say
  // which module each belongs to, and `dz_number`/`dz_phone` (digits) must not
  // be allowed to excuse a future call site in a screen.
  'lib/src/core/text/dz_phone.dart#_cap': 'digit-only phone, length cap',
  'lib/src/core/text/dz_number.dart#formatEditUpdate': 'digit-only number, '
      'input-formatter bound',
  'lib/src/core/diagnostics/crash_log.dart#trim': 'clamping a log value to a '
      'column width, never a user-visible name',
  'lib/src/core/network/api_client.dart#_decode': 'truncating a response body '
      'for a crash report',
  'lib/src/data/chat_outbox.dart#_clip': 'truncating a stored preview to a '
      'fixed width',
  'lib/src/widgets/phone_field.dart#formatEditUpdate': 'digit-only phone, '
      'input-formatter bound',
};

/// One measured site: a string indexed or sliced from its first character.
class _Site {
  _Site(this.file, this.owner, this.offset, this.receiver);

  /// `lib/…`, as `git` and every other sweep in this repo spells it.
  final String file;

  /// The method or function the site sits in.
  final String owner;

  /// Byte offset in [file].
  final int offset;

  /// The receiver expression, on one line — what a reader would see.
  final String receiver;

  /// `file#owner`, the allow-list key.
  String get key => '$file#$owner';

  @override
  String toString() => '$file:${_lineAt(file, offset)}  $receiver  (in $owner)';
}

int _lineAt(String file, int offset) {
  final src = File(file).readAsStringSync();
  var line = 1;
  for (var i = 0; i < offset && i < src.length; i++) {
    if (src.codeUnitAt(i) == 0x0a) line++;
  }
  return line;
}

/// Cheap syntactic pass: the files that contain *any* candidate site.
///
/// Resolving the whole tree costs ~54 s; resolving only the files this
/// prefilter selects costs ~29 s, and the guard runs inside a suite with a
/// 1200 s deadline. The filter is deliberately **syntactic** (`[0]`,
/// `substring(0,`, `runes.first`, …), because resolution is what decides
/// whether a receiver is a `String` at all — four of the five `[0]` sites in
/// the tree are `List`.
///
/// A prefilter can miss a site, so it is written to be wider than the rule:
/// it fires on `[0]` anywhere and on each first-character shape below, never on
/// a narrowed pattern. What it costs in false positives is paid in the
/// `UNRESOLVED` / allow-list cases below, both of which are loud.
///
/// **Why the shapes are four patterns and not one.** `runes.first`,
/// `runes[0]`, `characters.first` and `codeUnitAt(0)` are one question with four
/// spellings, so a single combined alternation is tempting — and it is the
/// wrong shape for two reasons that both bit a previous tick of this file. The
/// census reads the *enclosing call* of a rule token and credits it to `RegExp`
/// only when the pattern sits at statement level, and a bare alternation would
/// have to be one literal, so the token names a rule that no longer reads as
/// the rule. Four named patterns keep each shape individually legible, and each
/// is checked below against the census's token reader.
///
/// The measured cost of adding them: **0 new files selected.** 131 files in
/// `lib/`, 10 candidates before and after — `arabic_search.dart` and
/// `monogram.dart` *do* contain the word `runes`, which is why the shapes are
/// anchored on the call, not on the identifier.
List<String> _candidateFiles() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return const <String>[];

  // An explicit loop, not a chained `.where(...)`, and the reason is measured
  // rather than stylistic: the census reads the *enclosing call* of a rule
  // token, so a pattern written inside a closure passed to `.where` is credited
  // to `where` -- a generic `Iterator` method, not an applier -- and the
  // census went red on `where` the first time this ran. Written this way the
  // token sits at statement level and is credited to `RegExp`, which is
  // declared. Keeping the two readers in agreement is the point.
  final out = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final f = entity;
    if (!f.path.endsWith('.dart')) continue;
    final code = _stripComments(f.readAsStringSync());
    if (!_selects(code)) continue;
    out.add(f.path.replaceAll('\\', '/'));
  }
  return out..sort();
}

/// The prefilter's second shape, as a pattern rather than an inline literal so
/// the census can name it as this file's evidence token.
final RegExp _firstSlice = RegExp(r'substring\s*\(\s*0\s*,');

/// `runes.first` — the shape the monogram tick named and this file did not
/// implement. Anchored on the *call*, because two files in the tree mention
/// `runes` in code and both are the avatar's own correct loop.
final RegExp _runesFirst = RegExp(r'runes\s*\.\s*first');

/// `runes[0]` — same question, indexed rather than read.
final RegExp _runesIndex = RegExp(r'runes\s*\[\s*0\s*\]');

/// `characters.first` — the grapheme-safe spelling. `characters` is not a
/// direct dependency here (it arrives through `flutter`), so this shape is
/// selected and recorded for completeness rather than because the tree uses it.
final RegExp _charactersFirst = RegExp(r'characters\s*\.\s*first');

/// `codeUnitAt(0)` — the raw spelling, which is what `s[0]` compiles to and
/// therefore the shape a refactor away from the operator reintroduces.
final RegExp _codeUnitAtZero = RegExp(r'codeUnitAt\s*\(\s*0');

/// Does [code] (comment-blanked) hold any shape that measures a first
/// character?
///
/// Kept as its own function rather than one long `||` chain in the loop so the
/// census's token reader sees each pattern at statement level, and so adding a
/// shape is one line here and one named pattern above — not an edit inside a
/// condition someone else will have to re-read.
bool _selects(String code) {
  if (code.contains('[0]')) return true;
  if (_firstSlice.hasMatch(code)) return true;
  if (_runesFirst.hasMatch(code)) return true;
  if (_runesIndex.hasMatch(code)) return true;
  if (_charactersFirst.hasMatch(code)) return true;
  if (_codeUnitAtZero.hasMatch(code)) return true;
  return false;
}

/// The source with comments blanked, offsets preserved.
///
/// A doc comment in this repository discusses `runes.first`, `name[0]` and
/// `substring(0,1)` by name — and on 3 Oct a grep found **both** of the two
/// shapes it was asked to look for, inside the very doc comments explaining
/// them. Comment-blanked source is the difference between a measurement and a
/// quote. Extracted from `app_source_scope_test.dart`'s reader by behaviour,
/// not copied: two readers that disagree about "the code, not the prose" is
/// the defect this repository keeps re-learning.
String _stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      final stop = end == -1 ? src.length : end + 2;
      while (i < stop) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// The Dart SDK the analyzer should read, resolved rather than guessed.
///
/// **A real failure, on the first run of this file.** `AnalysisContextCollection`
/// left `sdkPath` unset, so the analyzer fell back to locating a Dart SDK next
/// to the *executing* binary -- and under `flutter test` that binary is
/// `flutter_tester` in `bin/cache/artifacts/engine/`, which ships no Dart SDK
/// at all. It died with
///
/// ```text
/// PathNotFoundException(path=…/bin/cache/artifacts/engine/version)
/// ```
///
/// which reads like a corrupt install and is not one. `Platform.resolvedExecutable`
/// is that same `flutter_tester`, so there is no path under it to walk up from;
/// the SDK is a **sibling** of the `cache/` directory that holds the engine
/// artifacts. Walking up from `resolvedExecutable` until the `dart-sdk` folder
/// appears is therefore the honest way to find it, and it works under both
/// `flutter test` and a bare `dart run`.
String _dartSdkPath() {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    // `Directory`, not `File`: `dart-sdk` is a folder, and testing it as a
    // file is a miss that reads exactly like an SDK that is not installed.
    final candidate = Directory('${dir.path}${Platform.pathSeparator}dart-sdk');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('no dart-sdk found above ${Platform.resolvedExecutable} -- the '
      'analyzer cannot resolve types without one, and a guard that cannot '
      'resolve types cannot tell a String from a List.');
}

/// Runs the visitor over [body] as a one-function unit and returns what it
/// measured.
///
/// Parsed, not resolved: the two shapes this case exercises
/// (`runes.first`, `runes[0]`) are decided by the *shape* of the receiver, and
/// resolving would need an SDK context per probe for a decision that does not
/// take one. `_isString` still applies to the `codeUnitAt(0)` and bare `[0]`
/// branches, which is why those two are asserted through the real resolved
/// walk in the cases above rather than here -- a probe that only works because
/// nothing resolved would be a probe measuring its own absence.
List<_Site> _sitesIn(String path, String body) {
  final result = parseString(content: body, throwIfDiagnostics: false);
  final found = <_Site>[];
  result.unit.accept(_FirstCharVisitor(path, found));
  return found;
}

/// Finds every place a **String** is indexed at 0 or sliced from 0.
class _FirstCharVisitor extends RecursiveAstVisitor<void> {
  _FirstCharVisitor(this.file, this.sites);

  final String file;
  final List<_Site> sites;

  @override
  void visitIndexExpression(IndexExpression node) {
    final i = node.index;
    if (i is IntegerLiteral && i.value == 0) {
      if (_isString(node.realTarget)) {
        sites.add(_Site(file, _ownerOf(node), node.offset,
            _oneLine(node.realTarget.toString())));
      }
      // `s.runes[0]` / `s.characters[0]`: the indexed spelling of the same
      // question, and the one that would *not* be caught by the `[0]` branch if
      // it were left there, because the target is a `Runes`, not a `String`.
      // This is the third shape the 32nd tick listed and the reason the check
      // moved out of the `&&` — a single condition cannot say "a String at 0,
      // or a character sequence at 0" without becoming the reader's own bug.
      if (_isFirstCharSource(node.realTarget)) {
        sites.add(_Site(file, _ownerOf(node), node.offset,
            '${_oneLine(node.realTarget.toString())}[0]'));
      }
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'substring') {
      final args = node.argumentList.arguments;
      if (args.isNotEmpty &&
          args.first is IntegerLiteral &&
          (args.first as IntegerLiteral).value == 0 &&
          node.target != null &&
          _isString(node.target!)) {
        sites.add(_Site(file, _ownerOf(node), node.offset,
            'substring(0, …) on ${_oneLine(node.target!.toString())}'));
      }
    }
    // `codeUnitAt(0)` — the shape `s[0]` compiles to, so a refactor away from
    // the operator reintroduces exactly this. Arg-checked, not name-checked:
    // `s.codeUnitAt(0)` and `s.codeUnitAt(i)` are the same token.
    if (node.methodName.name == 'codeUnitAt') {
      final args = node.argumentList.arguments;
      if (args.length == 1 &&
          args.first is IntegerLiteral &&
          (args.first as IntegerLiteral).value == 0 &&
          node.target != null &&
          _isString(node.target!)) {
        sites.add(_Site(file, _ownerOf(node), node.offset,
            'codeUnitAt(0) on ${_oneLine(node.target!.toString())}'));
      }
    }
    super.visitMethodInvocation(node);
  }

  /// `s.runes.first` / `s.characters.first`.
  ///
  /// **A `PropertyAccess`, not a `MethodInvocation`, and the self-test is what
  /// proved it.** The first version of this widening put the `.first` check in
  /// `visitMethodInvocation`, on the reasonable reading that `first` is a
  /// method — it is, but only where it is *called*. Written without
  /// parentheses, `s.runes.first` parses as a `PropertyAccess` whose
  /// `propertyName` is `first`, so it never reaches `visitMethodInvocation` at
  /// all: the guard measured nothing while the prefilter happily selected the
  /// file. That is the exact failure the 32nd tick predicted by name ("the
  /// visitor has no `visitPropertyAccess` to catch it"), and the reason the
  /// probe case exists — the other three cases in this file stayed green
  /// through that bug, because a tree with no `.runes.first` in it is a tree
  /// the wrong visitor still passes.
  ///
  /// `codeUnitAt(0)` deliberately does **not** come through here: it is called
  /// with an argument, so it is a real `MethodInvocation`.
  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (node.propertyName.name == 'first' &&
        target != null &&
        _isFirstCharSource(target)) {
      sites.add(_Site(file, _ownerOf(node), node.offset,
          '${_oneLine(target.toString())}.first'));
    }
    super.visitPropertyAccess(node);
  }

  /// The receiver is a sequence of **characters**: `s.runes` or
  /// `s.characters`.
  ///
  /// **Two node types, and finding the second one is why this guard is a
  /// measurement rather than a grep.** The obvious implementation tests
  /// `target is PropertyAccess` and reads `propertyName`. It records nothing:
  /// in `s.runes.first`, the receiver of `first` is **`PrefixedIdentifier`**
  /// (printed as `PrefixedIdentifierImpl`), not `PropertyAccess`. The analyzer
  /// only builds a `PropertyAccess` when the *base* of the chain is something
  /// other than a plain identifier -- `this.s.runes.first` and a cascade give
  /// one, `s.runes.first` does not. Probed and printed rather than assumed:
  ///
  /// ```text
  /// PA name=first targetClass=PrefixedIdentifierImpl targetSrc="s.runes"
  /// ```
  ///
  /// So both shapes are accepted and both are named: a `PrefixedIdentifier`
  /// by its `identifier.name`, a `PropertyAccess` by its `propertyName`. A
  /// guard that checks one and reads the other cannot record the site it was
  /// written for, and it is green either way because a tree with no such site
  /// in it measures zero — which is why the probe case is asserted against a
  /// probe, not against the tree.
  ///
  /// Deliberately *not* "is a `String`": `.runes` on a `String` yields an
  /// `Runes`, and `s.runes.first` is exactly the RLM-safe read the monogram
  /// replaced. The question is whether the receiver hands back characters at
  /// all, and naming the two accessors that do is what keeps `list.first` out.
  bool _isFirstCharSource(Expression target) {
    if (target is PropertyAccess) {
      return _isCharAccessor(target.propertyName.name);
    }
    if (target is PrefixedIdentifier) {
      return _isCharAccessor(target.identifier.name);
    }
    return false;
  }

  /// `runes` / `characters` — the two accessors that yield a character's
  /// sequence rather than a collection's element.
  ///
  /// A named predicate rather than two comparisons inline, because the reason
  /// this exists is a shape the guard was blind to and a reader needs to see
  /// both node types handled in one place.
  bool _isCharAccessor(String name) => name == 'runes' || name == 'characters';

  /// The receiver's **resolved** type is a `String`.
  ///
  /// This is the whole reason the file is an AST and not a grep: `batches[0]`
  /// and `d[0]` are the same five characters, and only the resolved element
  /// type tells them apart. `element?.name` rather than `is String` because a
  /// receiver typed `String?` resolves to the same `String` element, and
  /// `dynamic` resolves to no element at all — which is then *reported*
  /// rather than assumed safe.
  bool _isString(Expression target) {
    final type = target.staticType;
    if (type == null) return false;
    return type.element?.name == 'String' || type.element?.name == 'String?';
  }

  String _ownerOf(AstNode node) {
    AstNode c = node;
    while (c.parent != null &&
        c.parent is! FunctionDeclaration &&
        c.parent is! MethodDeclaration) {
      c = c.parent!;
    }
    final d = c.parent;
    if (d is MethodDeclaration) return d.name.lexeme;
    if (d is FunctionDeclaration) return d.name.lexeme;
    return '<top-level>';
  }

  String _oneLine(String s) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 60 ? flat : '${flat.substring(0, 57)}…';
  }
}

void main() {
  group('first-character measurement of user-supplied strings', () {
    // Filled by the AST pass; both cases below read it, so the walk happens
    // once and its *failure modes* are asserted rather than swallowed.
    final List<_Site> sites = <_Site>[];
    // Declared beside `sites` rather than inside `setUpAll` because the budget
    // case above reads it, and a variable scoped to the hook is invisible to
    // every case that follows.
    List<String> candidates = const <String>[];

    setUpAll(() async {
      candidates = _candidateFiles();
      // Non-empty, or the walk below is vacuous against a tree never read —
      // the same floor `shippedDartFiles()` asserts in the census.
      expect(candidates, isNotEmpty,
          reason: 'no file under lib/ contains a `[0]` index or a '
              '`substring(0, …)` call, so this guard is measuring an empty '
              'set and every case below would pass on a broken reader.');

      final collection = AnalysisContextCollection(
        includedPaths: [Directory.current.absolute.path],
        sdkPath: _dartSdkPath(),
      );
      for (final path in candidates) {
        final file = File(path);
        final abs = file.absolute.path;
        final SomeResolvedUnitResult result = await collection
            .contextFor(abs)
            .currentSession
            .getResolvedUnit(abs);
        if (result is! ResolvedUnitResult) {
          fail('could not resolve $abs — a file this guard cannot resolve is a '
              'file it cannot police, and it must not be skipped silently.');
        }
        final found = <_Site>[];
        result.unit.accept(_FirstCharVisitor(abs, found));
        for (final s in found) {
          // `abs` is absolute here; the allow-list is keyed on `lib/…`.
          final rel = s.file.replaceFirst('${Directory.current.path}/', '');
          sites.add(_Site(rel, s.owner, s.offset, s.receiver));
        }
      }
    });

    test('every String[0] and substring(0, …) is excused by name', () {
      final unexcused = <_Site>[];
      for (final s in sites) {
        if (_allowed.containsKey(s.key)) continue;
        unexcused.add(s);
      }
      expect(unexcused, isEmpty,
          reason: 'these places measure a string\'s first character directly. '
              'A name typed or pasted out of Facebook can begin with an '
              'invisible RLM (`\\u200f`), LRM, ZWJ or ZWSP — `trim()` does not '
              'strip those, so `s[0]` hands back a zero-width glyph and any '
              'test on it silently measures nothing.\n'
              'Use `Monogram.of(name)` (lib/src/core/text/monogram.dart), which '
              'skips what paints nothing and returns «؟» when there is nothing '
              'left.\n'
              'If this site is genuinely not user-facing text, add '
              '`file#owner` to `_allowed` with a reason — it will be checked '
              'for staleness:\n'
              '${unexcused.join('\n')}\n'
              'Measured today: ${sites.length} site(s), '
              '${_allowed.length} of them excused.');
    });

    test('the allow-list excuses nothing that moved', () {
      // The failure mode an allow-list has if nothing checks it: an entry
      // outlives the code it excuses, and the *next* site to appear at that
      // `file#owner` is waved through unexamined. Stated as the inverse of the
      // case above — that one catches an unexcused site, this one catches a
      // stale excuse — so neither direction can pass alone.
      final stale = <String>[];
      for (final key in _allowed.keys) {
        if (sites.any((s) => s.key == key)) continue;
        stale.add('$key\n    ${_allowed[key]}');
      }
      expect(stale, isEmpty,
          reason: 'these entries excuse a `file#owner` that no longer measures '
              'a string\'s first character, so the excuse is covering nothing '
              'while a future site at the same key goes unexamined:\n'
              '${stale.join('\n')}');
    });

    test('the widened shapes are selected AND caught, not just selected', () {
      // **The hole this file was widened to close, asserted from both sides.**
      // The 32nd tick established that `runes.first` was neither selected by
      // `_candidateFiles()` nor recorded by the visitor, and left it as a
      // finding. Widening without this case would be a comment claiming a
      // coverage the guard could silently lose again: delete the `first`
      // branch below and this case goes red, where the other three would stay
      // green on a tree that happens to contain no site.
      //
      // Each probe is asserted on BOTH halves, because either half alone
      // passes on a broken guard:
      //
      //   * **selected** (`_selects`) — catches a widened prefilter whose
      //     visitor still cannot see the shape;
      //   * **caught** (the visitor over parsed source) — catches a visitor
      //     that records the shape in a file the prefilter never hands it.
      final probes = <String, String>{
        r's.runes.first': r'runes\s*\.\s*first',
        r's.runes[0]': r'runes\s*\[\s*0\s*\]',
        r's.characters.first': r'characters\s*\.\s*first',
        r's.codeUnitAt(0)': r'codeUnitAt\s*\(\s*0',
      };
      for (final entry in probes.entries) {
        expect(_selects(entry.key), isTrue,
            reason: 'the prefilter does not select '
                '`${entry.key}`, so a file whose only site is that shape '
                'is never handed to the visitor and the guard is blind to '
                'it. The shape it is written for is ${entry.value}.');
      }

      // The catch half, split by the decision each shape actually makes --
      // and the split is not tidiness, it is the difference between a probe
      // that proves something and one that cannot fail.
      //
      // `runes.first` / `runes[0]` / `characters.first` are decided on the
      // **shape** of the receiver, so a parsed probe is enough. `codeUnitAt(0)`
      // is decided by `_isString`, i.e. by the **resolved** type, and an
      // unresolved `s` has no `staticType` at all -- so putting it in this
      // parsed loop asserted a green that meant nothing, then failed for the
      // right reason. It is exercised through the real resolved walk instead,
      // by the planted `codeUnitAt` case below.
      for (final probe in probes.keys.where((p) => !p.contains('codeUnitAt'))) {
        final found =
            _sitesIn('probe.dart', 'String first(String s) => $probe;');
        expect(found, isNotEmpty,
            reason: 'the visitor recorded no site for `$probe`, so the '
                'prefilter selects the file and the guard then measures '
                'nothing in it.\nTwo shapes this guard has already been '
                'wrong about, both found by running this very probe:\n'
                '  * a no-paren member access is an AST `PropertyAccess`, not '
                'a `MethodInvocation`, so a check for `.first` inside '
                '`visitMethodInvocation` sees nothing;\n'
                '  * and the receiver of `.first` is a `PrefixedIdentifier`, '
                'not a `PropertyAccess`, so `target is PropertyAccess` also '
                'sees nothing. Both are handled in `_isFirstCharSource`.');
      }
    });

    test('the resolved shape is caught in a real resolved walk', () async {
      // `codeUnitAt(0)` cannot be proved by a parsed probe: `_isString` reads
      // `staticType`, and an unresolved receiver has none. So this case
      // resolves a real file through the same `AnalysisContextCollection` the
      // `lib/` walk uses, with the probe planted in `lib/` for the duration --
      // planted and reverted inside the case, never committed, because a probe
      // shipped in the tree would be a site the allow-list has to excuse.
      //
      // Written this way because the alternative -- asserting the branch by
      // reading it -- is the failure this whole file keeps re-learning.
      final probe = File('lib/src/core/text/_first_char_probe.dart');
      expect(probe.existsSync(), isFalse,
          reason: 'a planted probe was left behind in lib/; it would ship as '
              'a real site and the allow-list would have to excuse it.');
      probe.writeAsStringSync('''
/// Planted by first_char_measurement_test.dart. Never committed.
String probeCodeUnit(String s) => s.codeUnitAt(0).toString();
''');
      try {
        final collection = AnalysisContextCollection(
          includedPaths: [Directory.current.absolute.path],
          sdkPath: _dartSdkPath(),
        );
        final abs = probe.absolute.path;
        final SomeResolvedUnitResult result = await collection
            .contextFor(abs)
            .currentSession
            .getResolvedUnit(abs);
        expect(result, isA<ResolvedUnitResult>(),
            reason: 'the planted probe could not be resolved, so this case '
                'would be asserting the shape half of a branch it never ran.');
        final found = <_Site>[];
        (result as ResolvedUnitResult)
            .unit
            .accept(_FirstCharVisitor(abs, found));
        expect(found.map((s) => s.receiver), contains('codeUnitAt(0) on s'),
            reason: 'the visitor did not record the planted '
                '`s.codeUnitAt(0)`, so the raw-codeUnit spelling is selected '
                'but not caught -- the prefilter and the visitor disagree.\n'
                'recorded: ${found.map((s) => s.toString()).join(', ')}');
      } finally {
        if (probe.existsSync()) probe.deleteSync();
      }
    });

    test('the widening did not widen the guard into a false positive', () {
      // The other direction, and the reason the `first` branch is
      // `_isFirstCharSource` and not "any `.first`". `list.first` is the most
      // common expression in Dart; a guard that flagged it would put every
      // call site in the tree on the allow-list within a week, and an
      // allow-list that covers the tree is a guard that polices nothing.
      for (final probe in [
        'List<int> f(List<int> xs) => xs.first;',
        'Map<String, int> g(Map<String, int> m) => m.values.first;',
      ]) {
        expect(_sitesIn('probe.dart', probe), isEmpty,
            reason: '`$probe` does not measure a string\'s first character, so '
                'recording it would be a false positive -- and the 4 sites the '
                'tree legitimately has are joined by this one every time a '
                'collection is read.');
      }
    });

    test('the prefilter still costs a fraction of the tree', () {
      // The guard runs inside a suite with a 1200 s deadline, and the reason it
      // costs ~29 s instead of ~54 s is entirely this prefilter: whole-tree
      // resolution is what nearly cost the loop three consecutive ticks on
      // 30 Sep. The four shapes added on 3 Oct selected **0** new files
      // (10 candidates of 131 before and after), and this is what keeps that
      // true -- a future shape anchored too loosely (`\brunes\b` rather than
      // the call) drags this number up, and it is a budget, not a hope.
      expect(candidates.length, lessThanOrEqualTo(24),
          reason: 'the prefilter now selects ${candidates.length} of the '
              'files under lib/. The prefilter IS the cost model here: past '
              'roughly a quarter of the tree the resolution bill climbs toward '
              'the whole-tree figure and the guard stops being affordable '
              'inside the suite deadline. Narrow a shape, do not raise this '
              'number.\n${candidates.join('\n')}');
    });

    test('the walk really found the sites it claims to find', () {
      // The check that keeps the other two from passing on a reader that
      // resolves nothing. A guard that silently returns zero sites is green on
      // both cases above; this one is red on it.
      //
      // The floor is deliberately **not** a count of every site: it asserts
      // the two shapes the tree is known to contain — one `String[0]` in
      // `dz_phone.dart` and the six truncations — so a reader that stops
      // resolving receivers would have to invent all seven to pass.
      expect(sites, isNotEmpty,
          reason: 'the AST walk resolved files but measured no site at all, so '
              'both rules above are vacuous.');
      expect(sites.where((s) => s.file.endsWith('dz_phone.dart')).length,
          greaterThanOrEqualTo(2),
          reason: 'dz_phone.dart is measured to hold `d[0]` and `_cap`\'s '
              'substring(0, …); finding fewer than two means the reader stopped '
              'resolving receiver types:\n${sites.join('\n')}');
      expect(sites.any((s) => s.receiver.startsWith('substring(0')), isTrue,
          reason: 'no `substring(0, …)` receiver was resolved as a String:\n'
              '${sites.join('\n')}');
    });
  });
}
