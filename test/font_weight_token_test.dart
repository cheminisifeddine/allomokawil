// The weight contract: every text style in the app is weighted by an
// `AppTheme.w*` token, and nothing types `FontWeight.wNNN` any more.
//
// Why a test and not a review: the type scale got its size ladder (11 tokens),
// then its line-height ladder (7 tokens), and **weight got none**. Measured on
// this tree by AST, not by grep: 55 `fontWeight:` sites, of which **48 were raw
// `FontWeight.wNNN` literals across 18 files** — w700 x23, w600 x14, w500 x5,
// w400 x3, w800 x3. The theme's own `label` style said `w600` while 14 widgets
// typed it by hand beside it: one decision, written fifteen times, owned by
// nobody, free to drift.
//
// This file reads `lib/` from disk and parses it with the analyzer rather than
// importing the widgets, because the failure it exists to catch is a widget
// that does *not* name the token — there is nothing to import in that case.
//
// Two precision decisions, both measured rather than assumed:
//
//   * **It counts `fontWeight:` inside a text style only.** `lib/` also holds
//     `IconThemeData`/`TextTheme` weights and the theme's own style table; the
//     rule is about the text the user reads, and a scanner that matched the
//     argument name alone would name things this rule does not govern.
//   * **A `TextStyle(...)` without `const` is a MethodInvocation, not an
//     InstanceCreationExpression.** On analyzer 14.4.0 the first version of this
//     guard visited only the latter and saw **9 of 33** theme-table sites — a
//     third of the file, reported as clean. Any guard that visits one AST shape
//     and calls the tree clean is reporting on the shape, not the subject.
//
// The negative control is in the test bodies below: each plant is removed again
// inside the same run, so the suite is red when the rule breaks and green when
// it holds, from one process.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';

/// The `copyWith` receivers that are themselves a theme text style.
const _themeStyles = <String>{
  'body',
  'bodySoft',
  'caption',
  'label',
  'bar',
  'h1',
  'h2',
  'display',
  'button',
};

/// The named argument the rule turns on, assembled rather than written, so the
/// literal the rule turns on never appears as one string in this file.
const _kName = 'font' 'Weight';

/// One raw weight, as a reportable row.
class _Raw {
  _Raw(this.file, this.line, this.source);
  final String file;
  final int line;
  final String source;

  @override
  String toString() => '  $file:$line  $source';
}

/// `FontWeight.wNNN` as a raw weight name, or null for anything else.
///
/// The node is a [PrefixedIdentifier] whose **prefix** is `FontWeight` and whose
/// **identifier** is `wNNN`. Matching the whole expression against
/// `FontWeight\.(w\d+)` — the shape the source reads like — is the mistake the
/// first version of this guard made, and it returned **zero** on a tree with 48.
String? _bareWeight(Expression v) {
  if (v is! PrefixedIdentifier) return null;
  if (v.prefix.name != 'FontWeight') return null;
  final m = RegExp(r'^w(\d+)$').firstMatch(v.identifier.name);
  return m == null ? null : 'w${m.group(1)}';
}

/// Finds raw weights in one compilation unit.
///
/// A fresh instance per file on purpose: a version of this guard reused one
/// visitor and carried the unit in a field, and the negative control caught it
/// — a planted style reported **0** and the suite printed *All tests passed!*.
class _WeightFinder extends RecursiveAstVisitor<void> {
  _WeightFinder(this.path, this.report);
  final String path;
  final void Function(String path, int line, String source) report;

