// A project budget of zero, and what the feed says about it.
//
// Found 1 Oct 2026, with the backlog at 0 unchecked, by walking the *write*
// path of the budget pair instead of the read path — every other copy in this
// repo had already been checked against a payload, and the one number a client
// types himself had not.
//
// `Project.budgetLabel` was given five arms: both null, min only, max only,
// equal ends, and a real band. A **zero** was in none of them, so it fell
// through to the band arm and printed
//
//     «من 0 إلى 50000 دج»
//
// on `project_card.dart` and `project_detail_screen.dart` — the card a
// contractor scrolls to pick a job, and the page he reads before quoting.
//
// **The zero is reachable from this app's own form, which is what makes it a
// defect rather than server state.** `DzNumber.tryParse` takes a `min` bound
// and the budget fields do not pass one (`_budgetMinValue` is a bare
// `DzNumber.tryParse(_budgetMin.text)`), so typing `0` parses to the integer
// 0. The form's own `_budgetError` refuses only `min > max`; `0` is not
// greater than anything, so the project publishes with a budget floor of zero.
// `Money.amountOnly(0)` then prints `0` rather than dropping it, because a
// legitimate `0` and a nonsense `0` are the same `0` by the time it is a
// string.
//
// **What it says to a man reading it.** «من 0 دج» is not "no budget given" —
// it is a claim that this renovation is available from nothing, and a
// contractor who reads it as a real floor has no way to tell it apart from
// the project's own «بدون ميزانية محددة», which is the honest rendering of a
// customer who left both boxes empty. Two different facts, one of them a price.
//
// The rule is the one `worker_stats_copy.dart` and `price_range_copy.dart`
// already keep: **a stored 0 is a server default standing in for an answer,
// and must be read as absent, not printed as a measurement.** The slider's own
// floor is 1; a budget of zero dinars is not a budget.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/text/dz_number.dart';
import 'package:allomokawil/src/models/project.dart';

Project _with(Object? min, Object? max) => Project.fromJson({
      'id': 'x',
      'customer_id': 1,
      'title': 't',
      'category': 'painting',
      'images': <String>[],
      'wilaya': '16',
      'budget_min': min,
      'budget_max': max,
      'urgency': 'flexible',
      'status': 'open',
    });

void main() {
  group('a budget of zero is an absent answer, not a price', () {
    test('a zero floor drops the bound and leaves the ceiling', () {
      // The exact sentence the card drew before this fix was
      // «من 0 إلى 50000 دج». Asserted by equality, not `contains('0 دج')`:
      // that substring is inside «حتى 50000 دج» too, so a test written that
      // way would have passed a label that still printed the zero.
      expect(_with(0, 50000).budgetLabel, 'حتى 50000 دج');
    });

    test('a zero ceiling drops the bound too, so a zero pair is silence', () {
      expect(_with(0, 0).budgetLabel, 'بدون ميزانية محددة');
    });

    test('a zero ceiling beside a real floor keeps only the floor', () {
      expect(_with(10000, 0).budgetLabel, 'من 10000 دج');
    });

    test('zero and absent read the same, because they are the same fact', () {
      // A customer who typed 0 has answered nothing, exactly like one who left
      // the box empty. The two rows must not disagree.
      expect(_with(0, 50000).budgetLabel, _with(null, 50000).budgetLabel);
      expect(_with(0, 0).budgetLabel, _with(null, null).budgetLabel);
    });

    test('the collapsed zero pair is the honest "no budget" sentence', () {
      // Never «من 0 إلى 0 دج»: a band whose two ends are the same number is
      // the defect `price_range_copy.dart` was opened for, and zero is where
      // it is reachable from this app's own form.
      expect(_with(0, 0).budgetLabel, 'بدون ميزانية محددة');
    });
  });

  group('the form is where the zero comes from', () {
    test('DzNumber parses a typed 0 as a value, so the label has to reject it',
        () {
      // Pinning the reachability rather than assuming it: with no `min` bound
      // this returns 0, and that 0 is what a published project carries.
      expect(DzNumber.tryParse('0'), 0);
    });

    test('a minus cannot reach the wire, so the zero rule is the whole fix', () {
      // Pinned as the truth it is, rather than as the truth I assumed: the
      // digit fold strips the sign, so «-5000» is read as 5000 and a budget can
      // never be negative. Only the zero has to be answered downstream.
      expect(DzNumber.tryParse('-5000'), 5000);
    });
  });

  group('a real budget is untouched', () {
    test('the band still reads the way the founder spelled it', () {
      expect(_with(60000, 90000).budgetLabel, 'من 60000 إلى 90000 دج');
    });

    test('a single end still reads as a bound', () {
      expect(_with(10000, null).budgetLabel, 'من 10000 دج');
      expect(_with(null, 50000).budgetLabel, 'حتى 50000 دج');
    });

    test('equal ends still collapse to one amount', () {
      expect(_with(7000, 7000).budgetLabel, '7000 دج');
    });
  });
}
