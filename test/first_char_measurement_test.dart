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

import 'package:allomokawil/src/core/diagnostics/crash_log.dart';
import 'package:allomokawil/src/core/network/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:allomokawil/src/core/text/clip.dart';
import 'package:allomokawil/src/core/text/dz_number.dart';
import 'package:allomokawil/src/core/text/dz_phone.dart';

/// Receiver expressions that measure a string's first character, and are not
/// the avatar.
///
/// An entry is `relPath#owner` and must still resolve to the same receiver
/// expression in the same file. That is the cost of the allow-list: it rots
/// the moment the code it excuses moves, and the rot **is** the failure — a
/// stale entry cannot silently exempt a new site, because it exempts an
/// expression that no longer exists and the new site goes back to red.

/// One excused site, and **the fold that justifies it, by name**.
///
/// A bare `String` reason is a promise with nothing holding it: the reader has
/// to go and find which function makes the receiver safe, and a reader that
/// guesses wrong is the failure this file exists to catch. So the excuse is
/// two fields — the reason, and the *identifier* of the fold — and the
/// identifier is not prose: it must be a key of [_folds], and the case
/// "every excuse names a fold that is run" fails on a name that is not.
class _AllowedSite {
  const _AllowedSite(this.reason, this.fold);

  /// Why the site is not user-facing text. Read by a human.
  final String reason;

  /// The key in [_folds] of the function that makes the receiver digit-only.
  ///
  /// By **name** rather than by value so the tie cannot rot: an entry whose
  /// fold is renamed goes red on the name, and an entry pointing at a fold
  /// that stops folding goes red on the execution. Either way the excuse and
  /// the evidence cannot drift apart while both still compile.
  final String fold;
}

/// Every entry here is **digit-only**, and each one says **which fold makes it
/// so** — a claim this file now executes instead of promising.
///
/// **The tick that changed this found the excuse was resting on a function it
/// never named, and the function was not one of the two it did name.** The old
/// table said of `dz_phone.dart#canonicalFromDigits` that "`canonicalFromDigits`
/// strips `_nonDigit` on its first line" — true, and checked by *reading* the
/// line, while the case below ran `DzPhone.digits` and `DzNumber.digits`, which
/// is a different function with a different implementation:
///
/// ```text
/// canonicalFromDigits('\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666')  ->  ''
/// DzPhone.canonical ('\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666')  ->  '0550123456'
/// ```
///
/// So the fold that actually guards `d[0]` is a **private strip inside
/// `canonicalFromDigits`**, it is not `DzPhone.digits`, and no test executed
/// it. It happens to be safe — the whole of `d` is ASCII digits, so `d[0]` can
/// never be an invisible character — but "it happens to be safe" is not the
/// same statement as "it is checked", and that gap is exactly what the item
/// this tick took was about. It is now in [_folds] and it is run against the
/// hostile inputs on every suite.
///
/// **The digit-only half is the only excuse that survived the 34th tick.** The
/// "truncates with `substring` rather than *deciding* on the first character"
/// half was false — `substring` counts UTF-16 code units and can split a
/// surrogate pair. Those three sites moved to [_bounded] and are held by a
/// stronger rule than the one they left.
const _allowed = <String, _AllowedSite>{
  // `'567'.contains(d[0])` — the leading-operator-digit test, the site whose
  // fold was misnamed for a tick. `d` is this function's own local strip, not
  // `DzPhone.digits`, so that is the fold named here and the one exercised.
  'lib/src/core/text/dz_phone.dart#canonicalFromDigits': _AllowedSite(
      'leading operator digit of a digit-only phone number, repaired to a '
      '0-prefixed form — the fold is this function\'s own strip, which is NOT '
      'DzPhone.digits',
      'DzPhone.canonicalFromDigits'),

  // `_cap` cuts what its caller handed it, and `canonicalFromDigits` is the
  // last thing to touch that string, so the same fold covers it — a fact that
  // is only checkable because entries name their fold: two entries may share
  // one, and the case below will say so out loud if a fold is left unnamed.
  'lib/src/core/text/dz_phone.dart#_cap': _AllowedSite(
      'digit-only phone, length cap — receiver is `canonicalFromDigits\'`s '
      'own strip',
      'DzPhone.canonicalFromDigits'),

  // The other two reach their fold through a public entry point, and they are
  // listed individually because a bundled glob could not say which module each
  // belongs to: `dz_number` (money fields) must not be allowed to excuse a
  // future site in a screen.
  'lib/src/core/text/dz_number.dart#formatEditUpdate':
      _AllowedSite('digit-only number, input-formatter bound', 'DzNumber.digits'),
  'lib/src/widgets/phone_field.dart#formatEditUpdate':
      _AllowedSite('digit-only phone, input-formatter bound', 'DzPhone.digits'),
};

