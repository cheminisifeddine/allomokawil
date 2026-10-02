// The subscription countdown counted 24-hour PERIODS, so across a
// spring-forward day it told a contractor with three midnights of paid cover
// left that he had two.
//
// `SubscriptionStatus.daysUntilExpiryAt` normalised both ends to midnight and
// then asked `lastDay.difference(today).inDays`. Stripping the clock is
// necessary but not sufficient: on a day the clocks jump forward the span
// between two local midnights is **23 hours**, and `.inDays` truncates towards
// zero, so the count floors a day early on every span containing a transition.
//
// Measured, not inferred: with the old rule on `TZ=Europe/Paris`,
// 29 Mar 2026 -> 1 Apr 2026 answers 2 where the calendar says 3, and the card
// prints «ينتهي الاشتراك بعد يومين» beside a plan with three days left.
//
// This is the same defect `chat_time.dart` was opened for on the other side of
// the app, and the reason it replaced its own hand-rolled day index with a
// Julian Day Number. That rule is now the one held here too, so a day count
// that is correct in the chat list cannot be wrong on the subscription card.
//
// **Why part of this file skips on a UTC host.** The loop's gate runs on UTC,
// where two consecutive midnights are exactly 24 hours apart and the old rule
// is accidentally correct. A test asserted there would be green against the
// very code it exists to catch -- a guard that cannot fail is not a guard. The
// group that needs a real transition therefore skips with a reason naming the
// command that does exercise it, so the skip is visible rather than buried:
//     TZ=Europe/Paris flutter test test/plan_expiry_dst_test.dart
// The two tests that hold in every zone never skip.

import 'package:allomokawil/src/data/chat_time.dart';
import 'package:allomokawil/src/models/plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// True when this host's zone actually shortens a day, measured rather than
/// matched by name.
///
/// The window is found by asking the calendar where the short day is, not by
/// picking a March and hoping: Europe/Paris springs forward at 02:00 on
/// 29 Mar 2026, so the SHORT midnight-to-midnight span is 29 -> 30, not
/// 28 -> 29. Guessing that date is how a first draft of this test passed green
/// in Paris and would have proved nothing at all.
bool get _zoneHasDst {
  final start = DateTime(2026, 3, 29);
  final end = DateTime(2026, 3, 30);
  return end.difference(start).inHours != 24;
}

/// `flutter test`'s skip reason when there is no transition to measure against.
///
/// Typed `Object` because `skip:` takes either `false` or a reason string, and
/// narrowing it to `String` would make the passing zone a type error.
Object get _skipIfUtc => _zoneHasDst
    ? false
    : 'No DST zone on this host, so no spring-forward day exists here and the '
        'old 24-hour-period rule is accidentally correct. This group is the '
        'only thing that catches it. Run it with:\n'
        '    TZ=Europe/Paris flutter test test/plan_expiry_dst_test.dart';

/// A paid plan ending on [endDay] local, a given number of minutes past
/// midnight so the instant is never itself a midnight.
SubscriptionStatus _paidUntil(DateTime endDay) {
  final at = endDay.add(const Duration(hours: 21));
  return SubscriptionStatus.fromJson({
    'plan': 'pro_monthly',
    // Carried as UTC and pinned back by `parseServerTime`, so the fixture does
    // not depend on the runner's zone to mean what it says.
    'expires_at': at.toUtc().toIso8601String(),
  });
}

void main() {
  group('subscription expiry counts calendar days, not 24-hour periods', () {
    test('29 Mar -> 1 Apr 2026 is three midnights, not two', () {
      // The witness. 29 and 30 Mar each cross a clock change and 31 Mar is the
      // expiry, so three midnights of paid cover -- which the old rule called
      // two, and printed as «ينتهي الاشتراك بعد يومين».
      final s = _paidUntil(DateTime(2026, 4, 1));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 29, 12)), 3);
    }, skip: _skipIfUtc);

    test('28 Mar -> 31 Mar 2026 is three midnights in Europe/Paris', () {
      final s = _paidUntil(DateTime(2026, 3, 31));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 28, 12)), 3);
    }, skip: _skipIfUtc);

    test('a one-day span across the transition counts one', () {
      // The smallest case and the one a user is most likely to hit: renew the
      // day after a DST change and the old rule read «بعد 0 يوم» on a paid plan,
      // which drops the countdown to the date-only sentence.
      final s = _paidUntil(DateTime(2026, 3, 30));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 29, 12)), 1);
    }, skip: _skipIfUtc);

    test('a span that straddles the change is counted whole from both ends',
        () {
      final s = _paidUntil(DateTime(2026, 4, 2));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 30, 12)), 3);
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 31, 12)), 2);
    }, skip: _skipIfUtc);

    test('the countdown sentence carries the whole count', () {
      final s = _paidUntil(DateTime(2026, 4, 1));
      final ar = s.expiryCountdownArAt(DateTime(2026, 3, 29, 12));
      expect(ar, contains('بعد 3 أيام'));
      expect(ar, isNot(contains('بعد 2 ')));
      expect(ar, isNot(contains('يومين')));
    }, skip: _skipIfUtc);
  });

  group('the rule holds in every timezone', () {
    test('a plan ending today is zero, and the card drops to the date', () {
      // The boundary this repo has already paid for once -- 0 must not print
      // «بعد 0 يوماً» -- and it has to survive the change of rule.
      final s = _paidUntil(DateTime(2026, 3, 29));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 29, 12)), 0);
      expect(s.expiryCountdownArAt(DateTime(2026, 3, 29, 12)),
          startsWith('ينتهي الاشتراك في'));
    });

    test('a plan ending next year counts every midnight between', () {
      final s = _paidUntil(DateTime(2027, 3, 29));
      expect(s.daysUntilExpiryAt(DateTime(2026, 3, 29, 12)), 365);
    });

    test('daysUntilExpiryAt equals calendarDaysBetween across the window', () {
      // The property that would have caught this by construction: one rule, two
      // callers. Swept across the whole transition window rather than sampled at
      // the two dates a test happens to name, so a later edit cannot make the
      // two agree on those and disagree everywhere else. True in every zone.
      for (var d = 0; d <= 7; d++) {
        final clock = DateTime(2026, 3, 28 + d, 12);
        final s = _paidUntil(DateTime(2026, 4, 1));
        expect(
          s.daysUntilExpiryAt(clock),
          calendarDaysBetween(
              DateTime(clock.year, clock.month, clock.day), DateTime(2026, 4, 1)),
          reason: 'the subscription card and the chat list must not disagree '
              'about how many calendar days separate these two dates',
        );
      }
    });

    test('the count never overstates the midnights remaining', () {
      // Understating is conventional; overstating takes paid cover away. The
      // count is bounded by the calendar answer in both directions.
      for (var d = 0; d <= 10; d++) {
        final clock = DateTime(2026, 3, 25 + d, 12);
        final s = _paidUntil(DateTime(2026, 4, 5));
        final got = s.daysUntilExpiryAt(clock)!;
        final want = calendarDaysBetween(
            DateTime(clock.year, clock.month, clock.day), DateTime(2026, 4, 5));
        expect(got, want);
      }
    });
  });
}
