// The comments that state the Arabic agreement rule are checked against the
// rule, because a comment that contradicts the code it documents is worse than
// no comment: it is the version a reader trusts.
//
// **The bug this guards.** `arabic_agreement.dart` is the one file every count
// in the app routes through, and its header comment at line 33 claimed
// «110 takes the singular exactly as 10 does». Measured against the helper two
// lines below it, 110 takes the *plural* — `110 % 100` is 10, and 10 is inside
// the broken-plural window. The same false sentence sat in
// `arabic_agreement_test.dart`, whose own group is titled "the plural range
// repeats every hundred" and whose first assertion loop feeds 110 to the
// plural. The code was right and had been right since 26 Sep; the prose said
// otherwise, in the two files a maintainer reads before touching the rule.
//
// Nothing caught it because both sentences were true *about something*: 110
// does behave like 10, that is the entire content of the mod-100 rule, and
// "the singular" is the word that slipped. A rule small enough to hold in your
// head is not evidence you are holding it — and a comment is the same: it
// asserts a number, so it is testable, so it is tested.
//
// **This is a comment test, deliberately.** It imports the real
// [arabicCount] rather than restating the rule, so the two cannot drift: were
// the rule changed, these claims would go red and would have to be rewritten
// on purpose rather than left lying about a rule nobody re-reads.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/arabic_agreement.dart';

// Nouns that cannot be confused with each other or with a digit, so a form is
// recovered by equality rather than by pattern.
const one = 'ONE';
const two = 'TWO';
const few = 'FEW';

/// One claim, recovered from a comment: "N takes the plural".
class _Claim {
  _Claim(this.file, this.line, this.from, this.to, this.form, this.text,
      {this.uniform = false});

  final String file;
  final int line;

  /// Inclusive range the sentence is about. A sentence about "3-10" is ten
  /// claims wearing one coat, and each of them is checked.
  final int from;
  final int to;

  /// 'singular' | 'dual' | 'plural' — what the sentence says the range takes.
  final String form;

  final String text;

  /// True when the sentence states a *boundary* rather than a form — "11 and up
  /// means up to 110" — so the claim is that the whole span takes the same form
  /// as its lower bound, whatever that form is.
  final bool uniform;

  @override
  String toString() => '$file:$line  "$text"';
}

/// `110 takes the singular`, `103 takes «أيام»`, `11-99 take the plural`.
///
/// One capture group per shape, named by what it recovered, so a caller never
/// has to remember which branch was which.
final _englishForm = RegExp(
    r'(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?\s+takes?\s+the\s+'
    r'(broken\s+plural|plural|dual|singular)',
    caseSensitive: false);
final _quotedNoun = RegExp(
    r'(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?\s+takes?\s+\u00ab([^\u00bb]+)\u00bb',
    caseSensitive: false);

/// `11+  (singular, counted)` — the open-ended form, which claims that *every*
/// number from N up takes the form. That is a claim about an unbounded range,
/// and one counterexample falsifies it, so it is tested over a window wider
/// than any count the app can produce.
final _open = RegExp(
    r'\b(\d+)\+\s*\(?\s*(broken\s+plural|plural|dual|singular)',
    caseSensitive: false);

/// `11 and up take the singular` — an unbounded claim written in words rather
/// than with a `+`. It is the header's own phrasing, and it is the form most
/// likely to be wrong, because "and up" is exactly the English reading of a
/// rule that does not work that way.
final _andUp = RegExp(
    r'(\d+)\s+and\s+up\s+(?:takes?|take|taking)\s+the\s+'
    r'(broken\s+plural|plural|dual|singular)',
    caseSensitive: false);

/// **The AND-UP COPULA form - the vocabulary's third gap, measured at two
/// claims, one of them FALSE.** [_andUp] above needs the literal verb
/// *takes*, and [_copula] needs the number to carry the verb itself. Neither
/// reads the sentence this tree actually writes about the open-ended range:
/// «11 and up are counted singular» -- an open-ended claim whose number and
/// whose verb are separated by a conjunction.
///
/// That is the most dangerous shape in the file, because it is the one the
/// rule's own English reading invites: "11 and up" is how English says it, and
/// this is exactly the phrase [_andUp] calls out as "exactly the English
/// reading of a rule that does not work that way". A guard that reads
/// "11 and up TAKE the singular" and stays silent on "11 and up ARE the
/// singular" is reading the grammar, not the claim.
///
/// **Measured: it hid a false claim in `lib/`.** `quote_duration_copy.dart:22`
/// -- the doc comment of the quote-duration copy -- states the open-ended range
/// with a conjunction and a copula, in a table row, and the sentence is FALSE:
/// 103 takes the plural «أيام», because the rule is `n % 100`. The same shape
/// sits in `portfolio_badge_copy_test.dart:16`, which is graded too. Both were
/// invisible to every pattern in this file before this one.
///
/// **And it caught this paragraph first.** The first draft of the sentence
/// above quoted only the Arabic and left the English claim standing, which is
/// an assertion -- and the self-scan read it and went red on this file, which
/// is the whole point of [_selfClaims]. The claim is written out here as the
/// correction rather than as the false sentence, which is the only reason a
/// file may state what is wrong at all.
final _andUpCopula = RegExp(
    r'(\d+)\s+and\s+up\s+'
    r'(?:is|are|was|were|counts\s+as|reads\s+as|is\s+counted(?:\s+as)?)\s+'
    r'(?:an?\s+|the\s+)?'
    r'(broken\s+plural|counted\s+singular|plural|dual|singular)',
    caseSensitive: false);

/// `11-99 take the singular`, `11–102 take the plural` — a bounded range in
/// words. Each number in the range is a claim.
final _ranged = RegExp(
    r'(\d+)\s*[-\u2013\u2014]\s*(\d+)\s+(?:takes?|take|taking)\s+the\s+'
    r'(broken\s+plural|plural|dual|singular)',
    caseSensitive: false);

/// `10 is plural`, `11 is counted singular`, `3-10 is the broken plural`,
/// `102 is counted singular` — the COPULA form, and the one the vocabulary was
/// missing.
///
/// Measured before it was added: eleven sentences in `lib/` and `test/` state
/// the agreement rule in this shape and NOT ONE of them was read, because all
/// six patterns above need the word *takes*. Ten of the eleven are correct;
/// the eleventh is a real false claim sitting in the very file that documents
/// this rule, ten lines under a correct comment saying the opposite. A shape
/// the vocabulary cannot parse is indistinguishable from a file that makes no
/// claim, which is the same blindness one grammar deeper as a reader that opens
/// a file and grades nothing.
final _copula = RegExp(
    r'(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?\s+'
    r'(?:is|are|was|were|counts\s+as|reads\s+as|is\s+counted(?:\s+as)?)\s+'
    r'(?:the\s+)?(broken\s+plural|counted\s+singular|plural|dual|singular)',
    caseSensitive: false);

/// **The LABEL form - the vocabulary's second gap, measured at 11 claims.**
///
/// A table of worked examples states the rule in a shape none of the seven
/// patterns above reads, because it has neither the word *takes* nor a copula:
/// the form is a **parenthetical**, and the range it is about is either the one
/// before the bracket or the ones named inside it.
///
///     `3-10 (plural)`                      <- BEFORE, in arabic_agreement.dart
///     `(broken plural, 3-10 and 103-110)`   <- INSIDE, in reviews_section_copy.dart
///
/// Measured before this was written: **eight rule-stating lines across three
/// files are read by no pattern in this file** - the agreement table that is
/// the header of the file the whole rule lives in, the three-row worked-example
/// table in `reviews_section_copy.dart`, and the class census in
/// `zero_is_silence_test.dart`. The header of `arabic_agreement.dart` is the
/// most-read comment in the app, and every one of its five rule rows was
/// invisible to a guard written to police it.
///
/// **And reading it found a false claim in `lib/`, on the tick it was added.**
/// `reviews_section_copy.dart:85` labelled its counted-singular row
/// `(counted singular, 11+ and 110+)` - and 110 is **plural**: 10 is inside
/// the broken-plural window, which is the mod-100 rule stated a few lines below
/// it in the same file. Corrected at the site to the two spans that really are
/// uniform, `11-102 and 111-202`.
///
/// Three guards on reading this shape. Each one exists because the plant that
/// pins it was written FIRST and the reader had to be fixed to pass it, which
/// is the only reason this tick's plants were written before the reader rather
/// than after:
///
///   * **A bracket's number is not necessarily the row's number.**
///     `قبل 7 دقائق   3-10 (plural)` is a claim about **3-10**; the 7 is an
///     example the row illustrates. So the number before the bracket is read
///     only when nothing but punctuation and spaces stands between them, and
///     never more than [_labelGap] characters of it. Without this the example
///     on every row of the header was graded instead of the rule, and three of
///     its five rows became claims about the wrong number.
///   * **A bracket that says the form carries no number is not a claim.**
///     `(dual, no number, the dual says two)` is about the WORD.
///   * **`mod-100` is not a count.** "see the mod-100 rule below" is prose
///     about the rule, so an inner range is only a claim when it does not
///     follow a letter or a hyphen. Without this the header's own fifth row was
///     read as "100 is plural", and it failed on a comment that was true.
final _paren = RegExp(r'\(([^()\n]*)\)');

