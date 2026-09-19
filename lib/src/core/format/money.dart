/// Algerian-dinar formatting.
///
/// The founder's call, verbatim: «use dinar format like 6000 دج instead of 6
/// الاف دينار». Arabic unit words (ألف / آلاف / مليون) turned a price into
/// something the reader had to translate before comparing it with the next one,
/// so every amount is now plain digits followed by `دج` — the same shape on a
/// project card, a quote, a budget range and a subscription block.
class Money {
  Money._();

  static const String currency = 'دج';

  /// Full label including the currency: `6000 دج`.
  static String dzd(num amount) => '${amountOnly(amount)} $currency';

  /// Number only, no currency — for ranges where the unit is printed once.
  ///
  /// Grouping separators are deliberately absent: `6000` is what the founder
  /// asked to see, not `6 000`.
  static String amountOnly(num n) {
    final v = n.round();
    return v < 0 ? '0' : v.toString();
  }
}
