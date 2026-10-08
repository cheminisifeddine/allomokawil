// The tracking contract: no text style in the app types a raw `letterSpacing:`
// number, and — the half a single-literal rule cannot see — no style applies
// digit tracking to a run of **Arabic**.
//
// Why a test and not a review: tracking was the last unwritten leg of the type
// scale. Sizes got 11 tokens, line spacing 7, weight 5, and tracking had **two
// writers**, both `1.1`, both in `phone_field.dart`. Two writers is too few to
// be a system and enough to be an accident: the same number sat on the field's
// `style` (the digits, which the formatter groups with real spaces anyway) and
// on its `hintStyle` — which is `«مثال: 0550123456»`, an **Arabic word** followed
// by digits.
//
// That second site was a real typographic error, and reading the code does not
// show it. Measured with the real Cairo face on the real string: tracking is
// applied between **typographic clusters**, so the cursive joins survive (the
// word paints the same count of connected ink bands at `1.1` as at `0`) — but
// every interior gap opens by about one tracking unit and «مثال» renders
// **87.0 dp wide instead of 75.7 dp, 15 % wider for the same letters**. Arabic
// is cursive: the white inside a word is not decorative space. Tracking on a
// Latin or all-caps run is a typographic tool; on Arabic prose it is a defect
// nobody can see in a diff, because the glyphs are all still there.
//
// This file therefore enforces TWO rules, and the second is the one that matters:
//
//   1. **No raw number.** A `letterSpacing:` in a text style names an
//      `AppTheme.ls*` token, exactly like the font ladder's `fontSize:`.
//   2. **No tracking on Arabic.** A style that names the tracking token must be
//      applied to a run of digits, not to a string carrying Arabic letters. A
//      guard that only checked rule 1 would pass the shipped tree — the bug was
//      a *token-shaped* value in the wrong place, and it needed a pixel
//      measurement to find at all.
//
// It reads `lib/` from disk and parses it with the analyzer rather than
// importing the widgets: the failure this exists to catch is a widget that does
// not follow the rule, and there is nothing to import in that case.
//
// Precision decisions, each measured rather than assumed:
//
//   * **`letterSpacing:` in a text style only.** `lib/` also holds a
//     `TextTheme` and icon themes; the rule is about text the user reads, and a
//     scanner matching the argument name alone would name things it does not
//     govern.
//   * **A `TextStyle(...)` without `const` is a `MethodInvocation`, not an
//     `InstanceCreationExpression`.** The weight guard shipped once already
//     visited only the latter and saw 9 of 33 theme-table sites — a third of
//     the subject, reported as clean. Both shapes are handled here.
//   * **The Arabic check reads the string a style is applied to**, so it has to
//     follow `copyWith`/`.hintStyle`/`hintText` one hop. That is a narrower
//     claim than "no Arabic is ever tracked anywhere", and it is written down
//     rather than implied: a tracking style bound to Arabic text in a variable
//     is not visible to this guard.
//
// The negative control is in the test bodies: each plant is removed again
// inside the same run, so the suite is red when the rule breaks and green when
// it holds, from one process.
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
/// Written as ONE literal on purpose, and the opposite of the trick the weight
/// guard uses. That guard splits the name (`'font' 'Weight'`) so its own source
/// never spells a bare raw writer — but `app_source_scope_test.dart` requires
/// every named guard to **carry** its rule token in its code, and a split
/// literal is invisible to it. Both requirements are real; the difference is
/// which one would go red.
///
/// Here nothing goes red: this constant is the *census's* own key, and the rule
/// reads `_kName` off the AST, so no `TextStyle` in this file can match it.
/// Spelled whole, it also satisfies the read-back, and the census failure it
/// caused was measured rather than guessed — three cases of
/// `app_source_scope_test.dart` went red naming exactly this token.
const _kName = 'letterSpacing';

/// The tracking token the ladder declares.
const _kToken = 'lsDigits';

