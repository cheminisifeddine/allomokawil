// Arabic number agreement, in one place.
//
// Every place in this app that writes a count into a sentence has to answer the
// same question: which form of the noun does this number take? Arabic changes
// the noun on the number, not the number on the noun —
//
//     قبل دقيقة      1   (singular)
//     قبل دقيقتين     2   (dual)
//     قبل 7 دقائق     3–10 (plural)
//     قبل 15 دقيقة   11–102 (singular, counted)
//     قبل 103 دقائق   103–110 (plural again — see the mod-100 rule below)
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
//     1 takes the singular.
//   * [two] is the dual, and is normally a different word: pass `'يومين'`.
//     2 takes the dual, and the dual takes no number, so the number is never
//     printed with it.
//   * [few] is the plural for a broken-plural count: 3–10 take the plural
//     «أيام», not «يوم».
//   * 11–102 take [one] again, because they are *counted singular*: the
//     number is what makes the noun singular, and the noun is what the number
//     is counted in. «بعد 100 يوماً», never «بعد 100 أيام».
//     **But "and up" stops at 102.** The plural range of a counted noun is
//     decided by the *last two digits* of the number, so it repeats: 103 takes
//     the plural «أيام» exactly as 3 does, and 110 takes the plural too,
//     because 10 is inside the 3–10 window. The whole rule is one clause —
//     `n % 100` — and 110 is the number that catches a reader who believes
//     "11 and up" the way they would in English. See [arabicCount].
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
  // The dual is only ever exactly two, however large the number is: 102 is
  // counted singular, not dual, so the `n == 2` test stays absolute.
  if (n == 1) return one;
  if (n == 2) return two ?? one;
  // **The plural range repeats every hundred, and this line is the whole bug.**
  // A counted noun is decided by the last two digits of the number, so 103
  // takes the broken plural exactly as 3 does, and so does 110 — 10 is in the
  // window, and "11 and up is singular" is the English reading of a rule that
  // does not work that way. The old test was `n <= 10`, which is the same
  // thing said only for the first hundred — correct for every number this app
  // printed until a count passed two digits by one, and wrong for every
  // three-digit count whose last two digits fall in 3-10.
  //
  // It was not a theoretical range. The service-radius row on the profile a
  // customer picks a tradesman from is set by a slider running `max: 200`
  // (`Slider(min: 1, max: 200, divisions: 199)` in profile_edit_screen.dart),
  // saved verbatim to the profile, and printed through this helper. A
  // contractor who covers a whole wilaya sets 105 and publishes
  // «105 كيلومتر», where Arabic requires «105 كيلومترات».
  if (n % 100 >= 3 && n % 100 <= 10) return few ?? one;
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