/// The form word that OPENS a label, and nothing else: `(broken plural, 3-10…)`
/// states that 3-10 is a broken plural, whereas a form word in the middle of a
/// bracket is prose.
final _labelForm = RegExp(
    r'^\s*(broken\s+plural|counted\s+singular|plural|dual|singular)\b',
    caseSensitive: false);

/// A range BEFORE the bracket - `3-10 (plural)`, `11+ (singular)`. The run
/// between the number and the bracket must be **punctuation and spaces only**,
/// and that character class is the whole guard: an Arabic word between a
/// number and its bracket is what separates the row's own number from the
/// example it illustrates, and no Arabic character can appear in the run.
///
/// **The length bound was tried and deleted, and the mutation test is why it
/// went.** An earlier version capped the run at eight characters. Widening that
/// class to "anything non-word" left the suite GREEN at 45/45 -- Arabic is not
/// a word character in Dart's regex, so the cap was never what excluded it,
/// and the constant was decoration the analyzer's own `unused_element` lint
/// caught when the cap stopped being enforced. Recorded because the
/// alternative -- keeping a bound that cannot fail -- is the exact failure this
/// file has been written to catch since 8 Oct, wearing a different hat.
final _labelBefore = RegExp(
    r'(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?(\+)?'
    r'[ \t>\-=,.:]*'
    r'\(\s*(broken\s+plural|counted\s+singular|plural|dual|singular)\b',
    caseSensitive: false);

/// A range INSIDE the bracket, after the form word that opened it:
/// `(broken plural, 3-10 and 103-110)`. The lookbehind is what keeps `mod-100`
/// and `n % 100` out of it.
final _rangeInLabel = RegExp(
    r'(?<![\w-])(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?(\+)?');

/// A bracket that says the form carries no number - `(dual, no number, the dual
/// says two)` is about the WORD, and the word it holds is not a count.
final _noNumberInLabel =
    RegExp(r'\bno\s+number\b|\bnot\s+a\s+number\b', caseSensitive: false);

/// The inner text of the bracket a given offset sits inside, or null.
///
/// The BEFORE rule is anchored on the number rather than on the bracket, so it
/// cannot ask "which bracket am I in?" for free: this walks the parentheses of
/// the one line and answers it. It has to be a walk rather than a second
/// capture in [_labelBefore], because the two brackets a line can hold are
/// independent - `2 -> (dual, no number) ... 3-10 (plural)` is two claims and
/// two different exemptions, and a pattern that could only see its own bracket
/// would grade the first one off the second one's exemption.
String? _bracketHolding(String text, int offset) {
  for (final m in _paren.allMatches(text)) {
    if (m.start <= offset && offset < m.end) return m.group(1);
  }
  return null;
}

/// Every claim the LABEL shape carries, from one place.
///
/// **One function, two callers, on purpose.** The tree scan and the self scan
/// must not be able to disagree about whether a bracket is a claim, so neither
/// owns the pattern: they both call this.
List<_Claim> _labelClaims(String text, String name, int line) {
  final out = <_Claim>[];

  void add(int lo, int hi, String form, String label) => out.add(_Claim(
      name, line, lo, hi,
      form.replaceAll('broken ', '').replaceAll('counted ', '').toLowerCase(),
      label));

  for (final m in _labelBefore.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    // The form word is what the bracket is ABOUT, so the exemption is asked
    // about the form word. Asked about [m.start] instead -- which is the number
    // and therefore usually OUTSIDE the bracket -- it read either the previous
    // bracket or nothing at all, and `2 -> (dual, no number)` was graded as a
    // claim about 2. One bracketed exemption, missed by one offset.
    final formOffset = m.end - m.group(4)!.length;
    if (_noNumberInLabel.hasMatch(_bracketHolding(text, formOffset) ?? '')) {
      continue;
    }
    final lo = int.parse(m.group(1)!);
    add(
        lo,
        m.group(3) != null
            ? lo + _window
            : int.parse(m.group(2) ?? '$lo'),
        m.group(4)!,
        m.group(0)!);
  }

  for (final pm in _paren.allMatches(text)) {
    final inner = pm.group(1)!;
    final fm = _labelForm.firstMatch(inner);
    if (fm == null) continue;
    if (_noNumberInLabel.hasMatch(inner)) continue;
    for (final r in _rangeInLabel.allMatches(inner.substring(fm.end))) {
      final lo = int.parse(r.group(1)!);
      add(lo,
          r.group(3) != null ? lo + _window : int.parse(r.group(2) ?? '$lo'),
          fm.group(1)!, '${r.group(0)} in (${fm.group(1)})');
    }
  }
  return out;
}

/// `11 and up means up to 110` — the boundary stated directly. It claims the
/// upper number is *inside* the open range, so the pair is one span: read as
/// "11 through 110 are all singular", which is the claim being made.
final _meansUpTo = RegExp(
    r'(\d+)\s+and\s+up\s+means(?:\s+up\s+to)?\s+(?:up\s+to\s+)?(\d+)',
    caseSensitive: false);

/// How far past its lower bound an open-ended claim is tested. 1000 covers every
/// three-digit count the app can reach (`Slider(max: 200)` for the service
/// radius) with room to spare, and it spans ten full centuries of the
/// repeating window, so "11+ is singular" is falsified by 103 the moment the
/// rule is read rather than the way it actually reads.
const _window = 1000;

/// "never 110 takes the singular" is a claim about something else. A negation
/// immediately before the number turns the sentence into an example, and an
/// example is not the rule.
final _negated = RegExp(r'(never|not|no|wrong|instead of|rather than|but)\s*$',
    caseSensitive: false);

/// The three nouns this rule is written about, in Arabic.
///
/// A quoted noun that is not one of these belongs to a sentence that happens
/// to contain a number, and is left alone — the alternative is a scanner that
/// fails on a phrase it was never meant to read.
const _arabicForms = {'أيام': 'plural', 'يومين': 'dual', 'يوم': 'singular'};

/// A form word as the pattern wrote it, and as the helper is asked about it.
///
/// "broken plural" and "counted singular" are two of the four names [_copula]
/// accepts, and both are adjectives sitting in front of the real form. A
/// reader that strips only one of them grades a corrected comment with the
/// wrong verb -- measured: correcting a false claim to «11-102 are counted
/// singular» produced a sentence NO pattern could read, which would have left
/// the correction in the tree unchecked and traded one blind spot for another.
String _formWord(String raw) => raw
    .replaceAll('broken ', '')
    .replaceAll('counted ', '')
    .toLowerCase();

String _form(String noun) =>
    noun == two ? 'dual' : (noun == few ? 'plural' : 'singular');

/// The noun a claim about [form] asserts [arabicCount] should return. The rule
/// is not written out here: it is read off the helper, so a change to the rule
/// cannot silently satisfy a comment written for the old one.
String _wanted(String form) {
  switch (form) {
    case 'singular':
      return one;
    case 'dual':
      return two;
    case 'plural':
    case 'broken plural':
      return few;
    default:
      throw ArgumentError('an agreement claim states one of singular, dual or '
          'plural, and this one states "$form"');
  }
}

/// Why [lastTwo] took the plural, for the failure message.
String _pluralWindow(int lastTwo) =>
    lastTwo >= 3 && lastTwo <= 10 ? 'is in the 3-10 window' : 'is outside it';

