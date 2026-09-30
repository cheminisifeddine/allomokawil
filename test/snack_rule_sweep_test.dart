// Keeps the one rule from being re-invented, and keeps it from being *missed*.
//
// The drift this file exists to end: four ticks in a row added a private
// `_showCommitResult` / `_verdict` / `_say` to one screen each, every copy
// correct, every copy with a comment explaining why the `hideCurrentSnackBar`
// is load-bearing. Nine private helpers, one of them (`chat_screen`'s `_toast`)
// never got the rule at all. Nothing was *wrong* in any single file, which is
// exactly why nothing caught it — a private helper is not reachable by a test
// and not visible to a sweep, and the class the ticks kept shipping (a silently
// shortened claim, a blank avatar, a dropped trade) always looked like one
// screen's bug.
//
// `core/l10n/snack.dart` now owns the rule, and this file is the mechanism that
// keeps the next screen from hand-rolling it again. It is deliberately a
// **source** sweep and not a widget test, for the reason
// `no_empty_text_site_test.dart` gives: a widget test only sees the screens it
// was written to pump, and a screen nobody thought of has no test.
//
// Two halves, and either alone is satisfiable by a codebase where the other is
// broken — the same structure as that file's:
//   1. No `ScaffoldMessenger` outside `snack.dart`. The rule is unreachable
//      except through the helper, so a tenth copy cannot be born quietly.
//   2. `showNote` and `showVerdict` really differ. A helper that grows two
//      names for one behaviour is how the *next* drift starts, and that is not
//      checkable by reading the sources.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/core/l10n/snack.dart';

/// The one file allowed to touch the messenger. Named explicitly rather than
/// matched by pattern, so a *new* file cannot inherit the exemption by being
/// called something similar.
const _owner = 'lib/src/core/l10n/snack.dart';

List<File> _sources() => Directory('lib/src')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Strips `//` and `///` comments, so a file that only *talks* about the rule in
/// a doc comment is not reported as using it. The house documents this rule at
/// length in six files, and a sweep that counted prose would either report six
/// false positives or force the prose out of the code.
String _code(String source) =>
    source.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  group('one rule, one home', () {
    test('no screen reaches the messenger outside the helper', () {
      final offenders = <String>[];
      for (final f in _sources()) {
        if (f.path == _owner) continue;
        if (_code(f.readAsStringSync()).contains('ScaffoldMessenger')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'the hide-then-show rule is load-bearing on every write that '
              'draws a recheck line, and it is now written once. A screen that '
              'reaches the messenger directly is either re-inventing the rule '
              'or missing it — both are the same defect. Use showNote() for a '
              'line that covers nothing, showVerdict() for one that replaces '
              'another, showNoteWithAction() for the one that needs a button.');
    });

    test('the helper is reachable from every screen that needs it', () {
      // The mirror of the rule above, and the half that would catch a helper
      // that was written and then never adopted: if the sweep passes because
      // nobody writes toasts at all, that is not a clean codebase, it is a
      // silent product. Nine screens wrote lines before this tick and must
      // still write them.
      final callers = <String>{};
      for (final f in _sources()) {
        if (f.path == _owner) continue;
        final code = _code(f.readAsStringSync());
        if (code.contains('showNote(') || code.contains('showVerdict(')) {
          callers.add(f.path);
        }
      }
      expect(callers.length, greaterThanOrEqualTo(8),
          reason: 'only ${callers.length} screens draw a line through the '
              'shared helper. Before the migration nine screens wrote '
              'snack bars; a drop here means the helper is not being used, not '
              'that the messages went away.');
    });
  });

  group('the two entries are not the same function twice', () {
    testWidgets('a verdict removes the line it is replacing', (tester) async {
      final keys = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return Column(children: [
              ElevatedButton(
                onPressed: () => showNote(context, 'نتحقّق من القائمة…'),
                child: const Text('note'),
              ),
              ElevatedButton(
                onPressed: () => showVerdict(context, 'وجدناه في القائمة'),
                child: const Text('verdict'),
              ),
            ]);
          }),
        ),
      ));

      await tester.tap(find.text('note'));
      await tester.pump();
      expect(find.text('نتحقّق من القائمة…'), findsOneWidget,
          reason: 'the note is on screen, which is what a second call has to '
              'be able to replace');
      keys.add('note-drawn');

      // The verdict while the note is still visible. This is the whole claim:
      // with `showNote` the second line would be **queued** and the note would
      // still be on screen a pump later.
      await tester.tap(find.text('verdict'));
      await tester.pump();
      expect(find.text('وجدناه في القائمة'), findsOneWidget);
      expect(find.text('نتحقّق من القائمة…'), findsNothing,
          reason: 'the note is 4 seconds of the user reading that the app is '
              'still checking, after the app already knows — the note must be '
              'gone, not sitting in a queue behind the answer');
    });

    testWidgets('a note covers nothing, so a second note queues and both show',
        (tester) async {
      // The other direction, and the reason [showNote] is not just
      // [showVerdict] with a different name: these two lines are about
      // different things («the photo was added», «the field is required») and
      // neither is replacing the other. Hiding here would blank a message
      // nobody was covering.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return Column(children: [
              ElevatedButton(
                onPressed: () => showNote(context, 'أُضيفت الصورة'),
                child: const Text('first'),
              ),
              ElevatedButton(
                onPressed: () => showNote(context, 'اختر الولاية أولاً'),
                child: const Text('second'),
              ),
            ]);
          }),
        ),
      ));
      await tester.tap(find.text('first'));
      await tester.pump();
      await tester.tap(find.text('second'));
      await tester.pump();
      expect(find.text('أُضيفت الصورة'), findsOneWidget);
      expect(find.text('اختر الولاية أولاً'), findsNothing,
          reason: 'a second note queues: the first is still on screen. That is '
              'correct here — neither line covers the other');
    });

    test('the recheck note is one function, so the two spellings cannot drift',
        () {
      // Two sentences for the same idea, chosen by a named argument. Before
      // this the eleven call sites wrote `S.writeUnconfirmedRecheck` or
      // `S.notifReadUnconfirmedRecheck` directly, and a screen that raised one
      // and answered with the other would have said «we are checking the
      // notifications» on the subscription screen.
      expect(recheckNote(notifications: false), contains('القائمة'));
      expect(recheckNote(notifications: true), contains('الإشعارات'));
      expect(recheckNote(notifications: true),
          isNot(recheckNote(notifications: false)));
    });
  });
}
