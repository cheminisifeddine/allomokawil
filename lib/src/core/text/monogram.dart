/// The first *visible* character of a person's name — the letter that goes in
/// the round avatar the app shows when there is no profile photo.
///
/// Two copies of this rule existed (`ui.dart`'s `InitialAvatar` and
/// `worker_card.dart`'s private `_initials`), and both of them were wrong in
/// the same way, which is what made the copy a defect rather than a style.
///
/// **The bug.** A name is stored verbatim from a plain `TextField`
/// (`auth_screen.dart:164` is `fullName: _name.text.trim()`), with no input
/// formatter and no server-side cleaning. Algerian users paste their own name
/// out of Facebook and WhatsApp constantly, and those apps bracket Arabic text
/// with invisible formatting characters:
///
///   * `U+200F` RIGHT-TO-LEFT MARK — inserted by many keyboards and editors
///   * `U+200E` LEFT-TO-RIGHT MARK, and `U+200D` ZERO WIDTH JOINER
///   * `U+200B` ZERO WIDTH SPACE
///
/// Dart's `String.trim()` strips whitespace, and these are `Cf` (format)
/// characters, **not** whitespace — so `'\u200fمحمد'.trim()` keeps its first
/// rune as `U+200F`. The avatar then took `runes.first` and painted a
/// **zero-width glyph in a 48 dp navy circle**: a blank blue dot where the
/// user's own initial should be, on the chat list, the worker card, the profile
/// and the quote row. Not a crash and not an error message — a *silently blank*
/// avatar, which on a marketplace is the picture a customer uses to tell two
/// tradesmen apart.
///
/// A name that is *only* such marks has the same outcome by a different road:
/// `trim()` leaves it non-empty, so it also produced a blank circle instead of
/// the «؟» the empty case prints.
///
/// **The fix is to skip the invisible characters, not to delete them from the
/// stored name.** The marks are not garbage: they carry the writing direction,
/// and `fullName` is rendered in a `Directionality` of its own. Stripping them
/// at the avatar would be right; stripping them from what the user typed would
/// be editing a name behind their back. So this is a read-time rule about *one
/// character*, exactly like the other input rules in this folder.
library;

class Monogram {
  const Monogram._();

  /// Shown when a name has no visible character at all. Arabic, like every
  /// other user-facing string in the app.
  static const String fallback = '؟';

  /// Directional and zero-width formatting characters that paint nothing.
  ///
  /// `U+200B-200F` are the marks a pasted Arabic name actually carries, and
  /// `U+FEFF` (BOM / zero-width no-break space) and `U+2060` (word joiner) are
  /// the two that turn up in text that has been through a desktop editor or a
  /// CSV. `U+061C` (Arabic letter mark) is included because it is the modern
  /// replacement for `U+200F` that many apps now emit by default.
  ///
  /// `U+00AD` (soft hyphen) is deliberately **not** here: it is a real
  /// formatting character, but it is one a word processor inserts mid-name
  /// («Moham-») and the letter after it is a perfectly good initial. This is
  /// "skip what paints nothing at the front", not "delete formatting".
  static final RegExp _invisible =
      RegExp('[\u200B-\u200F\u2060\uFEFF\u061C]');

  /// The first character of [name] that actually paints something, or
  /// [fallback] when there is none.
  ///
  /// Works on runes, not code units, so a name starting with an emoji or a
  /// supplementary character is not cut in half the way `name[0]` would.
  ///
  ///   * `محمد` -> `م`
  ///   * `'\u200fمحمد'` (a name pasted out of Facebook) -> `م`
  ///   * `'\u200f'` (nothing but marks) -> `؟`, the same answer as an empty
  ///     name — which is the whole point: a blank avatar is never shown.
  static String of(String name) {
    for (final rune in name.runes) {
      final ch = String.fromCharCode(rune);
      if (_invisible.hasMatch(ch)) continue;
      if (ch.trim().isEmpty) continue;
      return ch;
    }
    return fallback;
  }
}
