// The Arabic name of one urgency level, in one place.
//
// Found on 1 Oct 2026 by reading the two surfaces that print one. The
// `urgency` column is a four-value enum and every level is named in Arabic in
// two files, each with its own private `switch`:
//
//   lib/src/screens/project/project_detail_screen.dart
//       urgent  -> 'عاجل'
//   lib/src/screens/project/project_new_screen.dart
//       urgent  -> 'عاجل جداً'
//
// The three easier levels happen to agree — 'بدون استعجال', 'خلال أسبوع',
// 'خلال شهر' are byte-identical in both — so the mismatch is one word wide
// and invisible to a reader, an analyzer and a screenshot. That is the shape
// of every defect this layer exists to end: the two copies are identical
// three times out of four, which is exactly why nobody compares them.
//
// **The concrete cost is one word, and it is the word that means most.** A
// client taps «عاجل جداً» on the publish screen, the value is stored as
// `urgent`, and the project he then opens — the page a contractor reads to
// decide whether to bid tonight or tomorrow morning — prints «الاستعجال:
// عاجل». He chose "very urgent" and the app answered "urgent". Nobody is
// lied *to*, so nothing crashes and no test turns red; the project is simply
// described with less force than the client asked for, on the one row whose
// entire job is to carry that force.
//
// **Why a shared file and not a getter on the enum.** The model already owns
// the wire value ([UrgencyLevel.wire]) and the inverse
// ([UrgencyLevel.fromWire]), and putting Arabic display copy on the model
// would be the first step toward a model that knows what a sentence is. Every
// other enum-to-Arabic rule in this app lives under `data/` for that reason —
// `quote_status_copy.dart` is the exact sibling: a `QuoteStatus` in, a word
// out, with a screen that used to carry its own copy of the same switch.
//
// **The word, once.** The value each level prints is a single constant here,
// so the pill a client taps and the row a contractor reads cannot name the
// same stored value two ways. Adding a fifth level to the column now breaks
// this one switch at compile time rather than leaving one screen silent about
// it, which is the failure an exhaustive `switch` in a widget is worst at:
// `project_new_screen`'s table is a `const` list of tuples, so a new level
// there would not even fail to compile — it would simply be missing from the
// picker while the detail page still had an answer for it.
library;

import '../models/project.dart' show UrgencyLevel;

/// The Arabic name of [level], as the client typed it when publishing.
///
/// Non-null and total on purpose: every level the column can hold has a name
/// an Algerian reads without translating, and a level with no Arabic would be
/// a value the app could store but not say — which is a gap in the wire, not
/// something to paper over with an empty string.
String urgencyAr(UrgencyLevel level) {
  switch (level) {
    case UrgencyLevel.flexible:
      return 'بدون استعجال';
    case UrgencyLevel.withinWeek:
      return 'خلال أسبوع';
    case UrgencyLevel.withinMonth:
      return 'خلال شهر';
    case UrgencyLevel.urgent:
      // **'عاجل جداً', not 'عاجل'.** This is the word the publish pill has
      // carried since 26 Sep, and it is the one the detail row was getting
      // wrong. Kept verbatim so the two agree and the pill's own test
      // (`tap_target_test.dart`, which finds it by that exact string) keeps
      // describing the control the founder sees.
      return 'عاجل جداً';
  }
}

/// True for the one level the publish screen tints as a danger.
///
/// A property of the *level*, not of the pill: «عاجل جداً» is the only
/// urgency that earns red, and that judgement belongs to the enum's meaning
/// rather than to whichever widget happens to be drawing it. Kept here so a
/// second surface — the card, the detail row — cannot pick a different level
/// to make red, or forget to make one red at all.
bool isUrgentLevel(UrgencyLevel level) => level == UrgencyLevel.urgent;
