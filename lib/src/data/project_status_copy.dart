// The Arabic name of one project lifecycle state, in one place.
//
// Found on 2 Oct 2026 by reading the two surfaces that print one. `status` is
// a four-value column and the name of each value exists in two places with no
// shared source: the private `const` pill table in `projects_screen.dart`
// (the «مشاريعي» filter tabs) and the private switch in `StatusPill.project`
// (`ui.dart`), which draws the pill on the project card and on the project
// page. Three of the four agreed by accident. The fourth did not — and the
// pill was not merely using a different word.
//
// **What was actually broken.** `StatusPill.project` switched on
//
//     case 'inprogress':   // the Dart enum name, lowercased
//
// while **both** of its callers pass `project.status.wire`, which is
// `'in_progress'`. Not one caller in the repo ever passes the string the
// switch keys on, so that arm was dead code: no project anywhere in this app
// has ever been drawn with «قيد التنفيذ». Every job a contractor is currently
// working — the one he accepted a bid on, the one he drives to every
// morning, the one whose tab on «مشاريعي» says «قيد التنفيذ» — drew «مفتوح»,
// in the accent tint of a project still taking offers.
//
// That is worse than a wording disagreement. «مفتوح» is not a synonym for
// «قيد التنفيذ», it is the claim that *other contractors may still bid on
// this job*. A contractor reading the feed sees a live-looking job he has
// already started and offers on it. The client's tab reads «قيد التنفيذ» and
// the card underneath it reads «مفتوح», on the same screen, for the same
// project — the two surfaces disagreeing exactly the way this file is
// written to prevent.
//
// **Why the whole lifecycle is re-keyed, not just this one arm.** The fix is
// not a one-character edit to a string. The factory took a bare `String`, so
// nothing checked the argument: a caller could pass `.name`, `.wire` or a
// typo and the answer was silently whatever `open` meant. That is the trap
// the sibling pair already documents — «a display helper made forgiving of a
// broken write hides the write, not the symptom» — and the reason this file
// takes a [ProjectStatus] and not a string. Every caller already holds the
// parsed enum, so this costs no lookup and cannot be reached with a value the
// server never sent.
//
// So `StatusPill.project` now takes the enum, and `ProjectStatus.fromWire`
// is the single parser. A string the parser does not know is read as [open]
// before it reaches the pill — by the one function whose entire job is to
// decide that — instead of by a `switch` in a widget that was only asked to
// draw a colour.
//
// **Why the words.** `completed` was «منجز» on the filter tab and «منتهي» on
// the pill. «منتهي» is this app's word for an **expired subscription plan**
// (`subscription_screen.dart` prints it for a lapsed plan, and so does
// `_planSummary` in `profile_screen.dart`), so reusing it for a *finished
// renovation* gives one word two meanings on screens the reader has already
// learned it from. The shared value is «منجز» — the word the tab and the
// worker's own stats line («3 مشاريع منجزة») already use for a completed job.
//
// [urgencyAr] is the exact sibling of this file: an enum in, one Arabic word
// out, under `data/` so the model keeps knowing only the wire.
library;

import '../models/project.dart' show ProjectStatus;

/// The Arabic name of [status], as the user reads it.
///
/// Total and non-null on purpose, for the reason `urgencyAr` documents: every
/// state the column can hold has a name an Algerian reads without
/// translating, and a state with no Arabic would be a value the app can store
/// and never say.
String projectStatusAr(ProjectStatus status) {
  switch (status) {
    case ProjectStatus.open:
      return 'مفتوح';
    case ProjectStatus.inProgress:
      return 'قيد التنفيذ';
    case ProjectStatus.completed:
      // «منجز», not «منتهي». The pill said «منتهي», which is the word this
      // app prints for an **expired plan**; a finished renovation read as a
      // lapsed subscription. The filter tab already said «منجز».
      return 'منجز';
    case ProjectStatus.cancelled:
      return 'ملغى';
  }
}
