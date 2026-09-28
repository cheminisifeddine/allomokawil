import 'package:allomokawil/src/data/chat_time.dart';
import 'package:allomokawil/src/data/notification_copy.dart';
import 'package:flutter_test/flutter_test.dart';

/// A relative count has to stop being a count.
///
/// `relativeTimeAr` answers in minutes, then hours, then days, then months — and
/// the month arm had no upper bound, so it kept dividing forever. A conversation
/// from three years ago printed **«قبل 133 شهر»** in the chat list, and the same
/// string appeared on any old notification. Verified against the real function on
/// 28 Sep: 365 days -> «قبل 12 شهر», 1000 -> «قبل 33 شهر», 4000 -> «قبل 133 شهر».
///
/// The app already owns the answer twice, in two other files:
///
///   * [chatDayLabel] — «a day the user has to count is a day he wants dated, not
///     described» — prints `dd/MM/yyyy` past yesterday. A 2015 message already
///     reads as a date on the chat divider, while the row beside it said
///     «قبل 133 شهر». One thread, two answers, again.
///   * `Plan.maxCountedDays` — the subscription card stops counting past a year
///     and prints the date alone, for exactly the stated reason: «a count like
///     «بعد 26560 يوماً» is a number no contractor can read as time».
///
/// This tick makes the notification/chat clock obey the same rule it already
/// follows everywhere else, and routes the date through [chatDayLabel] so the
/// format cannot be written a second time.
void main() {
  final now = DateTime(2026, 9, 28, 12, 0);

  DateTime daysAgo(int d) =>
      DateTime(now.year, now.month, now.day).subtract(Duration(days: d));

  test('a year-old message is dated, not counted in months', () {
    // The boundary itself: 365 calendar days back is one year, and «قبل 12 شهر»
    // is the exact string this replaces.
    expect(relativeTimeAr(daysAgo(365), now: now), isNot(contains('شهر')));
    expect(relativeTimeAr(daysAgo(365), now: now), chatDayLabel(daysAgo(365), now: now));
  });

  test('the month arm cannot run away', () {
    // The regression itself. 4000 days is 2015, and the row beside a chat
    // divider that already said «16/10/2015» said «قبل 133 شهر».
    for (final d in [400, 1000, 1200, 2000, 4000, 9000]) {
      final out = relativeTimeAr(daysAgo(d), now: now);
      expect(out, isNot(contains('شهر')), reason: '$d days -> "$out"');
      expect(out, isNot(contains('يوم')), reason: '$d days -> "$out"');
    }
  });

  test('the dated arm is exactly what the chat divider says', () {
    // One format, one source. If these ever disagree it is the same defect the
    // whole file exists to prevent, so the two are asserted equal rather than
    // both written out as literals.
    for (final d in [365, 400, 1000, 4000]) {
      final at = daysAgo(d);
      expect(relativeTimeAr(at, now: now), chatDayLabel(at, now: now),
          reason: '$d days');
    }
  });

  test('the counted arms are untouched below a year', () {
    // The cap must not cost anything a user reads today. These are the exact
    // strings the suite already asserted before this change.
    expect(relativeTimeAr(now.subtract(const Duration(seconds: 30)), now: now), 'الآن');
    expect(relativeTimeAr(now.subtract(const Duration(minutes: 1)), now: now), 'قبل دقيقة');
    expect(relativeTimeAr(now.subtract(const Duration(minutes: 7)), now: now), 'قبل 7 دقائق');
    expect(relativeTimeAr(now.subtract(const Duration(hours: 3)), now: now), 'قبل 3 ساعات');
    expect(relativeTimeAr(daysAgo(4), now: now), 'قبل 4 أيام');
    expect(relativeTimeAr(daysAgo(59), now: now), 'قبل شهر');
    expect(relativeTimeAr(daysAgo(60), now: now), 'قبل شهرين');
    expect(relativeTimeAr(daysAgo(90), now: now), 'قبل 3 أشهر');
  });

  test('a clock skew and a missing time still behave', () {
    // The cap is arithmetic on the day count, so the two guards that already
    // existed have to keep firing before it: no «قبل -1 شهر» from a phone whose
    // clock is behind the server, and no text at all for a row with no time.
    expect(relativeTimeAr(null, now: now), '');
    expect(relativeTimeAr(now.add(const Duration(days: 40)), now: now), 'الآن');
  });
}
