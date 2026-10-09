// The one-hour window, 60 through 119 minutes, used to be one value.
//
// Written 29 Sep 2026. `relativeTimeAr` selected its hour arm on
// `diff.inHours < 24` and **floored**, so 60 and 90 and 119 minutes all
// printed «قبل ساعة» and the minutes were discarded outright. Probed on the
// function before the fix: 1 -> «قبل دقيقة», 59 -> «قبل 59 دقيقة»,
// 60 -> «قبل ساعة», 90 -> «قبل ساعة», 119 -> «قبل ساعة», 120 -> «قبل ساعتين».
//
// On a notification list that is cosmetic. On the stale-band copy the founder
// reads when deciding whether a price is safe to quote, a figure read an hour
// ago and a figure read an hour and a half ago were the same sentence. The
// band files pinned the defect by assertion for three cycles before it was
// fixed, each noting that a change to this function needs its own full-suite
// cycle — this is that cycle.
//
// The function is shared by the chat list, the notification centre and every
// member of the stale-band family, so these tests aim at the boundaries rather
// than at a screen: what matters is that one read has one age everywhere it is
// printed.
import 'package:allomokawil/src/data/notification_copy.dart';
import 'package:allomokawil/src/data/read_age_ar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed wall clock, so nothing here depends on when the suite runs.
  final base = DateTime.utc(2026, 9, 29, 15, 0);
  DateTime ago(int minutes) => base.subtract(Duration(minutes: minutes));

  group('the one-hour window carries its minutes', () {
    test('60 and 90 and 119 minutes are three different reads', () {
      // The regression itself. Before the fix these three were one string.
      expect(relativeTimeAr(ago(60), now: base), 'قبل ساعة');
      expect(relativeTimeAr(ago(90), now: base), 'قبل ساعة و 30 دقيقة');
      expect(relativeTimeAr(ago(119), now: base), 'قبل ساعة و 59 دقيقة');

      // The reason the fix was worth making, stated as an assertion so it
      // cannot be undone by "simplifying" the arm back to `inHours`.
      final distinct = {ago(60), ago(90), ago(119)}
          .map((at) => relativeTimeAr(at, now: base))
          .toSet();
      expect(distinct, hasLength(3),
          reason: 'three distinct ages collapsed to one: $distinct');
    });

    test('the preposition is written once, not once per half', () {
      // The first version of this line built both halves with the private
      // `_ago`, which is «قبل ‹noun›» on its own, and printed
      // «قبل ساعة و قبل دقيقة» on screen. The analyzer cannot see that and
      // no test covered it; it was caught by probing the function at 61
      // minutes and looking at the string. This pins the correct Arabic so
      // the mistake cannot come back through a refactor.
      final s = relativeTimeAr(ago(61), now: base);
      expect(s, 'قبل ساعة و دقيقة');
      expect(RegExp(r'و\s*قبل').hasMatch(s), isFalse,
          reason: 'the conjunction does not take its own preposition: "$s"');
      expect('قبل '.allMatches(s).length, 1,
          reason: 'one preposition for the whole phrase: "$s"');
    });

    test('the singular hour survives, and only the first minute has it', () {
      // **The fix that looks obvious is wrong.** Widening the *minute* band to
      // 119 would make «قبل ساعة» unreachable — 119 minutes would read
      // «قبل 119 دقيقة» and 120 already reads «قبل ساعتين» — turning the
      // singular into dead code in a function whose job is count agreement.
      // So the hour arm is kept for exactly one duration: the first minute of
      // the hour, 60, where the remainder is zero and «قبل ساعة» is the whole
      // truth. «قبل ساعة و 0 دقيقة» would be a sentence about a number nobody
      // can picture.
      expect(base.difference(ago(60)).inMinutes, 60);
      expect(relativeTimeAr(ago(60), now: base), isNot(contains('و')));
      for (final m in [61, 75, 90, 119]) {
        expect(relativeTimeAr(ago(m), now: base), contains('و '),
            reason: '$m minutes is past the first minute of the hour and must '
                'carry its remainder: "${relativeTimeAr(ago(m), now: base)}"');
      }
    });
  });

  group('two hours and up stay bare, on purpose', () {
    test('the compound never attaches past the first hour', () {
      // `stale_catalogue_test` pins «قبل ساعتين» for 2h05m with
      // `isNot(contains('و '))`: a figure dated two ways inside one app is the
      // exact defect `readAgeAr` exists to stop, so the app has no compound
      // relative time below the one-hour window. Past the first hour the bare
      // count is enough — nobody re-reads the 5 on «قبل ساعتين».
      expect(relativeTimeAr(ago(120), now: base), 'قبل ساعتين');
      expect(relativeTimeAr(ago(125), now: base), 'قبل ساعتين');
      expect(relativeTimeAr(ago(185), now: base), 'قبل 3 ساعات');
      for (final m in [120, 125, 150, 180, 185, 1439]) {
        expect(relativeTimeAr(ago(m), now: base), isNot(contains('و ')),
            reason: '$m minutes must stay bare: '
                '"${relativeTimeAr(ago(m), now: base)}"');
      }
    });

    test('the boundary either side of the window is still hour-accurate', () {
      // 59 is a minute count and 2 takes the dual: the two arms meet without a
      // gap and without an overlap, so every minute in the day has an answer
      // and no minute has two. The sentence names 2 and not 120 because 120 is
      // not the number the form is decided on -- 120 % 100 = 20, so 120 itself
      // takes the singular, and only the hour floor converts it to 2 first.
      expect(relativeTimeAr(ago(59), now: base), 'قبل 59 دقيقة');
      expect(relativeTimeAr(ago(119), now: base), 'قبل ساعة و 59 دقيقة');
      expect(relativeTimeAr(ago(120), now: base), 'قبل ساعتين');
    });
  });

  group('the rule reaches every surface that dates a read', () {
    test('readAgeAr is the same answer, and is never the lossy one', () {
      // The band family routes its age through [readAgeAr] rather than
      // re-deriving it, so a fix here reaches all of them — this is the claim
      // worth making, and it is the claim a test aimed at one screen cannot
      // make.
      expect(readAgeAr(ago(90), now: base), relativeTimeAr(ago(90), now: base));
      expect(readAgeAr(ago(90), now: base), 'قبل ساعة و 30 دقيقة');
      expect(readAgeAr(ago(30), now: base), 'قبل 30 دقيقة',
          reason: 'below the window the minute arm is untouched');
      expect(readAgeAr(ago(120), now: base), 'قبل ساعتين');
    });

    test('the silences above the window are unchanged', () {
      // This fix touched one arm. The other two reasons for saying nothing are
      // asserted here so a later edit cannot quietly widen or narrow them:
      // a read that never happened, one under a minute old, and one stamped
      // ahead of the phone (clock skew — the server's fault, not the
      // reader's).
      expect(readAgeAr(null, now: base), '');
      expect(readAgeAr(ago(0), now: base), '');
      expect(readAgeAr(base.add(const Duration(minutes: 3)), now: base), '');
      // `relativeTimeAr` itself folds skew into «الآن» rather than silence —
      // that difference is deliberate and documented in `read_age_ar.dart`.
      expect(relativeTimeAr(base.add(const Duration(minutes: 3)), now: base),
          'الآن');
    });
  });
}