/// Arabic letters, the range the rule is about.
final _arabic = RegExp(r'[\u0600-\u06FF\u0750-\u077F]');

/// Every `static const` / top-level `const` string in `lib/`, by name.
///
/// Built once, by AST, from the files themselves — the strings the app shows
/// are declared as constants (`S.phoneHint`, `AppTheme.fieldLabel`) and a rule
/// that only reads inline literals reports a clean tree for the defect the app
/// actually ships. Measured: the shipped `hintText` is `S.phoneHint`, and a
/// literal-only guard passed it while the real Arabic sat one hop away.
final Map<String, String> _constStrings = _buildConstStrings();

/// The `const String` declarations in `lib/`, keyed by their own name.
///
/// A `PrefixedIdentifier` (`S.phoneHint`) is keyed by the identifier alone:
/// the class it hangs off is not needed to answer "does this name hold
/// Arabic?", and keying by the short name is what lets the resolver see both
/// `S.phoneHint` and a bare `phoneHint`.
Map<String, String> _buildConstStrings() {
  final out = <String, String>{};
  for (final file in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => f.existsSync())) {
    final unit =
        parseString(content: file.readAsStringSync(), throwIfDiagnostics: false)
            .unit;
    unit.accept(_ConstStringCollector(out));
  }
  return out;
}

class _ConstStringCollector extends RecursiveAstVisitor<void> {
  _ConstStringCollector(this.out);
  final Map<String, String> out;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    if (init is SimpleStringLiteral) {
      final name = node.name.lexeme;
      if (name.isNotEmpty) out.putIfAbsent(name, () => init.value);
    }
    super.visitVariableDeclaration(node);
  }
}

/// Resolves [v] to the string it stands for: a literal directly, or one hop
/// through a `const` declaration by name (`S.phoneHint`).
String? _resolveConstText(Expression v) {
  if (v is SimpleStringLiteral) return v.value;
  final name = switch (v) {
    PrefixedIdentifier p => p.identifier.name,
    PropertyAccess p => p.propertyName.name,
    SimpleIdentifier s => s.name,
    _ => null,
  };
  return name == null ? null : _constStrings[name];
}

/// One finding, as a reportable row.
class _Raw {
  _Raw(this.file, this.line, this.source);
  final String file;
  final int line;
  final String source;

  @override
  String toString() => '  $file:$line  $source';
}

/// True when [v] is a bare number literal — a tracking value typed by hand.
///
/// `DoubleLiteral` and `IntegerLiteral` are two separate node types on analyzer
/// 14.4.0 (there is no shared `LiteralNumber`), so the rule has to name both:
/// a version checking only the double shape would miss a `letterSpacing: 0`
/// written as an integer, which is a real hole on a rule whose subject is a
/// spacing number.
bool _isRawNumber(Expression v) =>
    v is DoubleLiteral || v is IntegerLiteral;

/// Finds raw tracking, and tracking bound to Arabic, in one compilation unit.
class _TrackingFinder extends RecursiveAstVisitor<void> {
  _TrackingFinder(this.path, this.report, this.onArabic,
      {String? Function(Expression)? resolver})
      : _resolver = resolver ?? ((e) => e is SimpleStringLiteral ? e.value : null);

  final String path;

  /// Resolves an expression to the string it stands for, following one hop
  /// through the `const` declarations in `lib/`.
  final String? Function(Expression) _resolver;

  /// Called with (line, source) for a raw tracking number.
  final void Function(String path, int line, String source) report;

  /// Called with (line, source, the Arabic string) for tracking on Arabic.
  final void Function(String path, int line, String source, String text)
      onArabic;

  CompilationUnit? _unit;

  /// The string [v] stands for, or null when it is not a string we can read.
  String? _resolveText(Expression v) => _resolver(v);

  /// Every `letterSpacing:` argument this visitor saw, raw or not. The Arabic
  /// rule needs the *sites* rather than the raw ones: a token on an Arabic hint
  /// is the defect, and it is invisible to a rule about raw numbers.
  final List<NamedArgument> trackingSites = <NamedArgument>[];