/// Every claim shape a SINGLE LINE states -- the whole vocabulary, in one
/// place, for BOTH scanners.
///
/// This function is the third reader in the file and the one that ends the
/// defect the other two shared: [_scanClaims] (the run scanner, which reads
/// this file) and [_claims] (the tree scan, which reads `lib/` and `test/`)
/// each carried their OWN copy of every pattern, and a shape added to one was
/// silently absent from the other. Measured on the tick that added
/// [_andUpCopula]: it was written into the tree scan and the run scanner in
/// two edits, and a third shape had to be found by hand to confirm neither
/// copy had drifted.
///
/// Two scanners of one vocabulary that disagree about what a sentence says is
/// the same class of bug as the guard itself -- a sentence graded by one and
/// invisible to the other is graded by nobody, in practice. So there is now
/// one place where a claim shape exists, and both scanners call it.
List<_Claim> _lineClaims(String text, String name, int line) {
  final out = <_Claim>[];

  for (final m in _englishForm.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    final hi = int.parse(m.group(2) ?? '$lo');
    out.add(_Claim(name, line, lo, hi, _formWord(m.group(3)!), m.group(0)!));
  }

  for (final m in _quotedNoun.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final form = _arabicForms[m.group(3)!];
    if (form == null) continue; // a noun from some other sentence
    final lo = int.parse(m.group(1)!);
    final hi = int.parse(m.group(2) ?? '$lo');
    out.add(_Claim(name, line, lo, hi, form, m.group(0)!));
  }

  for (final m in _andUp.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    // No upper bound is given, so the claim runs to the end of the window --
    // checking only the lower number would let the one form of this sentence
    // that is always false pass.
    out.add(_Claim(name, line, lo, lo + _window, _formWord(m.group(2)!),
        m.group(0)!));
  }

  for (final m in _ranged.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    out.add(_Claim(name, line, int.parse(m.group(1)!), int.parse(m.group(2)!),
        _formWord(m.group(3)!), m.group(0)!));
  }

  for (final m in _meansUpTo.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    out.add(_Claim(name, line, lo, int.parse(m.group(2)!), 'singular',
        m.group(0)!,
        uniform: true));
  }

  for (final m in _open.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    out.add(_Claim(name, line, lo, lo + _window, _formWord(m.group(2)!),
        m.group(0)!));
  }

  // The copula form: "10 is plural", "11 is counted singular",
  // "3-10 is the broken plural". A range is a range here too -- "3-10 is the
  // broken plural" is ten claims wearing one coat.
  for (final m in _copula.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    final hi = int.parse(m.group(2) ?? '$lo');
    out.add(_Claim(name, line, lo, hi, _formWord(m.group(3)!), m.group(0)!));
  }

  // The and-up copula: an open-ended claim whose number and verb are split by
  // a conjunction. The lower bound is the number and the upper bound is the
  // WINDOW, because "and up" is unbounded and one counterexample -- 103 --
  // falsifies the whole sentence.
  for (final m in _andUpCopula.allMatches(text)) {
    if (_negated.hasMatch(text.substring(0, m.start))) continue;
    final lo = int.parse(m.group(1)!);
    out.add(_Claim(name, line, lo, lo + _window, _formWord(m.group(2)!),
        m.group(0)!));
  }

  // The label shape, through [_labelClaims]: "3-10 (plural)",
  // "(broken plural, 3-10 and 103-110)" -- a worked-example table, which is
  // how `arabic_agreement.dart` states the rule at all.
  out.addAll(_labelClaims(text, name, line));

  return out;
}

/// How many places in `lib/` and `test/` WRITE a sentence of [_andUpCopula]'s
/// shape -- graded or not.
///
/// The floor above cannot be a count of graded claims, and the reason is a
/// fact about the RULE rather than about this file. A mod-100 rule has no TRUE
/// unbounded claim: "N and up is singular" is false for every N, because 103
/// is inside the plural window, so every occurrence of this shape in the tree
/// is either false (and gets corrected) or an exhibit (and gets quoted). This
/// tick corrected both false ones -- and the graded count went to ZERO, not
/// because the reader stopped reaching the shape but because the reader had
/// just done its job.
///
/// So the reach is pinned on the raw shape instead: the sentence is still
/// WRITTEN in the tree (in the corrections, as the counter-example), and a
/// pattern that stops recognising it -- weakened, renamed, dropped -- moves
/// this number. That is the property the floor exists for, and it is the one
/// a graded-claim floor cannot give for this shape.
int _andUpCopulaWritten() {
  var n = 0;
  for (final dir in const ['lib', 'test']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.split(Platform.pathSeparator).contains('build')) continue;
      for (final line in e.readAsLinesSync()) {
        final t = line.trimLeft();
        if (!t.startsWith('//')) continue;
        n += _andUpCopula.allMatches(t).length;
      }
    }
  }
  return n;
}

/// Which files' comments are actually ABOUT this rule, measured rather than
/// assumed.
///
/// The last tick left this open: the reader has no way to know which rule a
/// comment is about, so every claim it grades is checked against [arabicCount],
/// and a sentence about a different rule is either ignored or falsely red. Two
/// answers were on the table -- require a file to route counts through the
/// helper before its comments are graded, or carry the rule on the claim itself
/// -- and neither was to be started without measuring which files drop out.
///
/// So this measures it, and the measurement REFUTES the census. A file is
/// `direct` when its own code calls the helper; it is `routed` when it, or
/// anything it imports, does. A comment about this rule is legitimately in a
/// file that only ever calls a *wrapper*: `reviews_section_copy.dart` states
/// the span rule and reaches [arabicCounted] two levels down through
/// `review_count.dart`.
({Set<String> direct, Set<String> routed}) _routingCensus() {
  final index = <String, String>{};
  for (final dir in const ['lib', 'test']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.split(Platform.pathSeparator).contains('build')) continue;
      index.putIfAbsent(
          e.path.split(Platform.pathSeparator).last, () => e.path);
    }
  }

  // CALL SITES, not mentions. `quote_duration_copy.dart` names the helper three
  // times in prose and calls it once; counting prose is what makes a census
  // look busier than it is. The `//` filter is what removes it -- doc comments
  // are exactly the mentions that are not delegations.
  final calls = RegExp(r'arabicCount(?:ed)?\s*\(');
  final importRe = RegExp('import' r'\s+["\x27]([^"\x27]+)["\x27]');

  String codeOf(String path) {
    return File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  }

  final direct = <String>{};
  for (final name in index.keys) {
    if (calls.hasMatch(codeOf(index[name]!))) direct.add(name);
  }

  // Fixpoint, because "imports something that routes" is recursive: the app's
  // count copy funnels through `review_count.dart` -> `arabic_agreement.dart`.
  final routed = <String>{...direct};
  var grew = true;
  while (grew) {
    grew = false;
    for (final name in index.keys) {
      if (routed.contains(name)) continue;
      for (final m in importRe.allMatches(codeOf(index[name]!))) {
        if (routed.contains(m.group(1)!.split('/').last)) {
          routed.add(name);
          grew = true;
          break;
        }
      }
    }
  }
  return (direct: direct, routed: routed);
}

/// HOW MANY SENTENCES WOULD THE RULE HAVE TO BE CARRIED ON -- the census the
/// last tick asked for, and its answer is that the fix is not worth its cost.
///
/// The reader grades every claim shape it finds against [arabicCount]. It has
/// one open false positive: `relative_time_hour_floor_test.dart:97` says
/// «120 is a dual», which is TRUE about the hour-floor rule the file tests and
/// FALSE about this one (120 % 100 = 20, so 120 is counted singular). The
/// reader misses it -- not because it is a sentence about a different rule, but
/// because the shape carries an article the vocabulary does not accept.
///
/// So the third candidate was to carry the rule ON THE CLAIM: annotate each
/// sentence with the rule it is about. Before doing that, count. This is the
/// count, and it is deliberately a LOOSER match than [_copula] -- a census that
/// reuses the reader's pattern would report only what the reader already finds,
/// which is the number the fix is trying to move.
///
/// **Measured on this tree: 25 claim-shaped sentences, 2 of them unread.** One
/// of the two is this file's own doc comment (a worked example, correctly
/// skipped); **the other is the false positive itself**. There is no backlog.
///
/// The count is PINNED by a test rather than written here, because a doc
/// comment is not evidence and this one already carried a number that had
/// drifted: it read 24 when the tree holds 25. The extra sentence is
/// `agreement_comment_test.dart:198` -- «3-10 is a broken plural», the doc
/// comment of [_labelForm] -- and it is unread for the same reason the false
/// positive is unread, because it carries an article the vocabulary does not
/// accept. A count that walks when the file it lives in gains a sentence is
/// exactly the kind of number this loop stops trusting.
///
/// **And the fix is not the article.** Measured by patching [_copula] to accept
/// `a`/`an` and running this file: 62 tests, **2 red**, and the second red is
/// not the tree at all -- it is this file's own `the only live claim here is the
/// counter-example` assertion, which pins `every((c) => c.from == 103)` and so
/// goes red the moment the reader is widened to find one more sentence in this
/// file. So widening the pattern costs a claim about the reader AND leaves the
/// one false positive to be argued about in prose forever, because the file
/// that carries it is testing a different rule entirely.
///
/// **The decision, therefore: fix the sentence, not the reader.** See the
/// `_articleCensus` group in `main()`.
class _ArticleCensus {
  _ArticleCensus(this.surface, this.unread);

  /// Every claim-shaped sentence in the tree, matched LOOSER than the reader.
  final List<_Claim> surface;

  /// The ones [_lineClaims] does not recover -- the unread surface.
  final List<_Claim> unread;

  int get unreadInLib =>
      unread.where((c) => c.file != 'agreement_comment_test.dart').length;
}

/// The loose vocabulary, and why it is looser than [_copula].
///
/// Deliberately over-matches: it accepts every verb the reader's seven shapes
/// use, plus a bare article or none. A census built from the reader's own
/// pattern would report the reader's current reach as if it were the problem's
/// size, and the whole question -- *how many sentences would the rule have to be
/// carried on* -- would be answered with the number it already knows.
///
/// It is a PROBE. Every sentence it finds is checked, so an over-broad match
/// shows up as a file:line a human has to judge, not as a silent undercount.
final _probeLoose = RegExp(
    r'(\d+)(?:\s*[-\u2013\u2014]\s*(\d+))?\s+'
    r'(?:is|are|was|were|takes?|counts\s+as|reads\s+as|means?|becomes?)\s+'
    r'(?:(?:the|a|an)\s+)?'
    r'(broken\s+plural|counted\s+singular|plural|dual|singular)',
    caseSensitive: false);

