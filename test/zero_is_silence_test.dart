// Zero is silence — and silence must never be dropped into a sentence.
//
// Found on 29 Sep 2026 by sweeping the family rather than the instance. Two
// cycles earlier the subscription card printed, for a brand-new free
// contractor — the default plan of every registration in the app:
//
//     «استعملت  من 3 عروض مجانية هذا الشهر»
//
// a double space where the count belongs. The cause is a contract these
// helpers share and it is easy to forget per-file: **a count of zero is an
// absence, not a number**, so `quotesAr(0)`, `photosAr(0)`, `communeCountAr(0)`
// and `wilayaSpanAr(0)` all return `''` rather than «صفر عروض». That is right on
// its own — «0 عروض» is a strained thing to say — but the moment one of these
// is interpolated into a sentence without a guard, the empty string is not a
// gap in the words, it is a **double space**, and Arabic typography reads that
// as a rendering fault rather than as «you have none».
//
// **Why this file rather than three more assertions in three files.** Each
// per-file test pins one string, so a zero-guard missing from a *different*
// helper in the same family goes green silently — which is what the instance
// tests did. This sweeps the family: every helper whose contract is «a count
// that is not there returns nothing», across a range wide enough to reach
// every Arabic agreement class (1, 2, 3-10, 11-99, 100+ and the negatives a bad
// parse produces), and asserts the *shape* of what comes back.
//
// The check is **structural, not golden**. A golden pins a string; a structural
// check pins a property. «Never two spaces, never a space before punctuation,
// never a leading or trailing space» holds for every count and every sentence
// these helpers are handed, so it survives a noun changing and — unlike the
// assertion written against the limit's noun — cannot pass while a hole sits
// beside it in the same string.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/commune_count_copy.dart';
import 'package:allomokawil/src/data/photo_count_copy.dart';
import 'package:allomokawil/src/data/plan_reach_copy.dart';
import 'package:allomokawil/src/data/portfolio_allowance.dart';
import 'package:allomokawil/src/data/project_photo_count_copy.dart';
import 'package:allomokawil/src/data/quote_count_copy.dart';
import 'package:allomokawil/src/data/quote_duration_copy.dart';

/// Every count a plan limit, a usage total or a list length can take, including
/// the two below zero a missing or malformed field produces, and the zero this
/// file is about.
///
/// Chosen to land in every agreement class at once: 1 (singular), 2 (dual),
/// 3 and 10 (few), 11/99/100/110/120 (many), and the negatives `_int()` returns
/// for an absent value. `0` is in the list too — the helpers are *supposed* to
/// return `''` for it. What is forbidden is a sentence with a hole, not an
/// empty helper.
const List<int> counts = <int>[
  -3, -1, 0, 1, 2, 3, 4, 5, 7, 10, 11, 12, 20, 30, 60, 99, 100, 101, 110, 120,
  1000,
];

/// The limits a plan can be configured with, live and not: free ships 3, the
/// paid tiers ship -1 for unlimited, the portfolio tiers ship 5/30/60/120, and
/// **0 is what `_int()` hands back for a field the server did not send** — so a
/// limit of 0 is a real parsed value, not a theoretical one.
const List<int> limits = <int>[-1, 0, 1, 2, 3, 5, 11, 20, 30, 60, 120];

/// The defect itself, checked structurally so it holds for every string.
void expectNoHole(String line, String what) {
  expect(line, isNot(contains('  ')), reason: '$what -> "[$line]" — two spaces');
  expect(line, isNot(contains(' .')), reason: '$what -> "[$line]"');
  expect(line, isNot(contains(' ،')), reason: '$what -> "[$line]"');
  expect(line, isNot(contains(' ؟')), reason: '$what -> "[$line]"');
  expect(line.trim(), line, reason: '$what -> "[$line]" — outer space');
  expect(line.isEmpty, isFalse, reason: '$what — a sentence that says nothing');
}

