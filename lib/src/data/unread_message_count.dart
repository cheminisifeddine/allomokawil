// The unread count a user sees on the tab he is not standing on.
//
// A contractor's whole reason to open **«الرسائل»** is unread messages, and
// before this the app had no way to tell him he had any. The count lived on
// the header bell, and `WorkerHomeScreen` builds
// `appBar: _tab == 0 ? AppBar(... NotificationsBell() ...) : null` — so
// switching to the messages tab **unmounted the bell and took the number with
// it**. The user stood in the inbox and the only evidence anything was waiting
// was nothing.
//
// **The number must come from the conversations, not from `/api/unread`,** and
// that is the whole reason this is a separate function rather than a second
// call to the bell's endpoint:
//
//   `/api/unread`      -> the **notifications** row count, cleared by
//                         `/api/notifications/read` — quotes, project
//                         updates, reviews, and `new_message` rows.
//   `/api/mobile/conversations` -> per-thread `unread_count`, cleared by
//                         reading the thread.
//
// Those are different tables with different clear-actions. Painting the
// notification count on a tab called «الرسائل», directly above the inbox list
// that draws its own per-row counts, would put **two different numbers for the
// same thing** on one screen — the tab claiming four unread while the list
// beneath it shows none. The tab badge is therefore the sum of the list the
// user is about to read, so the two agree by construction.
///
/// The sum is over `[Conversation.unreadCount]` and not over a request of its
/// own, because both home shells already hold the conversations list: the
/// client's for the first-run guide, the inbox for the rows themselves. Asking
// again would be a third copy of the same read on every app-open.
library;

import '../core/l10n/arabic_agreement.dart';
import '../models/chat.dart';

/// Total unread messages across every conversation the phone knows about.
///
/// Clamped per row at zero so a server that sends a negative count for a
/// thread cannot drag the whole badge below zero and make it disappear — a
/// badge that vanishes because of one bad row is worse than a wrong one.
int unreadMessageTotal(List<Conversation>? conversations) {
  if (conversations == null) return 0;
  var total = 0;
  for (final c in conversations) {
    final n = c.unreadCount;
    if (n > 0) total += n;
  }
  return total;
}

/// Spoken by a screen reader on a tab that has unread messages.
///
/// Arabic, because a sighted user reads the three digits under the icon and a
/// screen-reader user has no digits to read: announcing «غير مقروءة» alone would
/// leave them knowing the *state* but not the *amount*, and this is the one
/// number that tells them whether to open the tab now or later.
///
/// Capped at 99 the same way the pip is, so the sentence and the badge are
/// never two different claims — a pip that says 99+ beside a voice saying
/// «143 رسالة غير مقروءة» is the same class of bug the header pip was written
/// to fix.
String unreadMessagesLabel(int count) {
  if (count <= 0) return '';
  final n = count > 99 ? 99 : count;
  return n == 1
      ? 'رسالة غير مقروءة'
      : '${arabicCounted(n, 'رسالة غير مقروءة', two: 'رسالتان غير مقروءتان', few: 'رسائل غير مقروءة')}';
}
