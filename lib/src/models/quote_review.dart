/// A contractor's bid on an open project.
class Quote {
  final int id;
  final String projectId;
  final int workerId;
  final int amount; // DZD, must be >= 1000
  final String? message;
  final int? estimatedDays;
  final String workerFullName;
  final String? workerAvatarUrl;
  /// The score customers gave this contractor, or null when nobody has.
  ///
  /// **Null, not 0.0 — the same sentinel [WorkerProfile.avgRating] refuses.**
  /// `GET /api/mobile/projects/{id}/quotes` sends `worker_avg_rating: 0` for
  /// a contractor with no reviews, which is the server's "not rated yet" marker
  /// rather than a mean: the review form is 1-5, so no set of reviews can
  /// average to zero.
  ///
  /// This field was a non-nullable `double` that folded to `0`, so it read the
  /// *same wire value* the worker model reads as null, and it did so while
  /// [hasRating] — the gate the browse card and the profile use — was deciding
  /// a few lines away. Two models, one payload, two opposite answers about
  /// whether a score exists.
  final double? workerAvgRating;
  final int workerTotalReviews;
  final String workerVerificationStatus;

  const Quote({
    required this.id,
    required this.projectId,
    required this.workerId,
    required this.amount,
    this.message,
    this.estimatedDays,
    required this.workerFullName,
    this.workerAvatarUrl,
    this.workerAvgRating,
    required this.workerTotalReviews,
    required this.workerVerificationStatus,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        id: json['id'] as int,
        projectId: json['project_id'].toString(),
        workerId: json['worker_id'] as int,
        amount: (json['amount'] as num).toInt(),
        message: json['message'] as String?,
        estimatedDays: (json['estimated_days'] as num?)?.toInt(),
        workerFullName:
            (json['worker_full_name'] ?? '') as String,
        workerAvatarUrl: json['worker_avatar_url'] as String?,
        // A stored 0 is the server's "nobody has rated me yet" sentinel, not a
        // score. Folded to null exactly as [WorkerProfile.avgRating] folds it,
        // so both models read one wire value one way.
        workerAvgRating: _rating(json['worker_avg_rating']),
        workerTotalReviews:
            (json['worker_total_reviews'] as num?)?.toInt() ?? 0,
        workerVerificationStatus:
            (json['worker_verification_status'] ?? '') as String,
      );

  /// True when there is a real score to print, as opposed to a `0` the server
  /// sent to mean "nobody has rated me yet".
  ///
  /// Mirrors [WorkerProfile.hasRating] deliberately: the bid card and the
  /// browse card are the two places a customer chooses a tradesman from, and
  /// they must not answer differently about the same man.
  bool get hasRating => workerAvgRating != null;

  /// Null for a missing score and for a `0` the server sent as a sentinel.
  static double? _rating(Object? raw) {
    if (raw is! num) return null;
    final v = raw.toDouble();
    return v > 0 ? v : null;
  }
}

/// A customer's rating + comment left after a job completes.
class Review {
  final int id;
  final String projectId;
  final int workerId;
  final int rating; // 1-5
  final String? comment;
  final List<String> images;
  final String customerFullName;

  const Review({
    required this.id,
    required this.projectId,
    required this.workerId,
    required this.rating,
    this.comment,
    required this.images,
    required this.customerFullName,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    List<String> imgs = const [];
    final raw = json['images'];
    if (raw is List) imgs = raw.map((e) => e.toString()).toList();
    return Review(
      id: json['id'] as int,
      projectId: json['project_id'].toString(),
      workerId: json['worker_id'] as int,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      images: imgs,
      customerFullName:
          (json['customer_full_name'] ?? '') as String,
    );
  }
}