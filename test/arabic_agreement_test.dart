// Arabic number agreement, pinned in all four forms.
//
// Found on 26 Sep 2026 by auditing the code the *previous* cycle shipped. The
// subscription countdown was written as the app's third copy of the "which
// noun form does this number take" rule and it was wrong: it printed «يوماً» for
// every count, so a contractor one day from renewal read «ينتهي الاشتراك بعد 1
// يوماً» and one two days out read «بعد 2 يوماً». Two of the three copies were
// right, which is what made the third one safe-looking.
//
// These tests are for the primitive, not the screens, because the failure mode
// is a rule that is correct in one file and wrong in another. The screen-level
// consequence is pinned in `subscription_clock_test.dart`; this file makes sure
// the shared rule is right so the screen cannot be right by accident.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/arabic_agreement.dart';
import 'package:allomokawil/src/data/chat_outbox.dart' show queuedCountLabel;
import 'package:allomokawil/src/data/worker_stats_copy.dart'
    show responseTimeAr, serviceRadiusAr;
import 'package:allomokawil/src/data/notification_copy.dart'
    show relativeTimeAr;
import 'package:allomokawil/src/models/plan.dart' show SubscriptionStatus;

void main() {
  group('the four forms of a counted noun', () {
    // masculine — the shape «بعد N يوم» needs
    const one = 'يوم';
    const two = 'يومين';
    const few = 'أيام';

    test('one takes the singular, with no number in front of it', () {
      expect(arabicCount(1, one, two: two, few: few), one);
      // The singular is never counted with "1": the number is what makes the
      // noun singular, and it already is singular at one. Writing «1 يوم» is
      // the English habit, not the Arabic one. (An earlier version of this
      // helper printed exactly that and the notification test caught it.)
      expect(arabicCounted(1, one, two: two, few: few), one);
      expect(arabicCounted(1, one, two: two, few: few), isNot(contains('1')));
      expect('1 $one', isNot(arabicCounted(1, one, two: two, few: few)));
    });

    test('two takes the dual, and the dual is never counted', () {
      expect(arabicCount(2, one, two: two, few: few), two);
      // No "2" anywhere: the dual form already says "two".
      expect(arabicCounted(2, one, two: two, few: few), two);
      expect(arabicCounted(2, one, two: two, few: few), isNot(contains('2')));
    });

    test('three to ten take the broken plural', () {
      for (final n in [3, 4, 7, 9, 10]) {
        expect(arabicCounted(n, one, two: two, few: few), '$n $few',
            reason: 'n=$n is in the 3-10 plural range');
      }
    });

    test('eleven and up are counted singular again', () {
      // The rule people get wrong: 11+ is NOT the plural. «قبل 15 دقيقة»,
      // «بعد 100 يوماً» — never «بعد 100 أيام».
      //
      // "11 and up" does not mean up to infinity. It stops at 102: a count
      // ending in 3-10 takes the plural again, whatever the century. That is
      // why 110 is not in this list — see the mod-100 group below.
      for (final n in [11, 15, 40, 100, 365]) {
        expect(arabicCounted(n, one, two: two, few: few), '$n $one',
            reason: 'n=$n is counted singular');
      }
    });

    test('the boundary is 10/11, not 10/20 or 1/3', () {
      expect(arabicCounted(10, one, two: two, few: few), '10 $few');
      expect(arabicCounted(11, one, two: two, few: few), '11 $one');
    });
  });

  // The rule that was wrong in the helper itself, not in a copy of it.
  //
  // A counted noun is decided by the LAST TWO DIGITS of the number, so the
  // plural range repeats every hundred: 103 takes «أيام» exactly as 3 does,
  // and so does 110 — `110 % 100` is 10, and 10 is in the window. The helper
  // tested `n <= 10`, which is that rule said only for the first hundred, and
  // so gave the singular to every three-digit count ending in 3-10.
  //
  // The range is reachable: the service-radius slider on the profile-edit
  // screen runs `max: 200`, and its value is saved verbatim to the profile
  // and printed through this helper on the profile a customer picks a
  // tradesman from.
  group('the plural range repeats every hundred', () {
    const one = 'يوم';
    const two = 'يومين';
    const few = 'أيام';

    test('103-110 take the broken plural, exactly as 3-10 do', () {
      for (final n in [103, 104, 105, 107, 110]) {
        expect(arabicCounted(n, one, two: two, few: few), '$n $few',
            reason: 'n=$n ends in ${n % 100}, which is in the 3-10 plural '
                'range');
      }
    });

    test('111 and up are singular again, and so are 101 and 102', () {
      // The other side of the boundary: 101 and 102 are NOT dual and NOT
      // plural, and 111 has left the repeating range behind again.
      for (final n in [101, 102, 111, 150, 201, 302]) {
        expect(arabicCounted(n, one, two: two, few: few), '$n $one',
            reason: 'n=$n ends in ${n % 100}, which is not in 3-10');
      }
    });

    test('and the far side of the century is not the near side', () {
      // 203 and 305 end in 3 and 5, so they take the plural too. A fix that
      // only handled the first hundred would pass the test above and fail
      // here.
      for (final n in [203, 305, 1003]) {
        expect(arabicCounted(n, one, two: two, few: few), '$n $few',
            reason: 'n=$n ends in ${n % 100}, which is in the 3-10 range');
      }
    });

    test('a number that merely ends in 2 is not the dual', () {
      // 102 is not a dual. The dual form takes no number with it, so a
      // three-digit count must never borrow that shape on its last digit
      // alone. (2 itself IS the dual — that is the case one line above.)
      for (final n in [102, 202, 302, 1002]) {
        final out = arabicCounted(n, one, two: two, few: few);
        expect(out, isNot(contains(two)), reason: 'n=$n gave $out');
        expect(out, '$n $one', reason: 'n=$n gave $out');
      }
    });

    test('the two helpers pick the same noun for the same number', () {
      // [arabicCount] and [arabicCounted] differ only in printing: the
      // counted form drops the digit for 1 and 2. A fix to one that missed
      // the other would show up here and nowhere else. The suffix is compared
      // rather than the whole string, so 1 and 2 are real cases here too.
      for (final n in [1, 2, 3, 10, 11, 103, 110, 365]) {
        final plain = arabicCount(n, one, two: two, few: few);
        final counted = arabicCounted(n, one, two: two, few: few);
        expect(counted.endsWith(plain), isTrue,
            reason: 'n=$n: counted is "$counted", which does not end in the '
                'noun arabicCount chose, "$plain"');
      }
    });
  });

  group('the screen-level consequence of the mod-100 rule', () {
    // The primitive is only worth fixing if the number that reaches it can
    // actually be three digits. The service radius is the one in this app
    // that is: `Slider(min: 1, max: 200, divisions: 199)` in
    // profile_edit_screen.dart, written straight to the profile, and printed
    // on the worker profile a customer picks a tradesman from.
    test('a radius of 105 km takes the plural', () {
      expect(serviceRadiusAr(105), '105 كيلومترات');
    });

    test('a radius of 100 km stays singular', () {
      // The case the old helper got right by accident, and the one that
      // would catch a fix that over-corrected into plural for everything
      // above ten.
      expect(serviceRadiusAr(100), '100 كيلومتر');
    });

    test('a radius of 3 km is unchanged', () {
      expect(serviceRadiusAr(3), '3 كيلومترات');
    });

    test('a reply time of 103 hours takes the plural', () {
      expect(responseTimeAr(103), '103 ساعات');
    });
  });

  group('a feminine noun, because one rule is not one noun', () {
    // رسالة is feminine: its plural differs from its singular, which is the
    // whole reason the nouns are passed at the call site rather than derived.
    test('رسالة takes رسائل for 3-10 and رسالة for 11+', () {
      expect(arabicCounted(3, 'رسالة', two: 'رسالتان', few: 'رسائل'),
          '3 رسائل');
      expect(arabicCounted(11, 'رسالة', two: 'رسالتان', few: 'رسائل'),
          '11 رسالة');
      expect(arabicCounted(2, 'رسالة', two: 'رسالتان', few: 'رسائل'), 'رسالتان');
    });
  });

  group('the three call sites in the app agree with each other', () {
    // The regression this whole file exists for. Before the fix there were
    // three implementations of one rule; two were right and one was not, and
    // nothing compared them. Comparing them here is what makes a fourth
    // impossible.
    test('the subscription countdown agrees with the notification clock', () {
      // Same number, same threshold, same dual — read off two unrelated screens.
      final ar = _countdown(2);
      expect(ar, contains('بعد يومين'), reason: ar);
      expect(ar, isNot(contains('2 يوم')), reason: ar);
    });

    test('a one-day countdown is "بعد يوم", not "بعد 1 يوماً"', () {
      // The most common case a contractor ever sees: the last day of the
      // month he paid for. The previous cycle shipped «بعد 1 يوماً» for it.
      final ar = _countdown(1);
      expect(ar, contains('بعد يوم —'), reason: ar);
      expect(ar, isNot(contains('1 يوم')), reason: ar);
      expect(ar, isNot(contains('يوماً')), reason: ar);
    });

    test('a four-day countdown takes the plural', () {
      final ar = _countdown(4);
      expect(ar, contains('4 أيام'), reason: ar);
    });

    test('a hundred-day countdown is counted singular', () {
      final ar = _countdown(100);
      expect(ar, contains('100 يوم'), reason: ar);
      expect(ar, isNot(contains('أيام')), reason: ar);
    });

    test('relative time and the outbox label still print what they did', () {
      // The two copies that were already right. If this fails, the refactor
      // onto [arabicCounted] changed something it was not supposed to.
      final now = DateTime.utc(2026, 10, 1, 12);
      expect(relativeTimeAr(now.subtract(const Duration(minutes: 40)), now: now),
          'قبل 40 دقيقة');
      expect(relativeTimeAr(now.subtract(const Duration(minutes: 2)), now: now),
          'قبل دقيقتين');
      expect(relativeTimeAr(now.subtract(const Duration(days: 4)), now: now),
          'قبل 4 أيام');
      expect(queuedCountLabel(11), '11 رسالة لم تُرسل');
      expect(queuedCountLabel(5), '5 رسائل لم تُرسل');
      expect(queuedCountLabel(2), 'رسالتان لم تُرسلا');
    });
  });
}

/// The subscription line for a plan ending in [days] calendar days.
///
/// Built relative to the clock rather than from a frozen date, so the count is
/// a fact about the rule and not about when this suite happened to run.
String _countdown(int days) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day + days, 23, 0);
  final s = SubscriptionStatus.fromJson(<String, dynamic>{
    'plan': 'basic',
    'name_ar': 'أساسي',
    'status': 'active',
    'starts_at': null,
    'expires_at': end.toUtc().toIso8601String(),
    'quote_limit': -1,
    'portfolio_limit': 1,
    'quotes_used_this_month': 0,
    'renews_in_days': days,
  });
  return s.expiryCountdownAr ?? '';
}
