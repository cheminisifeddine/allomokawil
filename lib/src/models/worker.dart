import 'enums.dart';
import 'row_identity.dart';

/// A contractor's professional profile. Mirrors `WorkerProfile`/`WorkerWithUser`.
class WorkerProfile implements RenderableRow {
  /// A contractor with no readable id cannot be drawn.
  ///
  /// `worker_card` draws every row it is given, and tapping one pushes
  /// `/api/mobile/workers/$id` — so an id this app could not read used to be a
  /// `TypeError` (the row was dropped by `_rows`, and the market lost a card
  /// with an error on screen), and while the parser was being made tolerant it
  /// briefly became `id: 0`: a **real-looking card** whose only possible answer
  /// is a 404. Neither is right, and the two failure modes are what this getter
  /// is the seam between.
  ///
  /// Both ids, not one. `id` opens the profile (`worker_card` ->
  /// `/api/mobile/workers/$id`) and `userId` is what «مراسلة ${fullName}» sends
  /// to the chat screen (`worker_profile_screen.dart:226`) — so a card whose
  /// `user_id` is missing keeps its photo and its name and offers a button that
  /// opens a thread against user 0. A row that cannot be both opened and
  /// answered is not a card.
  ///
  /// A user id this phone has no session for is *not* the test: the browse
  /// directory is full of contractors nobody here is signed in as, and those
  /// rows must draw. 0 is the only unreadable answer, because 0 is the id a row
  /// nobody stated resolves to.
  @override
  bool get isRenderable => id > 0 && userId > 0;

  final int id;
  final int userId;
  final String fullName;
  final String? bio;
  final List<String> specialties;
  final int experienceYears;
  final int? priceRangeMin;
  final int? priceRangeMax;
  /// How far this contractor will travel, in km.
  ///
  /// **Null means never set, and null is not zero.** `POST /api/register` sends
  /// no `service_radius_km` at all — a contractor cannot reach the slider on
  /// the edit screen without first building a profile — so a brand-new account
  /// arrives here with the field absent, the parser turned it into `0`, and
  /// the public profile printed «نصف قطر الخدمة: 0 كم». That is the app
  /// claiming a measurement about a man's own business that nobody ever made:
  /// he has not said he will not travel anywhere, he has not answered.
  ///
  /// The same shape as [responseTimeHours], and the fix is the same: an absent
  /// measurement stays null all the way to the screen, which then has to decide
  /// what to say. The slider's own floor is 1, so 0 is not a value this app can
  /// produce either — a stored 0 is a server default and is read as unset.
  final int? serviceRadiusKm;
  final bool isAvailable;
  final VerificationStatus verificationStatus;
  /// How many documents are sitting in the admin queue for this profile.
  ///
  /// `verificationStatus` cannot answer "did my documents arrive?" on its own:
  /// a brand-new profile is stored as 'pending', exactly like a submitted
  /// dossier. Without this count the UI has to guess, and it guesses wrong in
  /// both directions (empty form for a man who uploaded everything, false
  /// "under review" for a man who uploaded nothing).
  final int verificationPendingDocs;
  /// Whether the identity half of the dossier (ID card + selfie) has already
  /// been accepted by a reviewer.
  ///
  /// `verificationStatus` is all-or-nothing: documents are approved one row at
  /// a time and the profile only flips to 'verified' once every row is
  /// approved. In between, a contractor whose ID was accepted and whose
  /// contractor card was refused saw the same blank form as a man who had sent
  /// nothing — the API was sending both flags and the app threw them away.
  final bool identityVerified;
  /// Whether the documents half (contractor card + certificates) has been
  /// accepted. See [identityVerified].
  final bool certificateVerified;
  /// The score customers gave this contractor, or null when nobody has.
  ///
  /// **Null, not 0.0, and this one is the loudest of the four.** The other
  /// unmeasured numbers were about the man's own business — how far he
  /// travels, how fast he answers, how many years he has done this. This one
  /// is a verdict about him, printed on the exact card a customer picks a
  /// tradesman from. The server sends `avg_rating: 0` for a contractor with no
  /// reviews (15 of the 26 in the live browse payload, checked 26 Sep), and
  /// every star row printed that `0` unconditionally: five empty stars, the
  /// score **«0.0»**, and «(0)» beside it.
  ///
  /// Zero is not a rating anybody gave. The review form is 1–5, so a stored 0
  /// is the server's "no reviews yet" sentinel, not the mean of a set — the
  /// same reading a stored `0` radius gets in [serviceRadiusKm]. A customer
  /// scrolling browse was told, in the app's own voice, that this man is the
  /// worst-rated tradesman on the platform when the truth is that nobody has
  /// worked with him yet, which is a different thing to say and a fairer one.
  ///
  /// The screens answer with «لا تقييمات بعد» — the sentence
  /// [WorkerProfile.hasRating] gates on — rather than a score.
  final double? avgRating;
  final int totalReviews;
  final int totalCompletedJobs;
  final int? responseTimeHours;
  final String? coverImageUrl;
  final String? avatarUrl;
  final String? wilaya;
  final String? commune;

