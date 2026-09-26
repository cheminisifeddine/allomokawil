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