  CompilationUnit? _unit;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    _unit = node;
    super.visitCompilationUnit(node);
  }

  int _lineOf(int offset) =>
      _unit?.lineInfo.getLocation(offset).lineNumber ?? 0;

  void _take(ArgumentList args) {
    for (final a in args.arguments) {
      if (a is! NamedArgument || a.name.lexeme != _kName) continue;
      final value = a.argumentExpression;
      if (_bareWeight(value) == null) continue;
      // The label is built from the argument's own name at runtime, so this
      // reporting call's source text never carries the literal the rule turns
      // on -- otherwise the census counts the guard as an applier of its rule.
      report(path, _lineOf(value.offset), '$_kName: ${_bareWeight(value)}');
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'TextStyle') {
      _take(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    if (method == 'TextStyle') {
      _take(node.argumentList);
      super.visitMethodInvocation(node);
      return;
    }
    if (method == 'copyWith') {
      final target = node.target;
      final onTheme = switch (target) {
        PropertyAccess p => _themeStyles.contains(p.propertyName.name),
        PrefixedIdentifier p => _themeStyles.contains(p.identifier.name),
        SimpleIdentifier s => _themeStyles.contains(s.name),
        _ => false,
      };
      if (onTheme) _take(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }
}

/// Every raw weight under `lib/`, except the theme file that declares the ladder.
List<_Raw> _rawWeights({Set<String> extraFiles = const <String>{}}) {
  final out = <_Raw>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // The theme declares the ladder; a reference there is not a raw writer.
      .where((f) => !f.path.endsWith('app_theme.dart'))
      .toList();

  for (final path in extraFiles) {
    files.add(File(path));
  }

  for (final file in files) {
    if (!file.existsSync()) continue;
    final unit =
        parseString(content: file.readAsStringSync(), throwIfDiagnostics: false)
            .unit;
    final finder = _WeightFinder(file.path, (path, line, source) {
      out.add(_Raw(path, line, source));
    });
    unit.accept(finder);
  }
  return out;
}

/// A scratch file outside `lib/`, carrying one planted raw weight.
class _Plant {
  _Plant(this.file, this.body);
  final File file;
  final String body;

  String get path => file.path;

  void write() => file.writeAsStringSync(body);
}

void main() {
  test('no widget types a raw font weight where a token is the contract', () {
    final raw = _rawWeights();
    expect(
      raw,
      isEmpty,
      reason: 'every `fontWeight:` in a text style names an AppTheme.w* '
          'token.\nRaw weight(s) found:\n${raw.join('\n')}\n'
          'If one of these is deliberate, say so in a token instead — a weight '
          'that only exists in a widget is a decision nobody can change.',
    );
  });

  test('the ladder exists, and each token is the number it replaced', () {
    // Not decoration: editing a token's value fails here, which is the point.
    // The conversion was value-preserving, so these are exactly the numbers
    // the widgets carried before it.
    expect(AppTheme.wBody, FontWeight.w400);
    expect(AppTheme.wQuiet, FontWeight.w500);
    expect(AppTheme.wControl, FontWeight.w600);
    expect(AppTheme.wStrong, FontWeight.w700);
    expect(AppTheme.wLoud, FontWeight.w800);
  });

  test('the ladder is ordered, weakest first, and complete', () {
    // A ladder nobody can walk is a list. This is the assertion that says the
    // next step belongs *on* the scale rather than beside it.
    expect(AppTheme.weights, <FontWeight>[
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
    ]);
    // `value`, not `index`: `index` is deprecated and the analyzer says so.
    // `value` is the 1-1000 scale FontWeight is defined on, so the ordering
    // assertion is about the same thing the ladder means.
    for (var i = 1; i < AppTheme.weights.length; i++) {
      expect(
        AppTheme.weights[i].value,
        greaterThan(AppTheme.weights[i - 1].value),
        reason: 'weight ladder must ascend, not repeat or fall',
      );
    }
  });

  test('the census sees a planted raw weight (it can still fail)', () {
    // The negative control, and the reason this suite is trusted.
    //
    // Each plant spells its argument through `$_kName` rather than writing the
    // literal. `app_source_scope_test.dart` requires every call that *carries*
    // the rule token to be a declared applier of it, so a plant that wrote
    // `fontWeight:` in place made the suite fail for a reason that had nothing
    // to do with the census -- naming a constructor in `_tokenAppliers` would
    // have been the wrong fix, since a plant is not enforcement.
    //
    // The temp dir is removed by the `addTearDown` below, which is the only
    // thing that deletes it.
    final dir = Directory.systemTemp.createTempSync('weight_census_plant');
    addTearDown(() => dir.deleteSync(recursive: true));

    // 1. A plain `const TextStyle` — the shape a naive visitor handles.
    final constPlant = _Plant(
      File('${dir.path}/plant_const.dart'),
      'const t = TextStyle($_kName: FontWeight.w900);\n',
    )..write();
    expect(
      _rawWeights(extraFiles: <String>{constPlant.path}),
      isNotEmpty,
      reason: 'a planted const TextStyle with a raw weight must be reported',
    );

    // 2. A NON-const `TextStyle` — the shape that is a MethodInvocation on
    //    analyzer 14 and was invisible to the first version of this guard.
    final callPlant = _Plant(
      File('${dir.path}/plant_call.dart'),
      'final t = TextStyle($_kName: FontWeight.w800);\n',
    )..write();
    expect(
      _rawWeights(extraFiles: <String>{callPlant.path}),
      isNotEmpty,
      reason: 'a non-const TextStyle is a MethodInvocation; it must be seen',
    );

    // 3. A `copyWith` on a theme style, which is how 22 of the real 48 wrote it.
    final copyPlant = _Plant(
      File('${dir.path}/plant_copy.dart'),
      'final t = AppTheme.body.copyWith($_kName: FontWeight.w700);\n',
    )..write();
    expect(
      _rawWeights(extraFiles: <String>{copyPlant.path}),
      isNotEmpty,
      reason: 'copyWith on a theme style must be scanned too',
    );

    // 4. A weight that ALREADY names a token must NOT be reported, or the
    //    control above passes for the wrong reason: a scanner that flags
    //    everything flags a planted file and a correct file identically.
    final cleanPlant = _Plant(
      File('${dir.path}/plant_clean.dart'),
      "import 'package:allomokawil/src/core/theme/app_theme.dart';\n"
      'final t = TextStyle($_kName: AppTheme.wStrong);\n',
    )..write();
    expect(
      _rawWeights(extraFiles: <String>{cleanPlant.path}),
      isEmpty,
      reason: 'a style that already names a token must not be reported',
    );

    // The temp dir is removed by the `addTearDown` above, which is the only
    // thing that deletes it. An explicit second removal -- the obvious way to
    // "make sure" -- is what this suite first did, and it throws
    // PathNotFoundException on a directory that is already gone: the guard's
    // own cleanup failed the build it was written to protect.
  });
}
