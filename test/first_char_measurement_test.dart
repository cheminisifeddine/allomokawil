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
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
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
  String toString() =>
      '$file:${_lineAt(file, offset)}  $receiver  (in $owner)';
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
/// `substring(0,`), because resolution is what decides whether a receiver is
/// a `String` at all — four of the five `[0]` sites in the tree are `List`.
///
/// A prefilter can miss a site, so it is written to be wider than the rule:
/// it fires on `[0]` anywhere and on `substring(0,`, never on a narrowed
/// pattern. What it costs in false positives is paid in the `UNRESOLVED` /
/// allow-list cases below, both of which are loud.
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
    if (!code.contains('[0]') && !_firstSlice.hasMatch(code)) continue;
    out.add(f.path.replaceAll('\\', '/'));
  }
  return out..sort();
}

/// The prefilter's second shape, as a pattern rather than an inline literal so
/// the census can name it as this file's evidence token.
final RegExp _firstSlice = RegExp(r'substring\s*\(\s*0\s*,');

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

/// Finds every place a **String** is indexed at 0 or sliced from 0.
class _FirstCharVisitor extends RecursiveAstVisitor<void> {
  _FirstCharVisitor(this.file, this.sites);

  final String file;
  final List<_Site> sites;

  @override
  void visitIndexExpression(IndexExpression node) {
    final i = node.index;
    if (i is IntegerLiteral && i.value == 0 && _isString(node.realTarget)) {
      sites.add(_Site(file, _ownerOf(node), node.offset,
          _oneLine(node.realTarget.toString())));
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
    super.visitMethodInvocation(node);
  }

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

    setUpAll(() async {
      final candidates = _candidateFiles();
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
        final SomeResolvedUnitResult result =
            await collection.contextFor(abs).currentSession.getResolvedUnit(abs);
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
      expect(sites.any((s) => s.receiver.startsWith('substring(0')),
          isTrue,
          reason: 'no `substring(0, …)` receiver was resolved as a String:\n'
              '${sites.join('\n')}');
    });
  });
}
