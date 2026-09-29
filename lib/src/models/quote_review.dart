import 'enums.dart' show QuoteStatus;
import 'notification.dart' show parseServerTime;

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

  /// Whether the bid is still on the table, or has been taken or thrown out.
  ///
  /// The Worker sends this on every quote row and this parser used to **drop
  /// it**, so a bid the server had already rejected drew with a live
  /// «قبول العرض» button. Tapping it answers 200 and changes nothing, because
  /// the backend rejected every other bid at the moment the owner accepted
  /// one. The card is byte-for-byte identical before and after the tap, and the
  /// project reads a different `selected_worker_id` than the man on the card —
  /// so the one write in this product that signs a contract looked like it
  /// worked while committing nothing.
  ///
  /// Defaulting to [QuoteStatus.pending] for a missing value is deliberate: the
  /// card stays drawable, and the alternative — hiding a bid the server never
  /// labelled — would remove the contractor from a decision the owner still has
  /// to make.
  final QuoteStatus status;

  /// When the contractor sent this bid, or null when the server sent no
  /// timestamp.
  ///
  /// The sibling of [Review.createdAt], dropped in the same way: the Worker
  /// sends `created_at` on every quote (observed on production, and in the
  /// `POST` answer as well as the `GET`), and this model kept `amount`,
  /// `message`, `estimatedDays` and nothing that said when. A bid sent this
  /// morning and one sent last March drew identically on the one screen where
  /// a customer compares two or three people against each other.
  ///
  /// Read through [parseServerTime] for the same reason every other model on
  /// this wire does: D1 writes UTC with no zone marker, so `tryParse` would
  /// read it as Algiers wall-clock and date the bid an hour early.
  final DateTime? createdAt;

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
    this.status = QuoteStatus.pending,
    this.createdAt,
  });

  /// True when this bid is no longer a decision the owner can make.
  ///
  /// One boolean, read by both call sites, because the card and the list have
  /// to agree: a losing bid has to stop offering a button *and* stop counting
  /// as live. Same rule as `hasPriceRange` — a rule that can only be tested by
  /// pumping a screen is a rule that ships untested.
  bool get isDecided => status != QuoteStatus.pending;

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
        status: QuoteStatus.from(json['status'] as String?),
        createdAt: parseServerTime(json['created_at']),
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

  /// When the customer left the rating, or null when the server sent no
  /// timestamp.
  ///
  /// The Worker sends `created_at` on every review row — it is in the payload
  /// `live_payload_models_test.dart` captured from production, and in every
  /// fixture this app has been driven with — and this parser **dropped it**,
  /// so every review on a contractor's profile drew as an undated card. On the
  /// one page a customer picks a tradesman from, a review left last week and a
  /// review left eight months ago looked identical, which is the difference
  /// between a man whose work kept being good and a man who was good once.
  /// See `data/review_order.dart`.
  ///
  /// Read through [parseServerTime] rather than [DateTime.tryParse], for the
  /// same reason every other model on this wire does: D1 writes
  /// `YYYY-MM-DD HH:MM:SS` in **UTC with no zone marker**, and `tryParse`
  /// would read it as Algiers wall-clock — so the review would be dated an
  /// hour off, and one sent late on the 31st would file itself under the 1st.
  final DateTime? createdAt;

  const Review({
    required this.id,
    required this.projectId,
    required this.workerId,
    required this.rating,
    this.comment,
    required this.images,
    required this.customerFullName,
    this.createdAt,
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
      // Nullable on purpose: a row the server could not date is an absence,
      // and `review_order.dart` puts those last rather than dropping them.
      createdAt: parseServerTime(json['created_at']),
    );
  }
}