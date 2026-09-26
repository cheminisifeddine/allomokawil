import 'enums.dart';

/// A contractor's professional profile. Mirrors `WorkerProfile`/`WorkerWithUser`.
class WorkerProfile {
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
      id: json['id'] as int,
      userId: json['user_id'] as int,
      fullName: (json['full_name'] ?? json['name'] ?? '') as String,
      bio: json['bio'] as String?,
      specialties: specs,
      experienceYears: (json['experience_years'] as num?)?.toInt() ?? 0,
      priceRangeMin: (json['price_range_min'] as num?)?.toInt(),
      priceRangeMax: (json['price_range_max'] as num?)?.toInt(),
      // Null, not 0: see [serviceRadiusKm]. A radius nobody has set is not a
      // radius of nothing.
      serviceRadiusKm: (json['service_radius_km'] as num?)?.toInt(),
      isAvailable: (json['is_available'] as num?)?.toInt() == 1,
      verificationStatus: _vd(json['verification_status'] as String?),
      verificationPendingDocs:
          (json['verification_pending_docs'] as num?)?.toInt() ?? 0,
      identityVerified: (json['is_identity_verified'] as num?)?.toInt() == 1,
      certificateVerified:
          (json['is_certificate_verified'] as num?)?.toInt() == 1,
      // A stored 0 is the server's "never rated" sentinel, not a mean: see
      // [avgRating]. Folded to null here so no caller can print it by accident.
      avgRating: _rating(json['avg_rating']),
      totalReviews: (json['total_reviews'] as num?)?.toInt() ?? 0,
      totalCompletedJobs: (json['total_completed_jobs'] as num?)?.toInt() ?? 0,
      responseTimeHours: (json['response_time_hours'] as num?)?.toInt(),
      coverImageUrl: json['cover_image_url'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      wilaya: (json['user_wilaya'] ?? json['wilaya']) as String?,
      commune: json['commune'] as String?,
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

  static VerificationStatus _vd(String? v) {
    switch (v) {
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}