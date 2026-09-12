/// Arabic-aware text comparison for search, filters and lookups.
///
/// Algerian users spell the same word several ways and a plain `contains()`
/// fails every one of them, so search quietly returns nothing and the app feels
/// foreign:
///
///   * with or without the hamza — `احمد` vs `أحمد`
///   * ta marbuta or ha — `مقاوله` vs `مقاولة`
///   * alef maqsura or ya — `مصطفي` vs `مصطفى`
///   * hamza on waw/ya — `مسوول` vs `مسؤول`
///   * tatweel used for emphasis — `دهـــان`
///   * diacritics, which most phone keyboards omit anyway — `دَهَّان`
///   * Arabic-Indic digits pasted from a contact — `٠٧٧٠` vs `0770`
///   * the definite article glued on — `بحث` should find `البحث`
///
/// Everything that compares user-entered text to stored text goes through
/// [normalize] first. It is deliberately a *matching* transform, not a display
/// transform: it never touches what the user sees.
class ArabicSearch {
  const ArabicSearch._();

  /// Harakat, superscript alef and the Quranic annotation block.
  static final RegExp _diacritics =
      RegExp(r'[\u064B-\u0652\u0670\u06D6-\u06ED]');

  /// Tatweel — a purely decorative horizontal stretch.
  static final RegExp _tatweel = RegExp('\u0640');

  /// Anything that is not an Arabic letter, a Latin letter, a digit or a space.
  /// Punctuation becomes a space so `حسين داي، الجزائر` still tokenises.
  static final RegExp _nonWord =
      RegExp(r'[^\u0621-\u064A\u0660-\u0669a-z0-9\s]');

  static final RegExp _runs = RegExp(r'\s+');

  /// Letter forms that are the same letter to a reader.
  static const Map<String, String> _letters = {
    '\u0622': '\u0627', // آ
    '\u0623': '\u0627', // أ
    '\u0625': '\u0627', // إ
    '\u0671': '\u0627', // ٱ
    '\u0672': '\u0627', // ٲ
    '\u0673': '\u0627', // ٳ
    '\u0649': '\u064A', // ى -> ي
    '\u0626': '\u064A', // ئ -> ي
    '\u06CC': '\u064A', // Persian yeh
    '\u0629': '\u0647', // ة -> ه
    '\u0624': '\u0648', // ؤ -> و
    '\u06A9': '\u0643', // Persian kaf
  };

  /// Arabic-Indic and Persian digits, which arrive when someone pastes a phone
  /// number out of their contacts.
  static const Map<String, String> _digits = {
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
  };

  /// Fold [input] to a comparable form. Idempotent: normalising twice is the
  /// same as normalising once, so it is safe to apply at both ends.
  static String normalize(String input) {
    if (input.isEmpty) return '';
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return '';
    s = s.replaceAll(_diacritics, '').replaceAll(_tatweel, '');

    final folded = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final letter = _letters[ch];
      if (letter != null) {
        folded.write(letter);
        continue;
      }
      final digit = _digits[ch];
      if (digit != null) {
        folded.write(digit);
        continue;
      }
      folded.write(ch);
    }

    return folded
        .toString()
        .replaceAll(_nonWord, ' ')
        .replaceAll(_runs, ' ')
        .trim();
  }

  /// True when every whitespace-separated token of [query] occurs in at least
  /// one of [fields]. An empty (or punctuation-only) query matches everything,
  /// which is what an empty search box should do.
  ///
  /// Word order is ignored and the definite article is not stripped, so
  /// `بحث` matches `البحث` by substring while `دهان شقة` requires both words.
  static bool matches(String query, Iterable<String?> fields) {
    final q = normalize(query);
    if (q.isEmpty) return true;
    final haystack = fields
        .where((f) => f != null && f.isNotEmpty)
        .map((f) => normalize(f!))
        .join(' ');
    if (haystack.isEmpty) return false;
    // Spaces are not reliable input on a phone keyboard, so a query typed
    // without them ("حسينداي") is also compared against a space-free copy.
    final compact = haystack.replaceAll(' ', '');
    for (final token in q.split(' ')) {
      if (haystack.contains(token)) continue;
      if (compact.contains(token.replaceAll(' ', ''))) continue;
      return false;
    }
    return true;
  }

  /// Convenience for looking a single field up, e.g. a wilaya name.
  static bool equals(String a, String b) => normalize(a) == normalize(b);
}
