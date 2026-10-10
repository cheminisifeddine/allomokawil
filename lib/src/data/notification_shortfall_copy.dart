// «The list you are looking at is not the whole unread set» — measured, not
// assumed.
//
// Found 10 Oct 2026 by `tool/notification_read_audit.py`, which is the member
// of this family that **measured** production instead of reasoning about it,
// and the measurement is what makes this file necessary:
//
//     GET  /api/notifications   -> 100 rows, and a hard cap at 100
//     GET  /api/unread          -> the server's real count (140)
//     POST /api/notifications/read with 100 ids -> HTTP 500
//
// The centre counted its unread rows out of the **list it was drawing**, so
// `if (_unread > 0)` gated «تعليم الكل كمقروء» on a list the server had already
// capped. The sequence a real user walks, and every step of it is measured:
//
//   1. the centre draws the newest 100; the other 40 are invisible;
//   2. the user reads or clears everything he can see — `_unread` reaches 0;
//   3. `_unread > 0` is the gate, so **the button disappears**;
//   4. the server still reports **40 unread**.
//
// Step 3 is the defect, and it is a *claim about data the phone never read*:
// the app says «nothing is unread» about a set it is holding 100 of 140 rows
// for. Nothing on screen contradicts it — no error, no amber band, no way to
// tell that a button went missing rather than that a job got done.
//
// **Why a band against the screen's own count would have been wrong, and why
// the number has to come from the wire.** A band is a header on rows the reader
// can scroll, so «40 unread» drawn over a list where those 40 are not present
// points at nothing: the user scrolls the whole centre, finds no trace of them,
// and is told to look harder. That is a fabrication of exactly the kind this
// screen has been fixed for seven times. The count only becomes a *usable*
// sentence if it is the server's own, and it is only the server's when
// `/api/unread` actually answered — which is what [NotificationShortfall]
// records and what the band below refuses to draw without.
//
// **So the trust flag and this file are one mechanism seen from two sides.**
// `notification_count_trust.dart` is one-directional on purpose: only a real
// read of `/api/unread` restores it, because a successful
// `GET /api/notifications` proves a *row* is read and says nothing about the
// size of the whole set the pip paints. This screen issues that read, so it is
// the one place in the app that can put the pip back — and until this tick it
// never did, so the one screen that owns the number was the one that could not
// refresh the proof of it.
//
// Pure, so the wording and the arithmetic are testable without pumping a
// widget — the same split `stale_notifications_copy.dart` and
// `notification_read_outcome.dart` use.
library;

import '../core/l10n/arabic_agreement.dart';

/// The server's unread count beside the rows, as the centre last read it.
///
/// [serverUnread] is null when `/api/unread` has not answered yet, or failed.
/// That is a **different state from zero**, and keeping the two apart is the
/// point of the file: 0 is a fact the server stated, null is the phone
/// admitting it has no fact. A null that read as 0 would be the very defect
/// this closes, one level up.
class NotificationShortfall {
  /// Both counts default to 0 because the only other place this is built is a
  /// test asking about the server number alone -- and an unnamed list has no
  /// rows in it at all, drawn or unread. Required would be stricter; defaulted
  /// is what keeps `const NotificationShortfall(serverUnread: 140)` readable
  /// at a call site that is about the number, not the list.
  const NotificationShortfall(
      {this.serverUnread, this.unreadDrawn = 0, this.drawn = 0});

  /// `GET /api/unread`, or null when it could not be read.
  final int? serverUnread;

  /// How many UNREAD rows are actually in the list on screen.
  ///
  /// This is the *subtrahend*: the server counts every unread row it holds,
  /// including the ones past the cap, so the gap is `serverUnread` minus this.
  final int unreadDrawn;

  /// How many rows are in the list on screen at all, read or not.
  ///
  /// **A different fact from [unreadDrawn], and it was one field doing both
  /// jobs** -- which is why the band could not draw on the one screen whose
  /// whole job is to report a gap. A user who cleared every row he could see
  /// drives [unreadDrawn] to 0 while [drawn] is still 100: the centre is full
  /// of notifications he has seen, he just cannot reach the other 40. The
  /// guard against a band floating over an empty screen asks *"is the list
  /// empty?"*, and that question is only ever about [drawn]. Reading it as
  /// unread rows is what suppressed the band in exactly the state the server
  /// audit measured.
  final int drawn;

