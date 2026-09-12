/// Algerian-dinar formatting written for low-digital-literacy readers.
///
/// `60000 دج` forces the reader to count zeros; `60 ألف دج` is understood at a
/// glance. Rounded amounts therefore use Arabic unit words (ألف / آلاف /
/// مليون), and everything else is grouped with a non-breaking space so the
/// number never breaks across lines and never gets ellipsised mid-digits.
class Money {
  Money._();

  static const String _nbsp = '\u00A0';
  static const String currency = 'دج';

  /// Full label including the currency: `60 ألف دج`.
  static String dzd(num amount) => '${amountOnly(amount)} $currency';

  /// Number only, no currency — for ranges where the unit is printed once.
  static String amountOnly(num n) {
    final v = n.round();
    if (v < 0) return '0';
    if (v >= 1000000) {
      final m = v / 1000000;
      if (m == m.roundToDouble()) {
        final mi = m.round();
        return mi == 1 ? 'مليون' : '$mi مليون';
      }
      return '${_trim(m)} مليون';
    }
    if (v >= 1000 && v % 1000 == 0) {
      final k = v ~/ 1000;
      if (k == 1) return 'ألف';
      if (k == 2) return 'ألفان';
      if (k <= 10) return '$k آلاف';
      return '$k ألف';
    }
    return _grouped(v);
  }

  /// `7500` -> `7 500`
  static String _grouped(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(_nbsp);
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// `1.5` -> `1.5`, `2.0` -> `2`
  static String _trim(double v) {
    final r = v.toStringAsFixed(1);
    return r.endsWith('.0') ? r.substring(0, r.length - 2) : r;
  }
}
