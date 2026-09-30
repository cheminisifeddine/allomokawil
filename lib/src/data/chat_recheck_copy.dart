// One sentence for the banner's re-read, however many messages it settled.
//
// The banner's «تحقّق» button reads the thread once and can answer for **every**
// outstanding message at the same time — that is what the re-read is, and it is
// why the button exists. The screen answered it one toast per message, and
// `ScaffoldMessenger` **queues**: a second `showSnackBar` while one is visible
// waits for the first to time out, four seconds by default.
//
// So a user with three unconfirmed messages who pressed one button read three
// sentences, twelve seconds apart, each about a different message and none of
// them a summary — and the last one, the only one still on screen when he
// looked away, was the verdict for a message he had already stopped looking
// at. The one control in the app that can tell him the state of his whole
// outbox instead told him about whichever message happened to be last.
//
// **Three outcomes, not two, and the middle one is the whole point.** A summary
// that lumps «the re-read found the thread empty» in with «the re-read could
// not reach the server» would tell a man on a dead connection that his messages
// are not there, and he would re-send them. [WriteOutcome.missing] is *proof of
// absence* — the list came back and the words are not in it, so re-sending is
// safe and is what the app should be inviting. [WriteOutcome.unknown] is no
// proof at all, and must never be summarised next to a statement that is. So
// the sentence names which of the two the rest are, in the only case where both
// are present, and stays silent about it when they are not — which is why the
// copy below reads differently for one class than for the other rather than
// appending a caveat to a sentence that is about something else.
//
// The count goes through [arabicCounted] because Arabic changes the noun on the
// number, not the number on the noun. The verb is chosen to need no agreement
// of its own so a copy change cannot produce a number/noun mismatch.
library;

import '../core/l10n/arabic_agreement.dart';

/// The banner's re-read answered for [landed] + [absent] + [unclear] messages.
///
/// [landed] are on the server. [absent] are **proven** not to be — the thread
/// came back without them, so re-sending them is safe. [unclear] are the ones
/// the app could not judge either way, which is a strictly weaker fact and is
/// never counted with [absent].
String chatRecheckVerdict({
  required int landed,
  required int absent,
  required int unclear,
}) {
  final checked = landed + absent + unclear;
  assert(
      checked > 1,
      'one message keeps its own per-outcome sentence; this '
      'function is for the plural case');
  assert(landed >= 0 && absent >= 0 && unclear >= 0,
      'a re-read cannot classify a message as less than nothing');

  // The two clean cases, and they are the two the screen already prints one
  // message at a time. When only one class is present the summary is that same
  // sentence with a count in it, so nothing is claimed that the per-message
  // version would not have claimed either.
  if (unclear == 0 && absent == 0) {
    return 'وجدناهم في القائمة — ${_messages(landed)} في المحادثة الآن';
  }
  if (unclear == 0) {
    // A proven absence, and nothing to add. «أعِد إرسالها» is not decoration
    // here: these are the messages the app can offer to send again, and that
    // is the whole difference between this branch and the one below.
    return 'لم نجد ${_messages(absent)} في المحادثة — أعِد إرسالها';
  }
  if (landed == 0 && absent == 0) {
    // No answer at all. The one sentence that is honest is the one that
    // refuses to answer, and it must not wear the clothes of the [absent] case.
    return 'لم يتأكّد وصول ${_messages(checked)} — النتيجة غير معروفة';
  }

  // Two or more classes are present, so the sentence has to name which is
  // which. The clearest words the app already uses for the difference are the
  // two it prints one message at a time — «لم نجده» for a proven absence and
  // «لم يتأكّد وصول» for no answer at all — and merging them into one blurred
  // clause is precisely the defect this file exists to prevent.
  if (landed == 0) {
    return 'لم نجد ${_messages(absent)} في المحادثة — أعِد إرسالها، و${_messages(unclear)} لم يتأكّد وصولها';
  }
  if (absent == 0) {
    return 'وصلت ${_messages(landed)} — و${_messages(unclear)} لم يتأكّد وصولها';
  }
  return 'وصلت ${_messages(landed)}، ولم نجد ${_messages(absent)}، و${_messages(unclear)} لم يتأكّد وصولها';
}

/// «رسالة / رسالتان / N رسائل» — the noun phrase, and only the noun phrase.
String _messages(int n) =>
    arabicCounted(n, 'رسالة', two: 'رسالتان', few: 'رسائل');