void main() {
  group('the family contract: a count of zero is an absence, not a number', () {
    test('every silent helper is silent on zero', () {
      for (final entry in <String, String Function(int)>{
        'quotesAr': quotesAr,
        'photosAr': photosAr,
        'communeCountAr': communeCountAr,
        'wilayaSpanAr': wilayaSpanAr,
        'durationDaysAr': durationDaysAr,
        'addedAdjectiveAr': addedAdjectiveAr,
      }.entries) {
        expect(entry.value(0), '', reason: '${entry.key}(0) must be silence');
        expect(entry.value(-1), '', reason: '${entry.key}(-1) must be silence');
      }
    });
  });

  group('quotes: no sentence has a hole, in either count', () {
    test('the capped usage line, free and paid, at every count and limit', () {
      for (final used in counts) {
        for (final limit in limits) {
          for (final isFree in [true, false]) {
            expectNoHole(cappedQuotesUsageAr(used, limit, isFree: isFree),
                'cappedQuotesUsageAr($used, $limit, isFree: $isFree)');
          }
        }
      }
    });

    test('the left line and the unlimited line, at every count', () {
      for (final n in counts) {
        for (final limit in limits) {
          expectNoHole(quotesLeftLineAr('محترف', n, limit),
              'quotesLeftLineAr(محترف, $n, $limit)');
        }
        expectNoHole(unlimitedQuotesUsageAr(n), 'unlimitedQuotesUsageAr($n)');
      }
    });

    test('a limit the server did not state never leaves a hole in the middle',
        () {
      // The other half of the live defect, and the one the first fix missed:
      // the guard went on the *usage* count, and the **limit** went into the
      // same sentence still unguarded. `quote_limit: 0` is a value this app
      // really parses — `_int()` returns it for a field sent as 0, and only a
      // literal `null` gets the 3-default on `SubscriptionStatus.fromJson`.
      for (final used in [1, 2, 3, 11, 20]) {
        final line = cappedQuotesUsageAr(used, 0, isFree: true);
        expectNoHole(line, 'cappedQuotesUsageAr($used, 0)');
        expect(line, isNot(contains('من ')),
            reason: 'no allowance was stated, so none is claimed: [$line]');
      }
    });
  });

  group('photos: no sentence has a hole, in either count', () {
    test('the gallery count and the session count', () {
      // These three already return `''` on a zero, which is the **contract**,
      // not a hole: an absent count is dropped and the caller keeps whatever
      // sentence it has. So the assertion here is one-directional — if they
      // answer, the sentence must be whole. Asserting they always answer would
      // be this file inventing a rule the code does not have and never had.
      for (final n in counts) {
        for (final f in <String, String Function(int)>{
          'portfolioCountLineAr': portfolioCountLineAr,
          'uploadedThisSessionAr': uploadedThisSessionAr,
          'addedPhotosLineAr': addedPhotosLineAr,
        }.entries) {
          final line = f.value(n);
          if (line.isEmpty) continue;
          expectNoHole(line, '${f.key}($n)');
        }
      }
    });

    test('the allowance line, reached through the real allowance object', () {
      for (final limit in limits) {
        for (final used in counts) {
          expectNoHole(_allowance(used, limit), 'allowance(used: $used, $limit)');
        }
        // The count is the second argument since 9 Oct, so this sweeps the
        // cross-product: a limit is a plan value and a count is a gallery
        // length, and the two have crossed only by accident (a downgrade, the
        // free-plan default for a silent server). Every pairing must still
        // return a whole sentence -- including `used > limit`, which is the
        // branch that prints both numbers.
        for (final used in counts) {
          expectNoHole(portfolioFullLineAr(limit, used),
              'portfolioFullLineAr($limit, $used)');
        }
      }
    });

    test('no room left is a sentence, not a blank in front of "من"', () {
      for (final limit in limits) {
        for (final left in [-3, -1, 0]) {
          expectNoHole(
              portfolioLeftLineAr(left, limit), 'portfolioLeftLineAr($left, $limit)');
        }
      }
    });
  });

  group('reach: a span that is not there drops the row rather than the count', () {
    test('planReachLineAr returns null instead of printing a gap', () {
      for (final n in counts) {
        final line = planReachLineAr(n);
        if (line != null) expectNoHole(line, 'planReachLineAr($n)');
      }
      expect(planReachLineAr(0), isNull,
          reason: 'a zero span must drop the row, not print «وصول في »');
      expect(planReachLineAr(-1), isNull);
    });
  });
}

/// The gallery header line, built through the real allowance object so the
/// `left` that reaches the copy function is the one the screen would pass.
///
/// The branches are the screen's own, in its order — full, then unlimited,
/// then the room left — so this asserts the sentence for every state the header
/// can actually be in, not just the one the screen currently guards.
String _allowance(int used, int limit) {
  final a = PortfolioAllowance(limit: limit, used: used);
  if (a.isFull) return portfolioFullLineAr(a.limit, a.used);
  if (a.isUnlimited) return portfolioUnlimitedLineAr();
  return portfolioLeftLineAr(a.left!, a.limit);
}
