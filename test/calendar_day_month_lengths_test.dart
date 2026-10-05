// The day index behind every "how many days ago / how many days left" in the
// app, pinned by property rather than by the comment that warns about it.
//
// `calendarDaysBetween` used to be a packed `y*372 + m*31 + d`, and the packing
// is the trap the file header still describes: a stride of 31 assumes every
// month has 31 days, so 27 September lands *below* 1 October and a four-day span
// reads as five. That defect shipped once. Nothing in the test suite could
// catch a second one, because the twelve assertions that existed were all named
// dates -- and a named-date test passes against a wrong formula as long as the
// wrong formula happens to be right on that one date.
//
// So this file states the property instead of the examples: for **every** pair
// in a swept window, the count equals an oracle that shares no arithmetic with
// the code under test. The oracle is `DateTime.utc(...).difference(...).inDays`
// -- UTC has no DST, so its midnight-to-midnight spans are exactly 24 hours and
// `.inDays` is exact rather than truncating. The production code counts *local*
// calendar days, so each side is read through its own local date fields, and
// the two can only agree if the month lengths were honoured.
//
// The negative controls at the bottom are the point of the whole file: they
// re-derive the old packing here and assert it *disagrees*. A test that only
// proves the current code right cannot tell a correct formula from a lucky one;
// these two prove the window is wide enough for a wrong formula to be caught
// inside it.

import 'package:allomokawil/src/core/format/calendar_day.dart';
import 'package:flutter_test/flutter_test.dart';

/// Days between two dates as an independent arithmetic path.
///
/// Read through the local date fields on both sides, exactly as the production
/// code reads them, and then counted in UTC so that no DST transition can floor
/// the answer. This shares **no** term with the Julian Day Number: no `153`, no
/// `~/4`, no month-length weighting. If the two ever disagree, one of them has
/// stopped honouring month lengths.
int _oracle(DateTime from, DateTime to) => DateTime.utc(to.year, to.month, to.day)
    .difference(DateTime.utc(from.year, from.month, from.day))
    .inDays;

/// The packing the file header warns about, re-derived here on purpose.
///
/// Present so this test can *demonstrate* the failure it is guarding rather
/// than only assert the absence of one. Never called by a passing test path.
int _packed(int y, int m, int d) => y * 372 + m * 31 + d;

