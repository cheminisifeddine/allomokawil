// The numbers a contractor is judged on, written the way Arabic counts.
//
// Found on 26 Sep 2026 by auditing what is left after the countdown fix. Four
// screens print a worker's experience, completed jobs, review count and reply
// speed, and every one of them built its own sentence out of string
// interpolation: `'${worker.experienceYears} سنة خبرة'`. That is one fixed noun
// for every count, which is the same defect the subscription card shipped last
// cycle, one file over — «3 سنة خبرة» and «11 سنة خبرة» for a noun whose
// plural is «سنوات», and «3 تقييم» for a noun whose plural is «تقييمات». A
// customer choosing a tradesman reads these four numbers before he sends
// anyone a message.
//
// The agreement itself is not re-implemented here: it is [arabicCounted], the
// same one the notification clock and the subscription countdown now share.
// This file is only the nouns, plus the two cases that are not counts at all.
//
// Which brings the second defect, and it is the worse one. The profile cover
// printed `'استجابة خلال ${worker.responseTimeHours ?? 0}h'`. The column is
// nullable, and a contractor whose reply speed was never measured — every new
// account — read «استجابة خلال 0h»: the app asserting, as a measured fact on
// the profile a customer picks from, that this man answers instantly. A missing
// measurement is not a measurement. It now says so, or says nothing.
library;

import '../core/l10n/arabic_agreement.dart';

/// «سنة خبرة» / «سنتان خبرة» / «3 سنوات خبرة» / «11 سنة خبرة».
///
/// Null for zero, because «0 سنة خبرة» is a claim about a man who has none
/// rather than a fact about his profile: callers show the line only when
/// [WorkerProfile.experienceYears] is above zero.
String? experienceYearsAr(int years) {
  if (years <= 0) return null;
  return arabicCounted(
    years,
    'سنة خبرة',
    two: 'سنتان خبرة',
    few: 'سنوات خبرة',
  );
}

/// «مشروع منجز» / «مشروعان منجزان» / «3 مشاريع منجزة» / «11 مشروع منجز».
///
/// The participle rides in every form rather than trailing a bare noun, so the
/// line reads «3 مشاريع منجزة» and not «3 مشروع منجز».
String? completedJobsAr(int jobs) {
  if (jobs <= 0) return null;
  return arabicCounted(
    jobs,
    'مشروع منجز',
    two: 'مشروعان منجزان',
    few: 'مشاريع منجزة',
  );
}

/// «تقييم» / «تقييمان» / «3 تقييمات» / «11 تقييم».
///
/// The singular carries no number, so a single review reads «تقييم» on the
/// stats line rather than «1 تقييم».
String? reviewCountAr(int reviews) {
  if (reviews <= 0) return null;
  return arabicCounted(
    reviews,
    'تقييم',
    two: 'تقييمان',
    few: 'تقييمات',
  );
}

/// «30 كم» — the distance this contractor will travel, or null when it was
/// never set.
///
/// **The fourth unmeasured number, and the only one still printing a zero.**
/// [experienceYearsAr] and [completedJobsAr] already drop a zero, and
/// [responseTimeAr] was rewritten last cycle because it printed
/// «استجابة خلال 0h» for every account nobody had ever timed. The service
/// radius was the same defect one row further down the same card:
///
///     value: '${w.serviceRadiusKm} كم',
///
/// The parser gave an absent `service_radius_km` a `0` and this row printed it
/// unconditionally, so a contractor who registered yesterday — and
/// `POST /api/register` sends no radius, there is no screen on the way in that
/// asks for one — published **«نصف قطر الخدمة: 0 كم»** on the profile a customer
/// picks a tradesman from. Zero is the loudest claim in that card: it does not
/// read as missing, it reads as a man who will not travel past his own street.
///
/// Three outcomes, matching [responseTimeAr]:
///
///   * null  — no radius on the payload, or a stored `0`. The caller drops the
///             row entirely rather than print a number nobody set.
///   * 1     — «كيلومتر واحد».
///   * 2+    — the counted kilometres, agreeing with the number.
///
/// The full noun is used rather than the «كم» abbreviation the slider shows.
/// An abbreviation has no dual and no broken plural, so routing it through the
/// rule gives 3 → «3 كم» and 11 → «11 كم» — two arms, two different words, and
/// no way to tell from the string which one is a plural. That is the trap
/// [arabicCounted] exists to make unrepresentable, and it is cheaper to avoid
/// than to explain.

///
/// A stored `0` is folded into null on purpose. The slider's own floor is 1
/// (`Slider(min: 1)`), so this app cannot save a 0; a row carrying one is a
/// server default standing in for an answer, and treating it as «he will not
/// travel» would be reading a default as a decision.
String? serviceRadiusAr(int? km) {
  if (km == null || km <= 0) return null;
  if (km == 1) return 'كيلومتر واحد';
  return arabicCounted(km, 'كيلومتر', two: 'كيلومترين', few: 'كيلومترات');
}

/// How fast the contractor answers, or null when nothing has been measured.
///
/// Three outcomes, never two:
///
///   * null  — no reply has ever been timed. The caller drops the clause.
///   * 0     — a reply was timed and came inside the first hour. «أقل من ساعة»
///             is the only honest reading; «0 ساعة» is a claim nobody can check.
///   * 1+    — the counted hours, in the form the number selects.
String? responseTimeAr(int? hours) {
  if (hours == null) return null;
  if (hours <= 0) return 'أقل من ساعة';
  return arabicCounted(hours, 'ساعة', two: 'ساعتين', few: 'ساعات');
}
