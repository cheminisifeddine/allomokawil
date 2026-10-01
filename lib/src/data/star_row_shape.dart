// Which star each position of a rating row wears — one rule, in one place.
//
// Found on 26 Sep 2026. `RatingStars` used to branch on `rating.round()`
// first and only then ask about the half:
//
//     i <= rating.round()  ? star_rounded
//     : (i - 0.5 <= rating ? star_half_rounded : star_outline_rounded)
//
// Dart's `double.round()` rounds halves **away from zero**, so at 4.5 the
// first branch is already true for all five positions and the half branch is
// never reached. The row published five FULL gold stars beside the text «4.5»,
// while `A11y.rating` on the same widget said «التقييم 4.5 من 5» — one widget,
// two answers, on the number a customer uses to choose between two tradesmen.
//
// Worse, the half branch was not merely wrong at 4.5: it was **unreachable
// code**. Reaching it needs `i > round(rating)` and `i - 0.5 <= rating`
// together, which is only satisfiable by a score sitting exactly on a half that
// rounds *down* — and 0.5, 2.5 and 4.5 all round up. Enumerated over every
// value the app can hold in thousandths (0.000 … 5.000) the branch fires
// **zero** times. A `star_half_rounded` widget could not be found in the tree
// at any score, which is why no test ever caught it: the glyph was there in
// the source and absent from every screen.
//
// The rule, in one sentence: **every whole star below the score is filled, and
// the next one is half-filled once the score has reached halfway to it.**
// `4.5` → `FFFFH`, `4.4` → `FFFF.`, `4.7` → `FFFFH`, `3.0` → `FFF..`,
// `5.0` → `FFFFF`.
//
// Two properties make it the honest rule, and the old one had neither:
//
//   * **It never overstates.** A glyph row can only be as coarse as a glyph, so
//     the test it must pass is that it never draws *more* than the number beside
//     it. `round()` broke exactly that: 4.5 became five full stars, one more
//     than the «4.5» printed next to them. Understating is conventional and
//     harmless; overstating is a claim the row cannot back.
//   * **It is monotone.** More reviews can only ever move the row right, never
//     make a star go backwards.
//
// This lives in `data/` rather than inline in the widget for the same reason
// every other rule in this app does: it is arithmetic, it is checkable over
// all 5,001 values in thousandths in a millisecond, and a rule that can only
// be tested by pumping a widget is a rule that ships untested. The half-star it
// restores was drawn nowhere in three months of releases because the only way
// to test it was the way nobody did.
//
// Nothing is borrowed: all three glyphs are bundled Material icons this widget
// already used.
library;

import 'package:flutter/material.dart';

/// A score pinned to the scale the row actually draws: `0..count`.
///
/// **This is the rule for the digits as well as the glyphs**, and until 1 Oct it
/// was only the glyphs'. `starIconFor` clamped, and the number printed beside
/// the stars was the caller's raw `rating.toStringAsFixed(1)` — so an
/// `avg_rating: 7.5` off the API drew `FFFFF` (five full gold stars, the
/// clamp working) next to the text **7.5** and told a screen reader
/// «التقييم 7.5 من 5». The row it was opened to fix had simply been fixed
/// halfway: the glyphs stopped overstating and the digits kept on doing it, and
/// "never overstate" was true of the shapes and false of the sentence.
///
/// The two answers cannot both be right, and which of them to trust is not a
/// drawing question: the stars are a rendering of the score, so the score is
/// what has to be pinned, and the glyphs follow it down. Pinning it here, once,
/// is what keeps the label, the shapes and the printed number from each
/// growing their own private opinion about a score outside the scale.
///
/// NaN is treated as no score at all rather than being left to print as
/// «NaN» beside five empty stars.
double clampRating(double rating, {int count = 5}) {
  if (rating.isNaN) return 0.0;
  if (rating < 0) return 0.0;
  if (rating > count) return count.toDouble();
  return rating;
}

/// The glyph position [i] (1-based, of [count]) wears for a score of [rating].
///
/// [count] is the number of positions the row draws; the app's row is always
/// five. Scores outside `0..count` are clamped rather than trusted, because a
/// row that draws more stars than it has positions would throw at the icon.
IconData starIconFor(int i, double rating, {int count = 5}) {
  if (i < 1 || i > count) {
    throw RangeError.range(i, 1, count, 'i');
  }
  final r = clampRating(rating, count: count);
  final whole = r.floor();
  if (i <= whole) return Icons.star_rounded;
  // The first position past the whole stars, and only once the score has
  // reached halfway to it: a whole 4.0 must not draw four full stars and a
  // half, and a 4.4 must not claim a half it has not earned.
  if (i == whole + 1 && r - whole >= 0.5) return Icons.star_half_rounded;
  return Icons.star_outline_rounded;
}

/// The row as a five-character string, for tests and for reading a diff:
/// `F` full, `H` half, `.` empty. `4.5` -> `FFFFH`.
String starRowShape(double rating, {int count = 5}) => [
      for (var i = 1; i <= count; i++)
        switch (starIconFor(i, rating, count: count)) {
          Icons.star_rounded => 'F',
          Icons.star_half_rounded => 'H',
          _ => '.',
        }
    ].join();

/// What the row is worth, in stars: a full star is 1 and a half star is 0.5.
///
/// This is the number the "never overstate" property is checked against, and it
/// is exported so a caller can compare the row it is about to draw with the
/// score it is about to print, instead of re-deriving the rule.
///
/// A half is worth **half**, not one. Counting it as a whole star is exactly
/// the bug this file was opened for: it is what turns 4.5 into a row claiming
/// five, and a test that used that definition would have passed the old
/// `round()` code it exists to catch.
double starRowValue(double rating, {int count = 5}) {
  var value = 0.0;
  for (var i = 1; i <= count; i++) {
    final glyph = starIconFor(i, rating, count: count);
    if (glyph == Icons.star_rounded) {
      value += 1;
    } else if (glyph == Icons.star_half_rounded) {
      value += 0.5;
      break;
    }
  }
  return value;
}
