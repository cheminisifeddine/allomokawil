// The loop closed a **seam** census on 2 Oct 2026, and this file keeps it
// closed.
//
// Five ticks in a row found the same class of defect one screen at a time: a
// screen whose pixels depend on the wall clock, but which took no clock, so
// the label it drew was decided once and never re-evaluated. `chat_screen.dart`
// was the straggler (shipped `9821e3e`) — `chatDayLabel(at!)` with no `now:`,
// while the helper reached `DateTime.now()` inside itself. A user who opened a
// thread in the evening and came back in the morning saw **every** message
// stamped «اليوم».
//
// Every one of those fixes was made by hand, and this file is why the sixth
// cannot be made by accident. The rule is deliberately narrow, because a guard
// that bans a shape every correct screen already uses is a guard that gets
// deleted:
//
//   * **Injected-clock helpers.** Any top-level function taking
//     `{DateTime? now}` answers "how stale is this" relative to a clock it was
//     *handed*. On a screen that can age its own readings — and every one of
//     them now carries a once-a-minute timer — the default arm reaches the real
//     wall clock inside the helper, so the string is fixed at build time. The
//     seam exists for exactly this; a call that leaves it unused renders a
//     frozen label.
//   * **Wall-clock getters on the model.** `SubscriptionStatus` keeps
//     `daysUntilExpiry`, `expiryCountdownAr` and `isExpired` as no-argument
//     getters for code that has no clock of its own. Their `*At(clock)`
//     siblings are what a rendering surface must use.
//
// The family list is **derived from the source**, not hardcoded, for the same
// reason `no_empty_text_site_test.dart` keeps its own list honest: a guard that
// only knows about functions it has already met goes quietly blind the moment
// the app grows a new one. Deriving it here means a helper the loop has not
// met yet is covered automatically — and if the derivation ever breaks, the
// first case fails loudly instead of the sweep passing vacuously.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/read_age_ar.dart';

/// Every Dart file the app ships, **including `lib/main.dart`**.
///
/// This was `Directory('lib/src')`, which is a statement about where screens
/// live rather than a fact about where the app's code is. `lib/main.dart` sits
/// beside `lib/src/`, not inside it, so the sweep could not see the entry
/// point — and the entry point is where the app wires everything. Planting a
/// `ScaffoldMessenger` call there left this file green (verified: 21/21 across
/// the four `lib/src`-scoped sweeps). See `app_source_scope_test.dart`.
List<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// The parenthesised argument list starting at the `(` at [start], braces
/// excluded.
String _args(String src, int start) {
  var depth = 0;
  for (var i = start; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') {
      depth--;
      if (depth == 0) return src.substring(start + 1, i);
    }
  }
  return '';
}

/// The body of the function whose name occurs at [at] — brace-matched for a
/// block body, and to the semicolon for the `=> expr;` form, because a third
/// of this family is written that way and a body extractor that only
/// understands braces reads them as empty and passes them for free.
String _body(String src, int at) {
  final params = src.indexOf('(', at);
  var depth = 0;
  var close = params;
  for (var i = params; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')') {
      depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
  }
  var i = close + 1;
  while (i < src.length && (src[i] == ' ' || src[i] == '\n')) {
    i++;
  }
  if (src.startsWith('=>', i)) {
    final end = src.indexOf(';', i);
    return src.substring(i, end < 0 ? src.length : end);
  }
  if (src[i] != '{') return '';
  depth = 0;
  for (var j = i; j < src.length; j++) {
    if (src[j] == '{') depth++;
    if (src[j] == '}') {
      depth--;
      if (depth == 0) return src.substring(i + 1, j);
    }
  }
  return '';
}

/// True when [body] calls [callee] **and hands it a clock**. The argument
/// matters: `staleXAgeAr(readAt, now: now)` forwards the seam, and
/// `staleXAgeAr(readAt)` does not — one of them routes to the wall clock and
/// the other hands the question on unanswered.
bool _forwards(String body, String callee) {
  for (final m
      in RegExp('(?<![\\w.])${RegExp.escape(callee)}\\s*\\(').allMatches(body)) {
    if (RegExp(r'\bnow\s*:').hasMatch(_args(body, m.end - 1))) return true;
  }
  return false;
}

/// True for a line that is only a comment — a helper named in prose is not a
/// call site, and this file has to read the comments it lives next to.
bool _commented(String line) => line.trimLeft().startsWith('//');

/// Every top-level function in [src] whose parameter list carries the
/// `{DateTime? now}` seam, mapped name -> byte offset of the name in [src].
///
/// Returns the offset too because the declaration is syntactically
/// indistinguishable from a call — `readAgeAr(readAt, {DateTime? now})` opens
/// exactly like `readAgeAr(a, b)` — and treating it as a call reported all
/// nineteen functions as offenders on the first run of this file.
Map<String, int> _seamFunctions(String src) {
  final found = <String, int>{};
  for (final m in RegExp(r'^(?:String|bool|int)\s+(\w+)\s*\(', multiLine: true)
      .allMatches(src)) {
    final name = m.group(1)!;
    final args = _args(src, src.indexOf('(', m.start));
    if (RegExp(r'\{\s*DateTime\? now,?\s*\}').hasMatch(args)) {
      found[name] = src.indexOf(name, m.start);
    }
  }
  return found;
}

