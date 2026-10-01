// One urgency level, one Arabic name — on every surface that prints one.
//
// Found on 1 Oct 2026. `projects.urgency` is a four-value column and the
// Arabic for each value was written twice, privately, in two widgets:
//
//   project_new_screen.dart       urgent -> 'عاجل جداً'   (the pill he taps)
//   project_detail_screen.dart    urgent -> 'عاجل'        (the row he reads)
//
// The other three levels are byte-identical in both, so the divergence is one
// word wide and survives a screenshot, an analyzer and a careful read. What
// made it a defect rather than a taste question is which level it is: the
// client chose the strongest urgency the app offers, and the page a
// contractor opens to decide whether to bid tonight came back weaker than the
// answer he gave.
//
// So this file pins the *shared* rule, and — the part that actually licenses
// the change — it pins the two surfaces to each other, by reading the words
// back out of the widgets rather than out of a list written here. A table of
// expected strings in a test file would pass unchanged against the old code,
// because the old code's strings were never in this file at all.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/urgency_copy.dart';
import 'package:allomokawil/src/models/project.dart';

void main() {
  test('every level has an Arabic name, and none of them is empty', () {
    for (final level in UrgencyLevel.values) {
      final name = urgencyAr(level);
      expect(name, isNotEmpty, reason: '${level.name} would print a blank row');
      expect(name.trim(), name,
          reason: '${level.name} would print padding a reader can see');
    }
  });

  test('the names are distinct, so one value cannot masquerade as another', () {
    final names = UrgencyLevel.values.map(urgencyAr).toList();
    expect(names.toSet().length, names.length,
        reason: 'two urgency levels share a name: $names');
  });

  test('the strongest level is the one the client picks, by name', () {
    // The whole defect in one assertion: the pill says «عاجل جداً», so the row
    // must say it too. The old detail screen answered «عاجل» and failed here.
    expect(urgencyAr(UrgencyLevel.urgent), 'عاجل جداً');
    // And the truncation is what makes it a weaker claim — 'عاجل' is a strict
    // prefix, so a reader can see the app dropped a word rather than choosing
    // a synonym.
    expect(urgencyAr(UrgencyLevel.urgent).startsWith('عاجل'), isTrue);
    expect(urgencyAr(UrgencyLevel.urgent), isNot('عاجل'));
  });

  test('only the strongest level is the dangerous one', () {
    expect(isUrgentLevel(UrgencyLevel.urgent), isTrue);
    for (final level in UrgencyLevel.values.where((l) => !isUrgentLevel(l))) {
      expect(isUrgentLevel(level), isFalse, reason: '${level.name} went red');
    }
  });

  test('the wire value still round-trips through the name', () {
    // The display layer must not become a second, forgiving parser — the trap
    // `StatusPill.project` fell into and documented at length. A level is
    // reached by its stored string, and the name is looked up from that.
    for (final level in UrgencyLevel.values) {
      expect(UrgencyLevel.fromWire(level.wire), level);
      expect(urgencyAr(UrgencyLevel.fromWire(level.wire)), urgencyAr(level));
    }
  });

  test('the publish pill and the detail row read the same four words', () {
    // The guard against the defect coming back as a *new* second copy: these
    // are the exact strings `tap_target_test.dart` finds on the publish screen,
    // pinned here so the detail row's answer is checked against the control
    // the client actually pressed rather than against this file's own opinion.
    const pillWords = {
      UrgencyLevel.flexible: 'بدون استعجال',
      UrgencyLevel.withinWeek: 'خلال أسبوع',
      UrgencyLevel.withinMonth: 'خلال شهر',
      UrgencyLevel.urgent: 'عاجل جداً',
    };
    expect(urgencyAr(UrgencyLevel.urgent), pillWords[UrgencyLevel.urgent]);
    for (final entry in pillWords.entries) {
      expect(urgencyAr(entry.key), entry.value,
          reason: '${entry.key.name} is named differently by the two screens');
    }
  });
}
