import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';
import '../data/price_range_copy.dart';
import '../data/review_count.dart';
import '../data/specialty_label.dart';
import '../core/text/monogram.dart';
import '../data/worker_stats_copy.dart';
import '../models/enums.dart';
import '../models/worker.dart';
import 'net_image.dart';
import 'ui.dart';

/// Contractor card — used in the top-rated strip and in browse results.
///
/// `variant: vertical` is the compact column used in horizontal strips, and it
/// only fits if the caller gives it [AppTheme.stripH]: the tallest card this
/// file draws is a paused contractor's, 165 dp of content, and it is clipped
/// rather than shrunk if the box is short. `variant: row` is the full-width
/// list row used in browse, which is unbounded vertically and cannot clip.
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
      width: AppTheme.stripCardW,
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
          // Same answer as the row variant, on the other customer-facing
          // surface. The strip is a fixed 168 dp column, so this is the plain
          // line the years line uses rather than a pill: a Wrap at that width
          // would wrap a second time and push the card out of its 168 dp.
          if (availabilityAr(worker.isAvailable) case final a?) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.pause_circle_filled_rounded,
                    size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(a,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(
                          fontSize: AppTheme.fsBadge,
                          color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Full-width row (browse) ───────────────────────────────────────────
  Widget _row() {
    // Read once, used by the row gate and by both tags. Before this, the gate
    // recomputed the question from the columns while the tags asked the copy
    // helpers, which is how the two surfaces of one man came to disagree about
    // whether he has a price.
    final hasYearsToPrint = experienceYearsAr(worker.experienceYears) != null;
    final hasPriceToPrint = hasPriceRange(worker.priceRangeMin, worker.priceRangeMax);
    // Sixth answer read once, same reason as the two above: the gate and the
    // tag it wraps must not be able to disagree about whether this contractor
    // is taking work. Before this tick the field had no reader on this card at
    // all, so a contractor who paused drew exactly like one who did not.
    final availability = availabilityAr(worker.isAvailable);
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
                // One question, asked once. This gate and the two inside it
                // have to agree, and for a day they did not: this one asked
                // `years > 0 || min != null` while the tags it wraps were
                // already asking [hasPriceRange]. A contractor who typed a
                // single maximum -- `min` empty, `max` real -- therefore got
                // NO price tag at all, on the row a customer picks him from,
                // one line above the fix that shipped for exactly that man.
                // Both arms are read off the function that decides what gets
                // printed rather than off the raw column, so the row cannot be
                // dropped around a tag that exists (the empty-Wrap defect) nor
                // built around a tag that does not.
                if (hasYearsToPrint || hasPriceToPrint || availability != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (availability != null)
                        _MiniTag(
                            icon: Icons.pause_circle_filled_rounded,
                            text: availability),
                      if (experienceYearsAr(worker.experienceYears)
                          case final years?)
                        _MiniTag(
                            icon: Icons.workspace_premium_rounded,
                            text: years),
                      // `hasPriceRange`, not `min != null`: a contractor who
                      // typed a single maximum price had this tag on his profile
                      // and not here, so the row a customer picks him from was
                      // the one missing the price. Same string as the profile
                      // row, minus the dashes the card has always used.
                      if (hasPriceRange(worker.priceRangeMin, worker.priceRangeMax))
                        _MiniTag(
                          icon: Icons.payments_rounded,
                          text: (priceRangeAr(worker.priceRangeMin, worker.priceRangeMax) ?? '')
                              .replaceAll(' - ', '\u2013'),
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
          fontWeight: AppTheme.wStrong,
          color: AppTheme.onNavy,
        ),
      ),
    );
  }
}

/// The three facts a customer scans a contractor for, as pills.
///
/// **Was a hand-rolled pill**, and that was the defect: `symmetric(9, 5)`, a
/// 13 dp icon, a 4 dp gap and `fsBadge`, where the house pill — `MetaChip`,
/// `StatusPill`, `CategoryBadge` — is `AppTheme.pillPad` `symmetric(10, 6)`, a
/// 14 dp icon, `AppTheme.pillGap` and `fsCaption`. Measured off real layout:
/// **25.0 dp tall here, 26.0 there**, same `rPill` radius and the same
/// `lineSoft` wash, on a screen that draws both — the client home column holds
/// this card and `ProjectCard`'s status pills in one scroll.
///
/// Neither instrument could see it, which is why this is a caller now and not
/// a smaller duplicate. `card_recipe_test.dart`'s R4 reads off-grid literals
/// and `9` is one, but R4 is a budget and a single row inside it is invisible
/// to a counter that can only ask "make the count go down"; fixing it for R4
/// would have been a rename. `pill_inset_test.dart` compares three pills that
/// already *were* one component — it cannot see a pill that was spelled out
/// instead of reused, which is exactly what this was.
///
/// The three call sites pass `tone`/`wash` pairs that are the neutral defaults
/// `MetaChip` already carries, so each one now reads as the fact it is and not
/// as a re-declaration of a grey pill: "paused" stays grey, and the years and
/// price tags inherit the same one rather than each choosing their own.
class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniTag({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) =>
      MetaChip(icon: icon, text: text);
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
