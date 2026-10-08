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

    test('the reader found the claims it was written to find', () {
      // A scanner that silently matches nothing reports a clean tree, which is
      // indistinguishable from a clean tree. This is the backstop that makes
      // the result below it mean something.
      expect(claims.length, greaterThanOrEqualTo(6),
          reason: 'only ${claims.length} agreement claims were read out of '
              'lib/ and test/ -- this reader is broken, not the tree');
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
        final text = lines[i].trimLeft();
        if (!text.startsWith('//')) continue;

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
