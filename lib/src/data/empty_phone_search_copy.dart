// What the directory says when the customer searched for a phone number and no
// contractor carries it — and why the sentence it was drawing was about a word.
//
// Found 5 Oct 2026 by reading the empty state against the matcher that decides
// it, which is the only way to see this defect: the search box has accepted a
// number since 5 Oct (`data/worker_phone_search.dart`), and the screen that
// renders the answer to it was never changed to know which kind of query it is
// holding.
//
// A customer is handed a number in the street — «سمعت هذا المقاول، اتصل بيه» —
// pastes it into «ابحث عن مقاول», and this directory answers:
//
//   لا نتائج مطابقة
//   لا يوجد مقاول يطابق «0770123456».
//   جرّب كلمة أقصر أو امسح البحث
//   [ مسح البحث والفلاتر ]
//
// «جرّب كلمة أقصر» — *try a shorter word*. He typed a number. There is no word
// to shorten, and the one number he has is the only handle he will ever have on
// that man, so the sentence is advice about something that does not exist in
// what he is holding. The line above it compounds it by echoing the number back
// between «» where a name is expected: the directory is quoting a word-search
// result at a phone lookup.
//
// Both halves are wrong for a number, and both are right for a word, which is
// why nothing in the app could have caught it: the text arm was written for
// words, and the number arm was added *beside* it in the matcher without ever
// reaching the sentence.
//
// ## Why the number is worth naming, and the truth it has to keep
//
// The two facts a customer can act on are both missing:
//
// **The number was read, and it was understood.** He typed `0770123456` and got
// «لا نتائج مطابقة», which is indistinguishable from a network failure and from
// a typo in his paste. Saying the search was *a number search* is the cheapest
// possible proof that the app did the work — and it is true, because
// [phoneQueryDigits] is the same function that performed the matching. The
// directory is not guessing from the shape of the input; it is reporting the
// branch it actually took.
//
// **A shorter number is a real next step, and a shorter *word* is not.** Four
// remembered digits out of ten is the realistic input — nobody types a number
// from memory — so a customer who typed a full number and found nothing has
// exactly one useful move left: type less of it. That is the advice the state
// should give, and it is the advice it gives to exactly the wrong input. This
// is why the fix is a sentence and not a button: widening the digits is
// something the customer does in the box he is already looking at.
//
// ## What it must not claim
//
// It does not claim the number belongs to nobody, that it was never registered,
// or that the platform has no such contractor — «لا يوجد مقاول يطابق …» is a
// statement about this read, which is what the customer is entitled to, and the
// same restraint `empty_wilaya_copy.dart` applies to its own message. It also
// does not echo the number back: what a customer pasted is his own business,
// and an empty state is the wrong place to re-print a phone number he may have
// pasted by mistake. The button underneath is unchanged — «مسح البحث والفلاتر» —
// so the one action that is always safe stays the one he is offered.
//
// ## The rule
//
// Null for a word query, which the screen already draws correctly. Non-null
// exactly when [query] is a number query by the *same* test the matcher used
// ([phoneQueryDigits]), so the sentence cannot claim "a number search" for a
// word and cannot claim "no word matched" for a number. The two are decided in
// one place on purpose: a second, looser test here is how these two branches
// came to disagree in the first place.
library;

import 'worker_phone_search.dart';

/// The message for a search that was a phone number and matched no contractor,
/// or null when [query] is a word and the screen's own sentence already fits.
///
/// [query] is the raw text in the box, not the canonical number: the fold is
/// [phoneQueryDigits]' job and its result is deliberately unused, because the
/// sentence must not re-print a number the customer typed.
String? emptyPhoneSearchAr(String? query) {
  if (query == null) return null;
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;
  // The same predicate the matcher branches on. Null here means it was a word,
  // and a word is the case the screen was already right about.
  if (phoneQueryDigits(trimmed) == null) return null;
  return 'لم يُعثر على رقم مطابق.\n'
      'جرّب أرقامًا أقل من هذا الرقم.';
}
