/// Numbers, the way an Algerian actually types them.
///
/// Every money / year / day-count field in this app is an integer in Algerian
/// dinars or in days, and every one of them used to run `int.tryParse()` on the
/// raw field text. That is the wrong parser for this market, and it failed
/// silently in three ways that are all normal here:
///
///   * **Arabic-Indic digits.** A phone with an Arabic keypad, or a value pasted
///     out of a contact card / SMS, arrives as `٢٥٠٠٠`. `int.tryParse` returns
///     null, and the field was then treated as *empty* — the budget simply
///     vanished from the posted project and a `5000 دج` quote was rejected with
///     "the amount must be at least 1000".
///   * **Grouping separators.** `25.000`, `25,000` and `25 000` are all 25000
///     here. The parser saw the separator, gave up, and dropped the number.
///   * **Units glued on.** `25 000 دج` — what a user pastes from a note —
///     parsed to null for the same reason.
///
/// [DzNumber] folds all of those down to the digits that were meant, and
/// **refuses** a value it would have to guess about rather than picking one:
/// a fractional amount (`25,5`) returns null instead of silently becoming 255,
/// because rounding a contractor's price behind their back is worse than asking
/// again. Same rule for an absurd paste (more than [maxDigits] digits).
///
/// The fold itself is [ArabicSearch.normalize] — the app already owns exactly
/// one Arabic digit mapping (`٠٧٧٠` -> `0770`) and a second, subtly different
/// one in the money path is how the two drift apart.
library;

import 'package:flutter/services.dart';

import 'arabic_search.dart';

class DzNumber {
  const DzNumber._();

  /// Longest value any field in this app accepts: 999,999,999,999. Wider than
  /// any real renovation budget in dinars, narrow enough that a mis-typed or
  /// pasted novel cannot be submitted as a price.
  static const int maxDigits = 12;

  /// Highest experience value that is a real answer, not a typo.
  static const int maxExperienceYears = 70;

  /// Highest amount any money field accepts, in dinars: 900,000,000,000.
  ///
  /// A roof, not a tightening of [maxDigits] — 900 billion is 12 digits, so
  /// every value a box of the default width can hold is still a *number*; this
  /// only refuses the tail that is arithmetic rather than a renovation. The
  /// largest real figure in this market is a ministry-scale tender in the low
  /// billions, so the gap between this and a plausible amount is five orders of
  /// magnitude. A field with a floor and no roof let `999999999999` through as a
  /// price, which is a number no reader can mistake for anything but a typo.
  static const int maxAmountDzd = 900000000000;

  /// Longest duration any job can take, in days: 10 years.
  ///
  /// **This is the one that reaches a customer.** `quoteDurationLineAr` prints
  /// `estimated_days` verbatim on the quote card the customer picks a tradesman
  /// from, so an unroofed duration is not a bad number in a form — it is a bad
  /// number next to the worker's name and price, where it reads as a lie about
  /// the job rather than as a typo. Ten years is past the point where the
  /// bidder is describing a renovation at all.
  static const int maxDurationDays = 3650;

  /// Box widths that match the roofs above.
  ///
  /// [maxDigits] is the parser's ceiling, not a field's: a 4-day field that
  /// accepts 12 digits is a box that lets in 999999999999 and then refuses it
  /// at submit, which is the field lying about what it accepts. These make the
  /// two the same number, and [tryParse] takes the same constant so the box and
  /// the validator can no longer disagree.
  static const int amountDigits = 12; // 900000000000
  static const int durationDigits = 4; // 3650
  static const int experienceDigits = 2; // 70

  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  /// A fraction, not a grouping: `25,5`, `25.75`, `٢٥,٥`, `25٫5`. Algerian
  /// amounts are written with the separator grouping *triplets* when it means
  /// thousands, so one or two trailing digits can only be a decimal part —
  /// which this app's integer fields must not round away. `U+066B` is the
  /// Arabic decimal separator; `U+066C` (Arabic thousands separator) is left to
  /// the fold, which strips it as grouping.
  static final RegExp _fraction =
      RegExp('[.,\\u066B]([0-9\\u0660-\\u0669\\u06F0-\\u06F9]{1,2})'
          '(?![0-9\\u0660-\\u0669\\u06F0-\\u06F9])');

