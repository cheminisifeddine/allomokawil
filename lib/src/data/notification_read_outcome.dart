// Answering «did my tap on the notification actually mark it read» when the
// server never said.
//
// The backlog closed `markNotificationsRead` with the note that it "re-reads
// unconditionally, so it cannot claim a false landing". That is true of the
// **reload**, and the reload is not the whole method. Read
// `_NotificationsScreenState._markRead` as it stood:
//
//     setState(() { _items = [... ids → asRead() ...] });   // (1) the flip
//     try { await _repo.markNotificationsRead(ids: ids); }
//     catch (_) { /* the reload below puts the row back */ }  // (2) the shrug
//     await _load();                                          // (3) the reload
//
// The comment at (2) is a promise the code does not keep, and it fails on the
// one path that matters most:
//
//   * (3) succeeds → the screen shows the server's truth. Correct.
//   * (3) **fails** → `_load` sets `_error`, and `_body()` only reads `_error`
//     when `_items.isEmpty`. With rows on screen the error is **unreachable
//     state**: the optimistic flip from (1) stands, nothing is rendered, and
//     the user is left believing a notification was cleared that the database
//     still holds as unread.
//   * (2) swallowed `errWriteUnconfirmed` — the network layer's explicit
//     "this request left the phone and nobody answered" — with the same
//     `catch (_)` that would swallow a 403. The app already knows the two are
//     different, on seven other screens, and here it throws that knowledge away.
//
// So the last write in the app whose outcome is ambiguous is also the last one
// that answers it with silence. The unread pip is the one line on the home
// screen that claims something arrived; a row that is struck off the list
// because the phone guessed is exactly the guess this app is built not to make.
//
// **This is the opposite of `openConversation`, and that is the point of
// writing it down.** The thread that would not open is a *get-or-create* POST,
// where re-sending may make a second row, so `threadOpenOutcomeCopy` refuses
// every retry. `POST /api/notifications/read` is **idempotent by construction**:
// marking ids already marked read changes nothing, and the no-ids form clears
// what is already clear. There is no duplicate to risk here, so a verdict that
// says the write did not land may tell the user to press again — which is the
// sentence the thread screen is forbidden to print. Same family, opposite
// instruction, and `test/notification_read_outcome_test.dart` pins both halves
// so the two cannot drift into each other.
library;

import '../core/l10n/strings.dart';
import '../models/notification.dart';

/// What re-reading the centre proved about a mark-read whose answer never came.
enum NotificationReadOutcome {
  /// The fresh list shows every id read. The write reached the server.
  landed,

  /// The fresh list still holds one of them unread. The server answered and the
  /// write did not land, so asking again is safe and correct.
  missing,

  /// The re-read could not run, or it came back without one of the ids at all.
  ///
  /// Both are the same thing to the user: the phone cannot prove what the
  /// server now holds. An id that vanished from the list is **not** proof the
  /// write landed — it may have been deleted — so it is not folded into
  /// [landed]. Reporting a success on a row that is not there is the same lie
  /// as reporting one on a row that is still unread, and it is the more
  /// expensive of the two, because the user stops looking.
  unknown,
}

/// True when [fresh] proves every id in [ids] is now read.
///
/// An empty [ids] means the «تعليم الكل كمقروء» form, where the write clears
/// everything: then the proof is that **no** row is unread.
///
/// An id that is absent from [fresh] is not counted as read, on purpose —
/// absence is not confirmation, and the caller turns a false [true] into «the
/// notification was marked read» for a row that may not exist.
bool notificationsProvenRead({
  required List<AppNotification> fresh,
  List<int> ids = const [],
}) {
  if (ids.isEmpty) {
    return !fresh.any((n) => n.isRead == 0);
  }
  final wanted = ids.toSet();
  final seen = <int>{
    for (final n in fresh)
      if (wanted.contains(n.id)) n.id,
  };
  // Every id we asked about must be *present* before any of them counts. The
  // direction of this test is the whole thing: `wanted.containsAll(seen)` asks
  // the reverse question and is true whenever the fresh list mentions only ids
  // we happened to ask for — so a list holding one of the two ids we asked
  // about, and no trace of the other, was reported as proof of both. Absence is
  // not confirmation.
  if (!seen.containsAll(wanted)) return false;
  return !fresh.any((n) => wanted.contains(n.id) && n.isRead == 0);
}

/// Runs the honest re-read for a mark-read that was not confirmed.
///
/// [recheck] is a bare `GET` of the centre, so it is safe to run twice and
/// cannot change anything. It must not throw: a second network failure while
/// one is already being reported is [NotificationReadOutcome.unknown], never
/// [missing], because «the write did not land» is a claim and the app is in no
/// position to make it.
Future<NotificationReadOutcome> resolveNotificationReadOutcome({
  required Future<List<AppNotification>> Function() recheck,
  required List<int> ids,
}) async {
  List<AppNotification> fresh;
  try {
    fresh = await recheck();
  } catch (_) {
    return NotificationReadOutcome.unknown;
  }
  if (notificationsProvenRead(fresh: fresh, ids: ids)) {
    return NotificationReadOutcome.landed;
  }
  // The read worked. A row we asked about is either still unread or gone; only
  // the first of those is proof the write failed, so a missing id sends the
  // verdict back to «unknown» rather than being reported as a clean miss.
  final wanted = ids.toSet();
  final present = fresh.where((n) => wanted.contains(n.id)).map((n) => n.id);
  return present.length == wanted.length
      ? NotificationReadOutcome.missing
      : NotificationReadOutcome.unknown;
}

/// The sentence for a mark-read the app re-read the centre to find out about.
///
/// Its own copy, and not [writeOutcomeCopy], for the same reason
/// [threadOpenOutcomeCopy] has its own: the shared line is a claim about
/// finding a **row**, and the user's question is not «is there a row» but «is
/// my notification still counted as new».
///
/// **[NotificationReadOutcome.missing] and [NotificationReadOutcome.unknown]
/// point at different places, and the difference is the whole design.**
/// `missing` means the server answered and refused, and this write is
/// idempotent, so the honest instruction is to press again. `unknown` means the
/// phone cannot read the server, and re-sending a write whose outcome is
/// unknown is precisely the habit this app spent a cycle removing from the
/// thread screen — so that one sends the user to the list, which is a GET.
String notificationReadOutcomeCopy(NotificationReadOutcome outcome) =>
    switch (outcome) {
      NotificationReadOutcome.landed => S.notifReadUnconfirmedLanded,
      NotificationReadOutcome.missing => S.notifReadUnconfirmedMissing,
      NotificationReadOutcome.unknown => S.notifReadUnconfirmedUnknown,
    };
