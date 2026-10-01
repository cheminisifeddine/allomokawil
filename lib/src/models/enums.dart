/// Role selected at registration. Mirrors `UserType` in the web API.
enum UserRole {
  customer,
  worker,
  admin;

  static UserRole from(String? v) {
    switch (v) {
      case 'worker':
        return UserRole.worker;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.customer;
    }
  }

  String get wire => name;
}

/// Verification state of a worker's identity/certificate docs.
enum VerificationStatus { pending, verified, rejected }

/// Where a contractor's bid stands on the project it was made against.
///
/// Found on 29 Sep 2026, on the live API, driving a real accept. The Worker
/// sends `status` on every quote row (`"pending"`, then `"accepted"` /
/// `"rejected"` the moment the owner commits) and `Quote.fromJson` **dropped
/// it** — the model kept `amount`, `message`, `estimatedDays` and the three
/// `worker_*` trust fields, and threw away the one that says whether this bid
/// is still on the table.
///
/// The three answers the server can send, all observed on production the same
/// minute:
///
///   quote 48 -> `"pending"`    (two contractors bid on one project)
///   accept 48 -> `"accepted"`
///   quote 49 -> `"rejected"`   (the backend rejects every other bid)
///   accept 49 -> `{"ok":true}` — **200, and nothing changed**
///
/// That last line is the defect. The rejected bid is still drawn with a live,
/// enabled «قبول العرض» button, because the app cannot tell it was rejected;
/// the owner taps it, the server answers 200, the screen reloads, and the card
/// is byte-for-byte identical to the one before the tap. The project reads
/// `selected_worker_id: 125` — contractor 125, the bid that *won* — while the
/// card he just tapped offers contractor 126 and says nothing. A customer who
/// taps the losing card believes he hired the other man.
///
/// `pending` is the default because the majority of quotes in a healthy
/// project are pending, and a *missing* status is not evidence that a bid is
/// live — the server has been sending the column since before this file
/// existed. So an absent or unrecognised value answers as "not decided",
/// which keeps the card drawable instead of throwing on a value D1 might add.
enum QuoteStatus {
  pending,
  accepted,
  rejected;

  /// Reads the wire value, refusing to guess about one this app has not seen.
  ///
  /// Anything unknown — including null — is [pending], for the reason in the
  /// type doc: a bid is decided only when the server says it is.
  static QuoteStatus from(String? v) {
    switch (v) {
      case 'accepted':
        return QuoteStatus.accepted;
      case 'rejected':
        return QuoteStatus.rejected;
      default:
        return QuoteStatus.pending;
    }
  }
}