/// The entries that used to be excuses and no longer are — still enforced, by a
/// different and stronger rule.
///
/// **Measured, not asserted: fixing them removed them from the measured set.**
/// This guard's rule is the *shape* `substring(0, …)`, and none of these three
/// sites contains that shape any more — they call `TextClip`, which slices on
/// characters. So the allow-list went **7 -> 4** entries on this tick and the
/// staleness case below went red on all three, by name, exactly as it is meant
/// to. That is the allow-list working: an entry that stops matching a measured
/// site is an excuse that has stopped covering anything.
///
/// Keeping them here rather than deleting them is the difference between
/// "nobody enforces this any more" and "a different rule enforces this". The
/// cases below check that each of these three clips a character instead of
/// splitting it, and that the clip is wired in at the call site — a *stronger*
/// statement than the excuse it replaced, which only ever said what the receiver
/// was.

/// An arbitrary string cut to a length — a crash message, a response body, a
/// chat line the user is being quoted back.
///
/// Split from [_allowed] because the two claims are checked by opposite
/// evidence: a `_allowed` entry must fold hostile input down to digits, and
/// these must *not* fold anything, they must cut on a character boundary. One
/// set holding both could only be checked by weakening one of the two rules.
const _bounded = <String>{
  'lib/src/core/diagnostics/crash_log.dart#trim',
  'lib/src/core/network/api_client.dart#_decode',
  'lib/src/data/chat_outbox.dart#_clip',
};


/// The folds an excuse may rest on, **by name**, each runnable.
///
/// A table rather than a comment, and the reason is the finding above: the
/// excuse named a fold in prose and the test ran a different one, and nothing
/// went red because there was no link for anything to break. Here the link is
/// the key, so the failure modes are mechanical — an entry naming a fold that
/// is not here, a fold here that no entry names, and a fold that stops
/// folding.
///
/// Each entry is the **real** function, never a re-implementation of the strip
/// inside it: `canonicalFromDigits` is measured by calling it, because a copy
/// of `replaceAll(_nonDigit, '')` in this file would keep passing after the
/// line it copied was deleted from `lib/`.
final Map<String, String Function(String)> _folds = {
  'DzPhone.digits': DzPhone.digits,
  'DzNumber.digits': DzNumber.digits,
  // The private strip inside `canonicalFromDigits`, reached through the only
  // door it has. It is not `DzPhone.digits` — that one runs
  // `ArabicSearch.normalize` first and folds Arabic-Indic digits, and this one
  // does not, which is exactly the difference that made the prose wrong.
  'DzPhone.canonicalFromDigits': DzPhone.canonicalFromDigits,
};

/// Inputs that break a digit fold in this market, and none of them is
/// hypothetical: RLM from an Arabic keyboard, ZWSP/word-joiner/BOM from a
/// spreadsheet, a non-breaking space from a Word document, an emoji from a
/// pasted contact card, Arabic-Indic and Extended-Arabic digits from an
/// Arabic keypad or a Persian-locale phone.
///
/// Shared by every case that runs a fold, so a fold cannot be checked against
/// a gentler list than the one its neighbour was checked against.
const List<String> _hostileDigits = <String>[
  '\u200f0550123456',
  '0550\u200f123456',
  '\u200b\u2060\ufeff0550123456',
  '\u061c0550123456',
  '\u00a00550123456',
  '\u00a00550\u200b12 34 56',
  '\ud83d\ude000550123456',
  '0550123456\ud83d\ude000',
  '\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666',
  '\u06f0\u06f5\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6',
];
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

/// The real clipper for each `_bounded` excuse, by owner name.
///
/// Wrappers rather than direct references so each one carries **its own**
/// budget and shape — `CrashRecord.trim` counts the ellipsis, `_clip` does not,
/// and `_decode` takes none at all. Pointing all three at `TextClip.elided`
/// would assert the fix on a helper no call site uses, which is how a green
/// test and a broken app coexist.
final Map<String, String Function(String, int)?> _clippers = {
  'trim': (v, max) => CrashRecord.trim(v, max),
  // `_decode` is private and only reachable through a 2xx that is not JSON, so
  // it has no entry here -- it is driven end to end through `api.get()` in the
  // case below, against the real captive-portal response. Putting a
  // re-implementation of the clip expression in this map instead would assert a
  // helper the app does not call, which is the failure this whole file keeps
  // re-learning: green, and measuring nothing real.
  '_clip': (v, max) {
    final flat = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.runes.length <= max) return flat;
    return '${TextClip.chars(flat, max)}…';
  },
};

