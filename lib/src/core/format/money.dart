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
  ///
  /// **A negative amount is `0`, and a non-finite one is `0` too** — and the
  /// second half is here because the guard used to be only the first.
  ///
  /// `n` is a `num`, so `double` is inside this signature's contract, and
  /// `n.round()` is `toInt()`, which **throws** `UnsupportedError: Unsupported
  /// operation: Infinity or NaN toInt` on a value that is not finite. Measured:
  /// `double.nan`, `double.infinity` and the two things arithmetic actually
  /// produces — `0.0/0.0` and `1.0/0` — all throw. The test beside the
  /// negative arm had `expect(Money.amountOnly(-5), '0')` and passed, because a
  /// negative *is* a finite number and the `v < 0` fold caught it. The value the
  /// signature accepts and the value the guard covered were not the same set.
  ///
  /// It matters because this is a **money** path and the throw lands in a widget
  /// build: `UnsupportedError` is an `Error`, not an `Exception`, so
  /// `errorCopy`'s arms — every one of which is `is SomeException` — do not
  /// catch it. A NaN reaching `budgetLabel` takes the project card down rather
  /// than dropping the row, which is the opposite of what the negative fold
  /// does two lines below it.
  ///
  /// `0` is the honest answer in both cases and is already this function's
  /// answer for a negative price: neither is a number a contractor can be
  /// quoted, and a fold to `0` is what every count copy in this app does with a
  /// value that has no form (`photosAr`, `durationDaysAr`, `wilayaSpanAr`). A
  /// price of NaN rendered as `0 دج` is a false price; the alternative was a
  /// red screen, and on this screen that trade is not close.
  ///
  /// The test is `isFinite`, not `isNaN`: **Infinity is not NaN**, so the two
  /// halves of this guard are different bugs and a `isNaN` fold leaves three of
  /// the four non-finite values still throwing. `1.0/0` is infinite rather than
  /// NaN, which is the value a division by a zero limit actually produces on
  /// this app's own quota bar. `0.0/0.0` is NaN and the two infinities are
  /// neither, so `isFinite` is the only test that answers the question the
  /// signature asks — "is this a number at all" — in one place.
  static String amountOnly(num n) {
    if (!n.isFinite) return '0';
    final v = n.round();
    return v < 0 ? '0' : v.toString();
  }
}
