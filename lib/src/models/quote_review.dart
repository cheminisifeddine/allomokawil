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
  final double workerAvgRating;
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
    required this.workerAvgRating,
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
        workerAvgRating:
            (json['worker_avg_rating'] as num?)?.toDouble() ?? 0,
        workerTotalReviews:
            (json['worker_total_reviews'] as num?)?.toInt() ?? 0,
        workerVerificationStatus:
            (json['worker_verification_status'] ?? '') as String,
      );
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