void main() {
  test('the seam is honest end to end: every member reaches the wall clock',
      () {
    final members = <String, String>{};
    final offsets = <String, int>{};
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      _seamFunctions(src).forEach((name, at) {
        members[name] = f.path;
        offsets[name] = at;
      });
    }

    // The vacuity check. If the regex ever stops matching, every sweep below
    // passes having checked nothing — the shape of a detector that certifies a
    // broken detector. Nineteen on 2 Oct 2026.
    expect(members.length, greaterThanOrEqualTo(19),
        reason: 'the injected-clock family collapsed from 19 to '
            '${members.length}; every sweep below is about to pass '
            'vacuously.\nPresent: ${members.keys.toList()..sort()}');

    // Membership is transitive, and this is the case that earned it. Four
    // helpers read the clock themselves: `chatDayLabel`, `readAgeAr`,
    // `relativeTimeAr` and `statsAreStale`. The other fifteen do **not** — they
    // forward `now:` to one of those four, which is why a first version of
    // this file asserted "every member reads the wall clock" and failed on all
    // fifteen. The rule it *meant* is one hop stronger, and worth more: a
    // function that takes a clock, ignores it, and forwards nothing is a seam
    // that lies — a caller passes `now:`, gets a confident answer, and the
    // answer came from the real clock regardless. That is precisely the defect
    // this family was built to prevent, wearing the costume of the fix.
    final sources = <String, String>{
      for (final f in _sources()) f.path: f.readAsStringSync()
    };
    final reachesClock = <String, bool>{};

    bool reaches(String name, Set<String> seen) {
      final cached = reachesClock[name];
      if (cached != null) return cached;
      if (!seen.add(name)) return false; // a cycle proves nothing by itself
      final src = sources[members[name]]!;
      final at = offsets[name]!;
      final body = _body(src, at);
      final direct =
          body.contains('DateTime.now()') || body.contains('now ??');
      final result = direct ||
          members.keys
              .where((other) => other != name)
              .any((other) =>
                  _forwards(body, other) && reaches(other, seen));
      return reachesClock[name] = result;
    }

    final dishonest = members.keys
        .where((name) => !reaches(name, <String>{}))
        .toList()
      ..sort();
    expect(dishonest, isEmpty,
        reason: 'a helper takes `{DateTime? now}` but neither falls back to '
            'the wall clock nor forwards the clock to a helper that does, so '
            'passing `now:` to it changes nothing:\n$dishonest');
  });

  test('no screen calls an injected-clock helper without passing a clock',
      () {
    // The census this file encodes. Answer on 2 Oct 2026: **zero**, across
    // nineteen helpers and nine rendering screens. It is worth a guard
    // precisely because the answer was zero — a clean result is exactly what
    // a later edit erases without anyone noticing.
    final seamNames = <String>{};
    final declarations = <String, Set<int>>{};
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      final seams = _seamFunctions(src);
      seamNames.addAll(seams.keys);
      declarations[f.path] = seams.values.toSet();
    }

    final offenders = <String>[];
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      final declared = declarations[f.path]!;
      for (final m in RegExp(r'(?<![\w.])(\w+)\s*\(').allMatches(src)) {
        final name = m.group(1)!;
        if (!seamNames.contains(name)) continue;
        if (declared.contains(m.start)) continue; // the declaration
        final line = src.substring(0, m.start).split('\n').length;
        if (_commented(lines[line - 1])) continue;
        if (!RegExp(r'\bnow\s*:').hasMatch(_args(src, m.end - 1))) {
          offenders.add('${f.path}:$line  ${lines[line - 1].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a screen calls an injected-clock helper without passing a '
            'clock. The helper falls back to DateTime.now() inside its own '
            'body, so the label is decided once and never aged:\n'
            '${offenders.join('\n')}');
  });

  test('no screen reads the model\'s wall-clock getters', () {
    // The other half of the census, and the one the previous tick asked for
    // by name. Kept separate because the answer is zero *for a different
    // reason*: these three have no parameter to omit, so a call site cannot be
    // repaired by adding an argument, and this sweep cannot drift with the
    // signature of a helper that does not exist yet.
    const getters = <String>[
      'daysUntilExpiry',
      'expiryCountdownAr',
      'isExpired',
    ];
    final pattern = RegExp('\\.(${getters.join('|')})\\b(?!\\s*At)');

    final offenders = <String>[];
    for (final f in _sources()) {
      // The definitions themselves, and the doc comments that explain why the
      // `*At` form is preferred, both live here.
      if (f.path == 'lib/src/models/plan.dart') continue;
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      for (final m in pattern.allMatches(src)) {
        final line = src.substring(0, m.start).split('\n').length;
        if (_commented(lines[line - 1])) continue;
        offenders.add('${f.path}:$line  ${lines[line - 1].trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a screen asks SubscriptionStatus for a date answer against '
            'the wall clock instead of against a clock it was handed; the '
            'count and the rendered label can then disagree on one screen:\n'
            '${offenders.join('\n')}');
  });

  test('the seam is real — one payload, two clocks, two answers', () {
    // Positive control, and the reason the sweeps above mean anything. If the
    // helpers ignored `now` altogether, all three would pass for free.
    //
    // `readAgeAr` is the root: all eight `stale_*AgeAr` functions delegate to
    // it, so one divergence here means every member inherits it.
    final read = DateTime(2026, 9, 28, 11, 30);
    expect(readAgeAr(read, now: DateTime(2026, 9, 29, 12)), 'أمس');
    expect(readAgeAr(read, now: DateTime(2026, 9, 26, 9)), isNot('أمس'));
  });

  _testOmissions();
}

// ---------------------------------------------------------------------------
// The direction the family can still rot in, closed 2 Oct 2026 (2nd tick).
//
// The sweep above asks the question about **`lib/`**: does a screen pass a
// clock it was handed? The answer is zero, and it is enforced.
//
// This asks the question about **`test/`**, and the two are not the same
// check. A test that holds a fake clock and then calls a seam helper *without*
// it is a test computing its quantity against the real machine's date — which
// is not a flaky test, it is a *silently different* one: it passed on the day
// it was written and will keep passing until the wall clock crosses the
// fixture. `stats_freshness_test.dart` held exactly that, at line 319, in a
// form that read as correct: `statsAreStale(now)` handed the screen's *current*
// clock to the **`readAt`** slot and let the function reach the real one. It
// asserted `isTrue` and got `true` from a 5-day difference instead of the
// 65 minutes it meant. Nothing was red; the answer was simply about a
// different interval than the test claimed.
//
// So the rule is not "pass `now:`". It is narrower, and derived: a call that
// omits the seam **in a test that holds an injected clock** is the defect
// shape. Both halves are discovered from the source, so a helper or a fixture
// written after this file is covered without editing it.
void _testOmissions() {
  final seamNames = <String>{};
  for (final f in _sources()) {
    seamNames.addAll(_seamFunctions(f.readAsStringSync()).keys);
  }

  // The 19 minus the seven whose first positional parameter is a `String`:
  // `staleXLineWithAgeAr(String error, ...)` has no stamp to date, so omitting
  // a clock on it is not a defect and banning it would be a guard that gets
  // deleted. Derived, not hardcoded, so a new `...LineWithAgeAr` is recognised
  // by its shape rather than by being added to a list here.
  final dateArity = <String>{};
  for (final f in _sources()) {
    final src = f.readAsStringSync();
    _seamFunctions(src).forEach((name, at) {
      final first = _args(src, src.indexOf('(', at)).split(',').first.trim();
      if (first.startsWith('DateTime')) dateArity.add(name);
    });
  }

  test('a test that holds a fake clock does not drop it at a seam call site',
      () {
    // The floor is **11, not 12**, and the gap is deliberate: one member being
    // reshaped away from a date is the ordinary consequence of adding a
    // `...LineWithAgeAr`-shaped helper, and a guard that goes red for it gets
    // deleted on the next ordinary change. A *collapse* — four of them at once
    // — still lands under it and was verified red before this line shipped.
    expect(dateArity.length, greaterThanOrEqualTo(11),
        reason: 'the dated arm of the family fell from 12 to ${dateArity.length}; '
            'the sweep below is about to pass vacuously.\n'
            'Present: ${(dateArity.toList()..sort()).join(', ')}');

    final offenders = <String>[];
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      // A file that holds a clock at all: `clock: () => x`, `now: () => x`, or
      // a `var now = …` it mutates. Without one, an omission is a *unit* test
      // of the default arm, which `read_age_ar_test.dart` asserts on purpose.
      final holds = RegExp(r'(?:clock|now|at)\s*:\s*\(\)\s*=>').hasMatch(src) ||
          RegExp(r'\bvar\s+(?:now|_now|frozen)\s*=').hasMatch(src);
      if (!holds) continue;
      for (final m in RegExp(r'(?<![\w.])(\w+)\s*\(').allMatches(src)) {
        final name = m.group(1)!;
        if (!dateArity.contains(name)) continue;
        final line = src.substring(0, m.start).split('\n').length;
        if (_commented(lines[line - 1])) continue;
        if (!RegExp(r'\bnow\s*:').hasMatch(_args(src, m.end - 1))) {
          offenders.add('${f.path}:$line  ${lines[line - 1].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'this test injects a clock into its widget and then calls a '
            'seam helper without it, so the assertion is computed against the '
            "real machine's date rather than the fixture's:\n"
            '${offenders.join('\n')}');
  });
}
