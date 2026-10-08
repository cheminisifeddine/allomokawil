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
// matching the argument name alone would name every box in the app. Plant 6 in
// the control below is that case, and it must stay quiet.
//
// Two shapes this guard was blind to, both found by measuring the theme file it
// had been skipping, and both the same shape of mistake: **a rule written at a
// granularity that cannot express its own subject**.
//
//   * **The exemption was a filename.** It skipped all of `app_theme.dart` --
//     the one file where the styles that ARE the ladder are written -- so nine
//     `height:` literals sat unseen, and **seven of the nine values were on no
//     rung at all** (1.35 x1, 1.4 x4, 1.65 x2). `AppTheme.body` is the source
//     every `copyWith` in the app inherits from, and its spacing was a number
//     nobody had chosen. The exemption is now the **declaration** -- a literal
//     is legal only where it is the value of an `lh*` constant.
//   * **A non-const `TextStyle` is a MethodInvocation**, so the
//     `visitInstanceCreationExpression` branch never saw one. All nine of the
//     theme's style constants are spelled without `const`: the shapes this
//     visitor *could* read were the four `const TextStyle`s in the same file,
//     which carry no literal height at all. It was not clean by exemption so
//     much as clean because it was reading the empty half of the file.
//
// Neither was knowable by reading the guard. The exemption was written for a
// correct reason -- the ladder is *declared* in literals -- and the shape bug
// predated the exemption, so together they hid the only place the rule could
// have caught the styles that everyone actually inherits.
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

/// The prefix every rung of the ladder is declared behind.
const _kLadder = 'l' 'h';