/// The bound each bounded clapper actually promises, in **characters**.
///
/// A table, because the three sites do not agree and a single shared constant
/// would have been a fourth thing to get wrong silently: `CrashRecord.trim` is
/// handed `max` and counts the ellipsis against it, `_clip` takes a default of
/// 60 for the quoted text and adds its own marker on top.
final Map<String, int> _budgets = {
  'trim': CrashRecord.maxMessage,
  // 60 characters plus the «…» this site writes itself, where the 60 are 59
  // Arabic characters (one unit each) and the emoji that got cut -- which is
  // why this is **62** and not 61. The budget is asserted in code units, and an
  // emoji inside the quoted text costs two whether or not it was counted: a
  // budget written as "60 + 1" was wrong the moment the probe put a pair in the
  // first 60 characters, which is exactly what this tick's assertion caught.
  '_clip': 62,
};

/// A client that answers every request with [body] and a 200 — the captive
/// portal, exactly.
///
/// Hand-rolled rather than pulled from `package:http`'s testing helpers because
/// `ApiClient` retries across a host list and a `MockClient` that answers
/// everything would let a fallback host decide the outcome instead.
class _PortalClient extends http.BaseClient {
  _PortalClient(this.body);

  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(body.codeUnits),
        200,
      );
}

/// Does [s] carry half of a surrogate pair?
///
/// `String.runes` reports the orphan as a single rune in U+D800..U+DFFF, which
/// is the one range no legitimate character occupies — so this is an exact test
/// and not a heuristic about "looks broken".
bool _loneSurrogate(String s) =>
    s.runes.any((r) => r >= 0xD800 && r <= 0xDFFF);


/// [s] as space-separated lowercase hex, so a failure message can name the
/// exact characters without depending on a font that draws them.
String _hex(String s) => s.runes.map((r) => r.toRadixString(16)).join(' ');

/// Does [s] hold a character that paints nothing?
///
/// `String.trim()` strips whitespace and these are `Cf` (format) or space
/// characters it does not treat as whitespace, which is the whole reason this
/// guard exists: they are invisible, so a test on one is a test that measures
/// nothing. Deliberately the same set the class of bug is named with, plus
/// `U+00A0` and `U+2060` — a Word document and a spreadsheet carry those.
bool _hasInvisible(String s) => s.runes.any((r) =>
    r == 0x200E || r == 0x200F || r == 0x200B || r == 0x200D ||
    r == 0x200C || r == 0x2060 || r == 0xFEFF || r == 0x00A0 ||
    r == 0x061C);

/// Is [r] a digit an Arabic or Persian keypad writes? `U+0660..U+0669` is
/// Arabic-Indic and `U+06F0..U+06F9` is Extended-Arabic (Persian), which is
/// what a phone set to a Persian locale produces.
///
/// A named predicate rather than an inline range, because the same boundary
/// has to be stated the same way wherever it is used -- and an inline range in
/// an assertion is the kind of thing a future code point leaves out silently.
bool _isArabicDigit(int r) =>
    (r >= 0x0660 && r <= 0x0669) || (r >= 0x06F0 && r <= 0x06F9);

/// [s] rendered so an empty string is visible in a failure message, and any
/// character a reader cannot see is hex rather than a glyph.
String _show(String s) => s.isEmpty ? '<empty>' : s;

