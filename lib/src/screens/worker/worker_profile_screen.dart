import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../data/worker_stats_copy.dart';
import '../../models/enums.dart';
import '../../models/quote_review.dart';
import '../../models/worker.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../auth/auth_screen.dart';
import '../chat/chat_screen.dart';
import '../../core/l10n/error_copy.dart';

/// Public contractor profile: bio, specialties, price range, portfolio
/// gallery, reviews + contact.
///
/// Portfolio-style layout: navy cover header, key facts, gallery grid and a
/// sticky contact CTA. Behaviour (repository calls, chat navigation) is
/// unchanged — only the presentation moved onto the shared UI kit.
class WorkerProfileScreen extends StatefulWidget {
  final int workerId;
  const WorkerProfileScreen({super.key, required this.workerId});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  late final Repository _repo;
  late Future<WorkerProfile> _profile;
  late final Future<List<Review>> _reviews;
  late final Future<List<String>> _portfolio;

  bool _scopeReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _profile = _repo.getWorker(widget.workerId);
    _reviews = _repo.workerReviews(widget.workerId);
    _portfolio = _repo.portfolioImages(widget.workerId);
  }

  void _retry() {
    setState(() => _profile = _repo.getWorker(widget.workerId));
  }

  void _openChat(WorkerProfile w) {
    // A visitor with no account may read a profile; opening a conversation is
    // the one thing here that needs an identity to attach the thread to.
    if (!AppScope.of(context).auth.isAuthenticated) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AuthScreen(mode: AuthMode.signUp, role: UserRole.worker)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
              projectId: null,
              otherUserId: w.userId,
              otherName: w.fullName,
              repo: _repo,
            )));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkerProfile>(
      future: _profile,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final worker = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'ملف المقاول',
              style: AppTheme.bar,
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: loading || (!snap.hasError && worker == null)
                  ? const Shimmer(child: _ProfileSkeleton())
                  : snap.hasError
                      ? EmptyView(
                          icon: Icons.error_outline_rounded,
                          title: 'تعذّر تحميل الملف',
                          message: errorCopy(snap.error),
                          actionLabel: 'إعادة المحاولة',
                          onAction: _retry,
                          danger: true,
                        )
                      : _body(snap.requireData),
            ),
          ),
          // Primary action never sits below the fold.
          bottomNavigationBar: (!loading && worker != null)
              ? StickyCta(
                  child: PrimaryButton(
                    label: 'مراسلة ${worker.fullName}',
                    icon: Icons.chat_outlined,
                    onPressed: () => _openChat(worker),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _body(WorkerProfile w) {
    final slug = w.specialties.isNotEmpty ? w.specialties.first : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        _CoverHeader(worker: w),
        if (w.bio != null && w.bio!.trim().isNotEmpty) ...[
          const SectionTitle('نبذة', icon: Icons.notes_rounded),
          AppCard(child: Text(w.bio!, style: AppTheme.body)),
        ],
        const SectionTitle('التخصصات', icon: Icons.workspace_premium_rounded),
        _Specialties(worker: w),
        const SectionTitle('تفاصيل العمل', icon: Icons.fact_check_rounded),
        _WorkFacts(worker: w),
        const SectionTitle('معرض الأعمال', icon: Icons.photo_library_rounded),
        _PortfolioGrid(
          portfolio: _portfolio,
          slug: slug,
          onContact: () => _openChat(w),
        ),
        const SectionTitle('التقييمات', icon: Icons.star_rounded),
        _ReviewsSection(reviews: _reviews, onContact: () => _openChat(w)),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Cover header
// ─────────────────────────────────────────────────────────────────────────

class _CoverHeader extends StatelessWidget {
  final WorkerProfile worker;
  const _CoverHeader({required this.worker});

  /// The one caption under the rating pill: what he has finished, and how fast
  /// he answers.
  ///
  /// Null when there is nothing true to say. The old line was
  /// `'${worker.totalCompletedJobs} مشروع منجز • استجابة خلال ${worker
  /// .responseTimeHours ?? 0}h'`, which printed two claims a new account
  /// cannot support: «0 مشروع منجز» and «استجابة خلال 0h» — the second one
  /// asserting, on the profile a customer picks from, that a man who has never
  /// answered anyone answers within an hour. A clause that is not measured is
  /// dropped, not zeroed.
  String? get coverTail {
    final parts = <String>[
      if (completedJobsAr(worker.totalCompletedJobs) case final jobs?) jobs,
      if (responseTimeAr(worker.responseTimeHours) case final reply?)
        'استجابة خلال $reply',
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final cover = worker.coverImageUrl;
    final hasCover = cover != null && cover.isNotEmpty;
    final verified = worker.verificationStatus == VerificationStatus.verified;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rXl),
      child: Stack(
        children: [
          Positioned.fill(
            child: hasCover
                ? NetImage(
                    cover,
                    semanticLabel: 'صورة غلاف الملف',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: AppTheme.navy),
                  )
                : const ColoredBox(color: AppTheme.navy),
          ),
          // Scrim keeps the white text readable over any cover photo.
          Positioned.fill(
            child: ColoredBox(
                color: AppTheme.navyDeep.withValues(alpha: 0.55)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // White ring separates the navy avatar from the cover.
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppTheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: InitialAvatar(name: worker.fullName, size: 58),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worker.fullName.isEmpty ? 'حرفي' : worker.fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.h1
                                .copyWith(fontSize: AppTheme.fsBar, color: AppTheme.onNavy),
                          ),
                          if (verified) ...[
                            const SizedBox(height: 8),
                            const StatusPill(
                                label: 'مقاول موثّق',
                                color: AppTheme.success,
                                wash: AppTheme.successWash,
                                icon: Icons.verified_rounded),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // White pill: RatingStars paints dark text, which would be
                // invisible straight onto the navy cover.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: RatingStars(
                      rating: worker.avgRating,
                      count: worker.totalReviews,
                      size: 15),
                ),
                if (coverTail case final tail?) ...[
                  const SizedBox(height: 12),
                  Text(
                    tail,
                    style: AppTheme.caption.copyWith(
                        fontSize: AppTheme.fsCaption, color: AppTheme.onNavyMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Specialties + key facts
// ─────────────────────────────────────────────────────────────────────────

class _Specialties extends StatelessWidget {
  final WorkerProfile worker;
  const _Specialties({required this.worker});

  @override
  Widget build(BuildContext context) {
    if (worker.specialties.isEmpty) {
      return const Text('غير محدد', style: AppTheme.bodySoft);
    }
    // Wrap, never Row: specialty labels are long and would overflow.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in worker.specialties) CategoryBadge(slug: s),
      ],
    );
  }
}

class _WorkFacts extends StatelessWidget {
  final WorkerProfile worker;
  const _WorkFacts({required this.worker});

  @override
  Widget build(BuildContext context) {
    final w = worker;
    final hasWilaya = w.wilaya != null && w.wilaya!.isNotEmpty;
    return AppCard(
      child: Column(
        children: [
          InfoRow(
            icon: Icons.workspace_premium_rounded,
            label: 'الخبرة',
            value: experienceYearsAr(w.experienceYears) ?? 'لم يُسجّل بعد',
            color: AppTheme.info,
          ),
          if (w.priceRangeMin != null || w.priceRangeMax != null)
            InfoRow(
              icon: Icons.payments_rounded,
              label: 'نطاق الأسعار',
              value: _priceLabel(w),
              color: AppTheme.accentDeep,
            ),
          InfoRow(
            icon: Icons.radar_rounded,
            label: 'نصف قطر الخدمة',
            value: '${w.serviceRadiusKm} كم',
            color: AppTheme.navy,
          ),
          if (hasWilaya)
            InfoRow(
              icon: Icons.location_on_rounded,
              label: 'الولاية',
              value: Taxonomy.wilayaName(w.wilaya!),
              color: AppTheme.success,
            ),
        ],
      ),
    );
  }

  static String _priceLabel(WorkerProfile w) {
    if (w.priceRangeMin != null && w.priceRangeMax != null) {
      return '${Money.amountOnly(w.priceRangeMin!)} - ${Money.dzd(w.priceRangeMax!)}';
    }
    if (w.priceRangeMax != null) return 'حتى ${Money.dzd(w.priceRangeMax!)}';
    return 'من ${Money.dzd(w.priceRangeMin!)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Portfolio gallery
// ─────────────────────────────────────────────────────────────────────────

class _PortfolioGrid extends StatelessWidget {
  final Future<List<String>> portfolio;

  /// First specialty — drives the tint/wash of the fallback tiles.
  final String? slug;

  /// Opens the conversation with this contractor.
  ///
  /// A visitor cannot upload for him, so "لم يضف صوراً بعد" on its own was a
  /// statement about somebody else's to-do list. A visitor *can* ask — the row
  /// is now the way to do it.
  final VoidCallback onContact;

  const _PortfolioGrid({
    required this.portfolio,
    this.slug,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: portfolio,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Shimmer(child: _PortfolioSkeleton());
        }
        final urls = snap.data ?? const <String>[];
        if (urls.isEmpty) {
          return AppCard(
            key: const Key('profile-portfolio-empty'),
            onTap: onContact,
            child: const Row(
              children: [
                IconBubble(
                    icon: Icons.photo_library_rounded,
                    tint: AppTheme.textSecondary,
                    wash: AppTheme.lineSoft,
                    size: 42),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('لم يضف صوراً بعد', style: AppTheme.bodySoft),
                      SizedBox(height: 3),
                      Text('اطلب منه صور أعمال سابقة في المحادثة.',
                          style: AppTheme.caption),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded,
                    size: 20, color: AppTheme.textMuted),
              ],
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: urls.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, i) => _PortfolioTile(url: urls[i], slug: slug),
        );
      },
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  final String url;
  final String? slug;

  const _PortfolioTile({required this.url, this.slug});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: NetImage(
        url,
        semanticLabel: 'صورة من أعمال المقاول',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const ColoredBox(color: AppTheme.lineSoft),
      ),
    );
  }

  Widget _fallback() {
    final hasSlug = slug != null && slug!.isNotEmpty;
    return ColoredBox(
      color: hasSlug ? Taxonomy.categoryWash(slug!) : AppTheme.lineSoft,
      child: Center(
        child: Icon(
          hasSlug ? Taxonomy.categoryIcon(slug!) : Icons.image_rounded,
          size: 30,
          color: hasSlug ? Taxonomy.categoryTint(slug!) : AppTheme.textMuted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Reviews
// ─────────────────────────────────────────────────────────────────────────

class _ReviewsSection extends StatelessWidget {
  final Future<List<Review>> reviews;

  /// Who can write the first review here? Not the visitor. The review is
  /// written *after* a job is completed, so the only action that leads there is
  /// starting the conversation — the same row idiom the account screen uses,
  /// rather than another full-width button next to the sticky "مراسلة" CTA.
  final VoidCallback onContact;
  const _ReviewsSection({required this.reviews, required this.onContact});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Review>>(
      future: reviews,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Shimmer(child: _ReviewsSkeleton());
        }
        final list = snap.data ?? const <Review>[];
        if (list.isEmpty) {
          return AppCard(
            key: const Key('profile-reviews-empty'),
            onTap: onContact,
            child: const Row(
              children: [
                IconBubble(
                    icon: Icons.rate_review_rounded,
                    tint: AppTheme.star,
                    wash: AppTheme.accentWash,
                    size: 42),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('لا تقييمات بعد', style: AppTheme.bodySoft),
                      SizedBox(height: 3),
                      Text('التقييم يُكتب بعد إنجاز العمل — ابدأ بالتواصل معه.',
                          style: AppTheme.caption),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded,
                    size: 20, color: AppTheme.textMuted),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final r in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewCard(review: r),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final name = review.customerFullName.trim();
    final comment = review.comment;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(name: name, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name.isEmpty ? 'زبون' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label,
                ),
              ),
              const SizedBox(width: 8),
              RatingStars(rating: review.rating.toDouble(), size: 13),
            ],
          ),
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(comment, style: AppTheme.body),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Loading skeletons
// ─────────────────────────────────────────────────────────────────────────

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        const SkeletonBox(height: 176, radius: AppTheme.rXl, color: SkeletonTone.base),
        const SizedBox(height: 22),
        const SkeletonBox(width: 110, height: 16, color: SkeletonTone.base),
        const SizedBox(height: 10),
        const SkeletonBox(height: 78, radius: AppTheme.rLg, color: SkeletonTone.base),
        const SizedBox(height: 22),
        const SkeletonBox(width: 90, height: 16, color: SkeletonTone.base),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              const SkeletonBox(width: 118, height: 30, radius: 999, color: SkeletonTone.base),
          ],
        ),
        const SizedBox(height: 22),
        const SkeletonBox(height: 168, radius: AppTheme.rLg, color: SkeletonTone.base),
      ],
    );
  }
}

class _PortfolioSkeleton extends StatelessWidget {
  const _PortfolioSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (_, __) =>
          const SkeletonBox(height: double.infinity, radius: AppTheme.rMd, color: SkeletonTone.base),
    );
  }
}

class _ReviewsSkeleton extends StatelessWidget {
  const _ReviewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 2; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBox(height: 96, radius: AppTheme.rLg, color: SkeletonTone.base),
          ),
      ],
    );
  }
}
