/// The one-line trade summary printed under a contractor's name.
///
/// Two copies of this rule existed on the card — one per variant — and both
/// were wrong in the same way, which is what made the copy a defect rather than
/// a style.
///
/// **The bug.** The label is `specialties.take(2).join(' · ')` with no
/// ellipsis and no count. A contractor who registered three trades had the
/// third **silently deleted** from the line that exists to name his trades.
/// Nothing on the card says three: the name, the trades, the score and the
/// wilaya all read as if those two were all he does.
///
/// This is not hypothetical, and the row that proved it came from the live
/// API rather than from a guess about what the server might send. One wilaya
/// response (`/api/mobile/workers/search?wilaya=16`) returned contractor
/// **خالد رحماني** — verified, 4.6★ over 18 reviews, 32 completed jobs, the
/// profile a customer is most likely to tap in that province — carrying
/// `["painting","wallpaper","tiling_marble"]`. The card printed
///
///     دهان وطلاء ديكوري · ورق الجدران
///
/// and `بلاط وسيراميك ورخام` simply did not exist on screen.
///
/// **Why that is a defect and not a design choice.** The browse screen filters
/// *by trade* (`browse_screen.dart` keeps `_category` and the server filters
/// on it), so the number of trades a contractor carries decides **whether a
/// customer searching for that trade finds him at all**. He is returned for a
/// tiling-marble search, he is the top result in it, and the one line on the
/// card that would have said he does tiling is the line that dropped it. The
/// search says yes and the card says no, and the customer concludes the app is
/// broken. A customer looking for a tiler and a painter needs one man; a
/// customer looking for a tiler *only* needs a man whose card says so.
///
/// The fix keeps the two-trade line it always was — that line is not the bug,
/// it is the design — and makes the truncation **say it happened**. A count is
/// the smallest honest thing the card can add: «+1» costs seven glyphs and
/// turns a silent deletion into a promise the customer can check by tapping.
///
/// A profile with no trades at all still answers «حرفي» and not a count: a zero
/// is the absence of a count, the same rule every other count in this app
/// follows.
library;

import 'taxonomy.dart';

class SpecialtyLabel {
  const SpecialtyLabel._();

  /// Trades named on one line before the rest are counted rather than listed.
  ///
  /// Two is the width that fit a phone row at 12 dp without ellipsing the
  /// *first* trade, which is the one that must never be lost — so two stays
  /// two, and the change is only that the remainder is now counted.
  static const int named = 2;

  /// Shown when a contractor has registered no trade at all.
  static const String none = 'حرفي';

  /// The trade line for [specialties], naming at most [named] of them and
  /// counting whatever is left rather than dropping it.
  ///
  ///   * `[]` -> `حرفي` — a man who has not chosen a trade yet.
  ///   * `['painting']` -> `دهان وطلاء ديكوري`
  ///   * `['painting','plumbing']` -> `دهان وطلاء ديكوري · سباكة وترصيص صحي`
  ///   * `['painting','wallpaper','tiling_marble']` -> the two above, then `+1`
  ///
  /// Slugs are resolved through [Taxonomy.categoryName], which never leaks a
  /// raw English slug into the Arabic UI, and **the count is of what was
  /// resolved, not of what arrived** — so three entries that all fold to the
  /// same trade print that trade once, and never claim a `+2` over a list that
  /// only shows one name.
  static String of(Iterable<String> specialties) {
    // The whole list is walked, not just enough of it to fill the line: the
    // count claims how many trades the card is *not* showing, so stopping
    // early would make «+1» the answer to a five-trade contractor.
    final names = <String>[];
    for (final slug in specialties) {
      // A blank entry is not a trade. It is checked *before* resolution because
      // [Taxonomy.categoryName] folds an empty slug to the same «خدمات عامة»
      // it uses for an unknown one, and a profile carrying `['']` would
      // otherwise be labelled as a man who does general work.
      if (slug.trim().isEmpty) continue;
      final name = Taxonomy.categoryName(slug).trim();
      // De-duplicate after resolution: `painting` and `general_painting` are
      // two slugs for one trade, and a card that printed both would tell a
      // customer the man works in two things when he works in one.
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    if (names.isEmpty) return none;
    final head = names.take(named).join(' · ');
    final hidden = names.length - named;
    if (hidden <= 0) return head;
    // `+$hidden`, not a spelled-out count: this is a badge telling the
    // customer there is more to read, not a sentence, and it has to survive a
    // `maxLines: 1` ellipsis budget the card does not have room to waste.
    return '$head +$hidden';
  }
}
