// Proving that a portfolio photo reached the profile, on the one write whose
// failure costs a contractor the only thing he has to sell with.
//
// Found 27 Sep 2026 while auditing the write-outcome contract. Six write paths
// re-read the server after `errWriteUnconfirmed` and tell the user which of
// three things is true — it landed, it is missing, or it is still unknown:
// `project_new_screen`, `project_detail`, `chat_screen`, `review_screen`,
// `verification_screen`, `subscription_screen`. The seventh write — a
// contractor adding a photo of finished work to his own gallery — had none of
// it, and it is the write a contractor on the free plan touches first.
//
// The screen had one `catch` for the whole send, so it made two wrong claims
// about one failure:
//
//  * **The wrong sentence.** `addPortfolioImage` timed out, the transport
//    layer refused to guess, and the contractor was told
//    «تعذّر رفع الملف. تأكّد من الإنترنت ثم أعد المحاولة» — «we could not
//    upload the file». The file *did* upload: that call returned a URL, and it
//    is sitting in R2. What never answered was the second call, the one that
//    registers the URL against his profile.
//  * **The wrong instruction, and it costs the plan.** «أعد المحاولة» is the
//    correct instinct for a lost photo and a duplicate-making one here: a
//    retry uploads the picture a second time (a new R2 key, so a genuinely
//    different URL) and registers a second row. If the first registration had
//    in fact landed, the gallery now shows the same room twice — and each copy
//    spends one of the plan's `portfolio_limit` slots, so a contractor who
//    retries a photo he already has can discover his gallery «full» with half
//    the work missing.
//
// The identity question is easier here than in chat, and for the same
// structural reason: the chat bug compared a **local path** against an **R2
// URL**, two namespaces that can never be equal. By the time this write fails
// the phone is already holding the URL — that is the thing it is about to
// post — so the re-read asks a question with a real answer: is this exact URL
// in the gallery the server just sent back?
//
// The predicate is conservative for the same reason `threadHolds` is: a photo
// with no URL cannot be named, and a false **positive** here is not a
// duplicate, it is a tile drawn for a row nobody can see — a photo that
// appears under the contractor's own thumb and then vanishes on the next
// refresh. So no URL means «not there».
library;

import '../core/l10n/write_outcome.dart';

/// True when [fresh] — the gallery as the server just returned it — holds
/// [uploadedUrl], the URL this device is trying to register.
///
/// **The whole URL, never a prefix or a normalised form.** The other photos in
/// [fresh] come from the same contractor's own earlier uploads, so the decoy
/// here is not a stranger's image but a *previous copy of the same picture*:
/// two uploads of one room produce two keys, and a comparison that only
/// looked at the tail would call the retry a landing. The URLs are opaque keys
/// the app never rewrites, so there is nothing to normalise and nothing to
/// trim.
bool portfolioHolds(List<String> fresh, String? uploadedUrl) {
  if (uploadedUrl == null || uploadedUrl.isEmpty) return false;
  for (final url in fresh) {
    if (url == uploadedUrl) return true;
  }
  return false;
}

/// What an unconfirmed portfolio write turned out to be.
///
/// [gallery] is the server's answer when there was one, so the screen can put
/// the fresh list on screen rather than a guess. It is null exactly when
/// [PortfolioWriteResult.outcome] is [WriteOutcome.unknown] — the phone could
/// not read the gallery, which is not proof the write failed, and a list
/// assembled locally would be exactly the «check the list» that does not exist.
typedef PortfolioWriteResult = ({
  WriteOutcome outcome,
  List<String>? gallery,
});

/// Re-reads the contractor's own gallery and classifies an unconfirmed write.
///
/// [fetch] is a bare read of the profile's photos. It must never throw: a
/// second network failure while we are already reporting one would replace an
/// honest «outcome unknown» with a stack trace, so a throw is caught and read
/// as [WriteOutcome.unknown] — never as [WriteOutcome.missing], because
/// «the photo did not arrive, try again» is the one answer that would send a
/// man uploading the same room twice for a write that may already be filed.
Future<PortfolioWriteResult> resolvePortfolioWriteOutcome({
  required String? uploadedUrl,
  required Future<List<String>> Function() fetch,
}) async {
  final List<String> fresh;
  try {
    fresh = await fetch();
  } catch (_) {
    return (outcome: WriteOutcome.unknown, gallery: null);
  }
  return (
    outcome: portfolioHolds(fresh, uploadedUrl)
        ? WriteOutcome.landed
        : WriteOutcome.missing,
    gallery: fresh,
  );
}