/// The census: the loose surface, minus what the reader already reads.
_ArticleCensus _articleCensus() {
  final surface = <_Claim>[];
  final unread = <_Claim>[];

  for (final dir in const ['lib', 'test']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.split(Platform.pathSeparator).contains('build')) continue;
      final name = e.path.split(Platform.pathSeparator).last;

      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i].trimLeft();
        if (!raw.startsWith('//')) continue;
        final text = _blankQuotedSpans(raw);

        for (final m in _probeLoose.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          final hi = int.parse(m.group(2) ?? '$lo');
          final claim = _Claim(name, i + 1, lo, hi, _formWord(m.group(3)!),
              m.group(0)!.trim());
          surface.add(claim);
          // The reader's own view of the same line, via the shared vocabulary
          // -- so "unread" means "the reader misses it", not "my regex differs
          // from theirs by an accident of transcription".
          final read = _lineClaims(text, name, i + 1)
              .where((c) => c.text.trim() == claim.text)
              .isNotEmpty;
          if (!read) unread.add(claim);
        }
      }
    }
  }

  // `agreement_comment_test.dart` is a reader that quotes the shapes it hunts;
  // its own hits are the worked examples, not claims about the app. Counted
  // separately rather than dropped, so the exemption stays visible.
  return _ArticleCensus(surface, unread);
}

