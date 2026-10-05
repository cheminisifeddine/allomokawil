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

/// «لا تقييمات بعد» — the sentence printed in place of a score nobody gave.
///
/// The fifth unmeasured number, and the only one that is a **verdict** rather
/// than a measurement. The first four were about a man's own business: how far
/// he travels ([serviceRadiusAr]), how fast he answers ([responseTimeAr]), how
/// many years ([experienceYearsAr]), how many jobs ([completedJobsAr]). Nobody
/// is defamed by «0 سنة خبرة». They *are* by «0.0» out of five, printed in the
/// app's own voice on the card a customer picks a tradesman from.
///
/// The server sends `avg_rating: 0` to mean "no reviews yet" — the review form
/// is 1–5, so a zero cannot be a mean — and every star row printed it
/// unconditionally. On the live browse payload on 26 Sep that was **15 of 26
/// contractors**, all of them pending verification, all shown five empty stars
/// and «0.0». A new tradesman was being presented as the worst-rated on the
/// platform for the crime of being new.
///
/// So the score is null when it is not real, and the row says what is true:
/// no one has rated him yet. That is a fact about the scoreboard, not a claim
/// about the man.
String noRatingAr() => 'لا تقييمات بعد';

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

/// «متاح الآن» / «غير متاح الآن» — whether this contractor is taking work.
///
/// **The sixth number-to-word gap, and the first of the six that is a
/// decision rather than a measurement.** The first five live above and all of
/// them exist because the app was printing something the server had not said:
/// a zero radius, a zero reply time, a zero star score. This one is the
/// mirror image, and it is worse than the other five, because **the customer
/// path never asked the question at all**.
///
/// `is_available` is a column the worker sets on his own profile — the switch
/// on `profile_edit_screen.dart` writes it through `updateMyProfile`. It is a
/// man saying "I am not taking work right now". Until this tick it was drawn
/// in exactly one place, `_availabilityPill` in `worker_home_screen.dart:1581`,
/// which is **the worker's own home screen**: the man who paused sees a grey
/// «غير متاح» on his own dashboard, and no customer ever does.
///
/// Measured live on 5 Oct 2026, not inferred: `GET /api/mobile/workers/search`
/// returned **97 rows, exactly one with `is_available: 0`** — id 73, a real
/// September signup — and the API **serves it in browse**. Nothing between the
/// payload and the card filters it: `isAvailable` appears in no file under
/// `lib/src/screens/browse/` or `lib/src/screens/customer/`, and the only
/// reader of the field outside the worker-facing screens is the model. So on
/// the one row in the market that is genuinely paused, the customer-facing
/// card drew the same verified avatar, the same stars and the same tap target
/// as a man who is taking work today. He could message it, and quote it, and
/// wait on a reply that its owner has already said will not come.
///
/// That is not a styling omission. Every other state that changes what a
/// customer may *do* with a row is drawn: the verified tick, the price, the
/// radius, the reply speed. Availability is the only one of them that is
/// invisible on the surface where the decision is actually made.
///
/// Why the tag and not the filter — the two are not interchangeable, and this
/// is a deliberate limit, not an omission. **The server does not filter, so
/// the app must draw rather than hide.** Dropping paused contractors from the
/// list would be inventing a market the payload does not describe: browse
/// results are what the API returned, and a customer searching «plombier»
/// for a contractor who is busy until March deserves to see him *and* to know
/// he is busy. The 96 other rows are all available, so the tag is invisible on
/// the overwhelming majority of the market — it costs nothing where it is not
/// true and it is the whole answer where it is.
///
/// One deliberate omission of the badge, and it is the same rule the card
/// already follows for the score: **an available contractor gets no tag.** The
/// default is `is_available = 1` on every row that has never been touched
/// (96 of 97 rows live), so printing «متاح الآن» everywhere would be a wall of
/// green chips that says nothing. The card already made this exact call for
/// stars — a score of 0 is not a rating, and the row is dropped rather than
/// printed — and availability takes the same shape: only the **unusual**
/// state earns ink. «غير متاح» is worth a customer's attention precisely
/// because it is the one answer that is not true of everybody else.
String? availabilityAr(bool isAvailable) => isAvailable ? null : 'غير متاح الآن';
