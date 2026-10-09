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
    r'(?:the\s+)?(broken\s+plural|plural|dual|singular)',
    caseSensitive: false);

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

void main() {
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

      test('the real file yields zero claims, and that zero is correct', () {
        // The honest closure: this reader's live input really does produce
        // nothing, and the reason is stated rather than assumed.
        expect(_selfClaims(), isEmpty);
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
    for (final m in _englishForm.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      final lo = int.parse(m.group(1)!);
      final hi = int.parse(m.group(2) ?? '$lo');
      out.add(_Claim(name, 0, lo, hi,
          m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
    }
    for (final m in _quotedNoun.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      final form = _arabicForms[m.group(3)!];
      if (form == null) continue;
      final lo = int.parse(m.group(1)!);
      final hi = int.parse(m.group(2) ?? '$lo');
      out.add(_Claim(name, 0, lo, hi, form, m.group(0)!));
    }
    for (final m in _andUp.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      final lo = int.parse(m.group(1)!);
      out.add(_Claim(name, 0, lo, lo + _window,
          m.group(2)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
    }
    for (final m in _ranged.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      out.add(_Claim(name, 0, int.parse(m.group(1)!), int.parse(m.group(2)!),
          m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
    }
    for (final m in _meansUpTo.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      out.add(_Claim(name, 0, int.parse(m.group(1)!), int.parse(m.group(2)!),
          'singular', m.group(0)!, uniform: true));
    }

    // The copula form. A range is a range here too: "3-10 is the broken
    // plural" is ten claims wearing one coat, exactly as "3-10 takes the
    // broken plural" is above.
    for (final m in _copula.allMatches(text)) {
      if (_negated.hasMatch(text.substring(0, m.start))) continue;
      final lo = int.parse(m.group(1)!);
      final hi = int.parse(m.group(2) ?? '$lo');
      out.add(_Claim(name, 0, lo, hi,
          m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
    }
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
    _copula.hasMatch(text) == false;


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

        for (final m in _englishForm.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          final hi = int.parse(m.group(2) ?? '$lo');
          out.add(_Claim(relative, i + 1, lo, hi,
              m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
        }

        for (final m in _quotedNoun.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final form = _arabicForms[m.group(3)!];
          if (form == null) continue; // a noun from some other sentence
          final lo = int.parse(m.group(1)!);
          final hi = int.parse(m.group(2) ?? '$lo');
          out.add(_Claim(relative, i + 1, lo, hi, form, m.group(0)!));
        }

        for (final m in _andUp.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          // No upper bound is given, so the claim runs to the end of the
          // window — checking only the lower number would let the one form of
          // this sentence that is always false pass.
          out.add(_Claim(relative, i + 1, lo, lo + _window,
              m.group(2)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
        }

        for (final m in _ranged.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          out.add(_Claim(relative, i + 1, int.parse(m.group(1)!),
              int.parse(m.group(2)!),
              m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
        }

        for (final m in _meansUpTo.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          out.add(_Claim(relative, i + 1, lo, int.parse(m.group(2)!),
              'singular', m.group(0)!, uniform: true));
        }

        for (final m in _open.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          out.add(_Claim(relative, i + 1, lo, lo + _window,
              m.group(2)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
        }

        // The copula form, in the tree scan as well. Without this line the
        // reader reads a paragraph only when it holds the word *takes*, so
        // "10 is plural, 11 is counted singular" -- eleven true sentences
        // across the tree, and one false one -- is graded by nothing.
        for (final m in _copula.allMatches(text)) {
          if (_negated.hasMatch(text.substring(0, m.start))) continue;
          final lo = int.parse(m.group(1)!);
          final hi = int.parse(m.group(2) ?? '$lo');
          out.add(_Claim(relative, i + 1, lo, hi,
              m.group(3)!.replaceAll('broken ', '').toLowerCase(), m.group(0)!));
        }
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
