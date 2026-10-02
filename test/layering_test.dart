// The app's layer graph, asserted instead of described.
//
// Found 2 Oct 2026 with 0 unchecked backlog items, auditing a hint the previous
// tick left. `models/plan.dart` imported `data/chat_time.dart` for
// `calendarDaysBetween` — the **first `models/` -> `data/` edge** the app had
// ever carried, introduced by a bug fix (the DST countdown) rather than chosen.
// The layering the README states is the other way round: `models/` holds pure
// types, `data/` is screen-facing and imports them.
//
// Nothing was broken by it. That is exactly why it needed a guard: an import
// that merely inverts an architectural direction fails silently, for ever,
// because the analyzer has no opinion about it and no test looked. This file is
// that test.
//
// **Measured before it was written, so the rules are not invented.** Every
// layer's real imports were enumerated first, and the allowed edges below are
// the ones that exist in practice — not a wish list. That process also killed
// the premise that the graph was otherwise pristine: `core/` reaches *upward*
// in three files (`auth_gate.dart` -> `screens/`, `widgets/`; `app_scope.dart`
// -> `data/`). Those are recorded as allowed rather than "fixed", because they
// are pre-existing, deliberate wiring and a refactor of the DI scope is not a
// 10-minute change. What is forbidden is the *new* direction, and that is the
// one rule this file holds.
//
// A guard that would need a refactor to pass is not shipped, because a red suite
// teaches the next tick to ignore the suite. So: no forbidden edges today, and
// the rule is recorded so the ones already in place are a known list rather
// than a future surprise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `models/` is pure types. It may reach `core/` (formatting, l10n, theme) —
/// three files already do — but never `data/`, `screens/` or `widgets/`, which
/// are the layers that know what the app *does*.
///
/// The one edge this rule kills is the subscription card's day count reaching
/// into a chat file.
const Map<String, List<String>> _forbidden = {
  'models': ['data', 'screens', 'widgets'],
};

/// `core/` is the shared floor. It is allowed to reach `models/` and, in the
/// three files listed in the header, `screens/`/`widgets/`/`data/` — the DI
/// scope is assembled from the top and cannot be assembled from below. Asserting
/// that it cannot would be asserting a refactor nobody has asked for.
// Deliberately NOT a blanket `core/` rule: `core/app_scope.dart` imports
// `data/` and `core/auth_gate.dart` imports `screens/` and `widgets/`, because
// the DI scope is assembled from the top and cannot be assembled from below.
// `core/format/` is the one part of `core/` that IS a leaf — measured, it
// imports nothing at all — so that is the directory held to the strict rule.
// Recording those three as forbidden would be asserting a refactor nobody has
// asked for, and a red suite teaches the next tick to ignore the suite.

/// Every `import`/`export` in [file], as raw paths.
///
/// **`multiLine: true` is load-bearing, and the first draft omitted it.** With
/// `^` and no multiline flag the anchor means *start of string*, so `^import`
/// matched only line 1 — and because Dart puts the header comment first, the
/// pattern matched nothing at all. The scan returned an empty set, every
/// offender list came out empty, and all three tests passed against a tree
/// containing the exact import this file exists to forbid. It was found by
/// reintroducing the bad edge and watching which tests went red: only the
/// direct-string one did. A guard that greps and gets no matches is
/// indistinguishable from a clean tree, and this one had been reporting "no
/// problems" for a rule it was never evaluating.
Set<String> _importsIn(File file) {
  final src = file.readAsStringSync();
  Set<String> scan(RegExp re) =>
      re.allMatches(src).map((m) => m.group(1)!).toSet();
  // `export` is a re-export, which is an edge too.
  return {
    ...scan(RegExp(r'''^import\s+['"]([^'"]+)['"]''', multiLine: true)),
    ...scan(RegExp(r'''^export\s+['"]([^'"]+)['"]''', multiLine: true)),
  };
}

/// The layer an import path points into, or null for `core/` and `package:`.
String? _layerOf(String importPath) {
  if (importPath.startsWith('package:')) return null;
  final m = RegExp(r'(?:^|/)(core|data|models|screens|widgets)/')
      .firstMatch(importPath);
  return m?.group(1);
}

void main() {
  test('models/ does not import a layer above it', () {
    final offenders = <String>[];
    for (final f in Directory('lib/src/models').listSync()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final imp in _importsIn(File(f.path))) {
        final layer = _layerOf(imp);
        if (layer != null && _forbidden['models']!.contains(layer)) {
          offenders.add('${f.path} -> $imp');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'models/ is pure types and must not reach data/, screens/ or '
            'widgets/. It did once: plan.dart imported data/chat_time.dart for '
            'the calendar-day count, which now lives in '
            'core/format/calendar_day.dart.');
  });

  test('core/format/ is a leaf: it imports no layer of the app at all', () {
    // Not vacuous: a first draft of this ran against an allow-list that was
    // empty, so it could not fail — a guard that cannot fail is decoration.
    // `core/format/` genuinely imports nothing today, so "imports no app
    // layer" is the real assertion, and it can be broken by the next person to
    // reach for a helper one level up.
    final offenders = <String>[];
    for (final f in Directory('lib/src/core/format').listSync()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final imp in _importsIn(File(f.path))) {
        if (_layerOf(imp) != null) offenders.add('${f.path} -> $imp');
      }
    }
    expect(offenders, isEmpty,
        reason: 'core/format/ is shared formatting used by models/ and data/ '
            'alike. If it needs a helper from a higher layer, that helper is '
            'not shared and belongs in core/ as well.');
  });

  test(
      'calendarDaysBetween is defined once, in core/, and both layers see '
      'the same function', () {
    // A move can leave a second copy behind and the arithmetic can then drift,
    // which is the failure the move was made to prevent. This asserts the
    // *definition* is single, not merely that both names resolve.
    final home =
        File('lib/src/core/format/calendar_day.dart').readAsStringSync();
    expect(
        RegExp(r'^int calendarDaysBetween', multiLine: true)
            .allMatches(home)
            .length,
        1,
        reason: 'calendarDaysBetween must be defined exactly once, in core/.');

    final chat = File('lib/src/data/chat_time.dart').readAsStringSync();
    expect(
        RegExp(r'^int calendarDaysBetween', multiLine: true)
            .allMatches(chat)
            .length,
        0,
        reason: 'chat_time.dart must re-export, not keep a second copy — two '
            'copies of one calendar rule is the drift this move removed.');
    expect(
        RegExp(r'''export\s+['"][^'"]*calendar_day\.dart['"]''')
            .allMatches(chat)
            .length,
        1,
        reason: 'chat_time.dart keeps re-exporting the name so its callers and '
            'tests are untouched.');

    // And the billing model reads the core/ one, not the chat one.
    final plan = File('lib/src/models/plan.dart').readAsStringSync();
    expect(plan, isNot(contains("import '../data/chat_time.dart'")),
        reason: 'this is the edge that started it.');
    expect(plan, contains("core/format/calendar_day.dart"),
        reason: 'the day count on the subscription card must come from core/.');
  });
}
