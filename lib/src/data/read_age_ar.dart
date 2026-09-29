// How old a *read* is, in the app's words, when the read may not have been
// the most recent thing that happened.
//
// Created 29 Sep 2026 on the fourth tick of the stale-band family, and only
// because the fourth tick wrote the same seven lines a third time.
//
// Three surfaces already dated a read when this file was opened and each had
// arrived at the same rule independently: `stats_freshness_copy.dart` (the
// contractor header's numbers), `stale_market_copy.dart` (the open-project
// feed), `stale_projects_copy.dart` («مشاريعي») and, one tick later,
// `stale_directory_copy.dart` («ابحث عن مقاول»). Four copies of:
//
//     if (readAt == null) return '';
//     final diff = (now ?? DateTime.now()).difference(readAt);
//     if (diff.isNegative) return '';
//     if (diff.inSeconds < 60) return '';
//     return relativeTimeAr(readAt, now: today);
//
// Four identical copies is not a style problem, it is a **latent split-brain**:
// the copy that decides a read is old enough to be worth telling a user about
// is a policy, and a policy held in four places is a policy that will be held
// in four different states after the first edit. This repo has already paid
// for exactly that once — the subscription card hand-rolled its own copy of
// the same grammar and called three hours «قبل 3 ساعت» — and that is the
// argument for putting it in one file rather than four.
//
// ── The rule, and the three ways it is wrong ────────────────────────────
//
// **1. Under a minute is SILENCE, not «الآن».** [relativeTimeAr] answers
// «الآن» below a minute, which is correct for a message that genuinely just
// arrived and wrong everywhere this rule is used: these strings are
// *apologies*, and «قرأناها الآن» printed under a band that exists because the
// read did not refresh is the app claiming the reader is looking at the live
// list. The same applies to the header's freshness clause — a contractor's
// numbers read thirty seconds ago are not news, and printing «الآن» makes the
// clause *never absent*, so a reader learns to skip it and then misses it on
// the read where it is the only thing that matters.
//
// Sixty seconds is not an arbitrary round number either: it is the point at
// which [relativeTimeAr] itself stops answering «الآن» and starts answering
// with a count, so this threshold and that function cannot disagree without
// the disagreement being visible here.
//
// **2. Negative is CLOCK SKEW, not the future.** A stamp ahead of the phone is
// a broken clock somewhere between the server and the handset. Ageing it into
// «قبل -3 دقيقة» would be the app blaming the reader's phone for somebody
// else's timestamp, so the skewed read is reported as having no age and the
// caller keeps its own wording. Note this is *not* the same as arm 1: [relativeTimeAr]
// folds skew into «الآن», and doing the same here would reintroduce exactly
// the claim arm 1 forbids.
//
// **3. `null` is not an age of zero.** A read that never happened has no age,
// and says nothing — not «الآن», not «قبل 0 دقيقة». `statsFreshnessAr` has
// always meant this; the three band files meant it too, but each re-stated it.
//
// The grammar itself is deliberately **not** re-derived: [relativeTimeAr]
// already owns the Arabic count agreement and the calendar-day boundary, and
// the day/month arms are the reason this file is ten lines instead of forty.
library;

import 'notification_copy.dart';

/// The one answer to "how old is this read?", for every surface that dates a
/// read.
///
/// Returns `''` for a read that never happened, for one that is less than a
/// minute old, and for one stamped ahead of [now] — the three cases where the
/// honest answer is silence. Otherwise it returns [relativeTimeAr]'s own
/// wording: «قبل 12 دقيقة», «قبل ساعتين», «أمس», and past a year the calendar
/// date.
///
/// [now] exists so the whole app's copy is testable on a wall clock the test
/// owns, and so a widget can pass the same instant it used to stamp its cache.
String readAgeAr(DateTime? readAt, {DateTime? now}) {
  if (readAt == null) return '';
  final today = now ?? DateTime.now();
  final diff = today.difference(readAt);
  if (diff.isNegative) return '';
  if (diff.inSeconds < 60) return '';
  return relativeTimeAr(readAt, now: today);
}
