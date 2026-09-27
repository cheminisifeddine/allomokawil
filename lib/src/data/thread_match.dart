// Deciding whether the server already holds a message this phone sent.
//
// The whole duplicate-protection design in the chat outbox rests on one
// question: when a write's answer never arrived, is the row on the server or
// not? `resolveWriteOutcome` asks it by re-reading the thread, and this file is
// the predicate the re-read compares with.
//
// It exists as its own file, rather than as an `==` inlined at four call sites,
// because that inline comparison was wrong for photos and wrong *silently*.
//
// The bug it replaces, in one line: `row.content == local.content`. For a
// picture `content` is null on both sides, so the test was `null == null` —
// always true. It "found" a landed message in any thread that held any image
// from the same person, which is the wrong answer twice over:
//
//  * **a photo that never arrived was reported as delivered.** The outbox
//    record was then deleted as «settled», so the picture was not retried, not
//    redrawn, and no sentence anywhere said it had not been sent. The user had
//    a message he believed was delivered and there was nothing left on the
//    device to send it from — a silent loss of the very thing the outbox was
//    built to keep.
//  * and the *adopted* row was whichever image happened to be first, so the
//    bubble kept its negative local id in one case and a stranger's id in
//    another.
//
// Text was accidentally correct (`content` is non-null on both sides), which is
// why 1000+ tests never saw it. Equal words are still not a proof of identity
// — two «تمام» in a row are two messages — but that is a pre-existing limit of
// the text path and this file does not widen the claim it makes about photos.
library;

import '../models/chat.dart';

/// The identity of a message this device sent, as far as the server can be
/// asked about it.
///
/// A photo carries **two** different namespaces and the bug lived in treating
/// them as one: [imagePath] is a path on this phone (`/storage/…`), while the
/// thread read back holds a URL in R2. They can never be equal, so a photo is
/// identified by the URL its upload returned — [uploadedUrl] — and never by its
/// local path.
class LocalIdentity {
  /// The words, or null for a picture.
  final String? text;

  /// Absolute path of the picture on this device, if it has not been uploaded.
  final String? imagePath;

  /// The R2 URL the upload returned, once it has.
  ///
  /// This is the only value that can identify a photo in a re-read. Null before
  /// the upload answers, and permanently null if it never did — which is itself
  /// an answer, see [threadHolds].
  final String? uploadedUrl;

  const LocalIdentity({
    this.text,
    this.imagePath,
    this.uploadedUrl,
  });

  /// True when this is a picture rather than words.
  bool get isImage =>
      (uploadedUrl != null && uploadedUrl!.isNotEmpty) ||
      (imagePath != null && imagePath!.isNotEmpty);
}

/// True when [row] — a row from a fresh read of the thread — is the server's
/// copy of the message [mine] describes.
///
/// Two rules, and the second is the one that was missing:
///
///  1. **Someone else's row is never mine.** [me] is 0 when the app does not
///     know who it is, and then no check is possible, so the id is ignored —
///     the caller has already decided that.
///  2. **A picture is matched by its uploaded URL, or not at all.** A photo
///     whose upload never returned a URL has, by construction, no message row
///     on the server: the row is written *after* the upload, carrying the URL
///     the upload produced. So with no [LocalIdentity.uploadedUrl] the honest
///     answer is false — «not there» — which is also the safe direction, since
///     a false negative costs one duplicate and a false positive deletes the
///     user's own unsent picture.
///
/// Text requires a non-empty [LocalIdentity.text] on both sides for the same
/// reason `null == null` was never acceptable on either side of any comparison
/// in this app.
bool threadHolds(Message row, LocalIdentity mine, {required int me}) {
  if (me > 0 && row.senderId != me) return false;
  if (mine.isImage) {
    final url = mine.uploadedUrl;
    final rowUrl = row.imageUrl;
    if (url == null || url.isEmpty) return false;
    if (rowUrl == null || rowUrl.isEmpty) return false;
    // Compare the whole URL. A prefix match would be another way to invent a
    // match that is not there, and the URLs are opaque keys the app never
    // rewrites — there is nothing to normalise.
    return rowUrl == url;
  }
  final words = mine.text;
  final rowWords = row.content;
  if (words == null || words.isEmpty) return false;
  if (rowWords == null || rowWords.isEmpty) return false;
  return rowWords == words;
}
