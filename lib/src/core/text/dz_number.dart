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
  static int? tryParse(String raw, {int? min, int? max}) {
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

    var digits = DzNumber.digits(newValue.text);
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    if (digits == newValue.text) return newValue;

    return TextEditingValue(
      text: digits,
      // Digits-only input is append-only in practice, so parking the caret at
      // the end is always where the user is looking.
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
