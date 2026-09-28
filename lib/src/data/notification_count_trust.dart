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
  /// Called by the bell and by nobody else — see the note at the top of the
  /// file on why a list read is not enough.
  void restore() {
    if (!_confirmed) {
      _confirmed = true;
      notifyListeners();
    }
  }
}
