// The one rule that decides whether a read is old enough to mention.
//
// Written 29 Sep 2026, on the tick that lifted four copies of this rule into
// one file. The copies were not a style problem — they were a **latent split-
// brain**. Each of the four surfaces below decides for itself what "a minute
// and older" means, and the moment one of them is edited alone, the app has
// two honest answers to the same question on two screens the same user owns.
//
// This file is the contract for the lifted rule. It is deliberately written
// against [readAgeAr] directly rather than against whichever surface happened
// to call it, because the failure this guards is "the helper is right and a
// surface stopped using it" — which a test aimed at the surface would pass.
//
// The four surfaces are then checked *through* the helper, because that is the
// only claim worth making: not "the rule is in one place" (a grep proves
// that) but "one read, one age, everywhere it is printed".
import 'package:allomokawil/src/data/read_age_ar.dart';
import 'package:allomokawil/src/data/stale_directory_copy.dart';
import 'package:allomokawil/src/data/stale_market_copy.dart';
import 'package:allomokawil/src/data/stale_projects_copy.dart';
import 'package:allomokawil/src/data/stats_freshness_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fixed wall clock, so nothing here depends on when the suite runs.
  final base = DateTime(2026, 9, 29, 14, 30);

  group('readAgeAr — the three silences', () {
    test('a read that never happened has no age', () {
      // Not «الآن» and not «قبل 0 دقيقة». A surface that has never read has
      // nothing to apologise for, and printing a number there would invent a
      // measurement.
      expect(readAgeAr(null, now: base), '');
    });

    test('under a minute is silence, not «الآن»', () {
      // The threshold is 60s because it is the exact point at which
      // `relativeTimeAr` stops answering «الآن» and starts answering with a
      // count. «الآن» under an apology band would claim the reader is looking
      // at the live list — the band exists precisely because he is not.
      expect(readAgeAr(base.subtract(const Duration(seconds: 0)), now: base),
          '');
      expect(readAgeAr(base.subtract(const Duration(seconds: 30)), now: base),
          '');
      expect(readAgeAr(base.subtract(const Duration(seconds: 59)), now: base),
          '');
    });

    test('a stamp from the future is skew, not a negative age', () {
      // The app must not blame the reader's phone for a server timestamp that
      // is ahead of it. Silence, never «قبل -3 دقيقة».
      expect(readAgeAr(base.add(const Duration(minutes: 3)), now: base), '');
      expect(readAgeAr(base.add(const Duration(days: 400)), now: base), '');
    });

    test('exactly a minute crosses the threshold', () {
      // The boundary is the whole point of the rule, so it gets its own
      // assertion rather than being implied by the cases either side.
      expect(readAgeAr(base.subtract(const Duration(seconds: 60)), now: base),
          isNot(''));
    });
  });

  group('readAgeAr — past the threshold it is the shared grammar', () {
    test('minutes use the Arabic count agreement', () {
      // 1 -> «دقيقة», 2 -> «دقيقتين», 3-10 -> «دقائق», 11+ -> «دقيقة».
      // Taken from the app's own grammar rather than invented, which is the
      // entire point of routing through `relativeTimeAr`.
      expect(readAgeAr(base.subtract(const Duration(minutes: 1)), now: base),
          'قبل دقيقة');
      expect(readAgeAr(base.subtract(const Duration(minutes: 2)), now: base),
          'قبل دقيقتين');
      expect(readAgeAr(base.subtract(const Duration(minutes: 5)), now: base),
          'قبل 5 دقائق');
      expect(readAgeAr(base.subtract(const Duration(minutes: 12)), now: base),
          'قبل 12 دقيقة');
    });

    test('hours and days follow the calendar, not a 24h period count', () {
      expect(readAgeAr(base.subtract(const Duration(hours: 2)), now: base),
          'قبل ساعتين');
      expect(readAgeAr(base.subtract(const Duration(hours: 5)), now: base),
          'قبل 5 ساعات');
      // Yesterday, not "24 hours": the same 27-hour-old read must read «أمس»
      // here and in the notification list, or one user's timeline is dated two
      // ways.
      final yesterday = DateTime(2026, 9, 28, 11, 30);
      expect(readAgeAr(yesterday, now: base), 'أمس');
    });

    test('a year and older is a calendar date, not a latency figure', () {
      // «قبل 400 يوم» describes a year-old cache in the vocabulary of a
      // network blip.
      final old = DateTime(2025, 3, 14, 9, 0);
      expect(readAgeAr(old, now: base), isNot(contains('يوم')));
      expect(readAgeAr(old, now: base), isNotEmpty);
    });
  });

  group('readAgeAr — the default clock is the wall clock', () {
    test('omitting [now] still dates a read that is clearly old', () {
      // Proves `now` is an *injection point*, not a requirement: the shipping
      // screens call this with no argument at all.
      final longAgo = DateTime.now().subtract(const Duration(hours: 4));
      expect(readAgeAr(longAgo), isNotEmpty);
      expect(readAgeAr(null), '');
      expect(readAgeAr(DateTime.now().subtract(const Duration(seconds: 5))), '');
    });
  });

  group('every surface that dates a read is the same surface now', () {
    // The four functions the lift was for. They are called here by their old
    // names because four screens and their tests call them by those names;
    // what matters is that they answer identically, forever.
    final surfaces = <String, String Function(DateTime?, {DateTime? now})>{
      'header': statsFreshnessAr,
      'market': staleMarketAgeAr,
      'projects': staleProjectsAgeAr,
      'directory': staleDirectoryAgeAr,
    };

    test('one read, one age, on all four surfaces', () {
      // The sample points matter more than they look. A first pass used 30s
      // and 7min and 3h, and a deliberately drifted threshold (60 -> 300s)
      // still passed every one of them: 7 minutes is 420 seconds, which is
      // above both thresholds, so the divergence had nowhere to show. A
      // threshold bug lives *in the gap between two round numbers*, so the
      // samples now crowd it — 59/60/61 (the threshold itself) and a spread
      // through the first five minutes, where any drift has to land.
      for (final age in const [
        Duration(seconds: 30), // silence
        Duration(seconds: 59), // one short of the threshold
        Duration(seconds: 60), // on it
        Duration(seconds: 61), // one over
        Duration(minutes: 2),
        Duration(minutes: 3),
        Duration(minutes: 4), // inside a 300s threshold
        Duration(minutes: 5), // on a 300s threshold
        Duration(minutes: 7),
        Duration(hours: 3),
        Duration(days: 1),
      ]) {
        final read = base.subtract(age);
        final expected = readAgeAr(read, now: base);
        surfaces.forEach((name, fn) {
          expect(fn(read, now: base), expected,
              reason: '$name dated a ${age.inSeconds}s read differently');
        });
      }
    });

    test('a skewed read is silent on all four surfaces', () {
      // The arm most likely to be hardened in one place only, because a
      // future stamp is a rare bug and rare bugs get fixed once.
      final future = base.add(const Duration(minutes: 9));
      final expected = readAgeAr(future, now: base);
      expect(expected, '');
      surfaces.forEach((name, fn) {
        expect(fn(future, now: base), expected,
            reason: '$name aged a future read');
      });
    });

    test('a read that never happened is silent on all four surfaces', () {
      surfaces.forEach((name, fn) {
        expect(fn(null, now: base), '', reason: '$name dated a missing read');
      });
    });
  });

  group('the loud/muted threshold is deliberately NOT lifted', () {
    test('statsAreStale keeps its own hour', () {
      // `statsAreStale` answers a different question — should the header
      // *shout* — at a different number. Routing it through [readAgeAr] would
      // make a 61-second read loud and a 59-second read quiet-in-reverse, so
      // this asserts the two thresholds are genuinely independent. The second
      // assertion is the real one: at 59 minutes the read is dated out loud,
      // but not yet loud. The date and the volume are separate decisions.
      expect(statsAreStale(base.subtract(const Duration(minutes: 59)),
          now: base), isFalse);
      expect(statsAreStale(base.subtract(const Duration(minutes: 61)),
          now: base), isTrue);
      expect(
          readAgeAr(base.subtract(const Duration(minutes: 59)), now: base),
          isNot(''),
          reason: 'a read below the loud threshold is still dated');
    });
  });
}