  /// The unread rows the centre is **not** showing: the server's count minus
  /// the unread rows it drew.
  ///
  /// Never negative and never null-by-accident: a server count that came back
  /// *below* the rows on screen is not a shortfall but a disagreement — a read
  /// that raced a mark-read, or two endpoints answering for two accounts. The
  /// band must not claim «there are more above» over a list that already
  /// outnumbers the server's answer, so this floors at 0 and the caller gets
  /// [stranded] false instead of a negative number it would have to reason
  /// about itself.
  int get hidden => serverUnread == null
      ? 0
      : (serverUnread! - unreadDrawn).clamp(0, 1 << 31);

  /// True when rows are unread that this screen has never drawn.
  ///
  /// Requires the server's count. With only [unreadDrawn] there is no evidence
  /// of a gap at all — and *not knowing is not evidence of a gap*, so this is false
  /// rather than a guess in either direction.
  bool get stranded => hidden > 0;

  /// The band is worth drawing at all.
  ///
  /// False for a centre with nothing unread to begin with: an empty screen that
  /// says «there are 40 more you cannot see» would be a sentence about rows the
  /// reader has no reason to believe exist, attached to a screen that is simply
  /// empty.
  bool get worthReporting => stranded && drawn > 0;

  NotificationShortfall copyWith(
          {int? serverUnread, int? unreadDrawn, int? drawn}) =>
      NotificationShortfall(
        serverUnread: serverUnread ?? this.serverUnread,
        unreadDrawn: unreadDrawn ?? this.unreadDrawn,
        drawn: drawn ?? this.drawn,
      );

  @override
  String toString() => 'NotificationShortfall(serverUnread: $serverUnread, '
      'unreadDrawn: $unreadDrawn, drawn: $drawn)';
}

/// «يوجد 40 إشعاراً لم تصلك بعد» — the counted form.
///
/// Built on `arabicCounted`, the app's one agreement helper, so this noun
/// cannot drift from «تقييم» / «مشروع» / «رسالة» elsewhere: «إشعار واحد»,
/// «إشعاران», «3 إشعارات», «11 إشعاراً».
String notificationHiddenCountAr(int n) {
  if (n <= 0) return '';
  return arabicCounted(
    n,
    'إشعار',
    two: 'إشعاران',
    few: 'إشعارات',
  );
}

/// The band above a centre that is not showing the whole unread set.
///
/// **Null for every state in which the app cannot say it**, and that is the
/// majority of them. The caller draws its own banner for an empty centre and a
/// null string here means it draws nothing extra — a band over an empty screen
/// is a sentence about rows with nothing to attach them to.
///
/// The three refusals, each a different truth, and the reason none of them
/// falls through to a guess:
///
///  * **no server count** — the phone could not read `/api/unread`, so it does
///    not know the list is short. Not knowing is not evidence of a gap, and
///    claiming one would invent a number to go with it.
///  * **a centre with nothing on it** — there is no list to be short *of*.
///  * **no gap** — the server's count agrees with the rows, and saying
///    otherwise would be noise on the ordinary path.
///
/// The sentence names the number the server gave and not the rows on screen,
/// and that is the whole reason it is safe to draw: the user is told what is
/// waiting, and told it cannot be shown here, without being sent to scroll a
/// list that provably does not contain them.
///
/// **It must not tell the reader to refresh, and that is measured, not taste.**
/// The first draft closed «اسحب للأسفل للتحميل» -- and `tool/notification_read_audit.py`
/// had already measured on production that the cap cannot be raised from the
/// client: `?limit=200`, `?limit=500&page=1`, `?page=2`, `?offset=100` and
/// `?all=1` all return **the same 100 rows, byte-identical**. There is no
/// pagination on this endpoint and there is no page the user could pull to, so
/// the gesture is not merely useless -- it is an instruction to fail, on the
/// one screen whose whole job is to be the app's memory of what happened while
/// it was closed. The count is still worth printing: it is the server's own
/// number, and the thing the reader *cannot* do anything about is exactly the
/// thing they deserve to be told plainly.
///
/// «أقدم» is accurate because the order is measured too: rows come back
/// **newest first** (id descending, verified against `created_at`), so what the
/// cap holds back is the oldest slice of the set.
String notificationShortfallLineAr(NotificationShortfall s) {
  if (s.serverUnread == null || s.drawn <= 0 || !s.stranded) return '';
  return '${notificationHiddenCountAr(s.hidden)} أقدم من المعروض. '
      'لا يمكن عرضها في هذه القائمة.';
}
