import 'package:flutter/material.dart';

import '../core/format/money.dart';
import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
import '../data/review_count.dart';
import '../data/specialty_label.dart';
import '../core/text/monogram.dart';
import '../data/worker_stats_copy.dart';
import '../models/enums.dart';
import '../models/worker.dart';
import 'net_image.dart';
import 'rating_stars.dart';

/// Contractor card — used in the top-rated strip and in browse results.
///
/// `variant: vertical` is the compact 168px column used in horizontal strips;
/// `variant: row` is the full-width list row used in browse.
enum WorkerCardVariant { vertical, row }

class WorkerCard extends StatelessWidget {
  final WorkerProfile worker;
  final VoidCallback? onTap;
  final WorkerCardVariant variant;

  const WorkerCard({
    super.key,
    required this.worker,
    this.onTap,
    this.variant = WorkerCardVariant.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return variant == WorkerCardVariant.vertical
        ? _vertical()
        : _row();
  }

  // ── Vertical (strip) ──────────────────────────────────────────────────
  Widget _vertical() {
    return _Pressable(
      onTap: onTap,
      width: 172,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(worker: worker, size: 46),
              const Spacer(),
              if (worker.verificationStatus == VerificationStatus.verified)
                const Icon(Icons.verified_rounded,
                    size: 19, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            worker.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.label,
          ),
          const SizedBox(height: 3),
          Text(
            _specialtyLabel(worker),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
          const SizedBox(height: 8),
          // No score, no stars. The server sends 0 to mean "never rated" and a
          // 0 is not a thing the 1-5 review form can produce, so printing five
          // empty stars and «0.0» was telling a customer this new tradesman is
          // the worst on the platform. The row is dropped entirely: an empty
          // line is quieter than a verdict nobody earned.
          if (worker.hasRating)
            Row(
              children: [
                RatingStars(rating: worker.avgRating!, size: 14),
                const SizedBox(width: 3),
                // Same rule as the row variant and the bid card: a count of
                // zero is the absence of a count, and this card has a real
                // score above it. See [printableReviewCount].
                if (printableReviewCount(worker.totalReviews) case final n?) ...[
                  Flexible(
                    child: Text('($n)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge)),
                  ),
                ],
              ],
            )
          else
            Text(noRatingAr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge)),
          if (experienceYearsAr(worker.experienceYears) case final years?) ...[
            const SizedBox(height: 6),
            Text(years,
                style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge)),
          ],
        ],
      ),
    );
  }

  // ── Full-width row (browse) ───────────────────────────────────────────
  Widget _row() {
    return _Pressable(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(worker: worker, size: 58),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        worker.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.h2.copyWith(fontSize: AppTheme.fsLead),
                      ),
                    ),
                    if (worker.verificationStatus ==
                        VerificationStatus.verified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded,
                          size: 17, color: AppTheme.success),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _specialtyLabel(worker),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodySoft.copyWith(fontSize: AppTheme.fsMeta),
                ),
                const SizedBox(height: 8),
                // Same rule as the vertical card: a score of 0 from the server
                // is "never rated", not a rating. See [WorkerProfile.avgRating].
                // The wilaya chip shares this row, so it is kept either way —
                // dropping the score must not cost the card its location.
                Row(
                  children: [
                    if (worker.hasRating)
                      RatingStars(
                          rating: worker.avgRating!,
                          count: worker.totalReviews,
                          size: 14)
                    else
                      Flexible(
                        child: Text(noRatingAr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption),
                      ),
                    // Gate on the *resolved* name, not on a non-empty string:
                    // a contractor whose `user_wilaya` is a code this build does
                    // not know used to have the chip removed and «الجزائر»
                    // printed in its place, so he appeared to work in the
                    // capital from every wilaya. The chip is simply absent.
                    if (Taxonomy.wilayaNameOrNull(worker.wilaya) != null) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.location_on_rounded,
                          size: 13, color: AppTheme.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          Taxonomy.wilayaNameOrNull(worker.wilaya)!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption,
                        ),
                      ),
                    ],
                  ],
                ),
                if (worker.experienceYears > 0 ||
                    worker.priceRangeMin != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (experienceYearsAr(worker.experienceYears)
                          case final years?)
                        _MiniTag(
                            icon: Icons.workspace_premium_rounded,
                            text: years),
                      if (worker.priceRangeMin != null)
                        _MiniTag(
                          icon: Icons.payments_rounded,
                          text: worker.priceRangeMax != null
                              ? '${Money.amountOnly(worker.priceRangeMin!)}–${Money.dzd(worker.priceRangeMax!)}'
                              : 'من ${Money.dzd(worker.priceRangeMin!)}',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The rule lives in [SpecialtyLabel] so both variants and any future
  // surface print the same line. It used to be `take(2)` with no ellipsis,
  // which silently deleted a contractor's third trade from the one line on
  // the card that exists to name his trades.
  static String _specialtyLabel(WorkerProfile w) =>
      SpecialtyLabel.of(w.specialties);
}

class _Avatar extends StatelessWidget {
  final WorkerProfile worker;
  final double size;
  const _Avatar({required this.worker, required this.size});

  @override
  Widget build(BuildContext context) {
    if (worker.avatarUrl != null && worker.avatarUrl!.isNotEmpty) {
      return ClipOval(
        // The card prints the name right beside the photo; the photo saying its
        // own name too is the same fact read twice.
        child: NetImage(
          worker.avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => _initials(),
        ),
      );
    }
    return _initials();
  }

  Widget _initials() {
    final initial = Monogram.of(worker.fullName);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.navy,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: AppTheme.monogram(size, ratio: 0.4),
          fontWeight: FontWeight.w700,
          color: AppTheme.onNavy,
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.lineSoft,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(text,
              style: AppTheme.caption.copyWith(
                  fontSize: AppTheme.fsBadge, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _Pressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? width;

  const _Pressable({required this.child, this.onTap, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          onTap: onTap,
          child: Container(
            padding: AppTheme.cardPad,
            decoration: AppTheme.cardDecoration,
            child: child,
          ),
        ),
      ),
    );
  }
}
