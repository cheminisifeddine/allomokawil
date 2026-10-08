// The control-outline contract: every tappable boundary in the app is drawn at
// `AppTheme.hairline`, and nothing types the number any more.
//
// Why a test and not a review: `1.5` was a bare literal in **eight** widgets
// and one theme, all meaning "the edge of something you can tap". Nobody owned
// it, so the outline could drift per-widget and nothing would notice — and the
// two hand-built buttons in `big_button.dart`/`ui.dart` already disagreed with
// the theme they sit beside in a way no reviewer would catch by eye.
//
// The census is the guard that would have caught it: a new widget that hardcodes
// a border width fails here. It reads `lib/` from disk rather than importing
// the widgets, because the failure it exists to catch is a widget that does
// *not* name the token — there is nothing to import in that case.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';

/// The constructors that take a **border** width.
const _borderConstructors = <String>['Border.all', 'BorderSide'];

/// The borders that are deliberately **not** control outlines, with the reason
/// each keeps its own width. Listed rather than left to a heuristic: an earlier
/// version of this guard demanded every border in the app equal `hairline` and
/// flagged the focused-field ring and the tab-bar divider along with it, which
/// is the kind of failure that gets a guard switched off rather than fixed.
///
/// Each key is the *file* plus the width that is allowed to stay raw there —
/// not a line number, because line numbers rot on every edit above them, and a
/// guard whose excuse stops matching after an unrelated commit is a guard that
/// gets deleted. A key here is a decision someone agreed to, not a hole.
const _deliberateRawWidths = <String, Set<String>>{
  // Focus rings. 2 is what separates "I am typing here" from a resting field,
  // and it is deliberately *not* the outline thickness.
  'lib/src/core/theme/app_theme.dart': {'2'},
  'lib/src/screens/auth/auth_screen.dart': {'2'},
  // The 1 dp divider the tab bar floats on — a hairline would vanish into the
  // surface it separates. And the 4 dp ring lifting the middle button off it.
  'lib/src/widgets/app_tab_bar.dart': {'1', '4'},
};

/// Every raw border width under [root], as (file, line, label, value).
///
/// [value] is **null** when the width is not a plain literal but an expression —
/// `width: selected ? 2 : 1`. Those are the ones this guard originally could not
/// see at all, and they were the majority in `lib/`: six sites picked between
/// two hand-typed numbers. A regex that only matches `width: <number>` reports
/// such a tree clean, which is worse than having no guard, because it is read as
/// evidence. A conditional width is reported so the author names the token.
List<({
    String file,
    int line,
    String label,
    String source,
    Width kind,
    double? value
  })> _rawBorderWidths(List<File> files) {
  final hits = <({
    String file,
    int line,
    String label,
    String source,
    Width kind,
    double? value
  })>[];

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      // Scan a window rather than one line: `dart format` puts `Border.all(`
      // on one line and `width:` on the next the moment the call is a little
      // too long, and **that is the shape this repo's own formatter produced
      // for five of the writers this guard exists for**. A line-at-a-time
      // scanner went green on a tree that contained a raw `1.2` written
      // exactly that way, so the window is not defensive coding — it is the
      // case that actually occurs.
      final window =
          lines.sublist(i, (i + 4).clamp(0, lines.length).toInt()).join(' ');
      final first = lines[i].trimLeft();
      if (first.startsWith('//') || first.startsWith('*')) continue;

      // `borderWidth:` — BoxDecoration's own name, unambiguous on its own.
      // The value is `(?:const\s*)?(EXPR)` where EXPR is a literal **or** any
      // expression up to the comma that ends the argument. That second
      // alternative is the whole fix: `borderWidth: (focused || error != null)
      // ? 1.8 : 1` in `phone_field.dart` is a raw width the old guard skipped.
      for (final m in _namedArg.allMatches(window)) {
        if (m.group(1) != 'borderWidth') continue;
        hits.add(_hit(file.path, i + 1, 'borderWidth: ${m.group(2)!}',
            m.group(2)!));
      }

      // `width:` only *inside* a border constructor's argument list.
      for (final name in _borderConstructors) {
        final at = window.indexOf(name);
        if (at < 0) continue;
        final open = window.indexOf('(', at);
        if (open < 0) continue;
        final args = _argsFrom(window, open);
        for (final m in _namedArg.allMatches(args)) {
          if (m.group(1) != 'width') continue;
          hits.add(_hit(file.path, i + 1, '$name(width: ${m.group(2)!})',
              m.group(2)!));
        }
      }
    }
  }
  // The window scan sees the same constructor once per line it spans, so one
  // call is reported up to four times. Dedupe on (file, label, value) and keep
  // the *first* line the call was seen on, which is the line the constructor
  // name is on — the line a reader needs to jump to.
  final seen = <String,
      ({
        String file,
        int line,
        String label,
        String source,
        Width kind,
        double? value
      })>{};
  for (final hit in hits) {
    seen.putIfAbsent('${hit.file}|${hit.label}|${hit.value}', () => hit);
  }
  final unique = seen.values.toList()
    ..sort((a, b) {
      final byFile = a.file.compareTo(b.file);
      return byFile != 0 ? byFile : a.line.compareTo(b.line);
    });
  return unique;
}

