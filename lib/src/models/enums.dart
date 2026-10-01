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
///
/// One parser for the whole column, because until 2 Oct this app had **three**
/// and they did not agree. `WorkerProfile` read it through a private `_vd`
/// that did not trim, `Quote` carried it as a raw `String` and the trust
/// widget compared that string to `'verified'` in three separate places, and
/// a fourth copy (`quoteWireVerification`) existed only so a test could reach
/// it. `GET /api/mobile/workers/top` sends `verification_status` (observed
/// live, 2 Oct: `'pending'`) and `GET /api/mobile/projects/{id}/quotes` sends
/// `worker_verification_status` — the same fact, two column names, four
/// readers, no type making them agree.
///
/// The user-visible cost was not theoretical: a padded `' verified '` read as
/// **pending** through [WorkerProfile], so a verified contractor's own home
/// screen said «غير موثّق» and dropped the «مقاول موثّق» pill — while his bid
/// card, going through the string path that trims, drew the green tick at the
/// same moment. Two answers about one man on two screens he opens in the same
/// session. `dossierUnderReview` compounds it: pending is also what
/// [WorkerProfile.verificationPendingDocs] counts against, so a padded
/// verified profile could be told his papers are «قيد المراجعة».
enum VerificationStatus {
  pending,
  verified,
  rejected;

  /// The only string this state may be sent as, and the only string the app
  /// answers it with.
  ///
  /// `=> name`, because every value is a single lowercase word exactly as the
  /// Worker stores it. The getter exists so a future value with a different
  /// spelling has one place to change — see `PlanId.wire` for the case where
  /// it is genuinely needed.
  String get wire => name;

  /// Reads the wire value, or [pending] when the server did not name one this
  /// app knows.
  ///
  /// **Trimmed**, because that was the whole bug: this column arrives padded
  /// from a `JSON_EXTRACT`/D1 row at least as often as it arrives clean, and
  /// the other two readers of it in this app trimmed while this one did not.
  ///
  /// **Pending rather than a throw, for the reason [QuoteStatus.from]
  /// documents**: an absent value is not evidence of anything, and a bid or a
  /// profile the server has not described should still draw. `pending` is the
  /// state that says «asked, not answered», which is the truth when the app
  /// cannot read the answer.
  static VerificationStatus fromWire(String? value) {
    switch (value?.trim()) {
      case 'verified':
        return VerificationStatus.verified;
      case 'rejected':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}

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