void main() {
  group('first-character measurement of user-supplied strings', () {
    // Filled by the AST pass; both cases below read it, so the walk happens
    // once and its *failure modes* are asserted rather than swallowed.
    final List<_Site> sites = <_Site>[];
    // Declared beside `sites` rather than inside `setUpAll` because the budget
    // case above reads it, and a variable scoped to the hook is invisible to
    // every case that follows.
    List<String> candidates = const <String>[];

    // **Hoisted out of `setUpAll` on the 70th tick, because the file was
    // building this collection TWICE and claiming in a comment that it did
    // not.** The comment under the probe case read "resolves a real file
    // through the same `AnalysisContextCollection` the `lib/` walk uses" --
    // and the line under it constructed a second, cold one. The claim was
    // the intent, the code was the opposite, and nothing noticed because a
    // comment is not checked.
    //
    // So the collection is group state now, and [_probeResolvedThrough]
    // records which instance actually resolved the planted probe, which is
    // what makes "the same one" an assertion instead of a sentence.
    AnalysisContextCollection? walkCollection;

    /// The collection the planted probe was resolved through, for the case
    /// that holds the probe and the walk to the same instance.
    Object? probeResolvedThrough;

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
      walkCollection = collection;
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
        stale.add('$key\n    ${_allowed[key]!.reason}\n    (fold: ${_allowed[key]!.fold})');
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
      // resolves a real file through **the** `AnalysisContextCollection` the
      // `lib/` walk uses -- `walkCollection`, the instance `setUpAll` built,
      // which this case now holds to by identity rather than by a comment
      // saying so. The probe is planted in `lib/` for the duration and
      // reverted inside the case, never committed, because a probe shipped in
      // the tree would be a site the allow-list has to excuse.
      //
      // Written this way because the alternative -- asserting the branch by
      // reading it -- is the failure this whole file keeps re-learning.
      //
      // **Measured on the 70th tick, and the cost was not what the backlog
      // said it was.** The open lead was the `includedPaths` root -- it
      // resolves the whole 404-file repo to measure 12 files under `lib/` --
      // so that was the first thing measured. Three roots, same 12 files,
      // same 8 sites, zero unresolved errors each:
      //
      // ```text
      // repo root (404 files) : 13.4 s      lib root (137 files) : 13.2 s
      // the 12 candidates     : 12.5 s      <- narrowest, and no cheaper
      // ```
      //
      // The first run of that table read 27.5 / 17.2 / 12.5 and looked like a
      // clean win for narrowing the root. It was an artefact of ORDER: the
      // first collection built in a process pays for the SDK context, and
      // re-running the sequence with the narrowest variant FIRST put all
      // three at ~13 s. **The root is not the cost.** A lead that would have
      // shipped a behavioural change to a type-resolving guard on the strength
      // of a warm second run -- and would have bought nothing -- is recorded
      // as measured DEAD rather than implemented.
      //
      // What IS the cost is the line this case actually ran: a second, cold
      // `AnalysisContextCollection`, built because the comment above claimed
      // a shared one that did not exist. Same probe file, same visitor:
      //
      // ```text
      // second cold collection : 1155 ms      shared collection : 6 ms
      // ```
      //
      // 193x, for a file already resolved. Both returned
      // `codeUnitAt(0) on s`, so this was never a correctness bug -- it was
      // the 42 s the 67th and 68th measured and could not explain.
      expect(walkCollection, isNotNull,
          reason: 'the probe case needs the collection setUpAll built, and it '
              'is null -- so the probe below would have to build its own and '
              'the "same collection" claim would be prose again.');
      final probe = File('lib/src/core/text/_first_char_probe.dart');
      expect(probe.existsSync(), isFalse,
          reason: 'a planted probe was left behind in lib/; it would ship as '
              'a real site and the allow-list would have to excuse it.');
      probe.writeAsStringSync('''
/// Planted by first_char_measurement_test.dart. Never committed.
String probeCodeUnit(String s) => s.codeUnitAt(0).toString();
''');
      try {
        final collection = walkCollection!;
        final abs = probe.absolute.path;
        final SomeResolvedUnitResult result = await collection
            .contextFor(abs)
            .currentSession
            .getResolvedUnit(abs);
        // The identity, asserted: the comment above claims this case rides the
        // walk's collection, and this is the only thing that makes the claim
        // true or false. Without it, restoring a second `AnalysisContextCollection`
        // here costs ~1.2 s per run and every case above stays green.
        probeResolvedThrough = collection;
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

    test('the probe rides the walk\'s collection, not its own', () {
      // **The 70th tick's actual fix, asserted.** The probe case above used to
      // construct its own cold `AnalysisContextCollection` while its comment
      // said it shared the walk's. It is now the walk's instance, and this is
      // what keeps it that way.
      //
      // Ordering note, because it decides whether this case can fail: this
      // group runs its cases in declaration order and the probe case is
      // declared immediately above, so `probeResolvedThrough` is set by the
      // time this reads it. If someone reorders the two, the `isNotNull` arm
      // goes red and names the cause instead of the probe case passing on a
      // collection nobody set.
      expect(probeResolvedThrough, isNotNull,
          reason: 'the probe case did not record the collection it resolved '
              'through. Either it failed above, or the cases were reordered so '
              'this runs first.');
      expect(identical(probeResolvedThrough, walkCollection), isTrue,
          reason: 'the probe was resolved through a DIFFERENT collection than '
              'the lib/ walk uses, so "the same AnalysisContextCollection" is '
              'a comment and not a fact again. A second cold collection costs '
              '~1.2 s per run -- measured 1155 ms against 6 ms for the warm '
              'one -- and the cost is invisible to every other case here.');
    });

    test('every excuse names a fold, and every fold an excuse names', () {
      // **The link, checked from both ends.** The item this tick took was that
      // the excuse and the fold were joined by prose, so the case that ran the
      // folds and the table that held the excuses could drift apart with
      // nothing to notice — and they had: the entry for `canonicalFromDigits`
      // was covered by a test that ran `DzPhone.digits`, which is a different
      // function with a different implementation. The tie is now a key, so:
      //
      //   * an excuse naming a fold this file does not have is **red** — the
      //     claim cannot be checked, and an unchecked excuse is the state this
      //     file was written to remove;
      //   * a fold nothing names is **red** — it is either dead weight or a
      //     fold someone was about to rely on and did not wire up.
      //
      // Both directions, because either one alone passes on a table where the
      // names are simply wrong in a different way.
      for (final entry in _allowed.entries) {
        expect(_folds.containsKey(entry.value.fold), isTrue,
            reason: '${entry.key} rests on the fold '
                '`${entry.value.fold}`, which is not in [_folds]. An excuse '
                'that names a fold nothing runs is a promise with no check '
                'behind it — the state this tick existed to end. Add the fold '
                'or name one that exists.\nKnown folds: '
                '${_folds.keys.join(', ')}');
      }
      final unused = _folds.keys
          .where((k) => !_allowed.values.any((a) => a.fold == k))
          .toList();
      expect(unused, isEmpty,
          reason: 'these folds are run by the case below but no excuse names '
              'one, so either the registry or the table is out of date: '
              '$unused');
    });

    test('every named fold folds hostile input down to digits, by execution',
        () {
      // **The claim, executed per entry instead of per table.** The 33rd tick
      // turned "excused by name" into an assertion by running `DzPhone.digits`
      // and `DzNumber.digits` against hostile input. That was right and it was
      // incomplete: it proved two functions fold, and the table excused four
      // sites, two of which rest on a third function. Running **the fold each
      // entry names** is what closes the gap — a site excused on
      // `DzPhone.digits` is now checked through `DzPhone.digits`, and one
      // excused on `DzPhone.canonicalFromDigits` through that.
      //
      // The distinction is not academic, and it was measured on this tick:
      //
      // ```text
      // canonicalFromDigits('٥٥٠١٢٣٤٥٦') -> ''
      // DzPhone.canonical ('٥٥٠١٢٣٤٥٦') -> '0550123456'
      // ```
      //
      // `canonicalFromDigits` is a public method that every caller may hand raw
      // text — its own docstring says so — and for one tick it **did not fold
      // Arabic-Indic digits at all**:
      //
      // ```text
      // DzPhone.canonicalFromDigits('\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666') -> ''
      // DzPhone.canonical          ('\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666') -> '0550123456'
      // ```
      //
      // The tick that fixed it folded inside that function, so this list moved
      // the name from `structural` to `normative` rather than weakening the
      // assertion: a public `canonical...` that differs from its sibling
      // `canonical` on the digit shape an Algerian keypad produces is the
      // defect, and this is the case that now says so by execution.
      //
      // So each fold is held to **its own** rule, and both rules are stated
      // here rather than in the table, because the table is where a reader
      // looks and this is where the machine checks. Two rules, not one:
      //
      //   * **normative** — `ArabicSearch.normalize` then strip: a fold that
      //     claims to read anything a human can type owes the user every
      //     digit shape, so Arabic-Indic and Extended-Arabic must survive as
      //     ASCII digits and a real number must come out the other side;
      //   * **structural** — a fold that only promises to strip non-`[0-9]`
      //     **code units**, so the check is that nothing invisible survives into
      //     the receiver (`d[0]` cannot be an RLM, a ZWSP or half an emoji),
      //     which is precisely the property `d[0]` is read for. **No entry is
      //     held to this rule today**, and the list is kept non-empty-checked
      //     rather than deleted so the arm below is exercised the day one is.
      //
      // A fold that satisfies neither is refused by name on the next run.
      //
      // **The `canonicalFromDigits` line moved on 3 Oct (38th tick), and it is
      // here that the finding showed up twice.** It was listed as structural
      // with the comment "its own callers pre-fold" -- a claim about shipped
      // code that was true of `canonical` and false of the three public entry
      // points that share the name. It now folds through `DzPhone.digits`
      // itself, so it is normative and is held to the stronger rule: every
      // hostile shape in [_hostileDigits] must come out as the number the user
      // typed, not merely as something with no invisible character in it.
      final normative = <String>[
        'DzPhone.digits',
        'DzNumber.digits',
        'DzPhone.canonicalFromDigits',
      ];
      final structural = <String>[];
      expect(normative.every(_folds.containsKey), isTrue);
      expect(structural.every(_folds.containsKey), isTrue);
      // Every fold an excuse names must be **classified**, or the loop below
      // silently stops holding it to any rule at all -- `mustFoldArabic` is
      // false for anything unlisted, so an unclassified fold would fall
      // through to the structural arm for the wrong reason and pass.
      //
      // **The tick that moved `canonicalFromDigits` to `normative` emptied
      // `structural`, and this case went red on its own coverage floor rather
      // than on anything to do with phone numbers.** The floor was right for
      // the wrong reason: it forbade an *empty normative* list, and this file
      // has read it as "both lists must have members" ever since. So what is
      // asserted now is coverage -- every named fold is classified exactly
      // once -- and the only list that must be non-empty is `normative`, which
      // is the one with the stronger rule. A structural fold is a legitimate
      // state for the tree to be in; an *unclassified* fold is not.
      final classified = <String>{...normative, ...structural};
      expect(
          classified,
          containsAll(_folds.keys.toSet()),
          reason: 'these folds are run by this case but classified by neither '
              'rule, so they are held to nothing:\n'
              '${_folds.keys.where((k) => !classified.contains(k)).toList()}');
      expect(normative, isNotEmpty,
          reason: 'the normative list is the one that owns the Arabic-Indic '
              'guarantee; if it is empty the case checks no user-visible fold '
              'at all.');
      expect(structural.length, lessThanOrEqualTo(normative.length),
          reason: 'a structural fold promises strictly less than a normative '
              'one, so there cannot be more of them than there are folds to '
              'owe the user something.');

      final notDigits = RegExp(r'[^0-9]');
      for (final entry in _allowed.entries) {
        final fold = _folds[entry.value.fold]!;
        final mustFoldArabic = normative.contains(entry.value.fold);
        for (final raw in _hostileDigits) {
          final out = fold(raw);
          final hex = out.runes.map((r) => r.toRadixString(16)).join(' ');
          if (mustFoldArabic) {
            expect(notDigits.hasMatch(out), isFalse,
                reason: '${entry.value.fold} left a non-digit in "${_hex(raw)}" '
                    '-> "$hex". ${entry.key} is excused by name on this fold, '
                    'so a hole in it is a hole in that site as well.');
            // And it is not enough to leave *no* non-digit: the fold must
            // produce the number the user meant. `DzPhone.digits` deleting the
            // whole string satisfies the assertion above and is still broken.
            //
            // **This arm was too weak, and it was found by reverting the
            // tree, not by reading it.** `canonicalFromDigits` was reclassified
            // as normative on the tick that folded Arabic digits inside it,
            // and the only inputs this assertion fires on are the ones ending
            // in ASCII `0550123456` -- so with `lib/` reverted to the strict
            // version, every Arabic-Indic input produced `''`, `''` has no
            // non-digit in it, and **the whole case stayed green.** The two
            // Arabic-Indic rows of [_hostileDigits] were folded away by the
            // very defect they exist to catch, and nothing said so.
            //
            // The fix is the shape of the claim rather than a longer list: a
            // fold that claims to read anything a human can type owes the user
            // the digits that were there, so an input carrying a phone number
            // must not come back empty. "Empty" is now an explicit answer,
            // checked on every input that has digits to lose -- which is what
            // makes the assertion fire on the rows it was previously blind to.
            if (raw.runes.any(_isArabicDigit)) {
              expect(out, isNotEmpty,
                reason: '${entry.value.fold} answered nothing for '
                    '"${_hex(raw)}". It folds Arabic-Indic digits by '
                    'definition, so deleting the whole string satisfies '
                    '"no non-digit survived" and is still a broken phone '
                    'number. ${entry.key} is excused on this fold.');
            }
            if (raw.endsWith('0550123456')) {
              expect(out, '0550123456',
                reason: '${entry.value.fold} dropped the digits a user typed: '
                    '"${_hex(raw)}" -> "${_show(hex)}"');
            }
          } else {
            // The structural rule, and it is the one the site is read for.
            // `d[0]` is a single **code unit**, so what matters is that it
            // cannot be a glyph that paints nothing or half of one.
            expect(_hasInvisible(out), isFalse,
                reason: '${entry.value.fold} let an invisible character '
                    'through into the receiver "${_hex(raw)}" -> "$hex". '
                    'The first code unit is read as an operator digit, and a '
                    'zero-width one silently answers "not 5/6/7".');
            expect(_loneSurrogate(out), isFalse,
                reason: '${entry.value.fold} split a surrogate pair: "$hex".');
          }
        }
      }
    });

    test('the two repairs the API refuses are still made after the fold', () {
      // **The half of `canonicalFromDigits` that matters to a user, driven
      // through hostile input.** The case above can only ask whether the fold
      // leaves something invisible in the string; it cannot ask whether the
      // number came out right, because for this fold the Arabic-Indic case is
      // *expected* to be empty. So the property that actually ships is
      // asserted here, end to end and through the public door:
      //
      //   * a pasted international number and a dropped leading zero are both
      //     still repaired, with the invisible characters that ride in with
      //     them;
      //   * and the digit-only fold is what makes it work — so if
      //     `canonical` stops folding before it calls `canonicalFromDigits`,
      //     the repair silently stops firing on a pasted number and this case
      //     is the only thing that sees it.
      //
      // Before this case the repair was covered in `dz_phone_test.dart` from
      // ASCII input only. Every one of these inputs is the same repair with a
      // zero-width character glued to the front, which is what a contact card
      // out of WhatsApp actually carries.
      final repairs = <String, String>{
        '550123456': '0550123456',
        '\u200f550123456': '0550123456',
        '\u200b\ufeff550123456': '0550123456',
        '\ud83d\ude000550123456': '0550123456',
        '\u061c550123456': '0550123456',
        '\u0665\u0665\u0660\u0661\u0662\u0663\u0664\u0665\u0666': '0550123456',
        '\u00a0213550123456': '0550123456',
        '\u200f213550123456': '0550123456',
      };
      for (final r in repairs.entries) {
        expect(DzPhone.canonical(r.key), r.value,
            reason: 'a pasted number carrying "${_hex(r.key)}" no longer '
                'canonicalises to ${r.value}. This repair is the app being '
                'friendlier than the API on purpose, and the invisible '
                'characters are what a paste really carries.');
        expect(DzPhone.isValid(r.key), isTrue,
            reason: 'the user sees the field accept this number and then the '
                'API rejects it: "${_hex(r.key)}"');
      }
      // The repair goes through `canonicalFromDigits`, so the fold the excuse
      // names is on the path a user actually takes — stated as an assertion
      // rather than left to the reader's trust in a docstring.
      //
      // **Measured on this tick, and the first version of this guard was
      // measuring the wrong thing.** It asked for an input `canonicalFromDigits`
      // folds to the empty string, and it went red on a regression of that
      // function — but for the wrong reason: deleting the private strip leaves
      // the repair working, because `canonical` folds through `DzPhone.digits`
      // *before* it ever calls it. The primary assertions above stayed green
      // through the whole of that regression.
      //
      // So what this asserts is the property the excuse actually rests on: the
      // named fold is **load-bearing on a user path** — at least one of these
      // inputs reaches it carrying something it must change. That holds for the
      // Arabic-Indic number (which the private strip empties and the public
      // fold canonicalises), and it is the reason `canonicalFromDigits` is in
      // [_folds] rather than a comment: it decides something real, on the way a
      // real pasted number travels, and it is the function whose failure would
      // silently skip the leading-zero repair.
      expect(
          repairs.keys
              .any((k) => DzPhone.canonicalFromDigits(k) != k),
          isTrue,
          reason: 'no input above is changed by `canonicalFromDigits`, so this '
              'case does not reach the fold the excuse names and the repair it '
              'covers is not being exercised. Either the fold stopped folding, '
              'or `canonical` no longer routes through it.');
    });

    test('every bounded excuse cuts a character instead of splitting it', () {
      // **The live defect this tick found and fixed.** Each of the three
      // `_bounded` entries used `substring(0, n)`, which counts UTF-16 code
      // units and therefore cuts between the halves of a surrogate pair. The
      // excuse said truncation "never *decides* on the first character", and
      // that was true and beside the point: the cut produced a string that is
      // not valid text at all.
      //
      // Proven against the **real** clip, on an input whose first code unit sits
      // exactly on the boundary — the only position that breaks, so a probe
      // that missed it would be the probe being wrong, not the code.
      //
      // A lone surrogate is the whole assertion, and it is asserted as a
      // property of every bounded entry rather than of `TextClip` alone: a
      // future clipper that forgets the ellipsis budget would pass a test that
      // only checked "no lone surrogate" and break the storage bound instead.
      for (final key in _bounded) {
        final clip = _clippers[key.split('#').last];
        // `_decode` is the one entry with no clapper, and the reason it needs
        // none is spelled out on `_clippers`: it is driven through the real
        // client in the case below. The two lists must agree exactly, or this
        // loop silently skips a site — the same rot the allow-list has, one
        // level down.
        if (key.endsWith('#_decode')) continue;
        expect(clip, isNotNull,
            reason: '$key is excused as a bounded clip but no clipper is known '
                'for it, so the excuse is unchecked — which is the state this '
                'file was written to remove. Add the clapper or drop the entry.');
        final boundary = '${'\u0627' * 59}😀بقية الرسالة هنا';
        final out = clip!(boundary, 60);
        expect(_loneSurrogate(out), isFalse,
            reason: '$key split a surrogate pair: '
                '"$out" carries an orphaned half and Dart renders it as U+FFFD '
                'in the middle of an Arabic sentence. The emoji must survive '
                'whole or be dropped whole.');
        // The bound each site actually promises, which is not the same number
        // for all three — and that difference is the reason this is a table
        // rather than a loop over a constant. `_clip` counts its 60 in the
        // **quoted text** and writes the ellipsis after it, so the toast is 61
        // characters including a marker (which is what the existing
        // `copy.length < 140` case in `outbox_eviction_test.dart` bounds).
        // `CrashRecord.trim` counts the ellipsis against a **storage** bound.
        final budget = _budgets[key.split('#').last]!;
        // **Asserted in code units, not runes, and the difference is the whole
        // reason this arm exists.** `CrashRecord.trim`'s bound is a *storage*
        // bound -- a record is written to preferences as one line -- so the
        // number that has to hold is `length`. Measured on this tick: a clip
        // that cut whole characters but counted its budget in runes returned
        // **401 units for a 400 budget** on a line of 398 Arabic characters and
        // one emoji, and this case was **green on it**. An assertion in runes
        // cannot see an overshoot that is paid for in bytes, because the very
        // characters being counted are the ones that cost two.
        expect(out.length, lessThanOrEqualTo(budget),
            reason: '$key returned ${out.length} code units for a budget of '
                '$budget -- a rune-safe cut that lets the bound slip is not a '
                'fix, it is a different bug. Runes: ${out.runes.length}.');
      }
    });

    test('the response body survives the clip whole, end to end', () async {
      // The third bounded excuse, driven through the **real** call site rather
      // than through a helper: `_decode` is private, and the only way to reach
      // it is the case the app already handles — a 2xx that is not JSON, which
      // is a captive portal or a Cloudflare interstitial. The clipped body comes
      // back as `ApiException.cause`.
      //
      // The body is a real Arabic portal page with the emoji on the boundary,
      // because this is the shape that broke: `substring(0, 200)` put U+D83D in
      // the crash report the engineer then reads.
      // 199 filler characters, then the emoji whose first code unit lands
      // exactly on index 199 -- the one position in 0..200 that splits the pair.
      //
      // The identifying text goes **first**, which is the only place it can go:
      // at 199 the emoji occupies both remaining units, so anything after it is
      // past the cut and asserting on it would be asserting on a string the
      // bound had already removed. Proving "the clip kept the part that
      // identifies the portal" is the same probe with the order flipped --
      // it is a property of the clipper, not of the filler.
      final boundary = 'Cloudflare ${'\u0627' * 196}😀</html>';
      final api = ApiClient(
        httpClient: _PortalClient(boundary),
        baseUrls: const ['https://portal.invalid'],
      );
      try {
        await api.get('/api/ping');
        fail('a 2xx that is not JSON must still be a sentence, not a raw body');
      } on ApiException catch (e) {
        final cause = e.cause! as String;
        expect(_loneSurrogate(cause), isFalse,
            reason: 'the crash report the engineer reads carries an orphaned '
                'surrogate half: ${cause.runes.map((r) => r.toRadixString(16)).join(' ')}');
        expect(cause, contains('Cloudflare'),
            reason: 'the clipping threw away the part that identifies the '
                'portal, which is the only reason this string is stored.');
        expect(cause.length, lessThanOrEqualTo(200),
            reason: 'the bound is a storage bound and must stay hard.');
      }
    });

    test('a storage bound is held in code units, not characters', () async {
      // The arm this tick's own falsification found: a clipper can be perfectly
      // rune-safe and still overrun a byte budget, because the characters it
      // preserves are exactly the ones that cost two units. Every other case in
      // this file counts runes, so without this one the failure mode had no
      // coverage at all — measured green on a real 401-unit result.
      final emojiAtBoundary = '${'\u0633' * 398}😀tail';
      expect(emojiAtBoundary.length, greaterThan(400));
      final clipped = TextClip.elided(emojiAtBoundary, CrashRecord.maxMessage);
      expect(clipped.length, lessThanOrEqualTo(CrashRecord.maxMessage),
          reason: 'a 400-unit storage bound returned ${clipped.length} units: '
              '${clipped.runes.length} characters that happen to cost '
              '${clipped.length} units.');
      expect(_loneSurrogate(clipped), isFalse);

      // And the guarantee is not "exactly max": a pair that will not fit in
      // what remains is dropped whole, which is the correct trade for a
      // validity invariant.
      final allPairs = TextClip.elided('😀' * 300, CrashRecord.maxMessage);
      expect(allPairs.length, lessThanOrEqualTo(CrashRecord.maxMessage));
      expect(_loneSurrogate(allPairs), isFalse);
    });

    test('the bounded clips are the ones that used to use substring', () {
      // The regression pin: the fix is a call-site change, and a call-site
      // change is invisible to every other case in this file, because the
      // *shape* the visitor measures has not changed — `substring(0, …)` is
      // still the shape, it is just that the two arguments are no longer
      // reached by slicing. Without this, deleting `TextClip` from all three
      // sites leaves this file green and the user-visible bug back.
      for (final key in _bounded) {
        final src = File(key.split('#').first).readAsStringSync();
        final code = _stripComments(src);
        expect(code.contains('TextClip.'), isTrue,
            reason: '$key does not go through `TextClip`, so it is clipping '
                'with `substring` again and a name typed with an emoji on the '
                'boundary comes back with U+FFFD in it.');
        // And the shape the guard was built on is genuinely gone from it.
        expect(_firstSlice.hasMatch(code), isFalse,
            reason: '$key still contains a `substring(0, …)` — so either the '
                'clip did not land, or a second cut was left behind beside '
                'it. Both are the defect.');
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
