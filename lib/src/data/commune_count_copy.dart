// How many communes, in the form the number calls for.
//
// Found on 26 Sep 2026. The commune picker in `project_new_screen` printed its
// count twice, by hand, with one fixed noun both times:
//
//     '$_total بلدية'                     // the wilaya total
//     matches == 1 ? 'بلدية واحدة' : '$matches بلدية'
//
// The second one has a real bug and not a hypothetical one. `بلدية` is the
// broken plural, correct only for 3-10. Reading the bundled dataset this tick:
// 14 of the 58 wilayas have ten or fewer communes — four have **two** (Tindouf,
// Bordj Badji Mokhtar, In Guezzam and Djanet), two have three, and Ghardaïa and
// Timimoun have exactly ten — and the search count is smaller than the total on
// every keystroke. So the picker a user opened in Tindouf said «2 بلدية», and
// typing anything narrowed it to «2 بلدية» or «3 بلدية» where Arabic requires
// «بلديتان» and «3 بلديات».
// This is why the rule lives in a file: the copy was right in the two biggest
// wilayas and wrong for a quarter of the country, and nobody reviewing a
// screenshot of Algiers or Oran would ever have seen it.
//
// The rule is not re-implemented here: it is [arabicCounted], the one the
// notification clock, the chat outbox, the subscription countdown and a
// contractor's own stats already share. This file owns only the nouns and the
// two cases that are not plain counts.
library;

import '../core/l10n/arabic_agreement.dart';

/// «بلدية واحدة» / «بلديتان» / «3 بلديات» / «11 بلدية».
///
/// **One branches before the rule, and the bare singular goes in after it.**
/// [arabicCounted] does not print a number for 1 or 2 — «بلدية» alone is the
/// form for one, which is correct but thinner than what a picker header wants,
/// so 1 says *one* in the word: «بلدية واحدة». What must **not** happen is
/// passing that word in as the singular, because the rule reuses it for 11 and
/// up and would print «11 بلدية واحدة».
///
/// **Zero is silence**, not «0 بلدية»: the wilaya total is shown only after
/// the dataset loads, and a search with no hits renders its own empty state
/// («لا توجد بلدية بهذا الاسم»), so a zero would only ever be a count this
/// screen has no way to say.
String communeCountAr(int n) {
  if (n <= 0) return '';
  if (n == 1) return 'بلدية واحدة';
  return arabicCounted(n, 'بلدية', two: 'بلديتان', few: 'بلديات');
}
