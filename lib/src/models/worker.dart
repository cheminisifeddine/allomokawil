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
  final int serviceRadiusKm;
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
  final double avgRating;
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
    required this.serviceRadiusKm,
    required this.isAvailable,
    required this.verificationStatus,
    this.verificationPendingDocs = 0,
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
      serviceRadiusKm: (json['service_radius_km'] as num?)?.toInt() ?? 0,
      isAvailable: (json['is_available'] as num?)?.toInt() == 1,
      verificationStatus: _vd(json['verification_status'] as String?),
      verificationPendingDocs:
          (json['verification_pending_docs'] as num?)?.toInt() ?? 0,
      avgRating: (json['avg_rating'] as num?)?.toDouble() ?? 0,
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