  const WorkerProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    this.bio,
    required this.specialties,
    required this.experienceYears,
    this.priceRangeMin,
    this.priceRangeMax,
    this.serviceRadiusKm,
    required this.isAvailable,
    required this.verificationStatus,
    this.verificationPendingDocs = 0,
    this.identityVerified = false,
    this.certificateVerified = false,
    required this.avgRating,
    required this.totalReviews,
    required this.totalCompletedJobs,
    this.responseTimeHours,
    this.coverImageUrl,
    this.avatarUrl,
    this.wilaya,
    this.commune,
  });

  factory WorkerProfile.fromJson(Map<String, dynamic> json) {
    final raw = json['specialties'];
    List<String> specs = const [];
    if (raw is List) {
      specs = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      specs = (raw.replaceAll('[', '')
              .replaceAll(']', '')
              .replaceAll('"', '')
              .split(','))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return WorkerProfile(
      // Read, never cast — see [isRenderable] and [RenderableRow]. `id` is the
      // argument to `/api/mobile/workers/$id`, so an id this app cannot read is
      // a profile it cannot open; 0 is visibly wrong rather than a row that
      // took the whole card with it. [isRenderable] is what keeps that visible
      // wrong out of the market.
      id: _int(json['id']),
      userId: _int(json['user_id']),
      // A person's name is copy: trimmed, and **never** flattened into digits,
      // because `worker_card` and `worker_profile_screen` draw it as a name.
      // An unreadable one is empty, and the profile header already answers an
      // empty name with «حرفي» (`worker_profile_screen.dart:404`).
      fullName: _text(json['full_name'] ?? json['name']) ?? '',
      bio: _text(json['bio']),
      specialties: specs,
      experienceYears: _nullableInt(json['experience_years']) ?? 0,
      priceRangeMin: _nullableInt(json['price_range_min']),
      priceRangeMax: _nullableInt(json['price_range_max']),
      // Null, not 0: see [serviceRadiusKm]. A radius nobody has set is not a
      // radius of nothing.
      serviceRadiusKm: _nullableInt(json['service_radius_km']),
      isAvailable: _flag(json['is_available']),
      // A key, with its own fallback in the enum table. `_wireText` keeps a
      // number a number-as-text so `fromWire` still lands on pending — it can
      // never be a status this app will not recognise.
      verificationStatus:
          VerificationStatus.fromWire(_wireText(json['verification_status'])),
      verificationPendingDocs:
          _nullableInt(json['verification_pending_docs']) ?? 0,
      identityVerified: _flag(json['is_identity_verified']),
      certificateVerified: _flag(json['is_certificate_verified']),
      // A stored 0 is the server's "never rated" sentinel, not a mean: see
      // [avgRating]. Folded to null here so no caller can print it by accident.
      avgRating: _rating(json['avg_rating']),
      totalReviews: _nullableInt(json['total_reviews']) ?? 0,
      totalCompletedJobs: _nullableInt(json['total_completed_jobs']) ?? 0,
      responseTimeHours: _nullableInt(json['response_time_hours']),
      // A URL, or no image. `worker_card._Avatar` only checks null and empty,
      // so anything non-empty that is not a string would be handed to
      // `NetImage` as a URL — a number reaching an image loader is not a
      // picture, it is a red error box on the card.
      coverImageUrl: _text(json['cover_image_url']),
      avatarUrl: _text(json['avatar_url']),
      // A **code**, not copy, so `_wireText` and not `_text`: a code is an
      // identifier, and `16` and `"16"` are the same claim about the same
      // wilaya — JSON has no rule requiring an identifier to be quoted, and D1
      // returns it quoted only because SQLite stores every column as text.
      // `project.dart` reads its own `wilaya` the same way.
      //
      // The lie this must still refuse is flattening something that is *not* a
      // code — a name, a sentence, a column that drifted. Those draw nothing at
      // all, because `Taxonomy.wilayaNameOrNull` answers null for a code it
      // does not know and the card then draws no chip.
      wilaya: _wireText(json['user_wilaya'] ?? json['wilaya']),
      // Copy: the edit form seeds its commune box with this
      // (`profile_edit_screen.dart`), so a number here is a number typed into
      // a place.
      commune: _text(json['commune']),
    );
  }

  /// True only when documents have really been filed and are awaiting review.
  /// Single source of truth for the verification screen and the two home
  /// surfaces, so they can never disagree about the same profile.
  bool get dossierUnderReview =>
      verificationStatus == VerificationStatus.pending &&
      verificationPendingDocs > 0;

  /// True once a contractor has something to show for himself — a finished job
  /// or a review. Until then a rating and a job count are both zeroes, which is
  /// not information but a verdict; the home screens show him the next step
  /// instead of his own empty scoreboard.
  bool get hasHistory => totalCompletedJobs > 0 || totalReviews > 0;

  /// True when there is a real score to print, as opposed to a `0` the server
  /// sent to mean "nobody has rated me yet".
  ///
  /// Single source of truth for the four surfaces that print a star row — the
  /// two browse-card variants, the public profile cover and the contractor's
  /// own stats line — so they cannot disagree about the same profile.
  bool get hasRating => avgRating != null;

  /// Null for a missing score and for a `0` the server sent as a sentinel.
  static double? _rating(Object? raw) {
    if (raw is! num) return null;
    final v = raw.toDouble();
    return v > 0 ? v : null;
  }
}