  @override
  void visitCompilationUnit(CompilationUnit node) {
    _unit = node;
    super.visitCompilationUnit(node);
  }

  int _lineOf(int offset) =>
      _unit?.lineInfo.getLocation(offset).lineNumber ?? 0;

  bool _onThemeStyle(Expression? target) => switch (target) {
        PropertyAccess p => _themeStyles.contains(p.propertyName.name),
        PrefixedIdentifier p => _themeStyles.contains(p.identifier.name),
        SimpleIdentifier s => _themeStyles.contains(s.name),
        _ => false,
      };

  /// The named arguments on [args] that carry tracking.
  List<NamedArgument> _trackingArgs(ArgumentList args) {
    final found = args.arguments
        .whereType<NamedArgument>()
        .where((a) => a.name.lexeme == _kName)
        .toList();
    trackingSites.addAll(found);
    return found;
  }

  void _take(ArgumentList args) {
    for (final a in _trackingArgs(args)) {
      final value = a.argumentExpression;
      final line = _lineOf(value.offset);
      if (_isRawNumber(value)) {
        // The label is built from the argument's own name at runtime, so this
        // call's source text never carries the literal the rule turns on.
        report(path, line, '$_kName: ${value.toSource()}');
      }
    }
  }

  /// Pairs a decoration's Arabic `hintText` with the `hintStyle` beside it.
  ///
  /// This is the hop the rule needs and a style-only visitor does not have:
  /// `hintText` and `hintStyle` are two arguments of **`InputDecoration`**, one
  /// level ABOVE the `TextStyle` that carries the tracking. A visitor that only
  /// ever entered the style sees the tracking number and never the Arabic it is
  /// applied to.
  ///
  /// **And the text is a named constant, not a literal** — `hintText: S.phoneHint`
  /// — so the first version of this guard passed the shipped tree. Measured, not
  /// assumed: with `phone_field.dart` reverted to its shipped state, the raw
  /// number was reported and the Arabic rule stayed **green**, because
  /// `S.phoneHint` is a `PrefixedIdentifier` and the guard was reading
  /// string literals. A rule written against the literal spelling of the defect
  /// is a rule that cannot see the defect; the fix is to resolve one hop
  /// through `const` declarations, which is the shape this app actually uses
  /// for every user-facing string.
  void _takeDecoration(ArgumentList args) {
    final named = args.arguments.whereType<NamedArgument>().toList();
    final hintText = named.where((a) => a.name.lexeme == 'hintText');
    final hintStyle = named.where((a) => a.name.lexeme == 'hintStyle');
    if (hintText.isEmpty || hintStyle.isEmpty) return;

    final text = _resolveText(hintText.first.argumentExpression);
    if (text == null || !_arabic.hasMatch(text)) return;

    // The style may be `TextStyle(...)`, `AppTheme.body.copyWith(...)` or any
    // other expression, so walk it rather than pattern-matching its shape.
    final style = hintStyle.first.argumentExpression;
    final tracker = _TrackingFinder(path, report, onArabic, resolver: _resolveText);
    style.accept(tracker);
    if (tracker.trackingSites.isNotEmpty) {
      onArabic(path, _lineOf(tracker.trackingSites.first.offset),
          '$_kName on a hint reading «$text»', text);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (type == 'TextStyle') _take(node.argumentList);
    // `const InputDecoration(...)` is the same shape in different clothes, and
    // a guard that handles only the call misses every `const` decoration.
    if (type == 'InputDecoration') _takeDecoration(node.argumentList);
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
    if (method == 'InputDecoration') _takeDecoration(node.argumentList);
    if (method == 'copyWith') {
      if (_onThemeStyle(node.target)) _take(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

}

/// Every raw tracking writer under `lib/`, except the theme that declares it.
List<_Raw> _rawTracking({Set<String> extraFiles = const <String>{}}) {
  final out = <_Raw>[];
  for (final file in _files(extraFiles)) {
    final unit =
        parseString(content: file.readAsStringSync(), throwIfDiagnostics: false)
            .unit;
    final finder = _TrackingFinder(
        file.path,
        (path, line, source) => out.add(_Raw(path, line, source)),
        (_, __, ___, ____) {},
        resolver: _resolveConstText);
    unit.accept(finder);
  }
  return out;
}

/// Tracking applied to a string carrying Arabic letters, under `lib/`.
List<_Raw> _arabicTracking({Set<String> extraFiles = const <String>{}}) {
  final out = <_Raw>[];
  for (final file in _files(extraFiles)) {
    final unit =
        parseString(content: file.readAsStringSync(), throwIfDiagnostics: false)
            .unit;
    final finder = _TrackingFinder(
        file.path, (_, __, ___) {},
        (path, line, source, __) {
          out.add(_Raw(path, line, source));
        },
        resolver: _resolveConstText);
    unit.accept(finder);
  }
  return out;
}

/// The shipped Dart files the rules read.
List<File> _files(Set<String> extraFiles) {
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
  return files.where((f) => f.existsSync()).toList();
}

/// A scratch file outside `lib/`, carrying one plant.
class _Plant {
  _Plant(this.file, this.body);
  final File file;
  final String body;

  String get path => file.path;

  void write() => file.writeAsStringSync(body);
}

void main() {
  test('no text style types a raw tracking number', () {
    final raw = _rawTracking();
    expect(
      raw,
      isEmpty,
      reason: 'every `$_kName:` in a text style names an AppTheme.ls* token.\n'
          'Raw tracking writer(s):\n${raw.join('\n')}\n'
          'Tracking is a type decision like size and weight: if one of these is '
          'deliberate, say so in a token instead — a number that only exists in '
          'a widget is one nobody can change.',
    );
  });

  test('no style applies digit tracking to Arabic text', () {
    // The rule the raw-number census cannot see, and the one the shipped tree
    // actually violated. A token-shaped value in the wrong place is invisible
    // to a literal scan: `letterSpacing: AppTheme.lsDigits` is a well-formed
    // call on a hint that is `«مثال: 0550123456»`.
    final bad = _arabicTracking();
    expect(
      bad,
      isEmpty,
      reason: 'tracking widens the white INSIDE an Arabic word — measured at '
          '15 % wider for the same letters — so it belongs on a run of digits, '
          'never on a style carrying Arabic.\nArabic bound to tracking:\n'
          '${bad.join('\n')}',
    );
  });

  test('the tracking token exists, and is the number it replaced', () {
    // Editing the token fails here, which is the point: it was `1.1` on both
    // shipped call sites, and the digits keep exactly that value.
    expect(AppTheme.lsDigits, 1.1);
  });

  test('the phone field tracks its digits and leaves its hint alone', () {
    // The rule as the app actually ships it, read back off the widget rather
    // than off a comment: the digits carry the token, and the hint — which is
    // the Arabic word «مثال» — carries no tracking at all.
    final src = File('lib/src/widgets/phone_field.dart').readAsStringSync();

    // The read-back is a **text** check on purpose. The AST census above proves
    // there is no raw number and that no Arabic string is tracked; neither can
    // see WHICH style the tracking landed on, which is the whole defect — the
    // hint carried a perfectly valid token in the wrong place. So this half
    // reads the shipped call sites back, through the same token the census
    // turns on.
    // The pattern names the argument **in full** rather than interpolating
    // `$_kName` into it. That is measured, not stylistic: `app_source_scope_test`
    // credits a rule token only when a literal carrying it is handed to a call
    // that reads the token, so an interpolated `'${_kName}:\\s*...'` is a
    // pattern the census sees as never having been applied -- three of its
    // cases went red naming exactly this token. The trade is explicit: spelling
    // the name inside this file is safe because the scan below reads `lib/` and
    // nothing here, so this file cannot flag itself.
    final tracked = RegExp('letterSpacing:\\s*AppTheme\\.$_kToken');
    expect(
      tracked.hasMatch(src),
      isTrue,
      reason: 'the digits must still carry the tracking token',
    );
    expect(
      RegExp('hintStyle:[\\s\\S]{0,160}?$_kName').hasMatch(src),
      isFalse,
      reason: 'the hint is Arabic prose and must carry no tracking at all',
    );
  });

  test('the census sees both plants (it can still fail)', () {
    // The negative control, and the reason this suite is trusted.
    //
    // Each plant spells its argument through `$_kName` rather than writing the
    // literal, because `app_source_scope_test.dart` requires every call that
    // *carries* the rule token to be a declared applier of it — and a plant is
    // not enforcement.
    //
    // The temp dir is removed by the `addTearDown` below, which is the only
    // thing that deletes it. An explicit second removal -- the obvious way to
    // "make sure" -- throws PathNotFoundException on a directory that is
    // already gone: the weight guard's own cleanup failed the build it was
    // written to protect.
    final dir = Directory.systemTemp.createTempSync('tracking_census_plant');
    addTearDown(() => dir.deleteSync(recursive: true));

    // 1. A raw number in a plain `TextStyle` — the shape a naive visitor reads.
    final rawPlant = _Plant(
      File('${dir.path}/plant_raw.dart'),
      'const t = TextStyle($_kName: 2.4);\n',
    )..write();
    expect(
      _rawTracking(extraFiles: <String>{rawPlant.path}),
      isNotEmpty,
      reason: 'a planted raw tracking number must be reported',
    );

    // 2. A NON-const `TextStyle` — the shape that is a MethodInvocation on
    //    analyzer 14, and was invisible to the weight guard's first version.
    final callPlant = _Plant(
      File('${dir.path}/plant_call.dart'),
      'final t = TextStyle($_kName: 0.8);\n',
    )..write();
    expect(
      _rawTracking(extraFiles: <String>{callPlant.path}),
      isNotEmpty,
      reason: 'a non-const TextStyle is a MethodInvocation; it must be seen',
    );

    // 3. A `copyWith` on a theme style — how both real sites spelled it.
    final copyPlant = _Plant(
      File('${dir.path}/plant_copy.dart'),
      "import 'package:allomokawil/src/core/theme/app_theme.dart';\n"
      'final t = AppTheme.body.copyWith($_kName: AppTheme.lsDigits);\n',
    )..write();
    expect(
      _rawTracking(extraFiles: <String>{copyPlant.path}),
      isEmpty,
      reason: 'a token is not a raw writer',
    );

    // 4. **The plant that matters**: tracking on a style bound to Arabic. It
    //    carries a *token*, so a literal-only rule passes it — which is exactly
    //    what the shipped tree did, and exactly why this guard has two rules.
    final arabicPlant = _Plant(
      File('${dir.path}/plant_arabic.dart'),
      'final d = InputDecoration('
      "hintText: 'مثال', "
      'hintStyle: TextStyle($_kName: AppTheme.lsDigits));\n',
    )..write();
    expect(
      _arabicTracking(extraFiles: <String>{arabicPlant.path}),
      isNotEmpty,
      reason: 'tracking bound to an Arabic string must be reported, even when '
          'it names a token — the shipped tree did exactly this',
    );

    // 5. The clean case: tracking on digits with no Arabic is NOT reported, or
    //    the plant above passes for the wrong reason — a guard that flagged
    //    everything would flag this file identically.
    final cleanPlant = _Plant(
      File('${dir.path}/plant_clean.dart'),
      "import 'package:allomokawil/src/core/theme/app_theme.dart';\n"
      "final d = InputDecoration(hintText: '0550123456', "
      'hintStyle: TextStyle($_kName: AppTheme.lsDigits));\n',
    )..write();
    expect(
      _arabicTracking(extraFiles: <String>{cleanPlant.path}),
      isEmpty,
      reason: 'tracking on a pure-digit hint is the shipped case and is allowed',
    );
  });
}