void main() {  // -----------------------------------------------------------------------
  // WHICH RULE IS THIS COMMENT ABOUT -- the census, measured, and REFUTED.
  //
  // The reader grades every claim it finds against [arabicCount]. The open
  // question was whether a file should be required to route counts through
  // that helper before its comments are graded at all, so a sentence about a
  // DIFFERENT rule could not go falsely red. Measured here rather than
  // argued, and the answer is that the census would DELETE true claims.
  //
  // Measured on this tree: 13 files carry claims.
  //   * 3 write the call themselves -- `arabic_agreement.dart` (the rule),
  //     `arabic_agreement_test.dart` (20 call sites) and
  //     `quote_duration_copy.dart` (1 call site).
  //   * 10 do not, and all 17 claims in them are TRUE about this rule.
  //     `reviews_section_copy.dart:85` states the `11-102` span verbatim, and
  //     that file reaches the helper two levels down through `review_count`.
  //
  // So a direct-call census drops 17 of 30 true claims to fix a false positive
  // that had not yet been demonstrated. Net loss; rejected on its own numbers.
  //
  // The transitive closure is worse in the way that matters for a guard: it
  // routes 329 of 456 Dart files, excluding 72% of nothing. It still routes
  // `relative_time_hour_floor_test.dart` -- the very file carrying
  // `120 is a dual`, the false positive this question came from. A filter that
  // keeps the case it was written to catch is not a filter.
  //
  // Both candidates are therefore rejected BY MEASUREMENT. What is shipped is
  // not the census but the numbers that refute it, pinned so the decision is
  // re-measurable rather than inherited as an argument.
  group('a comment is graded against the rule it can actually be checked by',
      () {
    final claimFiles = {for (final c in _claims()) c.file};
    final census = _routingCensus();
    final routed = census.routed;

    test('the census that was rejected was measured on a real tree', () {
      // Without these the rejection above is an argument, and the next tick
      // re-raises it.
      expect(claimFiles.length, greaterThanOrEqualTo(10),
          reason: 'only ${claimFiles.length} files carry claims -- the '
              'measurement this rejection rests on was taken on a tree this '
              'reader does not describe');
      expect(routed.length, greaterThan(claimFiles.length),
          reason: 'the closure routed ${routed.length} files for '
              '${claimFiles.length} claim-bearing files, which is not what '
              'was measured');
    });

    test('a direct-call census would drop true claims, so it is rejected', () {
      // Every claim-bearing file that does not call the helper itself is a
      // claim the census would delete.
      const direct = {
        'arabic_agreement.dart',
        'arabic_agreement_test.dart',
        'quote_duration_copy.dart'
      };
      final wouldDrop = claimFiles.difference(direct);
      expect(wouldDrop.length, greaterThanOrEqualTo(8),
          reason: 'the census now excludes only ${wouldDrop.length} files -- '
              'if that is few it may no longer be dropping true claims, and '
              'the rejection must be re-measured rather than inherited');
      // The claim it is written to save: this file states the span rule while
      // calling the helper two levels down, so a direct-call census would
      // silently stop checking it.
      expect(wouldDrop.contains('reviews_section_copy.dart'), isTrue,
          reason: 'the file that states the span rule verbatim no longer '
              'illustrates why the census was rejected');
    });

    test('a mention in prose is not a delegation', () {
      // The comment filter in `codeOf` is load-bearing, and this is what makes
      // it so. Measured: dropping it and counting doc comments that merely
      // NAME the helper left the suite GREEN, because the closure routes those
      // files anyway -- so the claims above did not notice. What DOES notice is
      // the direct set growing: `reviews_section_copy.dart` says "a hand-written
      // copy of [arabicCounted]" in prose and calls nothing, and a census that
      // cannot tell the two apart is the census this guard rejected.
      final directClaimFiles =
          census.direct.intersection(claimFiles).difference({
        'arabic_agreement.dart',
        'arabic_agreement_test.dart',
        'quote_duration_copy.dart'
      });
      expect(directClaimFiles, isEmpty,
          reason: 'these files carry claims but only MENTION the helper in '
              'prose: ${directClaimFiles.join(', ')} -- prose is not a call '
              'site, and a census that cannot tell them apart is the one this '
              'guard rejected');
      // And the size, because the set-membership check above passed even when
      // the pattern was widened to the bare NAME and the direct set grew from
      // 20 to 40-odd. A census that stopped asking for a parenthesis and
      // started reading prose does not change WHICH claim-bearing files call
      // it -- so it changed nothing that was asserted. Pinned here so the
      // difference has to be visible somewhere.
      expect(census.direct.length, 20,
          reason: 'the direct call-site set is ${census.direct.length} files; '
              'it was 20 when measured, and a jump means `calls` started '
              'matching something other than a call');
    });

    test('a quoted example of the helper is not a call site', () {
      // The plant the real tree cannot supply. Every file in `lib/` and `test/`
      // that writes a QUOTED example of the helper in prose ALSO calls it, so
      // the comment filter in `_routingCensus` was unexercised: measured with
      // the filter removed, `direct` stayed at exactly 20 and the suite stayed
      // GREEN. A guard that cannot see the case it was written for is the
      // blindness this file exists to catch, one level down -- so it is
      // written here.
      //
      // Measured on why a weaker plant would not do: the first version of this
      // plant wrote `see [arabicCount]`, with no parenthesis, and the mutation
      // stayed GREEN for a mechanical reason -- the call-site pattern already
      // requires `(`, so that plant could not tell the two apart no matter
      // what the comment filter did. The plant has to carry the paren too.
      //
      // Both halves matter and the tree has only one of them. The positive half
      // (a file that DOES call it) is `arabic_agreement.dart` itself, already
      // pinned by the count below; the negative half is written to disk here
      // and removed again, because a comment-only file is exactly the shape
      // this tree does not have.
      const name = '_census_plant_mentions_only.dart';
      final path = 'test/$name'; // ignore: prefer_const_declarations
      File(path).writeAsStringSync("""// This file never calls the helper. The call below is QUOTED in a comment,
// which is what a worked example in a doc comment looks like:
//     return arabicCounted(3, 'x');
import 'package:allomokawil/src/core/l10n/arabic_agreement.dart';

String plantMentionOnly() => 'writes an example, calls nothing';
""");
      try {
        final planted = _routingCensus();
        expect(planted.direct.contains(name), isFalse,
            reason: 'a file whose only `arabicCounted(` is inside a comment was '
                'counted as a call site, so the census reads a worked EXAMPLE '
                'as a delegation -- the confusion that makes it unsafe as a '
                'filter');
      } finally {
        File(path).deleteSync();
      }
      // Really gone, so a green here is not the file simply never having been
      // written.
      expect(File(path).existsSync(), isFalse);
    });

    test('the transitive closure excludes too little to be a filter', () {
      // It keeps the false-positive case the question was raised by.
      // The one file that pins the CLOSURE as distinct from the direct set.
      // It reaches the helper through `notification_copy.dart` and calls nothing
      // itself, which is why the assertions above could not tell a closure from
      // a flat direct set: 20 and 13 satisfy every one of them.
      expect(routed.contains('relative_time_hour_floor_test.dart'), isTrue,
          reason: 'the closure no longer routes the file carrying '
              '"120 is a dual" -- re-measure before treating it as a filter');
      expect(census.direct.contains('relative_time_hour_floor_test.dart'),
          isFalse,
          reason: 'this file only reaches the helper through an import, so if '
              'it is now a direct call site the census is reading something '
              'other than call sites and the comparison above is not testing '
              'what it claims to test');
    });

    test('nothing is dropped: every claim the reader finds is still graded',
        () {
      // The invariant the rejected census would have broken. If this fails it
      // is because a claim stopped being readable, which is a different bug
      // and a louder one.
      final claims = _claims();
      expect(claims, isNotEmpty);
      expect(claims.length, greaterThanOrEqualTo(_selfClaims().length));
    });
  });

  // CARRYING THE RULE ON THE CLAIM -- the third candidate, measured.
  //
  // The census before this one asked WHICH FILES are about this rule and
  // rejected both answers on its own numbers. This one asks the question that
  // is left: how many sentences would have to be ANNOTATED for a reader to know
  // which rule each one is about. Measured, not estimated -- and the answer is
  // that there is no annotation backlog, and that the article is not the fix.
  group('the rule on the claim itself would have almost nothing to carry',
      () {
    final census = _articleCensus();

    test('the loose surface is a real surface, not a two-line tree', () {
      // The census below is only a decision if the thing it counts is bigger
      // than the defect it would prevent. Measured: 25 claim-shaped sentences.
      expect(census.surface.length, greaterThanOrEqualTo(20),
          reason: 'the loose probe found ${census.surface.length} sentences; '
              'it was written to over-match, so a collapse to a handful means '
              'the probe stopped over-matching and every number under it is '
              'now a floor, not a measurement');
      // ...and it is pinned EXACTLY, so the doc comment cannot drift again.
      // This is the number the annotation-pass decision rests on: it says one
      // sentence is unread, and therefore that the fix is one edit rather than
      // a scheme over 25 sentences. If a future sentence joins the surface the
      // count moves -- which is information -- but it must move HERE, where it
      // is a red test somebody has to look at, not in prose nobody re-measures.
      // Before this was pinned the prose said 24 while the tree held 25.
      expect(census.surface.length, 25,
          reason: 'the loose surface is ${census.surface.length} sentences; it '
              'was 25 when this was pinned (the doc comment claimed 24 and was '
              'wrong by one, the sentence it did not count being its own '
              '`3-10 is a broken plural`). A different number means the tree '
              'gained or lost a claim-shaped sentence: re-measure, then update '
              'the doc comment and this line together');
    });

    test('the unread surface is ONE sentence, and it is the false positive',
        () {
      // This is the whole finding. Every claim-shaped sentence in `lib/` and
      // `test/` is either readable or is this one.
      //
      // It is `relative_time_hour_floor_test.dart:97` -- «120 is a dual» --
      // which is true about the hour-floor rule that file tests and false about
      // this one, and which [_copula] misses because the shape carries an
      // article the vocabulary does not accept. The reader does not fail to
      // reach it for a structural reason; it fails on a missing word.
      expect(census.unreadInLib, 1,
          reason: 'the unread surface is ${census.unread.map((c) => "${c.file}:${c.line} \"${c.text}\"").join('; ')} -- '
              'this was measured at exactly 1, the false positive. More means '
              'the reader has a real gap and the annotation pass is cheap; '
              'fewer means the probe stopped matching what the reader matches '
              'and this count is not a measurement');
      final blind = census.unread
          .where((c) => c.file != 'agreement_comment_test.dart')
          .toList();
      expect(blind.single.file, 'relative_time_hour_floor_test.dart');
      expect(blind.single.line, 97);
      expect(blind.single.from, 120);
      expect(blind.single.form, 'dual');
    });

    test('the one unread sentence is FALSE about this rule, and it is about '
        'another one', () {
      // Why the reader is right to be unsure about it, and why grading it
      // would be wrong. 120 % 100 = 20, which is outside the 3-10 window, so
      // [arabicCount] calls 120 counted singular -- the comment says dual and
      // is wrong. But the sentence is not ABOUT this rule: it is the boundary
      // of an hour floor, where 120 minutes is two hours and
      // `arabicCount(2, ...)` really is the dual.
      expect(arabicCount(120, one, two: two, few: few), one,
          reason: '120 is counted singular, so a comment calling it a dual is '
              'false ABOUT THIS RULE -- which is why grading it and going red '
              'would be reporting a real falsehood');
      expect(arabicCount(2, one, two: two, few: few), two,
          reason: 'and it is true about the rule the file is actually testing: '
              'the hour floor converts 120 minutes to a two-hour count, and a '
              'two-hour count takes the dual');
    });

    test('widening the vocabulary is NOT the fix, and that was measured', () {
      // The obvious repair -- let [_copula] accept `a`/`an` -- was tried and
      // rejected on its output, not on taste. Patching the pattern to
      // `(?:(?:the|a|an)\s+)?` and running this file gave **62 tests, 2 red**:
      //
      //   1. `relative_time_hour_floor_test.dart:97` -- the sentence above,
      //      correctly red, on a file that is testing a different rule. The
      //      fix does not change that verdict; it only makes the file
      //      permanently unmergeable, because the comment cannot be corrected
      //      without deleting a true statement about the hour floor.
      //   2. `the real file is graded by the loop above` -- this file's own
      //      assertion that `every((c) => c.from == 103 && c.to == 103)`.
      //      Widening the reader finds one more sentence in THIS file, so a
      //      guard on the reader's content goes red for the same reason a
      //      guard on the tree does.
      //
      // Both reds are the argument. A vocabulary change buys a correct
      // diagnosis on a sentence that must not be graded, and costs a claim
      // about the reader to get it. So the sentence is fixed at the site
      // instead, and the reader is left alone.
      //
      // What this pins is the DECISION, so a later tick re-measures rather than
      // re-argues it: the defect is one sentence, and one sentence is a
      // two-line edit, not an annotation scheme over the tree.
      expect(census.unreadInLib, lessThan(3),
          reason: 'the annotation pass is only worth its cost above a handful '
              'of sentences; the measured surface is 1');
    });
  });


  group('the comments that state the rule agree with the rule', () {
    final claims = _claims();
    final selfClaims = _selfClaims();

    test('the reader found the claims it was written to find', () {
      // A scanner that silently matches nothing reports a clean tree, which is
      // indistinguishable from a clean tree. This is the backstop that makes
      // the result below it mean something.
      expect(claims.length, greaterThanOrEqualTo(6),
          reason: 'only ${claims.length} agreement claims were read out of '
              'lib/ and test/ -- this reader is broken, not the tree');
    });

    // THIS FILE'S OWN CLAIMS. The exemption above (`entity.path.endsWith(self)`
    // in `scan`) drops this file from its own sweep, and the exemption census
    // reports this file as having two compensating readers -- `orphan_decl`
    // and `wall_clock_seam_site` -- which open it only as incidental input to
    // a different guard (an orphan-declaration tally, a seam-arity check) and
    // judge nothing about a single line of its text. Measured: zero readers
    // of this file assert anything about its agreement claims, so nothing in
    // the tree ever checks the file that exists to check that comments do not
    // contradict the code they document.
    //
    // That gap was measured, not assumed. A false claim was planted in this
    // file's own header -- the sentence this guard was written after, quoted
    // verbatim in guillemets so it reads as the counter-example it is, exactly
    // as line 7 quotes it -- and the whole suite went green: 10 of 10 here,
    // 2546 of 2546 overall, because the one file that could read that line is
    // the one file that skips itself.
    //
    // The fix is the exemption's own escape hatch. A self-exemption is legal
    // only when the guard PINS something on its own text; the floor test above
    // pins the reader's reach, this pins its content.
    for (final c in selfClaims) {
      test(c.toString(), () {
        final want = c.uniform
            ? arabicCount(c.from, one, two: two, few: few)
            : _wanted(c.form);
        final wrong = <int>[];
        for (var n = c.from; n <= c.to; n += 1) {
          if (arabicCount(n, one, two: two, few: few) != want) wrong.add(n);
          if (wrong.length == 4) break;
        }
        expect(wrong, isEmpty,
            reason: 'this file skips itself, so nothing else in the tree '
                'reads this sentence${wrong
                    .map((n) => ' -- $n takes the ${_form(want)} form, because '
                        'its last two digits (${n % 100}) '
                        '${_pluralWindow(n % 100)}')
                    .join('; ')}');
      });
    }

    // THE VOCABULARY IS PINNED BY A FLOOR, because a loop over claims cannot
    // witness its own generator.
    //
    // Measured: deleting the copula branch from either scanner -- pattern, gate
    // or loop all together -- left the suite GREEN at 22, 22 and 14 tests. The
    // eight copula claims in the tree were checked only by the loop over
    // `_claims()`, so removing the branch removed the tests that would have
    // noticed. A reader that finds nothing reports a clean tree, which is the
    // blindness this file exists to catch, one shape deeper.
    //
    // So the reach is pinned the same way the takes-family is pinned above, as
    // a number that moves when a pattern stops recognising. Eight, measured,
    // across `lib/` and `test/` at this commit.
    test('the copula vocabulary still reaches the tree', () {
      final copulaClaims = claims.where((c) => _copula.hasMatch(c.text));
      expect(copulaClaims.length, greaterThanOrEqualTo(8),
          reason: 'only ${copulaClaims.length} copula-form claims were read '
              'out of lib/ and test/ -- "N is plural", "N is counted '
              'singular" and "3-10 is the broken plural" are stated in the '
              'tree and nothing read them, so a false one in this shape is '
              'graded by no one');
    });

    // THE LABEL VOCABULARY IS PINNED BY A FLOOR, for the reason the copula
    // floor above states: the eight label claims are graded only by the loop
    // over `_claims()`, so deleting the pattern deletes the tests that would
    // have noticed. Measured at 8 across `lib/` and `test/` at this commit --
    // five rows in `arabic_agreement.dart`, three in
    // `reviews_section_copy.dart`, two in `zero_is_silence_test.dart`.
    test('the label vocabulary still reaches the tree', () {
      final labelClaims =
          claims.where((c) => c.text.contains('in (') || _labelBefore
              .hasMatch(c.text)).toList();
      expect(labelClaims.length, greaterThanOrEqualTo(8),
          reason: 'only ${labelClaims.length} label-form claims were read out '
              'of lib/ and test/ -- "3-10 (plural)" and "(broken plural, 3-10 '
              'and 103-110)" are the shape the agreement table in '
              'arabic_agreement.dart is written in, and nothing read them');
    });

    // THE AND-UP COPULA VOCABULARY IS PINNED BY A FLOOR, for the reason the two
    // floors above state: a claim shape graded only by the loop over
    // `_claims()` cannot witness its own removal -- deleting the branch that
    // produces the claims deletes the tests that would have noticed.
    //
    // Measured: two claims in the tree state the open-ended range with a
    // conjunction and a copula, "11 and up are counted singular", in
    // `quote_duration_copy.dart` and `portfolio_badge_copy_test.dart`. BOTH are
    // false -- 103 takes the plural, because the rule is `n % 100` -- and both
    // were read by no pattern in this file before this one.
    test('the and-up copula vocabulary still reaches the tree', () {
      // Two claims were graded and BOTH were false; correcting them left the
      // graded count at zero. See [_andUpCopulaWritten] for why a graded-count
      // floor is unsatisfiable for this shape, and what is pinned instead.
      final graded = claims.where((c) => _andUpCopula.hasMatch(c.text)).length;
      final written = _andUpCopulaWritten();
      expect(written, greaterThanOrEqualTo(2),
          reason: 'only $written sentences of the "N and up is the <form>" '
              'shape are written in lib/ and test/ -- the shape is stated in '
              'the tree and a false one in it would be graded by no one');
      expect(graded, lessThanOrEqualTo(written),
          reason: 'the reader cannot read more than the tree writes');
    });

    // The two stages the real tree cannot exercise, planted.
    test('the label reader takes the range from before the bracket', () {
      final found = _labelClaims('before 7 دقائق   3-10 (plural)', 'p.dart', 0);
      expect(found.length, 1);
      expect(found.single.from, 3);
      expect(found.single.to, 10);
      expect(found.single.form, 'plural');
    });

    // The REAL line from `reviews_section_copy.dart`, copied verbatim -- Arabic
    // and all -- rather than a cleaned-up paraphrase of it.
    //
    // The paraphrase was the bug, and it was a bug in the PLANT rather than in
    // the reader: it dropped the Arabic between the row's number and its
    // bracket, so a `11 -> (` shaped string let the BEFORE rule fire on the row
    // number as well and the plant expected two claims where three are
    // correct. The Arabic is exactly what the gap guard in [_labelBefore]
    // exists to see, so a plant without it is a plant for a row this tree does
    // not have.
    test('the label reader takes the ranges named inside the bracket', () {
      final found = _labelClaims(
          '11 ->  يظهر أعلاه 11 تقييماً،  (counted singular, 11-102 and 111-202)',
          'p.dart',
          0);
      expect(found.map((c) => c.from), [11, 111]);
      expect(found.map((c) => c.to), [102, 202]);
    });

    // The same line WITHOUT the Arabic: the row's own number is then adjacent
    // to the bracket, so it IS the row's number and is a claim in its own
    // right. Pinned because the two readings differ only in the text between
    // them, which is the entire content of the gap guard.
    test('a number adjacent to its bracket is the row\'s own claim', () {
      final found = _labelClaims('11 -> (counted singular)', 'p.dart', 0);
      expect(found.length, 1);
      expect(found.single.from, 11);
      expect(found.single.form, 'singular');
    });

    // `11+` inside a bracket is an UNBOUNDED claim, and one counterexample
    // falsifies it -- `103` takes the plural. Planted so the open-ended
    // reading cannot
    // be dropped to make a wrong comment pass, which is the mistake this whole
    // file exists to catch.
    test('an open-ended range inside a bracket is tested to the window', () {
      final found = _labelClaims('11+ (singular)', 'p.dart', 0);
      expect(found.single.to, greaterThanOrEqualTo(1000));
    });

    // The two exclusions, each of which fails a correct table if dropped.
    test('a bracket that says the form carries no number is not a claim', () {
      expect(_labelClaims('2 -> (dual, no number, the dual says two)', 'p', 0),
          isEmpty);
    });

    // `mod-100` is the exclusion that applies to a range INSIDE a bracket: the
    // 100 is part of the name of the rule, not a count. The earlier version of
    // this plant wrote it in front of the bracket instead, where the number
    // really is the row's number and the reader is right to grade it -- a
    // correct comment that the plant was asking to be ignored.
    test('mod-100 inside a bracket is not a count', () {
      final found = _labelClaims(
          '11 -> (counted singular, 11-102 - see the mod-100 rule below)', 'p',
          0);
      // Two claims, not three: the row's own 11, and the 11-102 inside the
      // bracket. The 100 of `mod-100` is part of the NAME of the rule, and a
      // reader that graded it would fail this tree's own header -- which says
      // "see the mod-100 rule below" on the very row the guard reads.
      expect(found.map((c) => '${c.from}-${c.to}'), ['11-11', '11-102']);
      expect(found.any((c) => c.from == 100 || c.to == 100), isFalse);
    });

// The shape PLANTED, because the real tree cannot exercise the two stages
    // the run scanner owns on its own: `_selfClaims()` on this file is
    // correctly empty, so a plant is the only thing that can see those stages
    // go. Written before the scanner branch, and the first one of the two
    // caught a bug in it -- see the plant two below.
    group('the reader reads an open-ended claim joined by a conjunction', () {
      test('the lower bound is the number and the upper bound is the window',
          () {
        final found = _scanClaims(const [
          '// 11 and up are counted singular.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isNotEmpty,
            reason: 'the scanner found nothing, so it cannot fail');
        expect(found.single.from, 11);
        expect(found.single.form, 'singular');
        expect(found.single.to, greaterThanOrEqualTo(1000),
            reason: '"and up" is unbounded -- checking only 11 would let the '
                'one form of this sentence that is always false pass');
      });

      // The REAL sentence, verbatim, from `quote_duration_copy.dart` -- with
      // the bullet and the table around it, because the shape has to survive
      // the paragraph it really lives in.
      test('the real claim in lib/ is read out of its own table row', () {
        final found = _scanClaims(const [
          '//   * 3  -> «3 يوم»    3-10 need the broken plural «أيام»',
          '//   * 10 -> «10 يوم»   same',
          '//   * 11 -> «11 يوم»   11 and up are counted singular, so the word',
          '//     is right',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isNotEmpty);
        expect(found.single.from, 11);
        expect(found.single.form, 'singular');
      });

      // "and up" claims a form, not a boundary, so the copula's `the`
      // article and the `counted` qualifier are both optional -- and the
      // qualifier is the one that carries the meaning here.
      test('the counted qualifier is not part of the form name', () {
        final found = _scanClaims(const [
          '// 3 and up are the broken plural.',
          'void main() {}',
        ], 'planted.dart');
        expect(found.single.form, 'plural',
            reason: '"counted singular" must grade as `singular` and "broken '
                'plural" as `plural`, or _wanted() throws on a real claim');
      });

      // The wider verb set. **Mutation-measured: narrowing the copula to
      // `is|are` left the suite GREEN**, because the tree happens to write
      // only those two and every plant above used one of them -- the pattern
      // carried four alternatives that nothing could see go. A word list
      // nobody exercises is a word list that can shrink silently, and the
      // cost of shrinking it is a sentence no longer read.
      test('the passive and classificatory verbs are read too', () {
        for (final verb in <String>[
          'is',
          'are',
          'was',
          'were',
          'counts as',
          'reads as',
          'is counted',
          'is counted as',
        ]) {
          final found = _scanClaims([
            '// 3 and up $verb the broken plural.',
            'void main() {}',
          ], 'planted.dart');
          expect(found, hasLength(1), reason: '"$verb" is in the pattern and '
              'must be read; a narrower verb list passes by not noticing');
          expect(found.single.form, 'plural');
          expect(found.single.from, 3);
        }
      });

      test('a negated sentence is still only an example', () {
        expect(
            _scanClaims(const [
              '// never 11 and up are counted singular.',
              'void main() {}',
            ], 'planted.dart'),
            isEmpty);
      });
    });

    // THE READER, PLANTED. `_selfClaims` returns zero on this file -- correctly,
    // because all eight claim-shaped runs here are quotations or
    // counter-examples -- so the loop above adds no tests and a broken scanner
    // and a correct one look identical from the outside. These tests hand the
    // scanner prose it CAN grade, and a scanner that stops finding claims has
    // to go red here even though it can never go red on the real file.
    group('the reader finds a claim planted in a comment', () {
      test('a bare assertion is read, and a wrong one is caught', () {
        final found = _scanClaims(const [
          '// 110 takes the singular.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isNotEmpty,
            reason: 'the scanner found nothing, so it cannot fail');
        expect(found.single.form, 'singular');
        expect(found.single.from, 110);
      });

      test('a claim WRAPPED across a line break is still read', () {
        // The reason the unit is a run of lines and not a line. A per-line
        // scan splits this sentence in half and grades nothing.
        final found = _scanClaims(const [
          '// the wrong header, and the rule it broke:',
          '// 110 takes',
          '// the singular, exactly as 10 does',
          'void main() {}',
        ], 'planted.dart');
        expect(found.map((c) => c.form).toList(), contains('singular'),
            reason: 'a claim whose paragraph wraps was invisible to the scan');
        expect(found.any((c) => c.from == 110), isTrue,
            reason: 'the number in the wrapped paragraph was not recovered');
        // And the run must not be graded per line: a claim is one sentence
        // spread over a paragraph, not a line that happens to hold a digit.
        expect(found, hasLength(1),
            reason: 'the same claim was counted once per line it appears on');
      });

      // The copula form, planted. The floor test above pins the reach of the
      // pattern against the REAL tree, and the real tree is where the defect
      // was; these pin the two stages that the real file cannot exercise,
      // because `_selfClaims()` on it is correctly empty.
      //
      // Measured: with the exhibit gate reverted, or with the copula branch
      // removed from `_scanClaims`, the suite stayed GREEN at 23/23. Both
      // stages decide what a copula paragraph is and neither is reached by a
      // single line in this tree, so nothing could see them go.
      test('a copula claim is read, and a wrapped one is not missed', () {
        // Not quoted, so this is an ASSERTION about the rule -- the shape this
        // file's own prose avoided for three ticks by writing *takes*.
        final found = _scanClaims(const [
          '// the boundary every count in this app shares:',
          '// 10 is plural, 11 is',
          '// counted singular',
          'void main() {}',
        ], 'planted.dart');
        expect(found.map((c) => c.form).toList(),
            containsAll(<String>['plural', 'singular']),
            reason: 'a copula claim was invisible to the scan');
        expect(found.any((c) => c.from == 10 && c.to == 10), isTrue);
        expect(found.any((c) => c.from == 11 && c.to == 11), isTrue,
            reason: 'a copula claim whose paragraph wraps lost its number');
      });

      test('a copula RANGE is ten claims wearing one coat', () {
        final found = _scanClaims(const [
          '// 3-10 is the broken plural.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, hasLength(1));
        expect(found.single.from, 3);
        expect(found.single.to, 10);
        expect(found.single.form, 'plural',
            reason: '"broken plural" is the plural; the reader must not read '
                'the adjective as a different form');
      });

      test('a copula claim inside quotes is an EXHIBIT', () {
        final found = _scanClaims(const [
          '// it said "110 is singular" and was wrong.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isEmpty,
            reason: 'a corrected sentence quoted back is not a live claim');
      });

      test('a negated copula claim is a counter-example', () {
        final found = _scanClaims(const [
          '// never 110 is singular, the mod-100 rule says so.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isEmpty,
            reason: '"never" inverts the sentence');
      });

      test('a claim inside quotes is an EXHIBIT and is not graded', () {
        final found = _scanClaims(const [
          '// the sentence `110 takes the singular` is the counter-example.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isEmpty,
            reason: 'a quoted sentence states nothing about the app');
      });

      test('a negated claim is a counter-example and is not graded', () {
        final found = _scanClaims(const [
          '// never 110 takes the singular, because that was the bug.',
          'void main() {}',
        ], 'planted.dart');
        expect(found, isEmpty,
            reason: '"never" inverts the sentence; grading it fails a '
                'comment that is correct');
      });

      test('the real file is graded by the loop above, and it is not zero',
          () {
        // This assertion used to be `isEmpty`, and it was honest: every claim-
        // shaped sentence in this file was a quotation or a counter-example, so
        // the self-scan had nothing live to grade and the loop above added no
        // tests. Correcting the false `lib/` claim this tick wrote the
        // correction HERE, unquoted -- "103 takes the plural" is the counter-
        // example to the sentence being corrected -- so the self-scan now reads
        // a real, TRUE claim out of this file and grades it against the helper
        // like any other.
        //
        // That is strictly better than the zero it replaced: a live file the
        // loop grades is a self-policing file, and `isEmpty` would now be
        // failing on the very sentence this tick added. Pinned at >= 1 rather
        // than deleted, because a file that asserts a number and grades none of
        // them is the blindness this whole file was written after.
        expect(_selfClaims(), isNotEmpty,
            reason: 'this file states the correction to a false claim '
                'unquoted, so the loop above grades it -- if this is empty '
                'again, the self-scan has stopped reading this file');
        //
        // The set is pinned EXACTLY, and the reason it used to be `every((c) =>
        // c.from == 103)` is worth keeping: that proxy said "no unexpected live
        // claim has appeared in this file" without being able to tell a new
        // TRUE claim from a new FALSE one. Measured: adding a second, true,
        // unquoted claim to this file -- "120 is counted singular", written
        // while measuring the unread surface of [_articleCensus] -- turned the
        // proxy red for a reason that had nothing to do with correctness.
        //
        // So the expectation is named. Every live claim in this file is now
        // either the counter-example the correction needed, or the
        // census-tick's own statement of why 120 is unread; both are graded by
        // the loop above, so a FALSE one is still caught there. What this adds
        // is the property the proxy was reaching for: a NEW live claim cannot
        // slip in unvouched-for, because the set changes.
        final live = _selfClaims().map((c) => '${c.from}').toSet();
        expect(live, {'103', '120'},
            reason: 'this file now asserts two live claims, both true and both '
                'graded above: $live -- a live claim that is neither the '
                'counter-example (103) nor the census sentence (120) arrived '
                'without being written down here');
      });
    });

    // One test per claim, not one per number: a claim is a sentence, and a
    // sentence is either true or false. Enumerating every number turned a
    // single wrong word into 2196 red tests and drowned the failure in noise.
    for (final c in claims) {
      test(c.toString(), () {
        // A boundary sentence names a form only by reference to its own lower
        // bound, so the form is read off the helper rather than guessed.
        final want = c.uniform
            ? arabicCount(c.from, one, two: two, few: few)
            : _wanted(c.form);
        final wrong = <int>[];
        for (var n = c.from; n <= c.to; n += 1) {
          if (arabicCount(n, one, two: two, few: few) != want) wrong.add(n);
          if (wrong.length == 4) break;
        }
        expect(wrong, isEmpty,
            reason: wrong
                .map((n) => '$n takes the ${_form(want)} form, because its last '
                    'two digits (${n % 100}) ${_pluralWindow(n % 100)}')
                .join('; '));
      });
    }
  });
}

/// Every agreement claim written in a comment under [roots].
///
/// Only comment lines are read. A claim in a string literal is UI copy and
/// belongs to the app; a claim in a comment is an assertion about the code and
/// is this file's business.
/// The claims written in THIS file's own doc comments.
///
/// Same six patterns as [_claims], one root, and the difference that matters
/// is what is dropped. [_claims] skips this file because its comments QUOTE
/// the sentence shapes it hunts -- `110 takes the singular` appears here as
/// the worked example of a sentence the scanner must recognise, and reading
/// it as a claim would make the file grade its own vocabulary.
///
/// So this list is the opposite cut: it keeps only the lines that ASSERT, and
/// drops the ones that EXHIBIT. A line that names the file, a shape, or the
/// scanner is documentation about the mechanism; a line that states a rule
/// about the app is a claim about the app and is checked here.
///
/// Nothing in the tree does this. That is the whole point -- see the test
/// group above.
List<_Claim> _selfClaims() => _scanClaims(
      File('test/agreement_comment_test.dart').readAsLinesSync(),
      'agreement_comment_test.dart',
    );

/// The scanner, over LINES rather than over a file.
///
/// Taking lines instead of a path is what makes this reader honest. Called
/// with this file's own text it returns **zero**, and measured against the
/// eight claim-shaped runs in this file that zero is CORRECT: every one of
/// them is a quotation or a counter-example, an exhibit rather than an
/// assertion. But a reader that returns zero and is never asked about
/// anything else is indistinguishable from a reader that is broken, which is
/// the failure this whole file exists to catch -- so the scanner takes its
/// input as a parameter and is exercised below on prose planted to fail.
///
/// Measured: with the loop over `selfClaims` as the only evidence of this
/// reader, the file ran 10 tests before and 10 after, because a zero-length
/// list adds no tests and cannot fail.
List<_Claim> _scanClaims(List<String> lines, String name) {
  final out = <_Claim>[];

  // Prose WRAPS. A comment that states the claim writes it on one line and
  // finishes the sentence on the next, and a per-line scan is blind to every
  // claim written that way -- which is most of them, because `dart format`
  // wraps at 80 columns and "110 takes the singular" is 24 characters of a
  // line that already had a clause in it. Measured: a false claim planted
  // across a line break was read by nothing, and the suite stayed green.
  //
  // So the unit is a RUN of consecutive comment lines, joined with a space.
  // A blank line, or a non-comment line, ends a run -- which is what makes
  // this a paragraph rather than the whole file.
  final runs = <List<String>>[];
  var run = <String>[];
  void flush() {
    if (run.isNotEmpty) runs.add(List<String>.of(run));
    run = <String>[];
  }

  for (final line in lines) {
    final t = line.trimLeft();
    if (t.startsWith('//')) {
      run.add(t.replaceFirst(RegExp('^//+ ?'), ''));
    } else {
      flush();
    }
  }
  flush();

  // TWO STAGES, and the order is the whole point.
  //
  // Stage 1 blanks quoted spans PER LINE, because a quotation ends at its
  // closing fence and merging lines first would let a backtick opened on one
  // line swallow the rest of the paragraph.
  //
  // Stage 2 decides exhibit-vs-assertion on the JOINED RUN, not per line.
  // Measured: deciding per line made a claim that WRAPS unreadable -- "110
  // takes" carries no form word, so the line was discarded as an exhibit and
  // "the singular." arrived alone with no number attached. A claim is a
  // sentence, and `dart format` wraps sentences, so the unit has to be the
  // paragraph. The mutation test confirms this stage is load-bearing: making
  // the scan per-line leaves the suite green, because a self-contained plant
  // survives either way.
  for (final run in runs) {
    // Quotes are blanked TWICE, and the order is not redundant: a markdown
    // fence is a single line, so a per-line pass closes it where it opened,
    // and THEN the joined pass catches the quotes that WRAP -- "3-10 takes
    // the broken / plural" opens on one line and closes on the next, which a
    // per-line scan cannot balance. Measured: without the second pass the
    // scanner graded this file's own two explanatory sentences as claims.
    final text = _blankQuotedSpans(run.map(_blankQuotedSpans).join(' ')).trim();
    if (_isExhibitText(text)) continue;
    // Every claim shape, through the SAME reader the tree scan uses. Two
    // scanners of one vocabulary must not disagree about what a sentence
    // says -- which is the defect this shared reader exists to end, and the
    // reason the loops that used to sit here, twice, are gone.
    out.addAll(_lineClaims(text, name, 0));
  }
  return out;
}

/// A claim this file SHOWS is not a claim this file ASSERTS.
///
/// Two shapes mark an exhibit, and both are structural rather than a word
/// list:
///
///   * **quoted** -- the sentence sits inside backticks, guillemets or
///     straight double quotes. This file naming the shape its own scanner
///     recognises is an exhibit; the same words unwrapped, in a comment about
///     a day count, are an assertion about the app.
///
///     All three quote marks are blanked because this tree uses all three:
///     guillemets for a sentence quoted out of `arabic_agreement.dart`,
///     backticks for a pattern's worked example, and straight quotes for a
///     sentence mentioned in passing.
///
///     Escaped backticks are the one shape this cannot see, and it is a real
///     one: a backtick span that itself contains a backtick ends at the first
///     unescaped tick, so a quote written as an opening fence, an escaped
///     quote, the sentence, an escaped quote and a closing fence blanks only
///     up to the opening fence. Rather than write a parser for markdown no
///     other line in this tree uses, such a span is simply not written that
///     way: an exhibit that cannot be quoted unambiguously is rewritten as
///     prose saying what it exhibits. Recorded here because it is a real
///     limit, not a clean tree -- the sentence itself is spelled out three
///     lines below, in a comment that quotes it, and graded as the exhibit it
///     is.
///   * **negated** -- the guard's own `_negated` rule, the one that already
///     keeps "never 110 takes the singular" out of [_claims]. A sentence
///     introduced by *never*/*instead of* is a counter-example, and a
///     counter-example states the opposite of the rule; grading it as a claim
///     would fail a comment that is correct.
///
/// Everything left is graded. If this file ever asserts a count in prose, the
/// prose is now held to the same rule as the tree it was written to police.
/// Stage 1: a quoted span is SHOWN, not stated, so blank it.
///
/// Keeping the length and the offsets matters -- the group indices the
/// patterns read below still line up with the original text.
String _blankQuotedSpans(String text) => text
    .replaceAllMapped(RegExp(r'`[^`]*`'), (m) => ' ' * m.group(0)!.length)
    .replaceAllMapped(
        RegExp('\u00ab[^\u00bb]*\u00bb'), (m) => ' ' * m.group(0)!.length)
    .replaceAllMapped(RegExp('"[^"]*"'), (m) => ' ' * m.group(0)!.length);

/// Stage 2: does the surviving text ASSERT a rule, or merely EXHIBIT one?
///
/// Two structural shapes mark an exhibit, and both are shape-based rather
/// than a word list:
///
///   * **quoted** -- the sentence sits inside backticks, guillemets or
///     straight double quotes. Naming the shape this scanner recognises is an
///     exhibit; the same words unwrapped, in a comment about a day count, are
///     an assertion about the app. Handled by [_blankQuotedSpans] above.
///   * **negated** -- a sentence introduced by *never* / *instead of* states
///     the opposite of the rule, so grading it would fail a comment that is
///     correct.
///
/// A paragraph that still holds no claim shape is not an assertion at all --
/// this file's own doc comments are almost entirely about the mechanism, and
/// a rule has to be present in the text before its truth is a question.
bool _isExhibitText(String text) =>
    RegExp(r'(\d+)\s+takes?\s+').hasMatch(text) == false &&
    _copula.hasMatch(text) == false &&
    _andUpCopula.hasMatch(text) == false &&
    // A paragraph of worked examples is a paragraph of claims: the gate has to
    // ask the same question the scanners answer, or the label shape is the one
    // shape this file can exhibit forever without a reader.
    _labelBefore.hasMatch(text) == false &&
    _labelForm.hasMatch(text) == false;


List<_Claim> _claims() {
  final out = <_Claim>[];

  // This file's own doc comments quote the sentence shapes it looks for, which
  // is self-reference and not a claim about the app. Skipping itself is the one
  // exemption; the backstop below is what keeps that exemption honest.
  const self = 'agreement_comment_test.dart';

  void scan(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith(self)) continue;
      // `build/` holds a copy of the tree that no edit can reach.
      final parts = entity.path.split(Platform.pathSeparator);
      if (parts.contains('build')) continue;
      final relative = parts.last;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i].trimLeft();
        if (!raw.startsWith('//')) continue;
        // Quoted spans are blanked HERE, in the tree scan, and this line is the
        // reason the copula pattern could be added at all.
        //
        // Measured: this scan ran per line, matching against the raw text, and
        // never blanked a quoted span. Every pattern above got away with it,
        // because every one of them requires the literal word *takes* and this
        // file writes counter-examples as "110 takes the singular exactly as
        // 10 does" -- which _claims skips for a different reason. The copula
        // form is the FIRST shape that matches inside ordinary prose, so the
        // moment it was added it graded a quoted, corrected sentence ten lines
        // away as a live claim about the app.
        //
        // _scanClaims has always blanked them (stage 1, before the join). Two
        // scanners of the same vocabulary that disagreed about whether a
        // quotation is a statement about the rule, and only the tree scan
        // decides whether a real file goes red.
        final text = _blankQuotedSpans(raw);

        out.addAll(_lineClaims(text, relative, i + 1));
      }
    }
  }

  /// The trees this guard reads.
  ///
  /// A table rather than two calls, because of what the shape costs. The
  /// coverage census in `app_source_scope_test.dart` models a typed
  /// `<String>[...]` literal and `Directory('lib')`, and it **drops** a root
  /// written any other way -- `scan('lib')` is an argument to a call of its
  /// own, and nothing in it says "this guard walks the app". A guard whose
  /// roots the census cannot read registers no coverage, so this rule would
  /// have been enforced in every build while being invisible to the file whose
  /// whole job is noticing a rule that went dark.
  const roots = <String>['lib', 'test'];
  for (final dir in roots) {
    scan(dir);
  }

  // Two patterns can recognise the same sentence — "3-10 takes the broken
  // plural" is both a ranged claim and a prose one — and a claim checked twice
  // is one defect reported as two. Keyed by position and wording, so two
  // genuinely different claims on the same line survive.
  final unique = <String, _Claim>{};
  for (final c in out) {
    unique.putIfAbsent('${c.file}:${c.line}:${c.text}', () => c);
  }
  return unique.values.toList()
    ..sort((a, b) => a.file == b.file
        ? a.line.compareTo(b.line)
        : a.file.compareTo(b.file));
}
