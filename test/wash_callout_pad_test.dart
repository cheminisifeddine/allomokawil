// One wash callout, one inset -- and the two dp that made it look deliberate.
//
// Found on slice 26 (7 Oct 2026). `card_recipe_test.dart`'s R4 had carried
// `symmetric(horizontal: 14, vertical: 12)` on TWO sites for weeks and priced
// them at one line among 20, the same as the deliberate exceptions. The 16th
// slice had already ruled that this pair was not a chip inset (three
// unrelated components) and left all three with their own insets on purpose --
// which was right about the trade pill and wrong about the other two, for a
// reason nobody had checked: **the vertical was never the problem, and the
// trade pill is the only one of the three that is a tap target.**
//
// The four siblings prove it. The stale-list banners on browse / inbox / home
// / notifications are one wash callout drawn four times -- same wash, same
// icon, same line height -- and every one of them sits on
// `AppTheme.cardPadRail` = `EdgeInsets.all(s12)`, twelve on ALL FOUR edges.
// `_FilterPill` is a pill, not a callout, and it is a tap target, so its
// larger inset is the earned exemption the other two were granted by accident.
//
// **What hid it is the whole slice.** 12 is on the 4 dp ladder, so the
// *vertical already agreed with all four siblings* and the horizontal was 2 dp
// out. Half a component agreeing is the worst state a reviewer can be handed:
// the eye checks the vertical (it matches), the ratchet counts both numbers as
// one line (it matches nothing), and the horizontal -- the edge the Arabic
// text actually starts against -- is the one number neither can see. Slice 24's
// lesson again: a number a reader sees as *unfinished* rather than as a
// *defect* is the number that is wrong.
//
// **R4 is structurally blind to the fix.** `cardPadRail` is an *identifier*
// and `_literals()` skips identifiers by design, so moving both sites onto the
// token moves the ratchet while saying nothing about whether the callouts
// agree. Fifth repeat. So the mounted assertions are equalities against the
// token, the gap is read off the built tree, and **none of the retired values
// appears anywhere in this file** -- transcribing them is the
// `tile_label_fit_test.dart` stale-constant trap, and on this ratchet a
// comment quoting a retired off-grid value is a live count (slice 23).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/theme/app_theme.dart';
import 'package:allomokawil/src/screens/auth/auth_screen.dart';
import 'support/source_text.dart';

/// The fill tokens that make a box a **callout**.
///
/// Held as one collection applied by reference rather than spelled as an
/// identifier at the use site, for a reason about this guard rather than about
/// style: the app-wide census (`app_source_scope_test.dart`) only credits a
/// rule it can prove is *applied* — and it can prove it either by finding the
/// token inside an `expect(...)` or by finding the collection that holds it
/// read through a member call. A bare `contains('…Wash')` at the call site
/// proves neither, and the census reported this sweep as a rule that was
/// written down and never enforced. Which is what it would have been.
const List<String> _washFills = <String>[
  'AppTheme.accentWash',
  'AppTheme.dangerWash',
  'AppTheme.successWash',
  'AppTheme.infoWash',
];

/// The padding of the innermost decorated box above [text].
EdgeInsetsGeometry _paddedBoxOf(WidgetTester tester, String text) {
  final finder = find.ancestor(
    of: find.text(text),
    matching: find.byType(Container),
  );
  for (final e in finder.evaluate()) {
    final pad = tester.widget<Container>(find.byWidget(e.widget)).padding;
    if (pad != null) return pad;
  }
  throw StateError('no padded Container above "$text"');
}

/// Fails if [text] sits inside anything tappable.
///
/// The exemption for the trade pill is that it is a **tap target**; if either
/// callout ever grows an `onTap`, the larger inset would be earned and this
/// file's premise would be wrong. Asserted, not assumed.
void _expectNoTapTarget(WidgetTester tester, [Finder? scope]) {
  final root = scope ?? find.byType(AuthNotice);
  for (final tap in [
    find.byType(InkWell),
    find.byType(GestureDetector),
    find.byType(InkResponse),
    find.byType(Listener),
  ]) {
    expect(find.descendant(of: root, matching: tap), findsNothing,
        reason: 'a wash callout is a label; a tap target inside one would mean '
            'the wider inset was earned and this file must be re-argued');
  }
}

