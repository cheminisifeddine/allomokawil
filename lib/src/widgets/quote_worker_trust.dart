import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/enums.dart';
import '../models/quote_review.dart';
import 'net_image.dart';
import 'ui.dart';

/// The two trust signals the API sends on every quote and the quote card
/// used to print neither: the contractor's **photo** and whether he is
/// **verified**.
///
/// `GET /api/mobile/projects/{id}/quotes` returns
/// `worker_avatar_url` and `worker_verification_status` beside the name.
/// `Quote.fromJson` parses both. The card then drew
/// `InitialAvatar(quote.workerFullName)` — a coloured circle with the first
/// letter — and stopped. So a customer comparing four bids was choosing
/// between four monograms, and **a verified contractor looked exactly like an
/// unverified one**, on the one screen where he is about to hand someone his
/// house. Both fields had three sibling read paths already (the worker's
/// feed card, his profile and the worker list) rendering the same two facts
/// from the same payload.
///
/// Fifth in the same series as `quote_limit`, `portfolio_limit`, the renewal
/// fields and `categories`: the server sends it, the model parses it, the read
/// path drops it. Fixed here by giving the card and the worker card **one**
/// avatar and **one** badge, so the two cannot drift again.
class QuoteWorkerTrust extends StatelessWidget {
  const QuoteWorkerTrust({
    super.key,
    required this.quote,
    this.size = 48,
    this.badgeSize = 17,
  });

  final Quote quote;
  final double size;
  final double badgeSize;

  /// The server sends the raw string; `pending` and `rejected` both mean "not
  /// verified", and an absent field is not a promise. Only a literal
  /// `verified` earns the tick — an unknown value is treated as pending rather
  /// than optimistically true.
  bool get _isVerified => quote.workerVerificationStatus.trim() == 'verified';

  /// `pending` is the server's own word for "asked, not answered", and it is
  /// the state most contractors sit in for days. The customer has to be able
  /// to tell "not yet" from "no".
  bool get _isPending =>
      quote.workerVerificationStatus.trim().isEmpty ||
      quote.workerVerificationStatus.trim() == 'pending';

  @override
  Widget build(BuildContext context) {
    final url = quote.workerAvatarUrl;
    final hasPhoto = url != null && url.trim().isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (hasPhoto)
          ClipOval(
            // The name is printed directly to the right of the photo, so the
            // picture saying its own name again is the same fact read twice.
            child: NetImage(
              url.trim(),
              width: size,
              height: size,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => _monogram(),
            ),
          )
        else
          _monogram(),
        if (_isVerified || _isPending)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isVerified ? Icons.verified_rounded : Icons.schedule_rounded,
                size: badgeSize,
                color: _isVerified ? AppTheme.success : AppTheme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _monogram() => InitialAvatar(name: quote.workerFullName, size: size);
}

/// The badge on its own, for the row where the avatar is the monogram only.
Icon? quoteVerificationIcon(Quote quote, {double size = 17}) {
  final v = quote.workerVerificationStatus.trim();
  if (v == 'verified') {
    return Icon(Icons.verified_rounded, size: size, color: AppTheme.success);
  }
  if (v.isEmpty || v == 'pending') {
    return Icon(Icons.schedule_rounded,
        size: size, color: AppTheme.textSecondary);
  }
  return null;
}

/// Exposed for tests: the enum the model would produce for this wire value.
VerificationStatus quoteWireVerification(String? wire) {
  switch (wire?.trim()) {
    case 'verified':
      return VerificationStatus.verified;
    case 'rejected':
      return VerificationStatus.rejected;
    default:
      return VerificationStatus.pending;
  }
}
