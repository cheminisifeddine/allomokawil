/// Algerian phone numbers, the way they actually arrive.
///
/// The API (`workers/mobile.ts`) normalises every incoming number to
/// `0[567]xxxxxxxx` and rejects the rest with `رقم الهاتف غير صحيح`. The app used
/// to post whatever the user typed into a plain `TextField` — no grouping, no
/// local check, no hint that an Algerian mobile must start with 05/06/07 — so the
/// first feedback a user got was a round-trip error, often for a number that is
/// perfectly fine.
///
/// [DzPhone] mirrors the server rule locally and, deliberately, is a little
/// friendlier than it in three cases that are real on an Algerian phone:
///
///   * `+213 550 12 34 56` and `00213 550 12 34 56` (the forms people paste out
///     of their contacts) — the country code is replaced by the leading `0`.
///   * `550123456`: a 9-digit mobile with the zero dropped (typical of a number
///     saved internationally). The zero is put back.
///   * Arabic-Indic digits — `٠٥٥٠١٢٣٤٥٦` — through the same fold that
///     [ArabicSearch] already uses for search, so a paste from a contact card in
///     Arabic works instead of producing an empty field.
///
/// Nothing here is a display transform on stored data: every method takes what
/// the user has on screen and answers a question about it. The value sent to the
/// API is always [canonical].
library;

import 'arabic_search.dart';

class DzPhone {
  const DzPhone._();

  /// International dialling prefix for Algeria, shown as the field's chip.
  static const String intlCode = '+213';

  /// The local form of the same prefix: the leading `0` plus the operator digit.
  static const String localPrefix = '0X';

  /// A mobile number is exactly 10 digits: `0` + operator + 8 digits.
  static const int localLength = 10;

  /// The same number written internationally: 9 digits, no leading zero.
  static const int intlLength = 9;

  /// Operator prefixes that exist in Algeria: 05x, 06x, 07x. Landlines (02x,
  /// 03x, 04x) are intentionally NOT accepted — this is what the API enforces,
  /// and a marketplace account is reached by SMS on a mobile.
  static final RegExp _valid = RegExp(r'^0[5-7][0-9]{8}$');

  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  /// Digit-only form of anything the user typed or pasted: spaces, dashes,
  /// brackets, `+` and Arabic-Indic digits all stripped/folded.
  static String digits(String raw) =>
      ArabicSearch.normalize(raw).replaceAll(_nonDigit, '');

  /// Canonicalise an already digit-only string. Mirrors `normalizeDzPhone` in
  /// `workers/mobile.ts` and adds the missing-zero repair described above.
  static String canonicalFromDigits(String digitsOnly) {
    // Tolerates punctuation too, so callers may hand it the raw field text.
    var d = digitsOnly.replaceAll(_nonDigit, '');
    // 00213... / 213... — a pasted international number. The server does the
    // same substitution; do it before the length can hit a cap.
    if (d.startsWith('00213')) d = d.substring(2);
    if (d.startsWith('213') && d.length > intlLength) d = '0${d.substring(3)}';
    // 550123456 -> 0550123456 (zero dropped when the number was saved abroad).
    if (d.length == intlLength && '567'.contains(d[0])) d = '0$d';
    return d;
  }

  /// Canonical local form (`0XXXXXXXXX`) of any input, valid or not. Validation
  /// is a separate question — see [isValid].
  static String canonical(String raw) => canonicalFromDigits(digits(raw));

  /// The nine digits after `+213`: the canonical form without its leading zero.
  static String national(String raw) {
    final c = canonical(raw);
    return c.startsWith('0') ? c.substring(1) : c;
  }

  /// True only for a real Algerian mobile: `0` + 05/06/07 + 8 digits.
  static bool isValid(String raw) => _valid.hasMatch(canonical(raw));

  /// `0550123456` -> `05 50 12 34 56`, progressive while typing.
  static String groupLocal(String digitsOnly) => _group(
      _cap(canonicalFromDigits(digitsOnly), localLength),
      const [2, 2, 2, 2, 2]);

  /// `550123456` -> `550 12 34 56`, the half shown after the `+213` chip.
  static String groupIntl(String digitsOnly) =>
      _group(_cap(national(digitsOnly), intlLength), const [3, 2, 2, 2]);

  static String _cap(String d, int max) =>
      d.length > max ? d.substring(0, max) : d;

  /// Space digits into the given group sizes, leaving whatever is left over
  /// appended, so a half-typed number still reads as a number.
  static String _group(String d, List<int> sizes) {
    final buf = StringBuffer();
    var i = 0;
    for (final size in sizes) {
      if (i >= d.length) break;
      if (i > 0) buf.write(' ');
      final end = i + size > d.length ? d.length : i + size;
      buf.write(d.substring(i, end));
      i = end;
    }
    if (i < d.length) buf.write(d.substring(i));
    return buf.toString();
  }
}