void main() {
  group('the day count honours every month length', () {
    test('a whole leap year, day by day, matches the oracle', () {
      // 2024: February has 29 days, so it is the year that catches a formula
      // treating every February as 28 or as 31. Every consecutive pair in the
      // year is checked, not a sample of them -- 366 pairs, and the only way
      // through is a count that is right on all of them.
      var checked = 0;
      var day = DateTime(2024, 1, 1);
      while (day.year == 2024) {
        final next = day.add(const Duration(days: 1));
        expect(
          calendarDaysBetween(day, next),
          1,
          reason: 'consecutive days must be one day apart, and these are '
              '${day.year}-${day.month}-${day.day}',
        );
        expect(
          calendarDaysBetween(day, next),
          _oracle(day, next),
          reason: 'the oracle is UTC-exact and shares no term with the '
              'production formula; a disagreement means a month length was '
              'not honoured at ${day.year}-${day.month}-${day.day}',
        );
        checked++;
        day = next;
      }
      expect(checked, 366, reason: '2024 is a leap year and must be walked '
          'whole, otherwise this test is quietly testing less than it claims');
    });

    test('every month boundary in twelve consecutive years is exact', () {
      // The boundary is the only place a wrong month length can show: if
      // February is read as 30 days, 1 March is one day *below* 29 February and
      // every span that crosses it is wrong. Twelve years covers the Gregorian
      // leap rule end to end -- 2024 and 2028 leap, 2025 and 2027 do not, and
      // 2100-style century rules stay out of reach of any plan this app sells.
      for (var y = 2023; y <= 2034; y++) {
        for (var m = 1; m <= 12; m++) {
          final lastDay = DateTime(y, m + 1, 0).day;
          final last = DateTime(y, m, lastDay);
          final first = DateTime(y, m + 1, 1);
          expect(
            calendarDaysBetween(last, first),
            1,
            reason: '$y-${m.toString().padLeft(2, '0')} has $lastDay days, so '
                'its last day is exactly one day before the next month starts',
          );
          expect(
            calendarDaysBetween(first, last),
            -1,
            reason: 'a span is not a countdown: the reverse must be the '
                'negative of the forward, for $y month $m',
          );
          // The month is worth exactly as many days as it has.
          expect(
            calendarDaysBetween(DateTime(y, m, 1), first),
            lastDay,
            reason: '$y month $m must contribute its own $lastDay days, never '
                'a fixed 30 or a fixed 31',
          );
        }
      }
    });

    test('the September-to-October span the header names is four days', () {
      // The exact case the old packing got wrong, kept as a named regression so
      // a future reader does not have to re-derive it from the prose. 27, 28,
      // 29, 30 September and 1 October: five calendar days inclusive, four
      // midnights between them.
      expect(calendarDaysBetween(DateTime(2026, 9, 27), DateTime(2026, 10, 1)), 4);
      // And one day earlier, so the answer tracks the dates rather than a
      // constant: 26 September -> 1 October is five.
      expect(calendarDaysBetween(DateTime(2026, 9, 26), DateTime(2026, 10, 1)), 5);
    });

    test('spans across a leap day count the leap day', () {
      // The two spans a leap year makes different, in opposite directions.
      expect(calendarDaysBetween(DateTime(2024, 2, 28), DateTime(2024, 3, 1)), 2,
          reason: '2024 has a 29 February, so 28 Feb -> 1 Mar crosses one day');
      expect(calendarDaysBetween(DateTime(2025, 2, 28), DateTime(2025, 3, 1)), 1,
          reason: '2025 does not, so the same dates are one day apart');
      // A whole year either side of each, which is where a leap rule read as
      // "February is always 28" and one read as "always 29" both come apart.
      expect(calendarDaysBetween(DateTime(2024, 1, 1), DateTime(2025, 1, 1)), 366);
      expect(calendarDaysBetween(DateTime(2025, 1, 1), DateTime(2026, 1, 1)), 365);
    });

    test('the clock on either end does not move the count', () {
      // The count is of calendar days, so 23:59 and 00:01 on the same date are
      // the same day. This is the property that makes a message from 23:50
      // read as "yesterday" after midnight rather than as zero days, and it is
      // why the production code reads date fields instead of durations.
      final base = DateTime(2026, 10, 3);
      expect(calendarDaysBetween(base, DateTime(2026, 10, 4)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 3, 23, 59),
          DateTime(2026, 10, 4, 0, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 3, 23, 59),
          DateTime(2026, 10, 3, 0, 1)), 0);
    });

    test('a symmetric sweep agrees with the oracle in both directions', () {
      // 400 pairs across a year, each checked forwards and backwards, because
      // a subtraction is only correct if both of its operands are.
      for (var a = 0; a < 20; a++) {
        for (var b = 0; b < 20; b++) {
          final from = DateTime(2026, 1, 1).add(Duration(days: a * 18));
          final to = from.add(Duration(days: b * 9));
          expect(calendarDaysBetween(from, to), _oracle(from, to),
              reason: 'forward span $from -> $to');
          expect(calendarDaysBetween(to, from), _oracle(to, from),
              reason: 'reverse span $to -> $from');
          expect(calendarDaysBetween(from, to),
              -calendarDaysBetween(to, from),
              reason: 'the two directions must be exact negatives of each other '
                  'for $from and $to');
        }
      }
    });
  });

  group('negative controls — the old packing fails inside this window', () {
    test('a y*372+m*31+d index disagrees on 27 Sep -> 1 Oct', () {
      // This is the defect the header describes, computed rather than asserted
      // in prose. If it ever *agreed*, the guard above would have been proved
      // vacuous and the whole file would need rethinking.
      final packedSpan =
          _packed(2026, 10, 1) - _packed(2026, 9, 27);
      expect(packedSpan, 5,
          reason: 'the old packing reads a four-day span as five');
      expect(calendarDaysBetween(DateTime(2026, 9, 27), DateTime(2026, 10, 1)), 4);
      expect(packedSpan, isNot(calendarDaysBetween(
          DateTime(2026, 9, 27), DateTime(2026, 10, 1))),
          reason: 'if the wrong formula matched here, the sweeps above would '
              'have been measuring nothing');
    });

    test('a y*372+m*31+d index disagrees on every 30- and 31-day month', () {
      // The packing's month lengths, written out: advancing from any month to
      // the next contributes 31 regardless of what that month actually holds.
      // February, April, June, September and November all disagree, and the
      // test above would fail in the first of them it reached.
      for (final m in [2, 4, 6, 9, 11]) {
        final real = DateTime(2026, m + 1, 1).difference(DateTime(2026, m, 1)).inDays;
        final packedSpan = _packed(2026, m + 1, 1) - _packed(2026, m, 1);
        expect(packedSpan, 31,
            reason: 'the packing advances a full stride for every month');
        expect(packedSpan, isNot(real),
            reason: 'month $m really has $real days, which is not 31');
      }
    });
  });
}
