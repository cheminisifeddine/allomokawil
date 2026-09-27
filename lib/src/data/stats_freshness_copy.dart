// When the numbers on the contractor's header were read.
//
// Found on 27 Sep 2026, immediately after the market tab got its
// pull-to-refresh. The `RefreshIndicator` closed the *transport* half of that
// defect — a stale screen could be re-read — and in doing so made the other
// half visible. Before the pull, a stale header was at least a screen you had
// to come back to. After the pull it is a number he has just been offered a way
// to update, printed with no indication of when it was true, and the app's
// own gesture implies it is current. A contractor decides how hard to push to
// win a job off that line: «4 من 4» projects and a 4.6 are what he judges
// himself against before he sends an offer, and both are whatever the server
// said whenever the tab happened to be built.
//
// This is the same class as the five unmeasured numbers in
// [worker_stats_copy] — a missing measurement printed as a fact — except that
// none of those are missing here. They are *present and dated wrong by
// silence*. The rating is real, the job count is real, and the app states
// none of that.
//
// The fix is not a bigger number and not a warning icon. It is the one piece of
// information the sentence was missing: how long ago this was true. A value an
// hour old says «قبل ساعة», and a contractor who thinks about it for a second
// pulls. The same code path in `notifications_screen.dart` already renders
// [relativeTimeAr] for exactly this reason, and the count grammar is not
// re-invented here either — it routes through the same [arabicCounted] the
// rest of the app shares, so this file cannot drift from it the way a third
// hand-rolled copy already did once.
library;

// Only [relativeTimeAr] is needed: the day/month arms and the Arabic count
// grammar already live behind it, and re-deriving them here is how the same
// rule drifts into a second copy. `arabic_agreement` and `chat_time` are
// reached through it rather than imported directly.
import 'notification_copy.dart';

/// How long ago the header's numbers were read, in the app's own words.
///
/// Three outcomes, and the third is the one that earns the feature:
///
///   * **null** — the read never happened, so there is nothing to date. Same
///     empty string as a fresh read, and deliberately: a header that has never
///     been read has no age, and «الآن» over a number the app has never seen
///     would be the strongest claim this file could make and the least
///     deserved one.
///   * **under a minute** — **empty**, and the caller renders nothing at all. A
///     header that was read thirty seconds ago is fresh, and «الآن» under three
///     clauses of numbers is a fourth clause saying nothing: it makes the row
///     busier on the one occasion there is nothing to report, and it means the
///     clause is *never* absent, so a contractor learns to skip past it and
///     then misses it on the read where it is the only thing that matters.
///   * **a minute and older** — «قبل 3 دقائق», «قبل ساعة», «أمس», «قبل 3
///     أشهر». Copied from [relativeTimeAr] rather than re-derived, for the
///     reason its own comment gives: a 27-hour-old row must read «أمس» here for
///     the same reason it does in the notification list. Two surfaces dating
///     one read two different ways is the defect this file was opened for.
///
/// A read from the *future* is clock skew, not a value from tomorrow: it is
/// reported as «الآن» instead of being allowed to print a negative age.
String statsFreshnessAr(DateTime? readAt, {DateTime? now}) {
  if (readAt == null) return '';
  final today = now ?? DateTime.now();
  final diff = today.difference(readAt);
  // Silence, not «الآن». See the contract above: the clause exists to report a
  // read that has gone off, and a read that has not gone off is not an event.
  if (diff.isNegative || diff.inSeconds < 60) return '';
  return relativeTimeAr(readAt, now: today);
}

/// Whether a header read is old enough to be worth dating out loud.
///
/// Sixty seconds is the threshold and it is not arbitrary: it is the point at
/// which [relativeTimeAr] stops answering «الآن» and starts answering with a
/// count, so a caller that asked this question and then printed a *different*
/// threshold's answer would put «قبل 0 دقائق» under a fresh header.
///
/// The second condition is the one that matters more. A read that is hours old
/// is dated **loudly**, in the app's own warning tone, because a contractor
/// acting on a quarter-old job count is not making a decision, he is guessing
/// with the app's endorsement. Everything inside the threshold is muted: it is
/// there to be noticed by the person who *is* looking, not to shout at the
/// person who is not.
bool statsAreStale(DateTime? readAt, {DateTime? now}) {
  if (readAt == null) return false;
  final diff = (now ?? DateTime.now()).difference(readAt);
  // Skew in the other direction is a broken clock, not a fresh read, and
  // ageing it into a warning would be the app blaming the phone for the
  // server's timestamp.
  if (diff.isNegative) return false;
  return diff.inMinutes >= 60;
}