/// An integer column, tolerant of the two shapes D1 really answers with.
///
/// `_asInt` in `data/repository.dart` names them in its own words: a null from
/// a LEFT JOIN, a string from SQLite. `/api/mobile/workers` is a joined query —
/// it carries `user_wilaya`, `commune` and `wilaya_name` from the users table —
/// so the string form is not hypothetical, it is what a joined column does.
///
/// 0 when neither, and 0 on `id` is a row nobody should draw: it is plainly
/// wrong, which beats an exception that also drew nothing but took the whole
/// card with it.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// An integer that stays null when the field is absent or unreadable, so the
/// caller must choose a default instead of inheriting one by accident.
///
/// Every nullable measurement here depends on this: [WorkerProfile
/// .serviceRadiusKm] and [WorkerProfile.avgRating] are *absent answers* rather
/// than zeros, and a fabricated 0 in either one prints «نصف قطر الخدمة: 0 كم» or
/// «0.0 من 5» about a man who was never asked.
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A 0/1 flag, as a bool.
///
/// **Two shapes are real, and one of them is this app's own write.** The three
/// flags — `is_available`, `is_identity_verified`, `is_certificate_verified` —
/// are stored as SQLite integers, and every D1 read has been 0/1 so far. But
/// `repository.updateMyProfile` sends `'is_available': isAvailable` as a **JSON
/// bool** (`repository.dart:173`), so the profile the app writes is read back
/// through this parser by `ProfileSnapshot` on the very next read. Under the
/// old `(x as num?)?.toInt() == 1` a bool threw, and a thrown read is a row
/// `repository._rows` drops — the save screen would have reported "saved" over a
/// contractor who had just vanished from his own directory.
///
/// Truthiness is not used: `1` is true, `'1'` is true, `'true'` is true,
/// `0`/`'0'`/`false`/`null`/`''` are false, and **anything else is false**. An
/// unreadable flag is false because both false readings of the three here are
/// the safe ones: a contractor the app believes is unverified is shown his
/// dossier form, and one it believes is unavailable is offered, rather than a
/// verified badge or an available status nobody confirmed.
bool _flag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return false;
    if (v == '1' || v == 'true') return true;
    return int.tryParse(v) != null && int.tryParse(v) != 0;
  }
  return false;
}

/// A wire value as text, for a **key** column: a status name, a wilaya code.
///
/// Interpolation prints the literal «null» for an absent key, and «null» is a
/// string the verification table has never heard of — so it lands on exactly
/// the fallback an absent key gets. `''` is that fallback too, and neither can
/// become a status this app will not recognise.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Copy, trimmed, or null when absent/empty/not a string.
///
/// No flattening: a number is not a sentence somebody wrote, and every caller
/// here already has the honest answer for «there is nothing here» — the header
/// draws «حرفي» for an empty name, and a bio that is not a sentence is a bio
/// that is not drawn.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}
