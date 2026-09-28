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

import 'package:flutter/widgets.dart';

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

/// Re-reads a list when the phone comes back to the foreground, and only then.
///
/// **The badge is drawn from whatever the shell read last, and before this
/// nothing re-read it.** Every write that can change the count needs a gesture
/// the user has to make deliberately: pulling to refresh, opening a thread and
/// coming back, or pushing a screen and popping it. A message that arrived
/// while he was reading a quote in another app triggered **none** of them, so
/// the number he trusted was whatever the server said whenever he last
/// happened to navigate — drawn with no hint that it was old.
///
/// A badge that cannot go up is the worst failure available to it. It does not
/// look broken; it looks like a quiet day, which is the one reading the user
/// will act on when a client is waiting.
///
/// The app has **no push channel at all** (`pubspec.yaml` carries no firebase,
/// no socket, no workmanager), so polling would be the only way to see a
/// message land while he keeps the app open — and a poll is a request the
/// user's data pays for, every interval, to redraw a number that rarely
/// moves. Resume is the honest channel: it is free, it is the moment the
/// number is actually looked at, and it is the same trigger
/// [NotificationsBell] already uses for its own count, so the two numbers on
/// this home screen now go stale and fresh together.
///
/// `inactive` and `paused` are deliberately ignored. They fire for a dialog, a
/// permission sheet, the app switcher and the lock screen — the app is not
/// usable in any of them, and asking the network there spends data to draw
/// the number the user is about to see anyway.
mixin UnreadCountOnResume {
  /// Registers [observer] — the state — against the engine.
  ///
  /// The observer is passed in rather than taken as `this` because **inside a
  /// mixin `this` is the mixin, not the state**: `addObserver(this)` would
  /// register an object the engine can call the callback on but that has no
  /// `State` behind it, and the disposal half could not be paired with the
  /// registration half. The shell passes `this` from its own `initState` and
  /// the same `this` from `dispose`, so the two provably name one object.
  ///
  /// Both ends are the shell's job on purpose: a mixin that hid its own
  /// registration could not be seen to be undone, and an observer left
  /// attached outlives the state and keeps re-reading — and calling `setState`
  /// on — a widget the framework has already thrown away.
  void registerUnreadOnResume(WidgetsBindingObserver observer) {
    WidgetsBinding.instance.addObserver(observer);
  }

  /// The other half of [registerUnreadOnResume].
  void unregisterUnreadOnResume(WidgetsBindingObserver observer) {
    WidgetsBinding.instance.removeObserver(observer);
  }

  /// Issues the read. Implemented by the shell, which owns the repository.
  void readUnreadOnResume();

  /// The framework's lifecycle callback, mixed in by the state's own
  /// `with WidgetsBindingObserver` — a mixin cannot declare a superclass, so
  /// the observer is applied where the state already lives rather than hidden
  /// here.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The repository is assigned in `didChangeDependencies`, which the engine
    // can reach before it delivers the first lifecycle message. Reading a
    // `late final` here throws inside a framework callback, where it is
    // swallowed into a red-screen report about a bug the user never caused.
    readUnreadOnResume();
  }
}