/// A named argument `name: value`, where the value is everything up to the
/// next comma.
///
/// The value deliberately allows any characters — that is what turns
/// `width: selected ? 2 : 1` from invisible into a reported hit. A previous
/// version of this regex was `(\d+(?:\.\d+)?)`, which matched only bare
/// numbers, and the suite stayed 4/4 green on a tree holding six of them.
///
/// Nesting is *not* tracked here, and that is a real limit rather than a
/// shortcut: `Border.all(color: c, width: AppTheme.hairline)` yields a value of
/// `AppTheme.hairline` and is fine, but a ternary whose branches contain commas
/// (`width: a ? f(1, 2) : 1`) truncates at the inner comma. That truncation makes
/// the guard *over*-report, never under-report, which is the safe direction —
/// the cost is a manual allowlist entry, not a missed defect. Trimming that
/// false positive would mean a depth-tracking scan, and this file is worth more
/// as a net than as a parser.
final _namedArg = RegExp(r'(\w+)\s*:\s*([^,]*)');

/// What a width argument *is*, as opposed to what it evaluates to.
///
/// Three states, and the middle one is the reason this is a record and not a
/// `double?`: `width: AppTheme.hairline` and `width: selected ? 2 : 1` are both
/// "not a bare number", but the first is the token this guard exists to enforce
/// and the second is exactly the defect it must catch. A nullable double cannot
/// tell them apart and would have flagged every correct site in the app.
enum Width {
  /// A bare number typed at the call site.
  literal,

  /// A reference to [AppTheme.hairline] (optionally `const`).
  token,

  /// An expression with no digits — `cardLineWidth`, `borderWidth ??
  /// fieldLineWidth`. Names tokens, so it cannot go stale silently.
  named,

  /// An expression that hand-types at least one number — `selected ? 2 : 1`.
  /// The defect, and the one the first version of this guard could not see.
  raw,
}

/// Classifies a width argument.
///
/// The rule that carries the weight: **a width is raw exactly when it contains a
/// digit.** Anything that names a token — `AppTheme.hairline`, `cardLineWidth`,
/// a parameter forwarded by the caller — passes whatever shape it is written in,
/// because the value lives in one place and cannot drift per widget. Anything
/// that spells out a number is the defect, however it is spelled.
///
/// Keying on "has a digit" rather than on a syntax list is what lets the two
/// honest families through without an allowlist entry each. An earlier draft
/// allowed only `hairline` by name and reported `borderWidth ?? cardLineWidth`
/// as an offender, which would have meant allowlisting the theme's own
/// parameters — a net that closes behind itself.
Width _classify(String text) {
  final t = text.trim();
  final m = RegExp(r'^(?:const\s+)?(\d+(?:\.\d+)?)$').firstMatch(t);
  if (m != null) return Width.literal;
  if (RegExp(r'^(?:const\s+)?(?:AppTheme\.)?hairline$').hasMatch(t)) {
    return Width.token;
  }
  return RegExp(r'\d').hasMatch(t) ? Width.raw : Width.named;
}

/// The double [text] is, or null if it is not a plain number.
///
/// Null means "not a bare number" — see [_classify] for which of the two
/// non-literal cases this is. Kept separate so callers that only care about
/// allowlisting (which is keyed on a concrete width) can ignore the rest.
double? _literal(String text) {
  final m = RegExp(r'^(?:const\s+)?(\d+(?:\.\d+)?)$').firstMatch(text.trim());
  return m == null ? null : double.parse(m.group(1)!);
}

/// Builds one hit from the raw source text of the argument, classifying it once
/// here so the two consumers below never re-parse it.
({String file, int line, String label, String source, Width kind, double? value})
    _hit(String file, int line, String label, String source) {
  final kind = _classify(source);
  return (
    file: file,
    line: line,
    label: label,
    source: source.trim(),
    kind: kind,
    value: kind == Width.literal ? _literal(source) : null,
  );
}