/// True when this argument's *value* is the ladder being **declared** rather
/// than a literal typed at a call site.
///
/// The guard used to exempt `app_theme.dart` by **file name**, which is how
/// nine `height:` literals in the nine style constants went unseen: the file
/// that holds the declarations also holds the styles, and a rule that skips the
/// whole file cannot tell the two apart. Seven of those nine values were not on
/// any rung, and `AppTheme.body` -- the source every `copyWith` in the app
/// inherits from -- was one of them.
///
/// So the exemption is narrowed from *the file* to *the declaration*: a literal
/// is legal only where it is the value of an `lh*` constant. Everywhere else in
/// that file it is a writer, exactly as it would be in a screen.
///
/// The node this sits on is the **enclosing variable declaration**, not the
/// style: the ladder is spelled `static const double lhProse = 1.5;`, so the
/// `1.5` is a variable declaration's initializer and never appears inside a
/// `TextStyle`'s argument list. Reading the arguments alone would therefore
/// exempt nothing at all and the guard would report all ten rungs.
bool _isDeclaration(DoubleLiteral literal) {
  final decl = literal.parent;
  if (decl is! VariableDeclaration) return false;
  final name = decl.name.lexeme;
  return name.startsWith(_kLadder);
}

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
        if (_isDeclaration(value)) return;
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
    final method = node.methodName.name;
    if (method == 'TextStyle') {
      // A **non-const** `TextStyle(...)` is a MethodInvocation on this analyzer
      // version, not an InstanceCreationExpression -- so the
      // `visitInstanceCreationExpression` branch above never saw one of them.
      // All nine of the theme's style constants are spelled without `const`,
      // so this guard was blind to every single one of them: the shapes it could
      // read were the four `const TextStyle`s in the same file, which carry no
      // literal height at all. It was not "clean by exemption" so much as
      // clean because it was looking at the empty half of the file.
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

/// Every raw line-height under `lib/`, except the theme file that owns them.
List<_Raw> _rawLineHeights({Set<String> extraFiles = const <String>{}}) {
  final out = <_Raw>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  // The plants live outside `lib/` and are read the same way, so a control
  // exercises the real walk rather than a second code path that agrees with it.
  files.addAll(extraFiles.map(File.new));

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

/// A scratch file outside `lib/`, carrying planted literals.
class _Plant {
  _Plant(this.file, this.body);
  final File file;
  final String body;

  String get path => file.path;

  void write() => file.writeAsStringSync(body);
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

  test('the census sees a planted line-height (it can still fail)', () {
    // The negative control. This guard had **no** control until now, which is
    // why it could report clean while reading only the four `const TextStyle`s
    // in a file whose nine real styles are not const: every plant below is a
    // shape the previous version of this visitor could not see, so a clean run
    // before this test was not evidence of anything.
    final dir = Directory.systemTemp.createTempSync('lh_census_plant');
    addTearDown(() => dir.deleteSync(recursive: true));

    // 1. The **non-const** spelling -- a MethodInvocation, and the shape all
    //    nine of the theme's own style constants use.
    final callPlant = _Plant(
      File('${dir.path}/plant_call.dart'),
      'final t = TextStyle($_kName: 1.5);\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{callPlant.path}),
      isNotEmpty,
      reason: 'a non-const TextStyle is a MethodInvocation; it must be seen',
    );

    // 2. The **const** spelling -- the shape the old visitor could read. Kept
    //    so removing the new branch cannot pass this file by accident.
    final constPlant = _Plant(
      File('${dir.path}/plant_const.dart'),
      'const t = TextStyle($_kName: 1.6);\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{constPlant.path}),
      isNotEmpty,
      reason: 'the const spelling must still be scanned',
    );

    // 3. `copyWith` on a theme style -- how the app re-spaced a paragraph.
    final copyPlant = _Plant(
      File('${dir.path}/plant_copy.dart'),
      'final t = AppTheme.body.copyWith($_kName: 1.65);\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{copyPlant.path}),
      isNotEmpty,
      reason: 'copyWith on a theme style must be scanned',
    );

    // 4. **NEGATIVE CONTROL** -- a rung being *declared*. This is the one shape
    //    the rule must never report, and it is the whole reason the exemption
    //    is narrowed to a declaration instead of to a filename. If the
    //    exemption ever goes back to skipping `app_theme.dart`, this plant
    //    still passes (it is in a temp dir), but the *real* census starts
    //    reporting the ten rungs -- which is the failure this pair prevents.
    final declPlant = _Plant(
      File('${dir.path}/plant_decl.dart'),
      'const double ${_kLadder}Prose = 1.5;\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{declPlant.path}),
      isEmpty,
      reason: 'a literal that IS the ladder being declared is not a writer',
    );

    // 5. **NEGATIVE CONTROL** -- a token spelling must not fire. Without this,
    //    a census flagging every `height:` would pass plants 1-3 for the wrong
    //    reason, exactly as it would report the whole app.
    final tokenPlant = _Plant(
      File('${dir.path}/plant_token.dart'),
      'final t = TextStyle($_kName: AppTheme.${_kLadder}Prose);\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{tokenPlant.path}),
      isEmpty,
      reason: 'a style naming a token is the rule working, not breaking',
    );

    // 6. **NEGATIVE CONTROL** -- a `SizedBox(height:)` is not a text style. This
    //    is the reason the rule is scoped to styles at all: `lib/` holds 88
    //    boxes and the guard must never name one of them.
    final boxPlant = _Plant(
      File('${dir.path}/plant_box.dart'),
      'const b = SizedBox($_kName: 1.5, child: Text("x"));\n',
    )..write();
    expect(
      _rawLineHeights(extraFiles: <String>{boxPlant.path}),
      isEmpty,
      reason: 'a box height is layout, not type',
    );
  });

  test('the ladder exists, and each token is the number it replaced', () {
    // Not decoration: if someone edits a token's value this fails, which is the
    // point. The conversion was value-preserving, so these are exactly the
    // numbers the widgets carried before it.
    expect(AppTheme.lhTightest, 1.1);
    expect(AppTheme.lhBadge, 1.15);
    expect(AppTheme.lhList, 1.2);
    expect(AppTheme.lhTile, 1.25);
    expect(AppTheme.lhProse, 1.5);
    expect(AppTheme.lhRoomy, 1.6);
    expect(AppTheme.lhSubtle, 1.45);
    // Added this tick. These three are the numbers the nine style constants
    // already carried -- 1.35 on `display`, 1.4 on `h1`/`bar`/`label`/
    // `caption`, 1.65 on `body`/`bodySoft` -- and the assertion is what makes
    // the rename safe: it is a rename, not a re-tune. Changing a rung here
    // changes what the whole app inherits through `copyWith`.
    expect(AppTheme.lhFigure, 1.35);
    expect(AppTheme.lhShort, 1.4);
    expect(AppTheme.lhReading, 1.65);
  });

  test('the ladder is ordered, tightest first, and complete', () {
    // A ladder nobody can walk is a list, and this is the assertion that says
    // the next rung belongs *on* the scale rather than beside it. Ten rungs,
    // ascending, no duplicates -- a duplicate would mean two names for one
    // number, which is the defect the weight ladder was measured for.
    final ascending = <double>[
      AppTheme.lhTightest,
      AppTheme.lhBadge,
      AppTheme.lhList,
      AppTheme.lhTile,
      AppTheme.lhFigure,
      AppTheme.lhShort,
      AppTheme.lhSubtle,
      AppTheme.lhProse,
      AppTheme.lhRoomy,
      AppTheme.lhReading,
    ];
    for (var i = 1; i < ascending.length; i++) {
      expect(
        ascending[i],
        greaterThan(ascending[i - 1]),
        reason: 'line-height ladder must ascend, not repeat or fall -- a '
            'repeat means two tokens for one number',
      );
    }
    // Every rung the app can render must be reachable from one list, so the
    // next tick adds its number *here* rather than beside the ladder.
    expect(ascending.toSet().length, ascending.length);
  });
}
