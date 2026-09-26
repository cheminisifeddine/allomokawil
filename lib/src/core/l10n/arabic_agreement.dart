// Arabic number agreement, in one place.
//
// Every place in this app that writes a count into a sentence has to answer the
// same question: which form of the noun does this number take? Arabic changes
// the noun on the number, not the number on the noun —
//
//     قبل دقيقة      1   (singular)
//     قبل دقيقتين     2   (dual)
//     قبل 7 دقائق     3–10 (plural)
//     قبل 15 دقيقة   11+  (singular, counted)
//
// The rule is four lines long and it was implemented three separate times, in
// three files, with three different sets of nouns. Two of the three copies were
// right; the third — the subscription countdown added on 26 Sep — was not, and
// printed «بعد 3 يوماً», «بعد 2 يوماً» and «بعد 1 يوماً» on the one card whose
// job is to tell a paying contractor how long he has paid for. That is the whole
// reason this file exists: a rule small enough to hold in your head is not
// evidence you are holding it, and a rule copied into a third place is a rule
// that has already drifted once.
//
// Rules, spelled out rather than implied:
//   * [one] is the singular, already carrying any needed tanween — pass
//     `'يوماً'` for a count in an accusative ("after N days"), not `'يوم'`.
//   * [two] is the dual, and is normally a different word: pass `'يومين'`. The
//     dual takes no number, so the number is never printed with it.
//   * [few] is the plural used for 3–10, which in a count is the broken plural
//     — `'أيام'`, not `'يوم'`.
//   * 11 and up take [one] again, because they are *counted singular*: the
//     number is what makes the noun singular, and the noun is what the number
//     is counted in. «بعد 100 يوماً», never «بعد 100 أيام».
//
// Nouns are passed in, never derived, so a caller can never accidentally print
// the singular form of a feminine noun in the dual slot: the compiler sees the
// four words at the call site, side by side.
library;

/// Counted-noun agreement for an Arabic sentence.
///
/// [n] is the count. [one]/[two]/[few] are the three noun forms the count
/// selects between; [two] and [few] may be omitted when the caller does not
/// need them, in which case [one] is used for the dual and plural slots — which
/// is right for a noun whose forms are the same word, and visibly wrong for one
/// that is not, which is why every call site in this app passes all four.
///
/// Assumes [n] >= 1. A count of zero or less has no Arabic form here: it is
/// not a thing the app should be able to print. Call sites that can see a zero
/// are expected to branch to copy that does not mention a count at all, because
/// «بعد 0 يوماً» and «قبل -3 دقائق» are exactly the failures this file exists
/// to make unrepresentable.
String arabicCount(int n, String one, {String? two, String? few}) {
  assert(n >= 1, 'a count of $n has no Arabic form; branch to copy without '
      'a count instead of printing a number that is not one');
  if (n == 1) return one;
  if (n == 2) return two ?? one;
  if (n <= 10) return few ?? one;
  return one;
}

/// [arabicCount] with the number in front, the way 3–10 and 11+ are written.
///
/// The number is omitted twice, and both omissions are the grammar rather than
/// a convenience: the **singular** is not counted (one is what «يوم» already
/// means, so «قبل دقيقة» and never «قبل 1 دقيقة»), and the **dual** already
/// says two (so «قبل دقيقتين», never «قبل 2 دقيقتين»).
String arabicCounted(int n, String one, {String? two, String? few}) {
  final noun = arabicCount(n, one, two: two, few: few);
  if (n == 1 || n == 2) return noun;
  return '$n $noun';
}
