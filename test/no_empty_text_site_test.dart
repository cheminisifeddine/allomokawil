// A family-wide guard, in the same spirit as `zero_is_silence_test.dart`.
//
// That file proves a copy *function* never returns a half-sentence. This one
// proves the *callers* never hand a possibly-empty sentence to a widget that
// would reserve a line box for it. The two halves are the same defect seen from
// each side, and either alone is satisfied by a codebase where the other half
// is broken.
//
// The rule: an expression built from a copy function that can answer `''`
// reaches a `Text` only through `CopyLine` or behind an `isNotEmpty` / `isEmpty`
// branch. Both are legitimate; a bare `Text(fn())` is the hole.
//
// Why the source and not the widget tree: a widget test only sees the screens
// it was written to pump, and a screen nobody thought of has no test. The
// source sweep sees every one of them — including the two that already had a
// correct branch, which is why the rule tolerates a branch instead of banning
// the pattern outright.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/notification_copy.dart';
import 'package:allomokawil/src/data/notification_shortfall_copy.dart';
import 'package:allomokawil/src/data/partial_market_copy.dart';
import 'package:allomokawil/src/data/partial_thread_copy.dart';
import 'package:allomokawil/src/data/quote_status_copy.dart';
import 'package:allomokawil/src/models/enums.dart' show QuoteStatus;
import 'package:allomokawil/src/models/quote_review.dart';

/// Copy functions whose contract is "empty string when the value cannot be
/// printed". Kept honest by the first test below, which fails if the codebase
/// grows one this file has never heard of.
const _emptyReturning = <String>{
  'addedAdjectiveAr',
  'addedPhotosLineAr',
  'communeCountAr',
  'durationDaysAr',
  // The `partial_*` family, added 9 Oct 2026 — the list had gone stale for
  // weeks and the sweep below was policing 19 functions out of 23.
  'lostPagesAr',
  // Added 10 Oct 2026 with `notification_shortfall_copy.dart`. Both of its
  // functions answer '' and BOTH were reported by this guard one after the
  // other, which is the guard working: the file was registered, the next entry
  // turned up on the following run.
  //   * `notificationHiddenCountAr` is '' for `n <= 0` -- there is no noun to
  //     print.
  //   * `notificationShortfallLineAr` is '' in the three states the phone
  //     cannot claim: no server count, an empty centre, or no gap.
  // Both are proved from the real functions below rather than described.
  'notificationHiddenCountAr',
  'notificationShortfallLineAr',
  'partialMarketLineAr',
  'partialThreadLineAr',
  'photosAr',
  'portfolioCountLineAr',
  'queuedCountLabel',
  'quoteDurationLineAr',
  'quoteStatusAr',
  'quoteStatusNoteAr',
  'quotesAr',
  'readAgeAr',
  'relativeTimeAr',
  'undrawnMessagesAr',
  'unreadMessagesLabel',
  'uploadedThisSessionAr',
  'wilayaSpanAr',
};

/// Two screens whose call site branches on the **predicate** rather than on
/// the string. Each is proved by [the exemptions are still non-empty].
const _exempt = <String>{
  'lib/src/screens/chat/chat_list_screen.dart',
  'lib/src/screens/project/project_detail_screen.dart',
};

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

/// The body of the function whose declaration ends at [start], brace-matched.
String _body(String src, int start) {
  final open = src.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return '';
}

/// True when the [before] lines around a `Text` show a deliberate branch or a
/// [CopyLine].
bool _isGuarded(List<String> before) => before.any((l) =>
    l.contains('isNotEmpty') ||
    l.contains('isEmpty') ||
    l.contains('CopyLine'));

