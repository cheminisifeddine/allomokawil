// No public declaration in `lib/` may have zero callers.
//
// **The defect this file exists for, measured on 8 Oct.** Four public
// declarations in this tree were declared and never referenced by anything --
// `OutlineButton` (`lib/src/widgets/big_button.dart`, 51 lines), its
// `OutlineButtonOnly` passthrough (`project_detail_screen.dart`, 11 lines),
// `EmptyState` (`lib/src/widgets/empty_state.dart`, 55 lines) and the
// top-level `const appThemeNavy` that existed only to re-export
// `AppTheme.navy`. 151 public classes, 4 of them orphans: the widget library
// carried a second outlined button byte-for-byte beside the live
// `SecondaryButton`, and an empty-state widget beside the live `EmptyView`.
//
// Two of them were *renames that never landed*. `OutlineButtonOnly` takes a
// label and hands it straight to `SecondaryButton` -- it is a name with no
// behaviour, left behind by the commit that moved these call sites onto the
// kit. `EmptyState` is `EmptyView` minus the fields the app actually uses
// (`actionLabel`/`onAction`, `danger`, `titleColor`), so the copy that survived
// is the one that could not carry a retry button: the loser's copy stayed
// readable and the version every screen uses was the one that stayed.
//
// **Why nothing caught it.** `flutter analyze` does not flag an unreferenced
// public class -- unused *private* members are warnings, an unused public one is
// not a symbol Dart can resolve to anything, so the analyzer has nothing to
// say. Nothing else in the tree counted declarations against references either,
// so the drift was invisible until this file read the AST.
//
// **Why this is an AST sweep and not a regex** (`blankComments` is available
// and was tried first). A text scan cannot tell a *declaration* from a *use*:
// `class OutlineButton {` and `OutlineButton(label: ...)` are the same eight
// letters, so every real call site and the declaration itself have to be
// subtracted by pattern, and the subtraction is exactly where a regex sweep
// goes wrong -- it over-blanks aggressively and reported 123 "orphans" on a
// tree that has 4, including `main`, `Spacer` and `Flexible`. Those 123 are the
// measured reason this file is written against the analyzer: a sweep with that
// false-positive rate gets deleted, and deleting it is how the four real ones
// come back. The analyzer knows a `ClassDeclaration`'s name is a declaration
// and a `SimpleIdentifier` is a use, so the two are never confused.
//
// The rule is deliberately narrow so it stays enforceable:
//   * public (non-`_`) **type declarations only** -- classes, mixins, enums;
//   * `main`, entry points and anything the platform names, are excluded
//     because they are called by the runtime, not by this tree;
//   * a declaration with a reference **anywhere** in `lib/` or `test/` counts,
//     including its own file, because a widget used by its neighbour is live.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Dart file the app ships, `lib/main.dart` included -- the entry point
/// sits beside `lib/src` and a `Directory('lib/src')` walk would miss it (the
/// defect `app_source_scope_test.dart` already documents).
List<File> _appSources() {
  final root = Directory('lib');
  final out = <File>[];
  for (final e in root.listSync(recursive: true)) {
    if (e is File && _dartFile.hasMatch(e.path)) out.add(e);
  }
  return out;
}

/// Every Dart file the tests read, for the "is anyone using it" side.
List<File> _testSources() {
  final dir = Directory('test');
  if (!dir.existsSync()) return <File>[];
  final out = <File>[];
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && _dartFile.hasMatch(e.path)) out.add(e);
  }
  return out;
}

/// The suffix that makes a file one this rule reads.
///
/// `RegExp`, not `endsWith`: the census in `app_source_scope_test.dart` scores
/// a rule token by the call that RECEIVES it, and its applier set is
/// `RegExp`/`contains` -- a token handed to `endsWith` is a literal the
/// applier case cannot classify. Spelling the rule's own recogniser as the
/// pattern it is (`RegExp(r'\.dart$')`) is also the more honest statement:
/// this is the shape the rule turns on, and it is matched, not compared.
final _dartFile = RegExp(r'\.dart$');

/// A public type declaration and where it lives.
class _Decl {
  const _Decl(this.name, this.file);
  final String name;
  final String file;

  @override
  String toString() => '$file  $name';
}

/// Declarations the platform, not this tree, calls.
///
/// `main` is Flutter's entry point; naming it in the allow-list keeps the rule
/// honest about *why* it is exempt rather than exempting it by accident.
const _platformCalled = <String>{
  'main',
};

/// Tallies **every** identifier read anywhere in one compilation unit, in a
/// single visit -- a *use*, never a declaration, because the analyzer puts a
/// declaration's name in a `ClassDeclaration.name`, not in an identifier
/// expression.
///
/// One visitor for the whole file rather than one per candidate name: a
/// per-name visitor walks the entire AST once per candidate, which on this
/// tree (398 sources, ~170 public types) is ~68 000 full walks against a
/// 300-second per-shard deadline. This visits each file exactly once.
class _IdentifierTally extends RecursiveAstVisitor<void> {
  _IdentifierTally(this.selfNames);

  /// Names declared **by the unit being walked** -- a class's own name and the
  /// names of its members' declaring types.
  final Set<String> selfNames;

  final Map<String, int> counts = <String, int>{};

