/// Cutting a string without cutting a character in half.
///
/// **The bug this exists to stop, measured rather than imagined.** A Dart
/// `String` is UTF-16, so any character outside the Basic Multilingual Plane
/// is stored as **two** code units — an emoji, a CJK ideograph, a musical
/// symbol, and every supplementary character a phone keyboard offers. Every
/// "keep the first n characters" in this app used to be
/// `s.substring(0, n)`, which counts **code units** and therefore slices
/// straight through the middle of one of those pairs. Measured on this tick:
///
/// ```text
/// flat = 'ا' * 59 + '😀' + 'بقية الرسالة'
/// flat.substring(0, 60)  ->  lone surrogate U+D83D, emoji gone
/// ```
///
/// The result is a string that is no longer valid text. Dart renders the
/// orphaned half as `U+FFFD` — the "�" replacement box — so what reaches the
/// user is a mojibake square in the middle of an Arabic sentence. This is not
/// a theoretical shape: an emoji lands exactly on the cut boundary once per
/// few hundred messages, and the one place a user is guaranteed to see it is
/// the toast that quotes back the message they just lost.
///
/// **The class is the same one [Monogram] was written for** — reading a
/// string as if a code unit were a character — and the same mistake in the
/// other direction. `Monogram.of` fixed the *first* character; this fixes the
/// *nth*.
///
/// Deliberately two functions rather than one with a flag: the call sites do
/// not agree about whether the ellipsis is part of the budget
/// (`CrashRecord.trim` counts it, `droppedMessageCopy` does not), and a
/// boolean that means "and by the way also recount the ellipsis" is a bug
/// waiting for the next caller.
class TextClip {
  const TextClip._();

  /// The first [max] **characters** of [text], or all of it when it is
  /// shorter. A character is a code point, so a surrogate pair is either
  /// wholly kept or wholly dropped.
  ///
  /// Never returns a string containing an orphaned half of a pair, which
  /// `substring` can and does.
  static String chars(String text, int max) {
    if (max <= 0) return '';
    final runes = text.runes;
    if (runes.length <= max) return text;
    final out = StringBuffer();
    var taken = 0;
    for (final rune in runes) {
      if (taken == max) break;
      out.writeCharCode(rune);
      taken++;
    }
    return out.toString();
  }

  /// [text] clipped to fit [max] **code units** including [ellipsis], and cut
  /// only between characters.
  ///
  /// **The budget is code units, on purpose, and the cut is characters.** Those
  /// are two different units and the call sites need both: `CrashRecord.trim`
  /// is a *storage* bound — a record is written to preferences as one line, and
  /// a bound counted in characters could double the bytes it saves — while the
  /// *thing being cut* must never be a pair. Counting the budget in code units
  /// and cutting on characters keeps the bound hard and the text valid.
  ///
  /// A pair that does not fit in what remains is **dropped whole**, which is why
  /// a run of emoji yields a shorter string than `max` rather than an invalid
  /// one. `substring` cannot express that choice at all: it has no way to know
  /// the next two units are one character.
  static String elided(String text, int max, {String ellipsis = '…'}) {
    if (max <= 0) return '';
    if (text.length <= max) return text;
    final room = max - ellipsis.length;
    if (room <= 0) return ellipsis.length <= max ? ellipsis : '';
    final out = StringBuffer();
    var units = 0;
    for (final rune in text.runes) {
      final width = rune >= 0x10000 ? 2 : 1;
      if (units + width > room) break;
      out.writeCharCode(rune);
      units += width;
    }
    return '$out$ellipsis';
  }
}