/// A `return` that produces **no widget at all**, between the start of the
/// enclosing block and the `Text`, is the other legitimate guard — and the one
/// the 3-line window could not see.
///
/// `chat_screen.dart::_olderStrip` and `worker_home_screen.dart::
/// _partialMarketSlivers` both branch on a **predicate** (`if
/// (partialThreadMayClaimComplete(...)) return const SizedBox.shrink();`) and
/// build the sentence twenty lines further down. Measuring three lines above
/// the `Text` called that a hole, and adding both files to [_exempt] would have
/// been the wrong repair: it switches off the *other* two sweeps for the whole
/// file, so a real hole anywhere else in a 2000-line chat screen would go
/// unseen. This accepts the shape and leaves the file under test.
///
/// The honest cost, recorded rather than hidden: a function that returns early
/// for an unrelated reason and *also* draws a possibly-empty copy raw would
/// pass. That is why the predicate's real claim is proved at runtime in
/// ['a predicate that bails before the draw is a real guard'] rather than
/// trusted from the text.
bool _bailsBeforeDraw(String src, int drawStart, int blockStart) => RegExp(
        r'return\s+(?:const\s+)?(?:SizedBox\.shrink\(\)|<\s*Widget\s*>\[\s*\])\s*;')
    .hasMatch(src.substring(blockStart, drawStart));

/// The span of the block enclosing [index] — the nearest `{` before it and its
/// match. This is what makes a local name *local*: a name declared in one
/// function says nothing about another function in the same file, and without
/// this the sweep reported every `Text(label)` in `ui.dart` because
/// `StatusPill.quote` declares a local called `label`.
List<int> _enclosingBlock(String src, int index) {
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    if (src[i] == '}') depth++;
    if (src[i] == '{') {
      if (depth == 0) {
        var d = 0;
        for (var j = i; j < src.length; j++) {
          if (src[j] == '{') d++;
          if (src[j] == '}') {
            d--;
            if (d == 0) return <int>[i, j];
          }
        }
        return <int>[i, src.length];
      }
      depth--;
    }
  }
  return <int>[0, src.length];
}

