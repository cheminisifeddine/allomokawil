// Whether a bid is still on the table, in words.
//
// Found on 29 Sep 2026 by driving a real accept on the live API, not by
// reading the screen. Two contractors bid on one project; the owner accepted
// the first; the Worker then answered with `status` on both rows:
//
//   quote 48 -> "accepted"     the bid the project is committed to
//   quote 49 -> "rejected"     the other contractor, thrown out at that moment
//
// and `Quote.fromJson` **dropped the field**. Every card on the owner's screen
// was therefore identical to the one before the tap: same name, same amount,
// same live «قبول العرض» button, on the bid the server had already refused.
// Tapping it answered `{"ok":true}` and changed nothing — the project kept
// `selected_worker_id: 125` while the card on screen offered 126. A customer
// who taps the losing card is told he hired a man he did not hire, and the one
// write in this product that signs a contract looks like it worked.
//
// **Why the customer cannot act on it.** The project itself is honest about
// the outcome — `_StatusRow` prints «قيد التنفيذ» and the owner's actions go
// away — but the *card* is where the choice was made, and the card is the
// only thing he is looking at when he decides. The screen must therefore say
// which bid won, not leave a rejected one looking live next to it.
//
// So there are two sentences here and they are the same problem seen twice:
// the word that rides on the card, and the sentence that replaces the button.
// Both belong to this file, because both are Arabic that has to agree, and a
// rule only a widget can exercise is a rule that ships untested.
//
// A third string — a label for the action row — was written here first and
// then deleted before this shipped. Nothing drew it: the card prints the note
// instead, because on a decided bid the useful thing to read is *which* bid
// won, not a restatement of the stamp three lines above it. Arabic that no
// widget can reach is Arabic nobody ever sees, and it stays here only to be
// asserted in a test.
library;

import '../models/enums.dart' show QuoteStatus;

/// «مقبول» / «مرفوض» — the word that rides on a bid the server has decided.
///
/// Empty for a bid still on the table, because a live bid needs no stamp: the
/// button is the label, and printing «قيد الانتظار» above a «قبول العرض» button
/// on every card would be noise on the common case.
///
/// The choice of word is the one the project status row already teaches in
/// this app — the accepted bid reads as an accomplished fact, the rejected one
/// as a closed door. Neither is a judgement about the contractor: he sent the
/// bid, the owner picked somebody else.
String quoteStatusAr(QuoteStatus s) {
  switch (s) {
    case QuoteStatus.accepted:
      return 'مقبول';
    case QuoteStatus.rejected:
      return 'مرفوض';
    case QuoteStatus.pending:
      return '';
  }
}

/// The one line under the amount on a decided bid.
///
/// Kept separate from [quoteStatusAr] because they answer different
/// questions and merging them is how a card ends up saying «مرفوض» and
/// explaining why. A decided bid is not an error and not an empty state: the
/// customer's bid was read and he lost it to somebody else, which is the
/// ordinary outcome of a competitive marketplace and deserves a sentence that
/// says so rather than a grey card that says nothing.
///
/// Empty for [QuoteStatus.pending], so the caller draws nothing at all for a
/// live bid — the row is not a placeholder and this file has never invented a
/// value to fill one.
String quoteStatusNoteAr(QuoteStatus s) {
  switch (s) {
    case QuoteStatus.accepted:
      return 'تم اختيار هذا المقاول للمشروع';
    case QuoteStatus.rejected:
      return 'تم اختيار عرض آخر — هذا العرض لم يُعتمد';
    case QuoteStatus.pending:
      return '';
  }
}
