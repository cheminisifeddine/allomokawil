// The pip the user comes home to, and the sentence he was just shown.
//
// `notification_read_outcome.dart` answers «did the mark-read land» and
// `NotificationReadOutcome.unknown` is the honest answer when the phone
// cannot read the server at all. Everything downstream of that verdict is
// **the phone's guess**: the rows still standing on the optimistic flip, and
// the unread count the bell is about to paint.
//
// That guess used to reach the home header wearing the same red as a count
// the server had actually stated. So the user read, in the centre:
//
//     تعذّر التأكّد. تحقّق من قائمة الإشعارات عند عودة الاتصال.
//
// — the app admitting it does not know — and then came back to a bold red
// **3** on the header that claimed, without qualification, the very number it
// had just disclaimed. One gesture apart, two answers, and the confident one
// was the one the app had just withdrawn.
//
// The flag is deliberately **one-directional**: the centre can withdraw
// confidence, only a real read of `/api/unread` can restore it. A successful
// `GET /api/notifications` does not count, because that list is a page of
// rows — proving a row is read says nothing about the size of the whole
// unread set the pip draws. Restoring trust on evidence that does not support
// it would be the same bug wearing a different hat.
library;

import 'package:flutter/foundation.dart';

/// Whether the unread count the bell paints is the server's answer, or the
/// phone's last memory of one it has been told it cannot check.
class NotificationCountTrust extends ChangeNotifier {
  bool _confirmed = true;

  /// The last count `/api/unread` actually answered, or null if it never has.
  ///
  /// **Added 10 Oct 2026 so the notification centre's own `/api/unread` read
  /// can serve the header instead of the header asking again.** The centre
  /// now reads the server's count to decide whether to draw the shortfall
  /// band and whether «تعليم الكل كمقروء» is honest to offer — and the bell was
  /// already reading the same endpoint on every resume. Two reads of one
  /// question per visit is a duplicated round-trip on a 2-core box with no
  /// swap, and worse than slow: `unread_round_trip_test.dart` pins "the same
  /// question is not asked twice", and the honest way to satisfy it is to
  /// publish the answer rather than to ask it again.
  ///
  /// Null is meaningful and is not zero: the flag simply has no server number
  /// yet, so the bell asks for one. Any other holder of this object — a test,
  /// a design shot — gets the same behaviour as before this field existed.
  int? _confirmedCount;

  /// The server's last stated count, or null when none has been read.
  ///
  /// **A published count is never withdrawn by [withdraw]** — that call is
  /// about *confidence*, not about forgetting. The number stays on record so a
  /// header resuming right after a failed centre read still has the server's
  /// last word to show, which is strictly better than a guess; what [unconfirmed]
  /// tells the bell is that this number may be behind.
  int? get confirmedCount => _confirmedCount;

  /// Publishes a count that came back from `GET /api/unread`.
  ///
  /// Restores confidence only if the number actually moved, so a bell that is
  /// already listening is not woken for a value it already holds.
  void publish(int n) {
    final moved = _confirmedCount != n;
    _confirmedCount = n;
    if (!_confirmed) {
      _confirmed = true;
      notifyListeners();
    } else if (moved) {
      notifyListeners();
    }
  }

  /// True while the count is the phone's guess rather than a server answer.
  bool get unconfirmed => !_confirmed;

  /// The app cannot read the server, so the count stops being a fact.
  void withdraw() {
    if (_confirmed) {
      _confirmed = false;
      notifyListeners();
    }
  }

  /// A read of `/api/unread` came back, so the count is the server's again.
  ///
  /// Called by the bell, and by [publish] when a read answers. See the note at
  /// the top of the file on why a list read is not enough.
  ///
  /// **The centre no longer calls this directly** — it calls [publish], which
  /// carries the number it read so the header can use it instead of issuing
  /// the same request again.
  void restore() {
    if (!_confirmed) {
      _confirmed = true;
      notifyListeners();
    }
  }
}
