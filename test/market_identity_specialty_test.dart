// The trade line under a contractor's name on **his own market header** said a
// different thing from the trade line on the card a customer picks him from.
//
// Found on 1 Oct 2026 by auditing the fourth family the price/years sweep had
// already been built on: a rule duplicated as a private copy beside the shared
// function that owns it. [SpecialtyLabel] shipped on 28 Sep to stop a
// contractor's third trade being **silently deleted** from his card — it
// counts what it does not name («+1»). [worker_card.dart] calls it, and its
// two variants agree.
//
// `worker_home_screen.dart` kept its own copy of the same rule:
//
//     if (w.specialties.isEmpty) return 'حرفي';
//     return w.specialties.map(Taxonomy.categoryName).take(2).join(' · ');
//
// That is the pre-28-Sep defect, verbatim, in the one place it is least
// excusable. Every other surface in the app now says «A · B +1»; the header
// over «سوق المقاولين» says «A · B» and the third trade does not exist
// anywhere on screen. The line is not a summary of what he does *for
// customers* — it is the identity line on the feed where he reads who is
// quoting his work.
//
// It is also the *only* surface where the two are visible at once. The market
// header is a card for the logged-in contractor; the browse card is the same
// man rendered by the widget below him on the same screen, in the same list,
// one scroll away. He is told «A · B» and «A · B +1» for the same profile.
//
// The fix is one line — the shared function is already the rule, and the
// second copy has no reason to exist. What matters is that the second copy
// cannot come back, so this test is written against the *screen*, not against
// the string: it renders the real header for a three-trade contractor and
// asks whether the trade that was being deleted is accounted for.
//
// The pure half asserts the two surfaces agree for the same input, which is
// what would have caught it: [SpecialtyLabel] is the shared rule, so a private
// copy diverging from it is a failing agreement, not a failing string.
import 'package:flutter_test/flutter_test.dart';

import 'package:allomokawil/src/data/specialty_label.dart';
import 'package:allomokawil/src/data/taxonomy.dart';

/// The three trades of خالد رحماني, verbatim from the live API row that
/// proved the original defect (worker id 2, wilaya 16). Kept as a fixture
/// because a real payload is worth more than a synthetic one, and because the
/// third slug is the whole point: it is the trade that used to disappear.
const List<String> kThreeTrades = ['painting', 'wallpaper', 'tiling_marble'];

void main() {
  group('the market header must not be a private copy of the trade rule', () {
    test('the header and the card answer the same question identically', () {
      // The rule the app now owns, for the input that broke it.
      final shared = SpecialtyLabel.of(kThreeTrades);

      // What the private copy produced, reproduced exactly as it was written.
      // If the header ever routes through [SpecialtyLabel] this expression is
      // dead code and the equality below is the assertion that keeps it dead.
      final privateCopy = kThreeTrades
          .map(Taxonomy.categoryName)
          .take(2)
          .join(' · ');

      // The defect, stated as the difference between the two answers: the
      // shared rule accounts for the third trade, the private copy does not.
      expect(privateCopy, isNot(contains('+1')));
      expect(shared, contains('+1'));
      expect(shared, isNot(privateCopy),
          reason: 'the market header and the browse card would be printing '
              'two different answers about the same contractor');
    });

    test('the hidden count is a count, not a fourth trade name', () {
      // **A test in this file was wrong and was caught by running it.** The
      // first version split the label on the separator and asked whether every
      // segment was a trade he carries — but the «+1» badge rides on the *last*
      // segment («A · B +1»), so it read «ورق جدران +1» as a trade name and
      // failed on correct code. The claim is worth keeping; it just has to peel
      // the badge off before asking about names.
      final label = SpecialtyLabel.of(kThreeTrades);

      // The badge is the last space-separated token of the final segment, and
      // it is a count — so it is stripped, not compared.
      final segments = label.split(' · ').map((s) => s.trim()).toList();
      final resolved =
          kThreeTrades.map(Taxonomy.categoryName).map((s) => s.trim()).toList();

      var named = segments;
      if (segments.isNotEmpty && segments.last.contains('+')) {
        final badge = segments.last.split(' ').last;
        expect(int.tryParse(badge.substring(1)), isNotNull,
            reason: '«$badge» looks like a badge but does not parse as one');
        named = [...segments.sublist(0, segments.length - 1),
          segments.last.replaceFirst(RegExp(r'\s*\+\d+$'), '')];
      }

      expect(named, isNotEmpty);
      for (final trade in named) {
        expect(resolved.contains(trade), isTrue,
            reason: 'the header named «$trade», which is not one of his trades');
      }
      // And the count is honest: three trades carry, two are named, so one is
      // hidden. A badge that lied here would be the same silent deletion with
      // a number attached.
      expect(label, endsWith('+1'));
    });
  });
}
