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

/// Every `.dart` file under [dir], recursively.
///
/// Recursive because `core/` nests (`core/format/`, `core/network/`) and a
/// census that only reads the top level would silently skip the deepest leaf,
/// which is the one most likely to reach upward.
List<File> _dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// The on-disk `.dart` file an import path lands in, or null if it is not one
/// of ours.
///
/// **Both import flavours are resolved, and the first draft of this census
/// resolved only one.** Dart files here are written two ways and both are live:
/// `../data/chat_time.dart` (relative to the file) and `data/repository.dart`
/// (relative to `lib/src/`). An instrument that only understands the first
/// marks the second as unresolvable and then *silently drops the edge* — the
/// census came back "0 upward edges", which is the one answer a broken scanner
/// is guaranteed to produce. The `_coverage` case below exists because of it.
///
/// It also skips `dart:` and `package:` (flutter, flutter_test), which are not
/// edges in this graph.
File? _resolveImport(File from, String spec) {
  if (spec.startsWith('dart:') || spec.startsWith('package:')) return null;
  // `Uri.resolve` is load-bearing, not stylistic. A hand-built
  // '$dir/$spec' string keeps its `..` segments, so
  // `lib/src/core/../data/x.dart` reached `_layerOf`, whose regex matches the
  // FIRST core|data|... segment it sees — it reported the *importing* layer
  // rather than the target. Every upward edge then looked downward, the
  // offender list came back empty, and the census reported a clean graph:
  // exactly the answer a broken instrument is guaranteed to produce.
  // resolve() collapses `..` per RFC 3986, which is what makes the target's
  // layer the real one.
  File? tryResolve(Uri base) {
    final path = base.resolve(spec).toFilePath();
    if (File(path).existsSync()) return File(path);
    if (File('$path/index.dart').existsSync()) return File('$path/index.dart');
    return null;
  }

  // A dotless spec is written relative to lib/src/, not to the importing
  // file — that is the flavour the first census scanner dropped.
  final resolved = tryResolve(from.uri) ??
      (spec.startsWith('.') ? null : tryResolve(Directory('lib/src').uri));
  if (resolved != null) return resolved;
  // An import that does not land on a file is reported, never dropped: a
  // silently discarded edge is how this census lied the first time.
  throw StateError(
      'import "$spec" in ${from.path} does not resolve to a file under lib/. '
      'A dropped edge reads as a clean graph.');
}

