import 'package:flutter/material.dart';

import '../core/l10n/arabic_agreement.dart';

/// Screen-reader plumbing, in one place.
///
/// The house already knew the shape — the bottom bar, the notification bell and
/// the auth role switch carry a `Semantics(button: true, label: …)` — but the
/// rest of the screens re-invented it or forgot, and the audit on 13 Sep found
/// nine controls a screen reader could not describe: five stars on the rating
/// form with no name at all, a photo-removal disc, a chat image bubble, a
/// rating row that read as five junk icons plus a bare number, four pickers
/// that never announced which option was on, an add-photo tile that went silent
/// while it uploaded, and not one described image in the whole app.
///
/// Two helpers, because there are exactly two cases:
///
///  * [tap] — an icon with no text of its own, so the name has to be written
///    here. The label is required: an icon-only control without one is a bug,
///    not a style choice.
///  * [button] — the control already prints its name (a filter pill, a plan, a
///    tile), so we only add the role and the state. On purpose there is no
///    label argument: handing the visible text over again makes TalkBack read
///    the control twice, which is worse than reading it not at all.
///
/// Both wrap in [MergeSemantics] so the name, the role and the tap action land
/// on the same node. Split over two nodes, TalkBack focuses a name it cannot
/// activate and then a nameless control it can — the worst of both.
///
/// Nothing in here changes a pixel: every helper is a semantics wrapper, so
/// layout, goldens and the tap-target audit are untouched.
class A11y {
  const A11y._();

  /// An icon-only control: it needs a name, and it is a button.
  static Widget tap({
    required String label,
    required Widget child,
    bool? selected,
    bool enabled = true,
  }) {
    return MergeSemantics(
      child: Semantics(
        label: label,
        button: true,
        enabled: enabled,
        selected: selected,
        child: child,
      ),
    );
  }

  /// A control that already prints its own name: add the role and the state.
  static Widget button({
    required Widget child,
    bool? selected,
    bool enabled = true,
  }) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        child: child,
      ),
    );
  }

  /// How many points the scale has. One constant for the star labels and the
  /// score line, so the two can never each hard-code a five and drift.
  static const int scale = 5;

  /// One star of the rating form, the way a person says it: «3 من 5».
  ///
  /// **Latin digits, deliberately.** This used to spell the scale in
  /// Arabic-Indic through a private digit table, on the theory that a spoken
  /// numeral should be spoken. The theory was wrong about what a screen reader
  /// reads: the score line right beside it already printed `4.5` in Latin, so a
  /// single pass said «التقييم 4.5 من ٥، 3 مراجعات» — the same "of five" two
  /// ways in one sentence, which is the thing this class exists to prevent.
  /// It is also the way the rest of the app writes numbers: [chatClock] prints
  /// `09:05` and the phone field reads `0550 12 34 56` back, both Latin,
  /// because an RTL run lays Arabic-Indic digits out in an order the user did
  /// not type them in. The table is deleted, not moved: [of] is printed as the
  /// number it is, so a star label and a score cannot disagree again.
  static String star(int n, {int of = scale}) => '$n من $of';

  /// The rating row as one sentence instead of five icons and a bare number.
  ///
  /// Same Latin digits as [star], and the same [scale] — the label a screen
  /// reader reads is now character-for-character what the row already printed
  /// on glass.
  static String rating(double value, {int? count}) {
    final score = 'التقييم ${value.toStringAsFixed(1)} من $scale';
    return count == null ? score : '$score، ${reviews(count)}';
  }

  /// Arabic counts its nouns — 0 / 1 / 2 / 3-10 / 11+ — and «3 مراجعة» is a
  /// machine talking, not a person.
  ///
  /// The thresholds belong to [arabicCounted], the same rule the notification
  /// clock, the chat outbox, the subscription countdown and a contractor's own
  /// stats share. This was the fourth hand-written copy of it, which is how
  /// «3 مراجعة» would have gone on sitting next to three files that had it
  /// right. Zero and one branch *before* the rule, and both branches are the
  /// rule's own two cases, not new ones: «لا مراجعات» is a sentence with no
  /// count in it, and «مراجعة واحدة» says *one* in the word, where
  /// [arabicCounted] leaves the bare singular «مراجعة».
  static String reviews(int count) {
    if (count <= 0) return 'لا مراجعات';
    if (count == 1) return 'مراجعة واحدة';
    return arabicCounted(count, 'مراجعة', two: 'مراجعتان', few: 'مراجعات');
  }
}
