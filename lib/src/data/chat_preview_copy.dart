// One rule for "what does the inbox row preview say?", in one place.
//
// Found on 28 Sep 2026 by posting a real picture to a real thread on the live
// API. `Repository.sendImage` posts `image_url` and `message_type: 'image'` and
// **no `content` field at all**, so the server stores a NULL and
// `/api/mobile/conversations` answers:
//
//     "last_message_at":"2026-09-28 22:01:12",
//     "last_message_content":null
//
// The row gated its one-line preview on `lastMessageContent != null`, so a
// thread whose last message was a photo rendered **the name, and nothing
// else**: no preview line, no row height for it, a shorter card than the thread
// beside it. The same null arrives for a conversation that was opened and
// never written to, so the *newest* thread in the inbox — the one a customer
// has just opened and is waiting on a reply to — is the emptiest-looking.
//
// This is the inbox on a marketplace where a photo of a finished bathroom is
// how a contractor answers. The row that is supposed to say "he sent you
// something" is the row that says nothing at all, and a user reads that as
// "he has not replied".
//
// The rule is therefore: **a preview is never optional.** A null content is
// not the absence of a preview, it is a preview that has to be *named* — and
// what it gets named is decided here, once, so the inbox cannot disagree with
// itself.
library;

/// The one-line preview for a conversation row, or null when the thread has
/// nothing to preview at all.
///
/// Three answers, never two:
///
///   * text     — the words, verbatim. The server owns them; nothing here
///                trims or rewrites what a person actually wrote.
///   * «صورة»   — the last message was a picture. `sendImage` sends no
///                content, so this is the *normal* state of a photo thread,
///                not an edge case.
///   * «لا رسائل بعد» — the thread was opened and nothing was sent. Distinct
///                from a photo on purpose: one is a reply waiting to be
///                written, the other is a reply that already arrived.
///
/// A **blank** string is folded to the same "no messages" copy rather than
/// drawn as an empty line. A whitespace-only `content` is a real risk here
/// because the chat composer can enqueue an empty draft, and a blank
/// ellipsised line is a row that looks broken rather than one that reads
/// «لا رسائل بعد».
///
/// The picture word is the one the photo viewer already titles itself
/// `الصورة` (`chat_screen.dart`), so the inbox and the thread the user opens
/// from it name the same thing the same way.
String? chatPreviewCopy(String? content) {
  final text = content?.trim() ?? '';
  if (text.isEmpty) return null;
  return text;
}

/// The preview for a thread whose last message carried no text, so the row
/// can say what arrived instead of dropping the line.
///
/// [hasMessage] is the one fact that separates the two namings: a timestamp on
/// the row means something was sent, and on this API the only thing sent
/// without content is a picture. No timestamp means the thread is simply
/// empty, which is a different sentence and a different state.
String? chatFallbackPreview({required bool hasMessage}) =>
    hasMessage ? 'صورة' : 'لا رسائل بعد';
