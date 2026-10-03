/// Reading another file's source for a rule that may not span one line.
///
/// **The defect this file exists to stop, proven on 3 Oct (26th).** The motion
/// rule -- "no screen types its own duration or curve" -- was enforced by
/// `motion_test.dart` *line by line*: `readAsLinesSync()`, then
/// `typedDuration.hasMatch(lines[i])`. Its regex is
/// `duration:\s*(?:const\s+)?Duration(`, and `\s` matches a newline, so the
/// pattern is written to span a line break. Applied per line it can never
/// match one. A screen therefore got past the rule by typing
///
/// ```dart
/// duration:
///     const Duration(milliseconds: 777),
/// ```
///
/// which is **not** a dodge anyone had to reach for: it is exactly what
/// `dart format` produces at its 80-column break, 51 argument labels in this
/// tree already sit alone on a line for that reason, and nothing in CI runs
/// `dart format` (`.github/workflows/android-release.yml` runs pub get, analyze,
/// test, then builds). Verified by planting both shapes with the rule
/// untouched:
///
///   * `duration: const Duration(milliseconds: 777),` on one line -> the guard
///     fires, naming `lib/src/widgets/category_grid.dart:74`;
///   * the same call wrapped across two lines -> `+14 All tests passed!`.
///
/// A rule that cannot see its own subject is worse than no rule, because
/// `app_source_scope_test.dart`'s `_ruleEvidence` still listed
/// `duration:\s*(?:const\s+)?Duration\(` as the literal that guard must carry:
/// the map proved the rule was **present** in the file and had no way to know
/// it was applied at a granularity that cannot match it.
///
/// So the scan unit is part of the rule. [offendingLines] matches over the
/// whole comment-blanked file, which is the granularity every whole-file token
/// in `_ruleEvidence` is written at, and reports the **line the match starts
/// on** so the failure still reads like a compiler diagnostic rather than a
/// byte offset.
///
/// [blankComments] blanks comments and strings **preserving every offset** --
/// it replaces comment and string bytes with spaces and keeps every newline --
/// so an offset found in [blankComments] output addresses the same position in
/// the original file. It was extracted from `app_source_scope_test.dart`
/// verbatim rather than copied: that reader had already been bitten once by
/// prose shadowing code (`_rootsOf` read the old root out of the doc comment
/// explaining the very fix), and two readers of "the code, not the prose"
/// that disagree is the defect this repository keeps re-learning.
library;

/// Replaces every comment in [src] with spaces, keeping `\n` in place so
/// **offsets and line numbers are unchanged**.
///
/// A guard that only *talks* about a rule in a doc comment is not enforcing
/// it, and this tree documents the motion rule at length in three files. A
/// reader that counted prose would either report those as offenders or force
/// the prose out of the code; both outcomes are worse than the rule.
///
/// [blankStrings] decides whether a string body survives, and the answer is
/// not the same for every reader:
///
///   * **true** (the motion rule) -- an Arabic string holding `Duration(` is
///     copy a user reads, not an animation, so it must not be an offender.
///   * **false** (`app_source_scope_test.dart`) -- the thing being read *is* a
///     string literal: a guard's root is written `Directory('lib')`, and
///     blanking the body would erase the very directory the census reports.
///
/// One implementation with a flag, rather than two readers of "the code, not
/// the prose" that can drift apart -- which is the defect this repository has
/// now paid for twice (`_rootsOf` reading a root out of the comment explaining
/// the fix, and the per-line motion scan missing a wrapped duration).
String blankComments(String src, {bool blankStrings = true}) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    // A raw string's `r` is not a comment start and not a quote, so step over
    // the marker and let the string branch below walk the body.
    final isRaw = (c == 'r' || c == 'R') &&
        i + 1 < n &&
        (src[i + 1] == "'" || src[i + 1] == '"') &&
        !(i > 0 && _isIdentChar(src[i - 1]));
    if (isRaw) {
      out.write(src[i]);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < n && src[i + 1] == '/') {
      while (i < n && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && src[i + 1] == '*') {
      out.write('  ');
      i += 2;
      var depth = 1;
      while (i < n && depth > 0) {
        if (src.startsWith('/*', i)) {
          out.write('  ');
          i += 2;
          depth++;
        } else if (src.startsWith('*/', i)) {
          out.write('  ');
          i += 2;
          depth--;
        } else {
          out.write(src[i] == '\n' ? '\n' : ' ');
          i++;
        }
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final triple = src.startsWith(c * 3, i);
      final term = c * (triple ? 3 : 1);
      // Only the delimiter goes through verbatim; the body is either kept (the
      // census reads `Directory('lib')` *out of* a string) or blanked to a
      // space of its own length, so an offset never moves.
      out.write(term);
      i += term.length;
      while (i < n) {
        if (src.startsWith(term, i)) {
          out.write(term);
          i += term.length;
          break;
        }
        final bool isNewline = src[i] == '\n';
        if (!triple && isNewline) break; // unterminated: do not run away
        if (src[i] == r'\' && !isRaw) {
          // An escape is two characters and must be skipped as a unit or the
          // quote after it would be read as the end of the string. Both bytes
          // are written so the length -- and therefore every offset after it --
          // is identical either way.
          out.write(blankStrings && src[i] != '\n' ? ' ' : src[i]);
          i++;
          if (i < n) {
            out.write(src[i] == '\n' ? '\n' : (blankStrings ? ' ' : src[i]));
            i++;
          }
          continue;
        }
        out.write(isNewline ? '\n' : (blankStrings ? ' ' : src[i]));
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

bool _isIdentChar(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || // 0-9
      (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      code == 0x5F || // _
      code == 0x24; // $
}

/// The 1-based line [offset] falls on, counting `\n` in [code].
///
/// Safe to call on [blankComments] output because that reader preserves
/// offsets, so the line is the line in the file the caller read.
int lineAt(String code, int offset) =>
    '\n'.allMatches(code.substring(0, offset)).length + 1;

/// One place in [source] where a rule matched.
class RuleHit {
  const RuleHit(this.line, this.text);

  /// The 1-based line the match **starts** on.
  final int line;

  /// That line's own text, from the file as written (not the blanked copy).
  final String text;

  @override
  String toString() => '$line: $text';
}

/// Every place in [source] where one of [rules] matches, in file order.
///
/// The scan unit is the **whole file**, not a line. A rule whose pattern can
/// match across a newline -- and most rules that read named arguments can,
/// because the label and its value are routinely separated by the formatter
/// -- is otherwise enforceable only in the one shape that keeps them together,
/// which is the shape that stops existing the moment the line grows.
///
/// Matched over [blankComments] output, so a rule quoted in a doc comment or
/// held inside an Arabic string cannot make the guard report itself. A match
/// spanning several lines is reported **once**, on the line it starts on: the
/// label is what a reader greps for, and counting the wrapped value as two
/// more hits would report one mistake three times.
List<RuleHit> ruleHits(String source, List<RegExp> rules) {
  final code = blankComments(source);
  final textLines = source.split('\n');
  final hitLines = <int>{};
  for (final rule in rules) {
    for (final m in rule.allMatches(code)) {
      hitLines.add(lineAt(code, m.start));
    }
  }
  final sorted = hitLines.toList()..sort();
  return [
    for (final line in sorted) RuleHit(line, textLines[line - 1].trim()),
  ];
}

/// [ruleHits] as `<line>: <text>` strings, for a failure message.
List<String> offendingLines(String source, List<RegExp> rules) =>
    ruleHits(source, rules).map((RuleHit h) => h.toString()).toList();
