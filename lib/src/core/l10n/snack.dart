// One rule for the app's two-sentence writes, in one place.
//
// `ScaffoldMessenger` **queues**. A second `showSnackBar` while one is visible
// does not replace it — it waits for the first to time out, four seconds by
// default. So on the recheck path the first line is «نتحقّق الآن من القائمة…»,
// a progress note with its own duration, and the second is the *only* sentence
// that answers «did my write land?».
//
// Four ticks in a row fixed this on one screen at a time — project, bid sheet,
// notification centre, verification, review, portfolio, profile, subscription,
// project-new. Each tick added its own private `_showCommitResult` / `_verdict`
// / `_say` with a comment explaining why the hide is load-bearing. Every copy
// is correct and every copy is private, which is the failure: a private helper
// cannot be audited, and nine private helpers have no answer to «which one does
// a new screen use?». This is the same shape as the wilaya-sheet item (the
// guard existed, nobody looked for the second copy) and as `Monogram` (three
// lines, two files, both wrong) — a rule small enough to hold in your head is
// not evidence you are holding it.
//
// **The rule, stated once:** a line that is about to be *replaced* must be
// removed first, so the answer to «did it land?» is the only thing on screen.
//
// Three entries, because there are exactly three cases and the difference
// between them is the whole content of this file:
//
//   * [note] — nothing is being replaced. A form is still being filled in, a
//     photo was added, a bid was accepted outright. Hiding here would blank a
//     message nobody is covering.
//   * [verdict] — this line replaces one raised a moment ago. The queue is
//     removed first and only the answer is left.
//   * [action] — [note] plus a tappable action, for the one case that needs
//     the user to do something («افتح الإعدادات» to switch location on).
//
// A new screen calls [note] by default and reaches for [verdict] only when it
// genuinely drew a line it is about to contradict — the exemption is now one
// named function instead of nine private methods.
library;

import 'package:flutter/material.dart';

import 'strings.dart';

/// A line that covers nothing and must cover nothing.
///
/// Everything that answers a form the user is still filling in, and every
/// message about something that already succeeded. Use this first: reaching
/// for [verdict] on a line with nothing above it blanks a message nobody was
/// covering.
void showNote(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// The answer to «did my write land?», drawn **in place of** the recheck line.
///
/// The queue is removed first, which is the entire content of this function.
/// [message] is the classified verdict — never the recheck note, because
/// drawing the note through this entry would cover it with itself.
void showVerdict(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// [note] with one action, for the one case that needs the user to move.
///
/// The action must be [onAction] rather than a re-send: the only caller is
/// the location failure, where the fix is a settings trip and not a retry, so
/// a retry-shaped action here would be a button that does the wrong thing.
void showNoteWithAction(
  BuildContext context,
  String message, {
  required String actionLabel,
  required VoidCallback onAction,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(label: actionLabel, onPressed: onAction),
    ));
}

/// The recheck line, from one place.
///
/// «نتحقّق من الإشعارات…» and «نتحقّق الآن من القائمة…» are two different
/// sentences about two different checks, and the difference is not cosmetic:
/// the notification one names the screen's own job, while the shared one
/// promises a list the screen must be able to reach. Exported so a screen that
/// raises a recheck line and later draws a verdict cannot answer with two
/// spellings of the same note.
String recheckNote({required bool notifications}) {
  return notifications
      ? S.notifReadUnconfirmedRecheck
      : S.writeUnconfirmedRecheck;
}
