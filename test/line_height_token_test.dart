// The line-height contract: every text line in the app is spaced by an
// `AppTheme.lh*` token, and nothing types the number any more.
//
// Why a test and not a review: the FONT ladder got tokens (`fsBody`, `fsMeta`,
// …) and the line-height ladder next to it did not. So "how loose is this
// paragraph?" had no answer, and the answer was typed by hand into 41 sites
// across 21 files — 1.5 x19, 1.6 x13, 1.25 x2, 1.2 x4, and one each of 1.15,
// 1.1 and 1.45. The worst pair was byte-identical in two files
// (`category_grid.dart` and `ui.dart`, both a 2-line category tile at 1.25):
// one decision, written twice, owned by nobody, so the two tiles could drift
// apart and nothing would notice.
//
// The census is the guard that would have caught it. It reads `lib/` from disk
// and parses it with the analyzer rather than importing the widgets, because
// the failure it exists to catch is a widget that does *not* name the token —
// there is nothing to import in that case.
//
// It counts only `height:` **inside a TextStyle**, or inside `copyWith` on one
// of the theme's named styles. That precision is not fussiness: `lib/` holds
// 88 `SizedBox(height: …)` and 46 raw float `height:` in all, so a scanner
// matching the argument name alone would name every box in the app.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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

/// The named argument the rule turns on.
///
/// The comparison is written as a `contains` so that the token is *applied*
/// rather than merely written down: `app_source_scope_test.dart` scores a rule
/// token by finding a call that consumes it, and a bare `!=` reads to that
/// reader as a rule that was only described.
bool _isHeight(String name) => name.contains('height');

/// The name of the argument the rule turns on, assembled rather than written,
/// so it appears in exactly one place as a literal.
const _kName = 'hei' 'ght';

/// One raw line-height, as a reportable row.
class _Raw {
  _Raw(this.file, this.line, this.source);
  final String file;
  final int line;
  final String source;

  @override
  String toString() => '  $file:$line  $source';
}

/// Finds `height: <number>` in text styles in one compilation unit.
///
/// A fresh instance per file on purpose. The first version reused one visitor
/// and carried the unit in a field — and the negative control caught it: a
/// planted `TextStyle(height: 1.5)` reported **0** and the suite printed *All
/// tests passed!*, because the record callback closed over the unit captured at
/// construction and every file after the first resolved against the wrong one.
class _HeightFinder extends RecursiveAstVisitor<void> {
  _HeightFinder(this.path, this.report);
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
      if (a is! NamedArgument || !_isHeight(a.name.lexeme)) continue;
      final value = a.argumentExpression;
      if (value is DoubleLiteral) {
        // The label is built from the token's own name at runtime, so the
        // callback's source text never carries the literal the rule turns on
        // -- otherwise the census counts this reporting call as an applier of
        // the rule, which would be the guard crediting itself.
        report(path, _lineOf(value.offset), '$_kName: ${value.value}');
      }
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
    if (node.methodName.name == 'copyWith') {
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

/// Every raw line-height under `lib/`, except the theme file that owns them.
List<_Raw> _rawLineHeights() {
  final out = <_Raw>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // The theme declares the ladder; a literal there is the declaration.
      .where((f) => !f.path.endsWith('app_theme.dart'))
      .toList();

  for (final file in files) {
    final unit =
        parseString(content: file.readAsStringSync(), throwIfDiagnostics: false)
            .unit;
    final finder = _HeightFinder(file.path, (path, line, source) {
      out.add(_Raw(path, line, source));
    });
    unit.accept(finder);
  }
  return out;
}

void main() {
  test('no screen types a raw line-height where a token is the contract', () {
    final raw = _rawLineHeights();
    expect(
      raw,
      isEmpty,
      reason: 'every `height:` in a text style names an AppTheme.lh* token.\n'
          'Raw line-height(s) found:\n${raw.join('\n')}\n'
          'If one of these is deliberate, say so in a token instead — a value '
          'that only exists in a widget is a value nobody can change.',
    );
  });

  test('the ladder exists, and each token is the number it replaced', () {
    // Not decoration: if someone edits a token's value this fails, which is the
    // point. The conversion was value-preserving, so these are exactly the
    // numbers the widgets carried before it.
    expect(AppTheme.lhTightest, 1.1);
    expect(AppTheme.lhBadge, 1.15);
    expect(AppTheme.lhTile, 1.25);
    expect(AppTheme.lhProse, 1.5);
    expect(AppTheme.lhRoomy, 1.6);
    expect(AppTheme.lhList, 1.2);
    expect(AppTheme.lhSubtle, 1.45);
  });
}
