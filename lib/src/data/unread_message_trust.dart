// The gold pip on the «الرسائل» tab, and the sentence it is not saying.
//
// `NotificationCountTrust` is a claim about a count **a pip is painting**:
// the header bell's `/api/unread`. This file is the same idea for a different
// table, and the separation is the entire point of it.
//
// The badge is `unreadMessageTotal(...)` over `/api/mobile/conversations` —
// per-thread `unread_count`, cleared by *reading a thread*. `/api/unread` is
// the notifications row count, cleared by `/api/notifications/read`. Two
// tables, two clear-actions. So:
//
//   * a failed **conversations** read does not move `NotificationCountTrust`,
//     which is about another table, and
//   * a notification withdrawal must not grey a number it knows nothing about.
//
// Reusing the existing flag would be the exact merge
// `unread_message_count.dart` exists to prevent, arriving from the other
// direction. The flag is deliberately **one-directional**: the phone can
// withdraw confidence, and only a **landed** read of
// `/api/mobile/conversations` can restore it. A successful read of any other
// list does not count — proving a row is read says nothing about the size of
// the whole unread set the badge sums.
library;

import 'package:flutter/foundation.dart';

/// Whether the unread count the messages tab paints is the server's answer,
/// or the phone's last memory of one it has been told it cannot check.
class UnreadMessageTrust extends ChangeNotifier {
  bool _confirmed = true;

  /// True while the count is the phone's guess rather than a server answer.
  bool get unconfirmed => !_confirmed;

  /// The app cannot read the server, so the count stops being a fact.
  ///
  /// One-directional, exactly as `NotificationCountTrust` is: nothing but a
  /// landed read calls [restore], so a transient failure cannot be undone by
  /// an unrelated success elsewhere in the app.
  void withdraw() {
    if (_confirmed) {
      _confirmed = false;
      notifyListeners();
    }
  }

  /// A read of `/api/mobile/conversations` came back, so the count is the
  /// server's again.
  ///
  /// Called by the two home shells and the inbox, and by nobody else — see
  /// the note at the top of the file on why any other landed read is not
  /// enough.
  void restore() {
    if (!_confirmed) {
      _confirmed = true;
      notifyListeners();
    }
  }
}
