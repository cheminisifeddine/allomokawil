import 'enums.dart' show QuoteStatus, VerificationStatus;
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
  /// Whether the contractor who sent this bid has been verified.
  ///
  /// **This was a raw `String`** and the app compared it to `'verified'` in
  /// three places, each of which had to remember to `.trim()` first. It is an
  /// enum now, parsed once by [VerificationStatus.fromWire] at the model
  /// boundary, so a fourth reader cannot be written that forgets.
  final VerificationStatus workerVerificationStatus;

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
        id: _int(json['id']),
        projectId: _wireText(json['project_id']),
        workerId: _int(json['worker_id']),
        amount: _int(json['amount']),
        message: _text(json['message']),
        estimatedDays: _nullableInt(json['estimated_days']),
        workerFullName:
            _text(json['worker_full_name']) ?? '',
        workerAvatarUrl: _text(json['worker_avatar_url']),
        // A stored 0 is the server's "nobody has rated me yet" sentinel, not a
        // score. Folded to null exactly as [WorkerProfile.avgRating] folds it,
        // so both models read one wire value one way.
        workerAvgRating: _rating(json['worker_avg_rating']),
        workerTotalReviews: _nullableInt(json['worker_total_reviews']) ?? 0,
        // Parsed here rather than carried as a String: the trust widget drew
        // the green tick off a trimmed compare while [WorkerProfile] read the
        // same fact off an untrimmed one, so a padded row made two screens
        // disagree about the same man.
        workerVerificationStatus: VerificationStatus.fromWire(
            _wireText(json['worker_verification_status'])),
        status: QuoteStatus.from(_wireText(json['status'])),
        createdAt: parseServerTime(json['created_at']),
      );

  /// True when there is a real score to print, as opposed to a `0` the server
  /// sent to mean "nobody has rated me yet".
  ///
  /// Mirrors [WorkerProfile.hasRating] deliberately: the bid card and the
  /// browse card are the two places a customer chooses a tradesman from, and
  /// they must not answer differently about the same man.
  bool get hasRating => workerAvgRating != null;

  /// True when [amount] is a price somebody actually typed.
  ///
  /// **The bid's own floor is 1000 DZD** — `submitQuote` refuses less
  /// ([DzNumber.tryParse] with `min: 1000`), and the server's own validator
  /// refuses it too — so on this row a 0 is never a real price: it is the
  /// reader's answer for a column it could not read. The card prints
  /// «المبلغ: 0 دج» for it otherwise, which is the one line on this screen
  /// that would be an outright lie rather than a missing fact.
  ///
  /// The reader cannot decide this on its own, because 0 is the right answer
  /// for an id and the wrong answer for a price — which is the whole of the
  /// "the caller decides the fallback" rule this file was rebuilt on.
  bool get amountIsReal => amount >= _minAmount;

  /// The lowest price a bid may carry, mirroring the validator on the write
  /// path. Named here rather than inlined so the card and this getter cannot
  /// drift apart on what counts as a price.
  static const int _minAmount = 1000;

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

  /// True when [rating] is a score somebody actually chose.
  ///
  /// The review form is 1-5 (`createReview` sends what the stars collected), so
  /// no set of real reviews can average to zero and a 0 here is the reader's
  /// answer for a column it could not read. `RatingStars` clamps whatever it
  /// is given, so the alternative is a row of five empty stars beside a
  /// customer's name: a review that says the man did badly work, on a card
  /// whose whole job is to say whether he did good work.
  bool get ratingIsReal => rating >= 1 && rating <= 5;

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
      id: _int(json['id']),
      projectId: _wireText(json['project_id']),
      workerId: _int(json['worker_id']),
      rating: _int(json['rating']),
      comment: _text(json['comment']),
      images: imgs,
      customerFullName:
          _text(json['customer_full_name']) ?? '',
      // Nullable on purpose: a row the server could not date is an absence,
      // and `review_order.dart` puts those last rather than dropping them.
      createdAt: parseServerTime(json['created_at']),
    );
  }
}// ---- reading the payload, not casting it -----------------------------------
//
// The same four readers `chat.dart`, `notification.dart` and `project.dart`
// keep, deliberately the same code: four files that each grew their own
// version of "how do we read a column" is how they drift apart, and the drift
// is invisible — a tolerant field in one model and a throwing one in the next
// is the same defect the audit found four times. Each stays private to its
// file, so a model cannot quietly borrow another model's leniency.

/// An integer column, tolerant of the two shapes D1 really answers with.
///
/// `_asInt` in `data/repository.dart` names them: a number from a JSON body, a
/// string from SQLite. 0 when neither.
///
/// **0 here is the honest floor, and the callers are what make it safe.** Two
/// of the three int columns on this row are ids that are only ever handed back
/// to the server (`acceptQuote(projectId, q.id)`), so a bid the app could not
/// identify answers 404 rather than accepting somebody else's bid — a visible
/// no-op, not a wrong contract. The third is `amount`, and a fabricated 0 is
/// printed as «المبلغ: 0 دج»: the one line on this card that would be a lie.
/// It is guarded by [amountIsReal] below rather than by the reader, because
/// only the card knows it is drawing a price.
int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

/// An integer that stays null when the field is absent or unreadable, so the
/// caller must choose a default instead of inheriting one by accident.
///
/// Both `estimated_days` and the review count use this. A 0 for a duration
/// would print «مدة الإنجاز: 0 يوم» — a promise the contractor never made — and
/// `quoteDurationLineAr` already treats null as "say nothing at all".
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A wire value as text, for a **key** column: a project id, a status name, a
/// verification state.
///
/// Interpolation prints the literal «null» for an absent key, and «null» is a
/// name neither table has heard of — so both land on their own fallback, which
/// is what an absent key gets anyway. Flattening a real number is right here
/// and only here: these are identifiers, not sentences.
///
/// Both callers take a `String?` and already answer every unknown value the
/// way this reader does, so nothing is invented here.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Copy, trimmed, or null when absent/empty/not a string.
///
/// **No flattening, unlike `_wireText`** — and the reason is the caller again.
/// `message` and `comment` are the contractor's and the customer's own words:
/// a number is not a sentence, and `_text` returning null makes the card leave
/// the block undrawn rather than print «5». `worker_avatar_url` is a URL fed
/// to `NetImage`, where a flattened number would be a request to a host that
/// does not exist; null falls back to the monogram the widget already draws.
/// The name uses `?? ''` because `Monogram.of` answers an empty string with
/// «؟» and the profile card has its own «زبون» for a nameless customer.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}
