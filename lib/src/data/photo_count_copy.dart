// How many photos, in the form the number calls for.
//
// Found on 26 Sep 2026 while auditing what the quote-allowance fix left. The
// portfolio header counted its own photos with string interpolation and a
// single fixed noun:
//
//     '$count صورة في معرض أعمالك'
//     'أضفت $uploaded صورة في هذه الجلسة.'
//
// Arabic changes the noun on the number, not the number on the noun: «5 صور»,
// never «5 صورة». That range is not hypothetical here — the free plan ships
// `portfolio_limit: 5`, so a contractor who fills his free allowance sees
// «5 صورة» on the one screen whose whole job is to show him what he has, and
// every upload after the first is a new count. The app never caps the list
// server-side either (`addPortfolioImage` posts with no ceiling), so the
// count climbs past ten on any paid plan, where the noun has to return to the
// counted singular («11 صورة») rather than stay plural.
//
// The agreement itself is not re-implemented here: it is [arabicCounted], the
// same one the notification clock, the subscription countdown, the commune
// picker and a contractor's own stats already share. This file owns the nouns
// and the two sentences that use them.
library;

import '../core/l10n/arabic_agreement.dart';

/// «صورة» / «صورتان» / «3 صور» / «11 صورة».
///
/// **The singular is the bare form, not «صورة واحدة»** — the same trap the
/// quote fix documents. A caller cannot pass «صورة واحدة» in as the singular:
/// it is right for 1 and wrong for everything from 11 up, which reuses that
/// slot and would read «11 صورة واحدة».
///
/// The dual is «صورتان» rather than «صوريان»/«صورتين» because this count is
/// only ever printed as the subject or object of a verb, and «صورتان» is the
/// form that reads correctly on its own in the one slot the app uses it in.
String photosAr(int n) {
  if (n <= 0) return '';
  return arabicCounted(n, 'صورة', two: 'صورتان', few: 'صور');
}

/// The line that counts the photos on the profile: «7 صور في معرض أعمالك».
///
/// A zero is silence, not «0 صور» — and the header is only built when the
/// list is not empty, so that branch is unreachable from the screen and the
/// empty gallery keeps the sentence it has always had.
String portfolioCountLineAr(int n) {
  final photos = photosAr(n);
  if (photos.isEmpty) return '';
  return '$photos في معرض أعمالك';
}

/// What the same screen says after an upload: «أضفت 3 صور في هذه الجلسة.».
///
/// This is the second half of the defect and the one that moves fastest: it
/// counts uploads in a single sitting, so a contractor who adds four photos in
/// a row passes 1 → 2 → 3 → 4 and reads a wrong noun on the third one, on a
/// screen he is looking at while the photos are still uploading. The sentence
/// is a claim about this session only, so it keeps its full stop and never
/// mentions the total.
String uploadedThisSessionAr(int uploaded) {
  final photos = photosAr(uploaded);
  if (photos.isEmpty) return '';
  return 'أضفت $photos في هذه الجلسة.';
}
