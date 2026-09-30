// What «معرض أعمالي» says when the photos on screen are not the photos on the
// server.
//
// Found 30 Sep 2026 with 0 unchecked items, by reading the family the last four
// items each named rather than inventing new work. It is the **tenth** screen to
// get this treatment, and the first one in the family whose data is not a list
// of *rows* at all — it is a grid of a contractor's own photographs, the one
// surface in the product he is the author of and the only one whose whole
// purpose is to be looked at.
//
// The mechanism is the family's original mistake, untouched, at
// `my_portfolio_screen.dart:335`:
//
//     body: _loading ? const SkeletonGrid() : ...
//
// **One nullable boolean is asked two questions.** `_loading` answers "is a
// read in flight?" and the builder uses it to answer "is there anything to
// draw?" — two different questions, and the gallery is the one surface where
// conflating them costs the user his work. A contractor taps «تحديث» on a
// gallery of twelve photos on hotel wifi; `myProfile()` drops the connection;
// `_loading` goes false, `_error` is set, `_images` still holds the twelve
// URLs — and the screen throws them away, because the only thing that could
// have drawn them is the flag that says a read is *in flight*.
//
// So the skeleton is shown for the two states it should never cover:
//
//   * a **failed re-read** — rows were on screen, the server went away, and the
//     answer is the grid that is already there with one line saying it might be
//     old. Instead the photos vanish and the contractor is left staring at grey
//     boxes, having done nothing. This is the *same* defect the inbox had, and
//     the sibling's file names why it is the worse half of the pair: seven
//     screens destroy the data and report the failure — loud, and still wrong.
//   * a **pending re-read** — the «تحديث» button arms a read, `_loading` is
//     true, and twelve photographs of finished jobs are replaced by a shimmer
//     for the length of a round trip. On every other screen in the family the
//     pending read falls back to the cache, because "the user did nothing at
//     all" is exactly the case a blanking read should not punish.
//
// What makes this screen the one where the failure is worst is spelled out in
// the file that fixed the *other* end of the same gallery
// (`test/portfolio_badge_failure_test.dart`): a contractor whose badge is wrong
// is told «أضف صوراً» — a **directive**, in the gold that means "you should do
// this" — and he obeys it by uploading duplicates. Here the photos do not even
// get that far; they simply are not on the screen any more, so the only thing
// that could tell him his work is safe is the band this file writes.
//
// The first read keeps the full-screen error, exactly as every sibling does:
// there is genuinely nothing to draw, and the retry button is the whole answer.
// The branch is not weakened, it is drawn where the data is.
library;

import 'read_age_ar.dart';

/// The line shown above a gallery that failed to re-read.
///
/// [error] is the already-curated Arabic sentence from `errorCopy`, which
/// describes a failure and nothing else. This composes it with the half it
/// cannot know: that what the reader is looking at survived an earlier read.
String staleGalleryLineAr(String error) {
  final reason = error.trim();
  // No sentence about the failure means no sentence. `errorCopy` always
  // produces one, so this arm is unreachable in the app and exists so a bare
  // failure cannot produce a band that explains nothing.
  if (reason.isEmpty) return 'قد لا تكون هذه الصور محدَّثة';
  return 'لم نتمكن من تحديث معرض أعمالك — هذه آخر صورة قرأناها. $reason';
}

/// How old the photos under the band actually are.
///
/// The **freshness half** of the family, and the tenth member to get it, after
/// the market, the projects list, the directory, the notifications, the two home
/// strips, the subscription catalogue, the inbox and the strip. The band
/// already says «هذه آخر صورة قرأناها» — *this is the last photo we read* —
/// which is true and answers nothing: a refresh that failed four seconds ago
/// and one that failed three days ago print the **same sentence**.
///
/// It matters more here than on most siblings, because on a gallery an age is a
/// *commercial* claim rather than a convenience. «قبل 12 دقيقة» and «قبل 3
/// أيام» are the same grid of photographs, and to the client who lands on
/// `worker_profile_screen.dart` they are the same pictures too — so the
/// contractor cannot tell a visitor whether the work he is looking at is what he
/// finished this morning or what he has not touched since the spring. A
/// contractor deciding whether to spend his evening re-uploading every photo he
/// has is a decision this band is supposed to inform, and today it cannot.
///
/// **The rule is not this file's.** It is [readAgeAr], which the whole app
/// routes through so that a header, a market, a project list, a directory, two
/// home strips, a catalogue, an inbox and now a gallery cannot each decide
/// separately what "old enough to mention" means. Null, clock skew and
/// under-a-minute are silence, and a band whose photos are still current keeps
/// its own words.
String staleGalleryAgeAr(DateTime? readAt, {DateTime? now}) =>
    readAgeAr(readAt, now: now);

/// The band line with its age, when the age is worth a word.
///
/// Same two rules as every sibling, and the second is the one that is easy to
/// get wrong:
///
///   * The age is **appended**, never substituted. The failure sentence names
///     the *kind* of failure `errorCopy` diagnosed, and the age says nothing
///     about it. A band that traded the reason for a timestamp would print
///     «قرأناها قبل 12 دقيقة» without saying *why* it might not be newer.
///   * A read with no age worth printing produces **exactly the old line**,
///     byte for byte, so a band added today cannot move a baseline captured
///     yesterday.
String staleGalleryLineWithAgeAr(
  String error,
  DateTime? readAt, {
  DateTime? now,
}) {
  final base = staleGalleryLineAr(error);
  final age = staleGalleryAgeAr(readAt, now: now);
  if (age.isEmpty) return base;
  return '$base\nالصور المعروضة $age.';
}