  /// True when [raw] carries a fractional part that integer fields must refuse.
  static bool hasFraction(String raw) => _fraction.hasMatch(raw);

  /// The digits of [raw], folded to ASCII, with every separator, space, bidi
  /// mark and unit label removed. `25.000 دج` -> `25000`, `٢٥٠٠٠` -> `25000`.
  ///
  /// Returns the empty string when there is nothing numeric in it. Not a
  /// validator: pair with [tryParse] (or a length check) before sending.
  static String digits(String raw) {
    if (raw.isEmpty) return '';
    return ArabicSearch.normalize(raw).replaceAll(_nonDigit, '');
  }

  /// [raw] as the integer the user meant, or null when it is not one:
  /// empty, non-numeric, fractional, longer than [maxDigits], or outside
  /// [min]/[max].
  ///
  /// `min`/`max` are inclusive bounds for fields that have a real range
  /// (experience in years, a quote amount); a null result is a "ask the user
  /// again", never a value to fall back on silently.
  ///
  /// [maxDigits] is the **box's** width, not the parser's ceiling, and it
  /// defaults to the ceiling so a field with no box of its own is unaffected.
  /// It is here because `NumberField.maxDigits` used to reach the formatter and
  /// stop: narrowing a box bounded what he could type while this validator went
  /// on accepting the parser's 12 digits regardless, so the two disagreed and
  /// only the parser's answer shipped. A caller that narrows its box passes the
  /// same constant here, and the field's promise — "no screen can accept a
  /// number the API would store as garbage" — becomes true of the validator as
  /// well as the keyboard.
  static int? tryParse(String raw, {int? min, int? max, int maxDigits = DzNumber.maxDigits}) {
    if (hasFraction(raw)) return null;
    final d = digits(raw);
    if (d.isEmpty || d.length > maxDigits) return null;
    final value = int.parse(d);
    if (min != null && value < min) return null;
    if (max != null && value > max) return null;
    return value;
  }

  /// Live input policy for a numeric field, as a [TextInputFormatter]:
  /// fold Arabic-Indic digits to ASCII as they are typed, drop separators and
  /// unit labels, and cap the length at [maxDigits].
  ///
  /// Folding on the way in (not on the way out) matters in RTL: a field holding
  /// `٢٥٠٠٠` renders the digits in an order the user did not type when the
  /// surrounding paragraph is right-to-left, so the value on screen and the
  /// value sent could disagree. ASCII digits are unambiguous in both
  /// directions.
  static TextInputFormatter formatter({int maxDigits = maxDigits}) =>
      DzNumberInputFormatter(maxDigits: maxDigits);
}

/// See [DzNumber.formatter]. Kept as a class so screens can pass it around
/// without rebuilding the instance on every `build`.
class DzNumberInputFormatter extends TextInputFormatter {
  const DzNumberInputFormatter({this.maxDigits = DzNumber.maxDigits});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // A fractional paste is refused outright rather than truncated to the
    // integer part: the field keeps what it had, and the screen's own
    // validation says why (see [DzNumber.hasFraction]).
    if (DzNumber.hasFraction(newValue.text)) return oldValue;

    // **An over-long paste is refused on the same rule, and this line used to
    // break it.** `digits.substring(0, maxDigits)` kept the first N digits and
    // dropped the rest with no error, no message and no marker, so the value on
    // screen was not the value he sent: the parser then validated the
    // *truncated* number, found it in range, and shipped that. One field, one
    // keystroke, two answers — a fraction was refused loudly on the row above
    // while a length overflow was rewritten quietly, and this file's own comment
    // calls rewriting "worse than asking again".
    //
    // Returning [oldValue] is what makes it loud: the field keeps a value he can
    // see and correct, nothing is rewritten behind him, and the screen's own
    // validation is still the thing that explains why it will not send. The
    // alternative — keep the tail, or keep the head and flag it — would put a
    // number on screen the app has already decided is wrong.
    final digits = DzNumber.digits(newValue.text);
    if (digits.length > maxDigits) return oldValue;
    if (digits == newValue.text) return newValue;

    return TextEditingValue(
      text: digits,
      // Digits-only input is append-only in practice, so parking the caret at
      // the end is always where the user is looking.
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
