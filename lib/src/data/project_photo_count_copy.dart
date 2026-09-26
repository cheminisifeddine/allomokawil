// How many photos the client has just attached, said the way the number says it.
//
// Found on 26 Sep 2026 while auditing what the quote-duration fix left. Same
// vein, sixth cycle down: a count is either delegated to [arabicCounted] or
// spelled out by hand, and every hand-written one so far has been wrong.
//
// The attach strip under "صور المشروع" on the publish screen built its line out
// of string interpolation and two fixed words:
//
//     '${images.length} صورة مضافة'
//
// That is **two agreements, not one**, and the old line got the easier one wrong
// and the harder one wrong for a different reason:
//
//   * the noun — «صورة» is the singular, and it is the wrong word for 2 and for
//     3-10, the same trap [photo_count_copy.dart] already documents and already
//     gets right on the contractor's portfolio;
//   * the adjective — «مضافة» is feminine singular, so the dual of the noun has
//     to drag the adjective to feminine dual with it («مضافتان») or the line
//     reads «صورتان مضافة», a feminine singular modifying a feminine dual.
//
// **The range is not hypothetical and it is not an edge case.** The strip hides
// its add tile at 6 thumbnails, so the first two photos a client ever attaches
// already print a wrong line: «2 صورة مضافة» instead of «صورتان مضافتان».
// The singular arm is the most-used one on the screen and the dual is the second
// photo, so the two ranges this file exists to fix are reached by almost
// everyone who attaches anything at all.
//
// **The ceiling is 10, and that is a real bound, not an assumption.** The add
// tile is drawn only while `images.length < 6` and `pickMultiImage(limit: 6)`
// caps one *selection*, not the running total, so a client who picks 5 and then
// 5 again reaches 10 and the tile disappears for good. The 11+ arm is therefore
// **unreachable from this screen today** — it is implemented anyway, because
// [photosAr] returns to the counted singular there and a line that agreed with
// the noun everywhere except the one arm the noun changes would be a landmine
// the day the cap moves. Saying so is the point: the arm is a contract with
// [photosAr], not a claim about a state a user can currently reach.
//
// This is the one place in the app where the counted noun carries an adjective,
// which is why it gets its own file rather than a line in
// [photo_count_copy.dart]: the noun forms are not re-invented here, they are
// borrowed from [photosAr], and this file owns only the agreement of the word
// that follows it.
library;

import '../core/l10n/arabic_agreement.dart';
import 'photo_count_copy.dart';

/// The bare feminine adjective that agrees with the counted noun:
/// «مضافة» / «مضافتان».
///
/// Split out so both the sentence and its tests read the same four words side by
/// side, which is the only way the dual arm cannot quietly go missing. 11+ takes
/// `one` back — «11 صورة مضافة» — because a counted singular agrees with a
/// singular adjective, and that is the same 11+ trap the noun itself has, so it
/// is covered in both directions rather than one.
String addedAdjectiveAr(int n) {
  if (n <= 0) return '';
  return arabicCount(n, 'مضافة', two: 'مضافتان', few: 'مضافة');
}

/// The line under the attach strip: «صورة مضافة» / «صورتان مضافتان» /
/// «3 صور مضافة» / «11 صورة مضافة».
///
/// The noun comes from [photosAr] rather than from a second set of literals, so
/// the two photo counts in this app cannot drift apart again — that is the exact
/// failure this file was opened to fix, and copying four words into it would
/// have recreated it one layer down.
///
/// A zero is silence rather than «0 صور مضافة»: [arabicCount] asserts on a count
/// it has no form for, and the screen already branches to copy with no count in
/// it when the strip is empty, so this only has to agree with it. That is the
/// same contract `photosAr` and `durationDaysAr` already have.
String addedPhotosLineAr(int n) {
  if (n <= 0) return '';
  final photos = photosAr(n);
  if (photos.isEmpty) return '';
  return '$photos ${addedAdjectiveAr(n)}';
}