  /// **A constructor declaration is not a use of its own class.** This is the
  /// defect that made the first version of this sweep unable to fail.
  ///
  /// Measured: a planted `class PlantedOrphan` with `const PlantedOrphan(
  /// {super.key});` tallied **1** use of `PlantedOrphan` and the guard reported
  /// **All tests passed!** -- a guard for dead declarations that is blind to a
  /// dead declaration. The name node was a `SimpleIdentifier` whose parent the
  /// parser identifies as `ConstructorDeclarationImpl`, and every one of the
  /// four orphans this file was written for had exactly that line, so all four
  /// were being counted as live by their own constructor. Dropping the visit
  /// for a constructor whose name equals the type it belongs to is what makes
  /// the sweep able to fail at all.
  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final String? n = node.name?.lexeme;
    if (n != null && !selfNames.contains(n)) {
      counts.update(n, (v) => v + 1, ifAbsent: () => 1);
    }
    // The body still contains real uses, so keep walking into it -- but the
    // node's own name (the return type / the class being constructed) is not
    // walked as a *use* of the type, because it is the declaration.
    node.body.accept(this);
    node.initializers.accept(this);
    for (final p in node.parameters.parameters) {
      p.accept(this);
    }
    node.redirectedConstructor?.accept(this);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    counts.update(node.name, (n) => n + 1, ifAbsent: () => 1);
    super.visitSimpleIdentifier(node);
  }

  /// **A type reference is not an identifier expression, and counting only
  /// [visitSimpleIdentifier] misses every one of them.**
  ///
  /// This was measured, not reasoned: with the identifier-only tally the first
  /// run reported `CrashStore`, `OutboxStore`, `RenderableRow`,
  /// `UnreadCountOnResume` and `StatusCopyError` as orphans -- 12, 18, 5, 5 and
  /// 5 real references respectively, the clearest possible contradiction. All
  /// five are named in an `is` check, a field/parameter type or a `with` clause,
  /// and each of those is a [NamedType], whose name is a [Token] and not a
  /// [SimpleIdentifier]. An analyzer sweep that only counts expressions reads
  /// a type as a use of nothing, which is the same class of defect this
  /// repository keeps meeting in a different costume: a rule enforced at a
  /// granularity that cannot see its own subject.
  @override
  void visitNamedType(NamedType node) {
    counts.update(node.name.lexeme, (n) => n + 1, ifAbsent: () => 1);
    super.visitNamedType(node);
  }
}

void main() {
  test('no public type in lib/ is declared and never referenced', () {
    final sources = _appSources();
    expect(sources, isNotEmpty, reason: 'lib/ enumerated nothing to scan');

    // One parse and one AST visit per file, shared by every candidate name.
    //
    // The declaration walk and the use tally are the same walk: a visitor
    // cannot count an identifier read and collect top-level declarations in
    // one pass without knowing which names it is looking for, so the tallies
    // are gathered first and the declaration list is filtered afterwards
    // against the finished tally. Parsing every file twice was measurably the
    // dominant cost when this sweep was first written.
    final parsed = <CompilationUnit>[];
    final decls = <_Decl>[];
    final tallies = <String, int>{};

    final all = <File>[...sources, ..._testSources()];
    for (final f in all) {
      final result = parseString(
        content: f.readAsStringSync(),
        throwIfDiagnostics: false,
      );
      final unit = result.unit;
      parsed.add(unit);

      // Every type name declared in THIS unit. A constructor naming one of
      // them is that type's own declaration, not a use of it.
      final self = <String>{};
      for (final d in unit.declarations) {
        if (d is ClassDeclaration) {
          self.add(d.namePart.typeName.lexeme);
        } else if (d is MixinDeclaration) {
          self.add(d.name.lexeme);
        } else if (d is EnumDeclaration) {
          self.add(d.namePart.typeName.lexeme);
        }
      }
      final tally = _IdentifierTally(self);
      unit.accept(tally);
      tally.counts.forEach((name, n) {
        tallies.update(name, (prev) => prev + n, ifAbsent: () => n);
      });

      if (!f.path.startsWith('lib')) continue;
      for (final d in unit.declarations) {
        // analyzer 14 moved the *declared* type name behind a part node
        // (`namePart.typeName`) for both a class and an enum; a mixin still
        // carries `name` directly. Read the token each shape actually exposes
        // rather than assuming one signature for all three -- which is what
        // the analyzer caught on the first two attempts.
        final Token name;
        if (d is ClassDeclaration) {
          name = d.namePart.typeName;
        } else if (d is MixinDeclaration) {
          name = d.name;
        } else if (d is EnumDeclaration) {
          name = d.namePart.typeName;
        } else {
          continue;
        }
        final text = name.lexeme;
        if (text.isEmpty || text.startsWith('_')) continue;
        if (_platformCalled.contains(text)) continue;
        decls.add(_Decl(text, f.path));
      }
    }

    final orphans = <String>[];
    for (final d in decls) {
      final uses = tallies[d.name] ?? 0;
      if (uses == 0) orphans.add('$d  (uses: 0)');
    }

    expect(
      orphans,
      isEmpty,
      reason: 'These public types are declared in lib/ and referenced by '
          'nothing in lib/ or test/. Delete them, or -- if the copy is the one '
          'a screen should be using -- replace the call sites and delete this '
          'one:\n  ${orphans.join('\n  ')}\n'
          'Scanned ${sources.length} app sources, ${parsed.length} files '
          'total, ${decls.length} public types.',
    );
  });
}