/// The argument list starting at the `(` at [openParenIndex], by counting
/// parentheses — these calls nest, and a regex that stops at the first `)`
/// grades the tail of a nested call as outside the border.
String _argsFrom(String text, int openParenIndex) {
  var depth = 0;
  for (var i = openParenIndex; i < text.length; i++) {
    final c = text[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return text.substring(openParenIndex + 1, i);
    }
  }
  return text.substring(openParenIndex + 1);
}

void main() {
  group('AppTheme.hairline', () {
    test('is 1.5 — the outline that separates a control from its card', () {
      // Pinned deliberately: this is the *reason* the token exists, so a
      // well-meaning "1 is fine, it looks cleaner" edit has to be a conscious
      // change to this line and not a quiet edit to a widget.
      expect(AppTheme.hairline, 1.5);
    });

    test('no tappable control types a raw border width any more', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final offenders = <String>[];
      for (final hit in _rawBorderWidths(files)) {
        // `token` and `named` both mean "the number lives in one place".
        if (hit.kind != Width.literal && hit.kind != Width.raw) continue;
        // A literal that happens to equal the token passes — it is correct, just
        // not named. An *expression* (`selected ? 2 : 1`) can never be
        // allowlisted: the point is that the author names the token instead of
        // typing whichever branch applies, so there is no width to key on.
        final v = hit.value;
        final allowed = v == null ? null : _deliberateRawWidths[hit.file];
        if (v != null && v == AppTheme.hairline) continue;
        if (allowed != null && allowed.contains(_num(v!))) continue;
        offenders.add('${hit.file}:${hit.line}  ${hit.label}');
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Name AppTheme.hairline instead of typing a border width '
            'on a tappable control. Legitimately-raw borders are listed in '
            '_deliberateRawWidths with a reason:\n${offenders.join('\n')}',
      );
    });

    test('the outline button theme draws its side at the token', () {
      // The one place the whole app inherits its outline from. If the theme
      // and the widgets disagree, every bare OutlinedButton is off-token while
      // the two hand-built buttons look right — the exact split this token
      // exists to close. Read the app's own theme: asserting against a theme
      // built here would pass even if the app's theme were wrong, which is the
      // same mistake as pinning the guard to a copy of the rule.
      final side = AppTheme.light.outlinedButtonTheme.style?.side;
      expect(side, isNotNull,
          reason: 'the outline button theme must define a side');
      // `resolve` is nullable per side: a theme may define the side as null and
      // let a variant supply it, so the empty-state answer is a real case.
      final resolved = side!.resolve(<WidgetState>{});
      expect(resolved, isNotNull);
      expect(resolved!.width, AppTheme.hairline);
    });

    test('a conditional width is judged by its digits, not its syntax', () {
      // The regression this guard needed and did not have. `_classify` is the
      // only thing between "a widget names a token" and "a widget typed a
      // number", and every case below was measured against it because reading
      // it is not the same as running it.
      //
      // The two that matter most are the last pair: they are the shape the app's
      // own theme uses, and an earlier draft of this guard reported both as
      // offenders — which would have pushed the theme's parameters into an
      // allowlist, i.e. a guard that fails on correct code.
      expect(_classify('1.5'), Width.literal);
      expect(_classify('1'), Width.literal);
      expect(_classify('const 2'), Width.literal);

      expect(_classify('AppTheme.hairline'), Width.token);
      expect(_classify('hairline'), Width.token);
      expect(_classify('const AppTheme.hairline'), Width.token);

      expect(_classify('cardLineWidth'), Width.named);
      expect(_classify('borderWidth ?? fieldLineWidth'), Width.named);

      expect(_classify('selected ? 2 : 1'), Width.raw);
      expect(_classify('unread ? 1.4 : 1'), Width.raw);
      expect(_classify('(focused || error != null) ? 1.8 : 1'), Width.raw);
    });

    test('an excuse nobody uses is a stale excuse', () {
      // Each allowlisted width is a decision, and an unused one means the line
      // moved or somebody reverted it to the token. Either way the list is
      // wrong now, and a guard that quietly keeps a dead entry is how the next
      // real offender walks past it.
      final used = <String, Set<String>>{};
      for (final hit in _rawBorderWidths(Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList())) {
        final v = hit.value;
        if (v == null) continue; // token/expression name no raw width
        (used[hit.file] ??= <String>{}).add(_num(v));
      }
      final stale = <String>[];
      _deliberateRawWidths.forEach((file, widths) {
        for (final w in widths) {
          if (!(used[file]?.contains(w) ?? false)) {
            stale.add('$file — width $w is allowlisted but no longer written');
          }
        }
      });
      expect(stale, isEmpty, reason: stale.join('\n'));
    });
  });
}

/// "1.5" -> "1.5", "1" -> "1" — the allowlist is keyed on how it is written.
String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