/// Every upward edge in `lib/src` today: **12**, measured 2 Oct 2026 and
/// cross-checked by a second, independent walk of the same tree before being
/// written down.
///
/// Rank is the README's own dependency order — `core/` is the floor, then
/// `models/`, `data/`, `widgets/`, `screens/` — so an edge pointing *up* that
/// list inverts it. Note the consequence: `models/` -> `core/` is **downward**
/// and therefore correct, which is why `plan.dart` reaching for
/// `core/format/money.dart` is deliberately absent from this list.
///
/// Three of the twelve were found only because the rank came from the README
/// rather than from the first census, which ranked `models` *below* `core`
/// and so hid `core/` -> `models/` as if those edges did not exist.
const _knownUpward = <String>{
  // DI is assembled from the top and cannot be assembled from below.
  'core/app_scope.dart -> ../data/notification_count_trust.dart',
  'core/app_scope.dart -> ../data/unread_message_trust.dart',
  'core/auth_gate.dart -> ../models/enums.dart',
  'core/auth_gate.dart -> ../screens/auth/auth_screen.dart',
  'core/auth_gate.dart -> ../widgets/big_button.dart',
  'core/auth_gate.dart -> ../widgets/ui.dart',
  'core/location/locator.dart -> ../../data/taxonomy.dart',
  'core/location/locator.dart -> ../../data/wilaya_centers.dart',
  'core/security/auth_state.dart -> ../../data/chat_outbox.dart',
  'core/security/auth_state.dart -> ../../models/enums.dart',
  'core/security/auth_state.dart -> ../../models/user.dart',
  // The bell opens the notification centre. A widget navigating is ordinary
  // Flutter; the alternative is a callback threaded from every home screen,
  // which is a refactor nobody asked for.
  'widgets/notifications_bell.dart -> ../screens/notifications/notifications_screen.dart',
};

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

  // ---------------------------------------------------------------------------
  // The census the 13th tick asked for and never ran.
  //
  // It asked for this as *read-only*: count every `data/` -> `screens/` and
  // `screens/` -> `data/` edge before anyone refactors anything. The count is
  // below and it is 0 in the dangerous direction — `data/` reaches no screen
  // at all — so there is nothing to refactor and no red suite to justify one.
  //
  // The numbers were produced by walking `lib/src` and are recorded here so a
  // future change that moves an edge is a *diff* against a baseline rather than
  // a fresh reading nobody can check. They are asserted, not commented.
  //
  // Layer order is the dependency order the README states. An edge pointing
  // *up* this list is an inversion; the ones that exist today are enumerated
  // explicitly rather than waved through, so adding a fourth is a test failure
  // naming the file and line.
  // ---------------------------------------------------------------------------

  test('data/ never reaches a screen: the 13th tick\'s open census is 0', () {
    final offenders = <String>[];
    for (final f in _dartFilesIn(Directory('lib/src/data'))) {
      for (final imp in _importsIn(f)) {
        final target = _resolveImport(f, imp);
        if (target == null) continue;
        final layer = _layerOf(target.path);
        if (layer == 'screens' || layer == 'widgets') {
          offenders.add('${f.path} -> $imp');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'data/ is the layer the screens call; a data file reaching '
            'back into a screen or a widget inverts that. The census on '
            '2 Oct 2026 found 0 such edges in 557 app-internal imports, and '
            'the two matches grep reports under data/ are comments in '
            'urgency_copy.dart naming the screens that consume it, not '
            'imports. If you are adding one, the logic belongs in core/ and '
            'the screen should keep its own copy.');
  });

  test('the census scanner resolves imports to their real target', () {
    // The anti-vacuous case, and the most important test in this file.
    //
    // A scanner that resolves nothing, or resolves to the wrong file, makes
    // every rule above pass for the wrong reason. It did exactly that twice
    // while this file was being written:
    //
    //   1. Unnormalised paths. `'$dir/$spec'` keeps its `..` segments, so
    //      `lib/src/core/../data/x.dart` reached `_layerOf`, which matches the
    //      FIRST core|data|... segment — the *importing* layer. Every upward
    //      edge looked downward and the offender list came back empty.
    //   2. Blind to the lib/src fallback. The first census assumed the app
    //      writes `data/x.dart` relative to lib/src/ and 192 imports looked
    //      unresolvable. Measured, that assumption is simply false: **all 557
    //      app-internal imports resolve relative to the importing file**, and
    //      none need the lib/src root. Deleting that fallback changed nothing
    //      and the mutation arm stayed green — proving the guard was testing
    //      a population that does not exist.
    //
    // So this asserts the two things that actually distinguish a working
    // scanner: that a spec is resolved to a file that EXISTS, and that a
    // `..`-laden spec lands on the target's layer rather than the importer's.
    final core = File('lib/src/core/auth_gate.dart');
    // `../` crosses up out of core/ into models/. A scanner that does not
    // collapse `..` keeps the literal `core/` prefix and calls this a
    // core->core edge, which is the bug in its most checkable form.
    expect(_layerOf(_resolveImport(core, '../models/enums.dart')!.path),
        'models',
        reason: 'a `..` import must resolve to the TARGET layer, not to the '
            'importer. An unnormalised path reports core/ and hides every '
            'inversion.');
    expect(_resolveImport(core, '../models/enums.dart')!.path,
        endsWith('lib/src/models/enums.dart'),
        reason: 'the resolved file must be the one that exists on disk.');

    // And the census as a whole must still land on real files: if resolution
    // breaks, this is where it shows, because a broken resolver either throws
    // (the StateError above) or silently counts a much smaller graph.
    var resolvedInternal = 0;
    for (final f in _dartFilesIn(Directory('lib/src'))) {
      for (final imp in _importsIn(f)) {
        if (imp.startsWith('dart:') || imp.startsWith('package:')) continue;
        if (_resolveImport(f, imp) != null) resolvedInternal++;
      }
    }
    expect(resolvedInternal, greaterThanOrEqualTo(557),
        reason: 'lib/src currently holds 557 app-internal imports, every one '
            'of which resolves to a file that exists. A smaller number means '
            'the scanner is dropping edges, and a dropped edge is '
            'indistinguishable from a clean graph.');
    expect(_dartFilesIn(Directory('lib/src')).length, greaterThanOrEqualTo(130),
        reason: '130 Dart files across 5 layers today; the walk must be '
            'recursive or it silently misses core/format/, the one directory '
            'held to the strict leaf rule.');
  });

  test('every upward edge in the app is one of the known, deliberate ones', () {
    // The whole graph, diffed against a baseline rather than asserted empty.
    //
    // An empty expectation would be the wrong guard: 12 upward edges exist
    // today and every one is deliberate. The contract is therefore not "none"
    // but "no *new* one" — a 14th fails and names itself, so the list stays a
    // list someone actually maintains.
    const rank = <String, int>{
      'core': 0,
      'models': 1,
      'data': 2,
      'widgets': 3,
      'screens': 4,
    };

    /// `layer/relative/path.dart -> the import as written`
    String label(File f, String spec) {
      final rel = f.path.substring('lib/src/'.length);
      return '$rel -> $spec';
    }

    final offenders = <String>[];
    for (final f in _dartFilesIn(Directory('lib/src'))) {
      final rel = f.path.substring('lib/src/'.length);
      final from = rel.split('/').first;
      if (!rank.containsKey(from)) continue;
      for (final imp in _importsIn(f)) {
        final target = _resolveImport(f, imp);
        if (target == null) continue;
        final to = _layerOf(target.path);
        if (to == null || !rank.containsKey(to)) continue;
        if (rank[to]! > rank[from]!) offenders.add(label(f, imp));
      }
    }
    offenders.sort();

    expect(_knownUpward, hasLength(12),
        reason: 'the baseline itself is wrong — recount before trusting the '
            'diff below.');
    expect(offenders, _knownUpward,
        reason: 'the layer graph grew an edge that nobody recorded.\n'
            'Each line is `file -> import`. If the new edge is deliberate, add '
            'it to _knownUpward with a comment saying why; if it is not, it is '
            'an inversion — the fix is to move the logic down, not to extend '
            'this list.');
  });
}
