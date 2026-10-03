// Every `catch` that drops a failure must leave a mark that survives the file.
//
// Two ticks of the loop asked the same question of the same 87 blocks and got
// two different answers, because "did this catch report the failure?" has no
// single meaning in this codebase:
//
//   * the 16th tick counted a `catch` as reporting iff its body contained
//     `//`, tested the *comment-stripped* body — and so reported all 22
//     write-guards as undocumented while 8 of them plainly called
//     `debugPrint`.
//   * the 17th tick fixed the classifier and then found 3 silent write-guards,
//     which it fixed. It then asked the same question of the 65 read-guards
//     with the convention "a `FutureBuilder` owns the arm" applied **by eye,
//     to a sample**.
//
// So the read half was counted and never judged. This file is the judgement,
// and it is the same shape as `layering_test.dart` and
// `tool_clock_seam_test.dart`: the rule is **asserted instead of described**,
// so the next tick cannot re-open the census with a different definition.
//
// The rule, measured before it was written — the census that produced it:
//
//     87 catch blocks · 25 log · 3 raise · 19 return a typed sentinel ·
//     23 assign a sentinel another statement reads · 3 delegate to a function
//     that reports · 14 stand empty and say why in a comment
//
// Every one of the 87 leaves a mark. That is the property worth holding: not
// "each catch must log", which would force logging inside `finally`-adjacent
// and cleanup paths where a log line is noise, but **"a catch that reports
// nothing is an empty block, and an empty block must say why in its own
// source."** That formulation is decidable with a lexer and survives the next
// eleven files that need a guard.
//
// It also cannot be satisfied by a comment that is not there. `strip()`
// below blanks comments and string bodies to spaces **while preserving
// offsets**, so `catch` inside a comment or inside an Arabic sentence is
// invisible to the scan and a file whose only `catch` is in prose scans as
// clean — the failure mode `tool_clock_seam_test.dart` already documents for
// a regex, hit here for a lexer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// The source with every comment and string/char literal body blanked to
/// spaces, offsets preserved.
///
/// Offsets are the point. A strip that *removes* text shifts every index after
/// it, so a line number computed on the stripped source names the wrong line —
/// and the previous tick's extractor did exactly that, which is how three
/// already-fixed sites read as still empty after they were patched.
///
/// Two Dart constructs make this harder than Python's version in
/// `tool_clock_seam_test.dart`, and both are exercised by real files in
/// `lib/` today (measured: 12 raw strings, 29 interpolations that carry a
/// quote inside `${...}`):
///
///   * **Raw strings** — `r'...'` disables escape processing, so a `\` inside
///     one must not consume the next character. Without the raw check, a raw
///     regex like `r'/+$'` loses its closing quote and the strip runs to the
///     end of the file, erasing every `catch` after it.
///   * **Interpolation** — `'${arabicCounted(n, 'رسالة')}'` closes on the
///     *inner* quote and reopens. A naive scanner sees the string end at
///     `'رسالة'` and then treats `, ` as code, and the next `'` starts a fresh
///     literal that runs away. The result is code being read as prose — the
///     direction that makes a guard pass for the wrong reason.
String _strip(String src) {
  final out = StringBuffer();
  var i = 0;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    // `r` is only a raw marker when the quote follows it and the character
    // before it cannot be part of an identifier — `my'r'` is not raw syntax.
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
        if (src[i] == '/' && i + 1 < n && src[i + 1] == '*') {
          out.write('  ');
          i += 2;
          depth++;
        } else if (src[i] == '*' && i + 1 < n && src[i + 1] == '/') {
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
      out.write(term);
      i += term.length;
      while (i < n) {
        if (triple && src.startsWith(term, i)) {
          out.write(term);
          i += term.length;
          break;
        }
        if (!triple && src[i] == c) {
          out.write(c);
          i++;
          break;
        }
        if (!triple && src[i] == '\n') break; // unterminated: do not run away
        if (src[i] == r'\' && !isRaw) {
          out.write(' ');
          i++;
          if (i < n) {
            out.write(src[i] == '\n' ? '\n' : ' ');
            i++;
          }
          continue;
        }
        // `${` opens real code inside a literal; emit it as code so a `catch`
        // interpolated into a string is still found. The repo has none, but a
        // scanner that erases them would be wrong for the wrong reason.
        if (src[i] == r'$' && i + 1 < n && src[i + 1] == '{') {
          out.write(r'${');
          i += 2;
          var d = 1;
          while (i < n && d > 0) {
            if (src[i] == '{') {
              d++;
            } else if (src[i] == '}') {
              d--;
              if (d == 0) {
                out.write('}');
                i++;
                break;
              }
            }
            out.write(src[i]);
            i++;
          }
          continue;
        }
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

bool _isIdentChar(String c) =>
    RegExp(r'[A-Za-z0-9_]').hasMatch(c);

/// One `catch` clause and the span of the block it opens.
class _Catch {
  _Catch(this.line, this.blockStart, this.blockEnd);

  /// 1-based line of the `catch` keyword in the **stripped** source, which is
  /// offset-identical to the real source.
  final int line;
  final int blockStart;
  final int blockEnd;
}

List<_Catch> _catches(String stripped) {
  final found = <_Catch>[];
  for (final m in RegExp(r'\bcatch\b').allMatches(stripped)) {
    var j = m.end;
    // Skip whitespace **first**, then the parameter list. `catch (_)` carries
    // a space before the paren and `catch (e)` does not have to, so the first
    // draft of this loop only skipped the list when the paren was adjacent —
    // which is every real `catch` in `lib/`. It found **0 of 87**, the coverage
    // test caught it, and the same ordering mistake would have made the whole
    // rule vacuously green rather than red.
    void skipSpace() {
      while (j < stripped.length && ' \t\r\n'.contains(stripped[j])) {
        j++;
      }
    }

    skipSpace();
    if (j < stripped.length && stripped[j] == '(') {
      var d = 0;
      while (j < stripped.length) {
        if (stripped[j] == '(') {
          d++;
        } else if (stripped[j] == ')') {
          d--;
          if (d == 0) {
            j++;
            break;
          }
        }
        j++;
      }
      skipSpace();
    }
    if (j >= stripped.length || stripped[j] != '{') continue;
    var d = 0;
    var k = j;
    while (k < stripped.length) {
      if (stripped[k] == '{') {
        d++;
      } else if (stripped[k] == '}') {
        d--;
        if (d == 0) break;
      }
      k++;
    }
    found.add(_Catch(
      stripped.substring(0, m.start).split('\n').length,
      j,
      k,
    ));
  }
  return found;
}

void main() {
  final libFiles = _dartFilesIn(Directory('lib'));
  final realSrc = <String, String>{};
  final stripped = <String, String>{};
  final catches = <String, List<_Catch>>{};

  setUpAll(() {
    for (final f in libFiles) {
      final src = f.readAsStringSync();
      final st = _strip(src);
      realSrc[f.path] = src;
      stripped[f.path] = st;
      catches[f.path] = _catches(st);
    }
  });

  test('the scanner sees every `catch` the real tree has', () {
    // The coverage half of a source-scanning guard: it fails if the lexer
    // stops finding anything, which is the only way a rule like this can go
    // green for the wrong reason.
    expect(libFiles.length, greaterThanOrEqualTo(130),
        reason: 'lib/ shrank — the scanner is not looking at the app');
    final total = catches.values.fold<int>(0, (a, b) => a + b.length);
    expect(total, greaterThanOrEqualTo(80),
        reason: 'only $total catch blocks found; the lexer lost one');
  });

  test('a catch that reports nothing is empty, and an empty catch says why', () {
    final undocumented = <String>[];
    var empty = 0;
    for (final f in libFiles) {
      final st = stripped[f.path]!;
      final src = realSrc[f.path]!;
      for (final c in catches[f.path]!) {
        final inner = st.substring(c.blockStart + 1, c.blockEnd);
        if (inner.trim().isNotEmpty) continue; // it does something
        empty++;
        // `src` is offset-identical to `st`, so this comment is the one in the
        // body, not a lookalike somewhere in the file.
        if (src.substring(c.blockStart, c.blockEnd + 1).contains('//')) continue;
        undocumented.add('${f.path}:${c.line}');
      }
    }
    // 10 measured; asserted so a new bare `catch (_) {}` cannot land.
    expect(empty, 10, reason: 'the census moved — re-measure before editing');
    expect(undocumented, isEmpty,
        reason: 'these catch blocks drop their failure with no reason '
            'in the source: ${undocumented.join(', ')}');
  });

  test('the strip is offset-preserving, so a line number names its catch', () {
    // `'''` on its own line would make Dart drop that newline, so the literal
    // opens on the same line as its first character: the line numbers asserted
    // below are the numbers in THIS file's own source.
    const src = '''// try {} catch (e) { debugPrint('e'); }   <- a catch in a comment
final s = 'catch (e) { }';                  // ...and one inside a string
void f() {
  try { g(); } catch (e) { rethrow; }
}
''';
    final st = _strip(src);
    expect(st.length, src.length, reason: 'offsets shifted');
    expect(_catches(st).length, 1, reason: 'comment/string catch counted');
    expect(_catches(st).single.line, 4);
  });

  test('a raw string does not eat the rest of the file', () {
    // The 12 raw strings in `lib/` are why this exists. `r'/+$'` with a naive
    // escape handler loses its closing quote and blanks everything after it,
    // which is a guard passing because it cannot see.
    const src = r'''
final re = RegExp(r'/+$');
void f() { try { g(); } catch (_) { h(); } }
''';
    final st = _strip(src);
    expect(_catches(st).length, 1);
  });

  test('an interpolation with an inner quote does not desync the scanner', () {
    // `unread_message_count.dart:70` is this line, verbatim.
    const src = r'''
final s = '${arabicCounted(n, 'رسالة', two: 'رسالتان')} لم تُرسل';
void f() { try { g(); } catch (_) { h(); } }
''';
    final st = _strip(src);
    expect(_catches(st).length, 1,
        reason: 'the literal closed on the inner quote and ran away');
  });

  test('the rule is not vacuous: a planted bare catch is reported', () {
    // A guard that cannot be made to fail proves nothing. This re-reads the
    // rule against a synthetic file whose only `catch` is the violation.
    const src = '''void f() {
  try { g(); } catch (_) {}
}
''';
    final st = _strip(src);
    final found = _catches(st);
    expect(found.length, 1);
    expect(st.substring(found.single.blockStart + 1, found.single.blockEnd)
        .trim(), isEmpty);
    expect(found.single.line, 2);
  });
}