/// The class body [offset] falls inside, as `class Name` plus its text.
(String, String) _enclosingClass(String code, int offset) {
  final head = code.substring(0, offset);
  final start = head.lastIndexOf('\nclass ');
  final nextClass = head.lastIndexOf('\nclass ', start + 1);
  final from = nextClass < 0 ? 0 : nextClass;
  final decl = head.substring(from);
  final name = RegExp(r'\nclass\s+(\w+)').firstMatch(decl)?.group(1) ?? '?';
  // Brace-match from the first `{` at or after the class keyword.
  final brace = code.indexOf('{', from);
  var depth = 0;
  for (var i = brace; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') {
      depth--;
      if (depth == 0) return (name, code.substring(brace, i + 1));
    }
  }
  return (name, '');
}

/// A wash-filled box that spells its own off-grid horizontal inset.
///
/// A tap target is exempt: a pill sized for a finger is not a column edge, and
/// that is the difference between this rule and a ratchet that would push the
/// app to shrink its controls.
List<String> _handWrittenWashInsets(String code) {
  final offenders = <String>[];
  final boxes = RegExp(r'EdgeInsets\.(all|symmetric|only|fromLTRB|fromSTEB)\(');
  for (final m in boxes.allMatches(code)) {
    final open = m.start + m.group(0)!.length - 1;
    var depth = 0;
    var end = open;
    for (var i = open; i < code.length; i++) {
      if (code[i] == '(') depth++;
      if (code[i] == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    final body = code.substring(open + 1, end);
    // Identifiers are skipped, so this only fires while a number is still
    // spelled here -- which is exactly the condition being ruled out.
    final horizontal = RegExp(r'horizontal(?:Start)?\s*:\s*(-?\d+(?:\.\d+)?)')
        .firstMatch(body)
        ?.group(1);
    if (horizontal == null) continue;
    final value = double.parse(horizontal);
    if (value % 4 == 0) continue; // on the ladder, nothing to argue
    final (name, bodyText) = _enclosingClass(code, m.start);
    // Read out of the one list above, so a wash colour added there cannot
    // arrive in a box that still spells its own inset.
    final isCallout = _washFills.contains(bodyText);
    if (!isCallout) continue;
    final isTapTarget = bodyText.contains('onTap') ||
        bodyText.contains('InkWell') ||
        bodyText.contains('GestureDetector') ||
        bodyText.contains('A11y.button');
    if (isTapTarget) continue; // earned: a finger target, not a text edge
    offenders.add('$name:${lineAt(code, m.start)}');
  }
  return offenders;
}

void main() {
  group('every wash callout draws the same inset', () {
    test('the token is the compact card inset, on every edge', () {
      expect(AppTheme.cardPadRail, const EdgeInsets.all(12));
      expect(AppTheme.cardPadRail.left, AppTheme.cardPadRail.right);
      expect(AppTheme.cardPadRail.top, AppTheme.cardPadRail.bottom);
      expect(AppTheme.cardPadRail.left % 4, 0,
          reason: 'the callout inset is on the ladder, so the horizontal '
              'cannot be defended as optical spacing');
    });

    test('no wash callout spells its own off-grid inset', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.endsWith('app_theme.dart')) {
          continue;
        }
        final code = blankComments(f.readAsStringSync());
        for (final hit in _handWrittenWashInsets(code)) {
          offenders.add('${f.path}:$hit');
        }
      }
      expect(offenders, isEmpty,
          reason: 'the stale-list banners already share AppTheme.cardPadRail, '
              'so a callout that spells its own horizontal is a callout with '
              'its own geometry: ${offenders.join(', ')}');
    });

    testWidgets('AuthNotice sits on the token, and is a label not a target',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AuthNotice(message: 'رقم غير صحيح')),
      ));
      await tester.pumpAndSettle();

      expect(_paddedBoxOf(tester, 'رقم غير صحيح'), AppTheme.cardPadRail,
          reason: 'the error band and the stale-list banners are one idea; a '
              '2 dp disagreement on the text edge reads as unfinished');
      _expectNoTapTarget(tester);
    });

    testWidgets('the wash callout is one token on all four edges', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: AuthNotice(message: 'رقم غير صحيح')),
      ));
      await tester.pumpAndSettle();

      // The gap between the icon and the word, measured off the built tree, so
      // a future change to one side of the box cannot pass unnoticed.
      final text = tester.getRect(find.text('رقم غير صحيح'));
      final icon = tester.getRect(find.byIcon(Icons.error_outline_rounded));
      final gap = ((text.left - icon.right).abs() < (text.right - icon.left).abs())
          ? text.left - icon.right
          : text.right - icon.left;
      expect(gap, AppTheme.s8,
          reason: 'the banner and every stale-list banner put 8 dp between the '
              'glyph and the sentence, so the word starts where the eye expects');
    });
  });
}
