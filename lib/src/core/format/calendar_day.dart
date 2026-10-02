// The calendar-day count: how many midnights separate two instants.
//
// This lives in `core/` and not in `data/chat_time.dart` because two layers
// need it and they do not point at each other. `models/plan.dart` counts the
// days of paid cover left on the subscription card; `data/chat_time.dart`
// dates the day dividers in a conversation. When `plan.dart` reached for the
// chat file's copy, it drew the **first `models/` -> `data/` edge in the app**
// — a direction the dependency graph had never carried before, inherited from a
// bug fix rather than chosen. The layering README states is the other way
// round: `models/` holds pure types, `data/` is screen-facing and imports them.
//
// So the arithmetic moved down to `core/`, which every layer already imports
// from (`models/plan.dart` -> `core/format/money.dart`, and a dozen files ->
// `core/l10n/arabic_agreement.dart`), and `chat_time.dart` keeps re-exporting
// the name so its own callers and tests are untouched. One implementation, two
// directions, and the rule can no longer be forked by whoever imports it next.

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
///
/// Negative when [to] is the earlier day: this is a span, not a countdown.
int calendarDaysBetween(DateTime from, DateTime to) => _jdn(to) - _jdn(from);

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