void main() {
  test('every declared empty-returning copy function is in the list', () {
    final declared = <String>{};
    final pattern = RegExp(r'''return\s+(''|"")\s*;''');
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r'^(?:String\??|String)\s+(\w+)\s*\([^)]*\)\s*\{',
              multiLine: true)
          .allMatches(src)) {
        if (pattern.hasMatch(_body(src, m.end - 1))) {
          declared.add(m.group(1)!);
        }
      }
    }
    // Normalisation helpers in core/text are allowed to answer '' too; they
    // are not copy and are never drawn.
    //
    // `_wireText` (plan.dart, added 1 Oct 2026) earns its place here for the
    // same reason `normalize` does: it is a wire reader, not copy. It answers
    // '' for an absent id so an id column never prints the literal «null» — and
    // nothing draws it directly. The one place an id reaches a label, `labelAr`,
    // goes through `_text` and then falls back to this, and `PaymentOptions`
    // drops any method whose id comes back empty precisely so that fallback can
    // never produce a nameless pay button. That chain is pinned in
    // `billing_json_shape_test.dart`, so an empty answer here is not copy
    // reaching a `Text()`.
    const notCopy = {'normalize', 'fold', 'digits', '_wireText'};
    final missing = declared.difference(_emptyReturning).difference(notCopy);
    expect(missing, isEmpty,
        reason: 'a copy function can now answer "" and this guard has never '
            'heard of it: $missing');
  });

  test('the exemptions are still non-empty by their own premise', () {
    // The exemptions are claims about the *inputs*, not about the strings, and
    // a claim that is only true today is worse than no guard. So each is proved
    // here, from the same function the screen calls.
    //
    // `chat_list_screen.dart` — `relativeTimeAr` is `''` **iff** its argument
    // is null, and the row draws it only when `lastMessageAt != null`.
    expect(relativeTimeAr(null), '');
    final now = DateTime(2026, 9, 29, 12);
    const ages = <int>[
      0, 1, 59, 60, 61, 119, 120, 300, 1440, 5000, 60000, 900000, //
    ];
    for (final minutes in ages) {
      final said =
          relativeTimeAr(now.subtract(Duration(minutes: minutes)), now: now);
      expect(said.isNotEmpty, isTrue, reason: 'a $minutes-minute-old row');
    }
    // A future timestamp is the other null-free input, and it answers «الآن».
    expect(relativeTimeAr(now.add(const Duration(hours: 5)), now: now), 'الآن');

    // `project_detail_screen.dart` — `quoteStatusNoteAr` is `''` for `pending`
    // and for nothing else, and the card draws it only on the `isDecided`
    // branch, which is `status != pending` by the same definition.
    expect(quoteStatusNoteAr(QuoteStatus.pending), '');
    expect(quoteStatusNoteAr(QuoteStatus.accepted).isNotEmpty, isTrue);
    expect(quoteStatusNoteAr(QuoteStatus.rejected).isNotEmpty, isTrue);
    expect(
      Quote.fromJson(<String, dynamic>{
        'id': 1,
        'project_id': '9',
        'worker_id': 3,
        'amount': 1000,
        'status': 'pending',
        'worker_full_name': 'س',
      }).isDecided,
      isFalse,
    );
  });

  test('a predicate that bails before the draw is a real guard', () {
    // The claim [_bailsBeforeDraw] accepts on the *text* of a source file:
    // that a function returned no widget before it reached the draw. Text is
    // not a proof, so the underlying claim is proved here instead, from the
    // copy and the predicate themselves: **the sentence is silent exactly when
    // the predicate says the read was complete.** Not "silent somewhere" — the
    // two sides are equal on every input, which is the only way the early
    // return is entitled to stand in for the missing `isEmpty` test.
    //
    // If either half drifts, the band goes blank on the inputs where they
    // disagree, and this is the assertion that catches it.
    const counts = [0, 1, 2, 3, 11, 130, 5000];
    for (final n in counts) {
      expect(partialThreadLineAr(undrawn: n, drawn: 100).isEmpty,
          partialThreadMayClaimComplete(undrawn: n),
          reason: 'thread: the band and the predicate disagree at undrawn=$n');
      expect(partialMarketLineAr(lost: n, total: 100).isEmpty,
          partialMarketMayClaimNoResults(lost: n, total: 100),
          reason: 'market: the band and the predicate disagree at lost=$n');
    }
    // Pinned, because the equality above holds for a reason and the reason is
    // that both spell the threshold the same way: `<= 0`, not `== 0`. Change
    // one side to `== 0` and a negative count makes exactly one of them lie.
    expect(partialThreadMayClaimComplete(undrawn: -1), isTrue);
    expect(partialMarketMayClaimNoResults(lost: -1, total: 5), isTrue);
    expect(partialThreadLineAr(undrawn: -1, drawn: 100), '');
    expect(partialMarketLineAr(lost: -1, total: 100), '');
    // `notification_shortfall_copy.dart` — `notificationHiddenCountAr` is ''
    // for `n <= 0`, and the band that draws it only exists when `hidden > 0`.
    // Proved from the real function, not asserted about the guard: the band
    // builder is given a shortfall whose `hidden` is already known positive,
    // so a zero count is unreachable from the drawing site rather than merely
    // filtered there.
    expect(notificationHiddenCountAr(0), '');
    expect(notificationHiddenCountAr(-1), '');
    expect(notificationHiddenCountAr(1), isNotEmpty);
    // The band refuses every state that would print a zero-count noun, so the
    // '' cannot reach a `Text()` even if a caller passed one.
    expect(
        notificationShortfallLineAr(const NotificationShortfall(
            serverUnread: 5, unreadDrawn: 5, drawn: 5)),
        '');
    expect(
        notificationShortfallLineAr(
            const NotificationShortfall(serverUnread: 0)),
        '');
    // And the count words themselves stay silent at zero — the guard is not
    // merely hiding an empty string behind a predicate.
    expect(undrawnMessagesAr(0), '');
    expect(lostPagesAr(0), '');
  });

  test('no Text() is handed a bare possibly-empty copy call', () {
    final offenders = <String>[];
    for (final f in _sources()) {
      if (_exempt.contains(f.path)) continue;
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      for (final m in RegExp(r'\bText\s*\(\s*(\w+)\s*\(').allMatches(src)) {
        if (!_emptyReturning.contains(m.group(1))) continue;
        final line = src.substring(0, m.start).split('\n').length;
        if (_isGuarded(
            lines.sublist((line - 3).clamp(0, lines.length), line))) {
          continue;
        }
        // The window above is three lines; the predicate shape is not. See
        // [_bailsBeforeDraw].
        final block = _enclosingBlock(src, m.start);
        if (_bailsBeforeDraw(src, m.start, block[0])) continue;
        offenders.add('${f.path}:$line  ${lines[line - 1].trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a copy function that answers "" is drawn by a raw Text, so '
            'an unanswered count becomes a blank band:\n${offenders.join("\n")}');
  });

  test('a possibly-empty local is not drawn raw either', () {
    // The first version of this sweep only looked for `Text(someFn(` — a call
    // written straight into the widget. It stayed green on a sabotage that
    // deleted the guard from the live wilaya sheet, because the honest way to
    // write that call site is to name the string first:
    //
    //     final countLine = communeCountAr(matches);
    //     Text(countLine, ...)
    //
    // which the regex cannot see at all. So this case follows the name from its
    // declaration to the widget. It is the shape a careful writer uses, which
    // makes it the one a lazy sweep misses.
    //
    // Scope is deliberately narrow: a local bound **directly** to one of the
    // copy calls, in a file that is not exempt. Matching on the name alone
    // reported five widgets in `ui.dart` that never call a copy function at
    // all — `StatusPill.quote` holds a local called `label`, and every button
    // in the kit holds one too.
    final offenders = <String>[];
    for (final f in _sources()) {
      if (_exempt.contains(f.path)) continue;
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      // name -> the span of the block that declares it, so the search for its
      // uses is confined to that function.
      final locals = <String, List<int>>{};
      for (final m in RegExp(r'(?:final|var)\s+(\w+)\s*=\s*(\w+)\s*\(')
          .allMatches(src)) {
        if (!_emptyReturning.contains(m.group(2))) continue;
        locals[m.group(1)!] = _enclosingBlock(src, m.start);
      }
      if (locals.isEmpty) continue;
      for (final m in RegExp(r'\bText\s*\(\s*(\w+)\s*[,)]').allMatches(src)) {
        final name = m.group(1)!;
        final span = locals[name];
        if (span == null) continue;
        if (m.start <= span[0] || m.start >= span[1]) continue;
        final line = src.substring(0, m.start).split('\n').length;
        // The guard is **anywhere between the binding and the draw**, not in
        // the three lines above it. A three-line window is what left both real
        // sites looking like holes: `if (countLine.isEmpty) return …` sits
        // eight lines above the `Text` it protects, and
        // `if (when.isNotEmpty) ...[` sits five. The test has to ask the
        // question the code actually answers — *was this name checked for
        // emptiness before it was drawn* — or it is measuring line distance.
        final declared = locals[name]!;
        final between = lines
            .sublist(
                (src.substring(0, declared[0]).split('\n').length - 1)
                    .clamp(0, lines.length),
                line)
            .join('\n');
        final tested =
            RegExp('$name\\s*\\.\\s*is\\s*(Not)?Empty').hasMatch(between);
        if (tested ||
            _isGuarded(
                lines.sublist((line - 3).clamp(0, lines.length), line))) {
          continue;
        }
        offenders.add('${f.path}:$line  ${lines[line - 1].trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'a local bound to a copy function is drawn by a raw Text:'
            '\n${offenders.join("\n")}');
  });

  test('a gap left outside a collapsing line does not survive it', () {
    // The second half of the portfolio-header fix, and the half that outlives
    // the text collapsing: a `const SizedBox(height: n)` left as a sibling of
    // a line that may be silent is n px of nothing by itself. Only the gap that
    // moves *inside* the line goes away with it.
    final offenders = <String>[];
    for (final f in _sources()) {
      final src = f.readAsStringSync();
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!RegExp(r'const SizedBox\(height:').hasMatch(lines[i])) continue;
        final window = [
          ...lines.sublist((i - 3).clamp(0, i), i),
          ...lines.sublist(i + 1, (i + 4).clamp(0, lines.length)),
        ].join('\n');
        if (window.contains('CopyLine')) {
          offenders.add('${f.path}:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a spacer left outside a collapsing line survives it:'
            '\n${offenders.join("\n")}');
  });
}
