import 'package:flutter/material.dart';

import '../core/format/money.dart';
import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
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
          Row(
            children: [
              RatingStars(rating: worker.avgRating, size: 14),
              const SizedBox(width: 3),
              Flexible(
                child: Text('(${worker.totalReviews})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontSize: AppTheme.fsBadge)),
              ),
            ],
          ),
          if (worker.experienceYears > 0) ...[
            const SizedBox(height: 6),
            Text('${worker.experienceYears} سنة خبرة',
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
                Row(
                  children: [
                    RatingStars(
                        rating: worker.avgRating,
                        count: worker.totalReviews,
                        size: 14),
                    if (worker.wilaya != null &&
                        worker.wilaya!.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.location_on_rounded,
                          size: 13, color: AppTheme.textMuted),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          Taxonomy.wilayaName(worker.wilaya!),
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
                      if (worker.experienceYears > 0)
                        _MiniTag(
                            icon: Icons.workspace_premium_rounded,
                            text: '${worker.experienceYears} سنة خبرة'),
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

  static String _specialtyLabel(WorkerProfile w) {
    if (w.specialties.isEmpty) return 'حرفي';
    return w.specialties
        .map((s) => Taxonomy.categoryName(s))
        .take(2)
        .join(' · ');
  }
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
    final name = worker.fullName.trim();
    final initial =
        name.isEmpty ? '؟' : String.fromCharCode(name.runes.first);
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
