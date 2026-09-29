// The copy helpers were audited for holes *inside* the sentence. This file is
// the other half: the hole *outside* it, where a function that correctly
// answered `''` still had a widget reserving a line box for the answer.
//
// The app's contract, documented in every copy file, is that a count it cannot
// print is silence rather than a lie. `zero_is_silence_test.dart` proves the
// function returns `''`. It cannot prove what the framework does with that `''`
// — and the answer turned out to be "reserve a full line box and draw nothing
// in it", which is a blank band on the screen.
//
// So these cases are measured, not asserted from reasoning. The measurement is
// the whole test: if Flutter ever collapses an empty `Text` on its own, the
// delta goes to zero and this file goes red, which is the correct signal that
// the app is carrying a guard it no longer needs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/widgets/ui.dart';

/// Height of a vertical stack of the given lines, in logical pixels.
Future<double> _stackHeight(WidgetTester tester, List<Widget> children) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(Column).first).height;
}

const _style = TextStyle(fontSize: 14, height: 1.4);

void main() {
  testWidgets('the defect: a raw Text('') reserves a line box', (tester) async {
    final two = await _stackHeight(tester, const [
      Text('سطر أول', style: _style),
      Text('سطر ثانٍ', style: _style),
    ]);
    final withHole = await _stackHeight(tester, const [
      Text('سطر أول', style: _style),
      Text('', style: _style),
      Text('سطر ثانٍ', style: _style),
    ]);
    // The number the fix is built on. If this ever fails, Flutter has started
    // collapsing empty text on its own and [CopyLine] is belt-and-braces.
    expect(withHole - two, 20,
        reason: 'an empty Text in a Column no longer reserves a line box — '
            're-measure before trusting the delta in the other cases');
  });

  testWidgets('CopyLine collapses to nothing when its copy is empty',
      (tester) async {
    final two = await _stackHeight(tester, const [
      CopyLine('سطر أول', style: _style),
      CopyLine('سطر ثانٍ', style: _style),
    ]);
    final withEmpty = await _stackHeight(tester, const [
      CopyLine('سطر أول', style: _style),
      CopyLine('', style: _style),
      CopyLine('سطر ثانٍ', style: _style),
    ]);
    expect(withEmpty, two, reason: 'a silent line still costs height');
  });

  testWidgets('the gap above belongs to the line it separated', (tester) async {
    // The shape the portfolio header had: a title, a `SizedBox(height: 2)`,
    // then a sentence. The 2 px spacer is 2 px of nothing when the sentence
    // is silent, and it survives the text collapsing — which is why the gap
    // moved inside the line.
    final withoutGap = await _stackHeight(tester, const [
      CopyLine('7 صور في معرض أعمالك', style: _style),
      CopyLine('أضفت 3 صور في هذه الجلسة.', style: _style),
    ]);
    final withGap = await _stackHeight(tester, const [
      CopyLine('7 صور في معرض أعمالك', style: _style),
      CopyLine('أضفت 3 صور في هذه الجلسة.', style: _style, gapAbove: 2),
    ]);
    final silentWithGap = await _stackHeight(tester, const [
      CopyLine('7 صور في معرض أعمالك', style: _style),
      CopyLine('', style: _style, gapAbove: 2),
    ]);
    final single = await _stackHeight(tester, const [
      CopyLine('7 صور في معرض أعمالك', style: _style),
    ]);
    expect(withGap - withoutGap, 2, reason: 'a gap that renders is 2 px');
    expect(silentWithGap, single,
        reason: 'a silent line must not leave its gap behind either');
  });

  testWidgets('CopyLine keeps the properties a line really uses',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: CopyLine(
          'نص طويل يفيض عن العرض المتاح في السطر الواحد',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          copyKey: Key('k'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final t = tester.widget<Text>(find.byKey(const Key('k')));
    expect(t.maxLines, 1);
    expect(t.overflow, TextOverflow.ellipsis);
  });
}
