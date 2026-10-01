// One rule for the sentence under a notification's headline.
//
// Found on 28 Sep 2026 by driving the real API: registered a customer, a
// contractor and a project, then made the three events a notification can come
// from — a quote, an accepted quote, a finished job and a review — and read
// `/api/notifications` back. Every row the Worker sends for a review carries
//
//     "type":"review_received","title":"تقييم جديد","body":"5/5"
//
// and the screen draws `body` under the headline. So the row a contractor
// opens to find out how a customer rated his work reads, in full:
//
//     ★  تقييم جديد
//        5/5
//        قبل ساعتين
//
// **"5/5" is not Arabic and it is not a sentence.** A score out of five is
// `star_row_shape` / `RatingStars` territory — the one place in the app that
// knows what a rating looks like. Printed as a bare fraction it is the only
// Latin-numeral string in the whole notification centre, and it is on the row
// whose entire job is to be understood without being taught. Worse, it is the
// *same two numbers for every rating* a customer can leave (the form is 1-5),
// so it carries no information: a 5/5 and a 1/5 differ only in a glyph.
//
// The rest of the API's bodies are real sentences, and they are read live above
// so this rule is written from the wire, not from a guess:
//
//   new_quote       "جاهز للبدء"            — the contractor's own words
//   project_update  "اختبار الإشعار"        — the project title
//   quote_accepted  "مبارك! تم اختيارك…"    — a sentence from the Worker
//   review_received "5/5"                  — a bare score, the outlier
//
// So the rule is not "make everything Arabic" — that would rewrite a real
// sentence a person typed. The rule is: **a body that is only a rating gets
// named; a body a person wrote is shown exactly as they wrote it.**
library;

import '../core/l10n/arabic_agreement.dart';

/// Matches a body that is nothing but a rating out of five: `5/5`, `3/5`,
/// `5 / 5`, and the same with spaces or Latin digits. Anchored, so `5/5 عمل
/// ممتاز` is *not* a bare score — that is a person writing, and the sentence
/// is theirs to keep.
final RegExp _bareScore = RegExp(r'^\s*[0-9٠-٩]+\s*/\s*[0-9٠-٩]+\s*$');

/// The scale this app's own review form measures on.
///
/// Five, because [ReviewScreen] draws five stars and refuses to submit a
/// narrower one — so `5/5` is the only fraction the Worker has ever written.
/// It is named rather than written into the arms so a future ten-star form has
/// one place to change.
const int _ratingScale = 5;

/// True when [body] carries a rating and nothing else.
bool isBareRatingBody(String? body) =>
    body != null && _bareScore.hasMatch(body);

/// The one line under a notification's headline.
///
/// Three answers, never a raw `5/5`:
///
///   * the words, verbatim, when a person wrote them;
///   * «حصلت على تقييم 5 من 5» when the Worker sent only a score;
///   * «لا تفاصيل» when the row has no body at all, so the card does not go
///     short beside its neighbours — the same rule the inbox preview shipped on
///     this same day for the same reason.
String notificationBodyCopy(String? body, {required String type}) {
  final text = body?.trim() ?? '';
  if (text.isEmpty) return _emptyFor(type);
  if (isBareRatingBody(text)) return _scoreCopy(text);
  return text;
}

/// The server writes Latin digits; a row typed on an Arabic keyboard can hold
/// Arabic-Indic ones. Both are numbers here.
int? _toInt(String raw) {
  final t = raw.trim();
  final latin = int.tryParse(t);
  if (latin != null) return latin;
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  var out = 0;
  for (final r in t.runes) {
    final d = arabicDigits.indexOf(String.fromCharCode(r));
    if (d < 0) return null;
    out = out * 10 + d;
  }
  return out;
}

/// «حصلت على تقييم 5 من 5» — the score named in words, with the number that
/// actually arrived rather than an assumed maximum.
String _scoreCopy(String body) {
  final parts = body.split('/');
  final raw = _toInt(parts.first.trim());
  // The denominator is the server's own, not a literal 5: a future form that
  // can leave ten stars must not have its score described as «من 5».
  final sent = parts.length > 1 ? _toInt(parts[1].trim()) : null;
  if (raw == null) return 'حصلت على تقييم';
  // A count of zero has no Arabic form, and `arabicCount` asserts against
  // exactly that rather than printing «0 نجوم». The review form cannot produce
  // a zero, so this is the branch that keeps a drifted column from taking the
  // screen down: copy with no number in it instead.
  if (raw < 1) return 'حصلت على تقييم';

  // **A numerator above its own scale is pinned down to it**, and this is the
  // same rule `clampRating` already applies to the other three rating surfaces
  // in this app, applied here for the first time.
  //
  // The Worker writes this body as a bare fraction, so the score reaches the
  // card straight off the wire with nothing on the way in bounding it, and
  // '7/5' printed «حصلت على تقييم 7 نجوم» — seven stars, on the one screen a
  // contractor opens to find out how his work was judged, beside a row that
  // can only draw five. `star_row_shape.dart` was opened on 26 Sep to kill
  // exactly that sentence and lifted `clampRating` out on 1 Oct so the glyphs,
  // the printed digits and the spoken label would all stop disagreeing about
  // one score. It reached six call sites. This file is the fourth rating
  // surface and it was not one of them, which is why the same contradiction
  // simply moved to the next screen.
  //
  // The pin is to the **denominator**, not to a literal five, because the
  // denominator is the scale the server stated and this copy file has always
  // deferred to it. 9/10 pins to ten; a future ten-star form does not get
  // silently described against the star row's five.
  //
  // A denominator that is absent, zero or negative is not a scale at all, and
  // this app's own is five. `_toInt` hands back 0 for both an unparseable and
  // a missing one, so '7/0' used to fall through to the `من $scale` arm and
  // print «حصلت على تقييم 7 من 0» — a score out of no scale, to the man it is
  // about most.
  final scale = (sent == null || sent <= 0) ? _ratingScale : sent;
  final got = raw > scale ? scale : raw;

  if (scale == _ratingScale) {
    return 'حصلت على تقييم ${arabicCounted(got, 'نجمة', two: 'نجمتين', few: 'نجوم')}';
  }
  return 'حصلت على تقييم $got من $scale';
}

/// The sentence for a row that arrived with no body.
///
/// Type-aware on purpose: «لا تفاصيل» on a **new_message** row is a lie, and
/// it is the one type where the missing body costs the user the most — the
/// headline says «رسالة جديدة» and the line under it would say there are no
/// details about a message that is sitting in the inbox unread. So a message
/// with no body points at the place the message actually is, and every other
/// type gets the honest «no details».
String _emptyFor(String type) =>
    type == 'new_message' ? 'افتح الرسائل للاطلاع عليها' : 'لا تفاصيل';
