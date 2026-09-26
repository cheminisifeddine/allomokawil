// The chat clock: one place that turns a timestamp into the Arabic a user reads
// inside a conversation — the clock under a bubble and the divider between two
// days.
//
// Two rules this file exists to keep:
//
//   1. **Latin digits, 24-hour.** That is what a phone in Algeria shows and what
//      this app already uses to read a number back (`05 50 12 34 56`). A thread
//      that mixed Arabic-Indic digits into a clock would read as a second,
//      different time to a user who only half-reads numbers.
//
//   2. **Days are compared on the local calendar.** D1 stores `created_at` in
//      UTC; a message sent at 00:20 in Algiers is stored at 23:20 the *previous*
//      UTC day. A divider that compared a raw UTC day would file tonight's
//      message under yesterday. Every timestamp reaching this file has already
//      been pinned to UTC and converted with `.toLocal()` by
//      `parseServerTime` (see `lib/src/models/notification.dart`).

/// `HH:mm`, 24-hour, zero-padded. `09:05`, `14:32`, `00:00`.
String chatClock(DateTime at) {
  final h = at.hour.toString().padLeft(2, '0');
  final m = at.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// True when two instants fall on the same calendar day (both local).
bool sameChatDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whole **calendar** days from [from] to [to], counted on the local date
/// fields — 1 for yesterday, 2 for the day before.
///
/// `Duration.inDays` is the wrong number for this and is the reason this
/// function exists. It counts 24-hour *periods*, so at 00:10 it reports 0 days
/// between a message from 23:50 and now — a message from **yesterday** — and at
/// 01:00 it reports 1 day between the message from 22:00 the day before and
/// now — a message from **two days ago**, called yesterday. Both are off by a
/// day, and both are wrong at exactly the hours people read a phone.
///
/// Built from an absolute day number rather than by subtracting two midnight
/// `DateTime`s and dividing by 24, so a DST transition (23- and 25-hour days)
/// cannot floor the count onto the previous day. The day number is the
/// standard Julian Day Number, which is exact for every Gregorian date.
///
/// The first version of this used a packed `y*372 + m*31 + d` index, and the
/// packing is the trap: a stride of 31 assumes every month has 31 days, so
/// 27 September (9*31+27) lands 4 days *below* 1 October (10*31+1) and the
/// span comes out as 5. A month-length-weighted packing has to be right for
/// all twelve months, which is exactly the arithmetic JDN already is, so this
/// uses it instead of inventing a second one.
int calendarDaysBetween(DateTime from, DateTime to) =>
    _jdn(to) - _jdn(from);

/// The Julian Day Number of a date's local calendar day.
int _jdn(DateTime t) {
  final m = t.month;
  final a = (14 - m) ~/ 12;
  final y = t.year + 4800 - a;
  final shifted = m + 12 * a - 3;
  // Every term is non-negative here (y >= 4800, shifted >= 0), so Dart's
  // truncating `~/` is a floor and the result is exact.
  return t.day +
      (153 * shifted + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}

/// The label inside a day divider: «اليوم» for today, «أمس» for yesterday, and
/// a plain `dd/MM/yyyy` beyond that — a day the user has to count is a day he
/// wants dated, not described.
///
/// [now] is injectable so a test can pin "today" instead of racing midnight.
String chatDayLabel(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (sameChatDay(at, today)) return 'اليوم';
  // Built by arithmetic on the day field so month and year roll over correctly
  // (DateTime normalises 2026-03-00 into 2026-02-28).
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (sameChatDay(at, yesterday)) return 'أمس';
  final dd = at.day.toString().padLeft(2, '0');
  final mm = at.month.toString().padLeft(2, '0');
  return '$dd/$mm/${at.year}';
}

/// The divider's ruling: print one above the first message, and above any
/// message whose day differs from the one before it.
///
/// A message with no server timestamp (a bubble still queued on this device)
/// never opens a divider: its day is the phone's own day, so a divider built
/// from it would sit above a date the server has not confirmed.
bool needsDayDivider(DateTime? previous, DateTime? current) {
  if (current == null) return false;
  if (previous == null) return true;
  return !sameChatDay(previous, current);
}
