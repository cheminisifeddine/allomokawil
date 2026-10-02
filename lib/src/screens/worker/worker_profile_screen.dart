import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/notification_copy.dart';
import '../../data/price_range_copy.dart';
import '../../data/repository.dart';
import '../../data/review_order.dart';
import '../../data/taxonomy.dart';
import '../../data/worker_stats_copy.dart';
import '../../data/reviews_section_copy.dart';
import '../../models/enums.dart';
import '../../models/quote_review.dart';
import '../../models/worker.dart';
import '../../widgets/net_image.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import '../auth/auth_screen.dart';
import '../chat/chat_screen.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';

/// Public contractor profile: bio, specialties, price range, portfolio
/// gallery, reviews + contact.
///
/// Portfolio-style layout: navy cover header, key facts, gallery grid and a
/// sticky contact CTA. Behaviour (repository calls, chat navigation) is
/// unchanged — only the presentation moved onto the shared UI kit.
class WorkerProfileScreen extends StatefulWidget {
  final int workerId;

  /// The wall clock the review dates are measured against. See
  /// [_ReviewCard.clock]: null in production, fixed in the golden and widget
  /// tests so a date cannot drift the suite.
  final DateTime Function()? clock;

  const WorkerProfileScreen(
      {super.key, required this.workerId, this.clock});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  late final Repository _repo;
  late Future<WorkerProfile> _profile;

  ///
  /// Not `late final`, and that is the fix. Captured once in
  /// [didChangeDependencies], the two section futures were *permanently*
  /// unfetchable: a failed `/portfolio` read left the rejected future in place
  /// and the screen's only retry, [_retry], re-read `_profile` alone. So a
  /// customer who opened the page while the host was down, watched the header
  /// recover, then scrolled to a gallery that had failed a moment earlier was
  /// shown the old answer for the rest of the visit — nothing on the page could
  /// fix it, and neither could the user. The three reads are one page, so they
  /// retry together; each section can also retry just itself.
  late Future<List<Review>> _reviews;
  late Future<List<String>> _portfolio;

  bool _scopeReady = false;

  /// The once-a-minute tick that re-labels every review card.
  ///
  /// [_ReviewCard] composes `relativeTimeAr(review.createdAt, now:
  /// clock?.call())` **at build time** (:817), and this screen rebuilds on
  /// exactly three things: the first pair of reads, «إعادة المحاولة» on the
  /// header, and either section's own retry. **None of them is "a minute
  /// passed."**
  ///
  /// So a customer comparing two contractors on a phone — this is the page he
  /// picks one from, and the reviews are the evidence he weighs — left the
  /// profile open, came back twenty minutes later, and read «قبل 12 دقيقة» on
  /// reviews that were now forty minutes old. Every card frozen from the
  /// single frame the page opened on, with the header's own count and the
  /// gallery beside them telling a different story.
  ///
  /// The **seam was already here** and was never the missing half: `clock` was
  /// added to stop the profile golden drifting on an hour boundary, exactly as
  /// it was to `NotificationsScreen`. Same fuse as the ten siblings this family
  /// has closed so far (`profile_screen`, `subscription_screen`,
  /// `notifications_screen`, `project_detail_screen`, `my_portfolio_screen`) —
  /// and the last of them. A computed answer whose screen never asks the
  /// question again.
  ///
  /// **Armed from the lifecycle, not from a load callback, and that is the
  /// shape question this file had to answer.** The review list is a `Future`
  /// behind a [FutureBuilder] — [reviews] is `_reviews`, exactly as the bid
  /// list is a `Future` on `project_detail_screen.dart`. So the State cannot
  /// ask "did a card land?" without duplicating the parse the builder already
  /// does, and the arm belongs where `project_detail_screen.dart` put it:
  /// [initState] and the retry. Arming from a hypothetical "first card arrived"
  /// callback would parse the payload a second time to learn something the
  /// builder already knows.
  ///
  /// There is no `_stale`-style predicate to gate on, and that is deliberate:
  /// a minute spent over the reviews skeleton costs one redraw and nothing
  /// else, because a `setState` with no fields changed is free when there is
  /// nothing to redraw.
  Timer? _ageTimer;

  @override
  void initState() {
    super.initState();
    _armAgeTick();
  }

  /// Starts the tick that keeps the review dates honest.
  ///
  /// **Called from [initState] and nowhere else, and that was a measured
  /// decision rather than a tidy one.** The obvious shape is the sibling's —
  /// `project_detail_screen.dart` re-arms from `_reload` — and the obvious
  /// shape is wrong here, or at least does nothing: this screen has exactly
  /// three retries (`_retry`, `_retryReviews`, `_retryPortfolio`) and **none of
  /// them can stop the timer**, because the only place it is cancelled is
  /// [dispose]. A tick armed once in [initState] already fires for the whole
  /// life of the page, so every re-arm on a retry replaces a live one-minute
  /// timer with an identical one.
  ///
  /// Deleting both retry arms was tried and **all four tests stayed green**
  /// (`test/profile_review_age_clock_test.dart`), which is the only reason
  /// they are not in the source: a call no mutation can distinguish from its
  /// absence is a line that costs a reader a question and answers none.
  /// Cancel-first is kept anyway, so the one caller that exists today cannot
  /// grow a second by accident and the next screen to copy this arm has the
  /// safe half already written.
  ///
  /// Not written in `build` — a timer made in `build` is a new timer every
  /// frame and the tick multiplies.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // A `setState` with no fields changed is the whole mechanism: _ReviewCard
      // reads the clock in `build`, so re-running the build is what re-reads
      // it. The card is a `StatelessWidget` and stays one — the timer belongs
      // to the page, not to a row that would each need their own.
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppScope is an InheritedWidget, so it cannot be read in initState.
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _profile = _repo.getWorker(widget.workerId);
    // Started here, not at first use: a section that loaded after the header
    // would paint late, and the gallery is the page's main event.
    _startSections();
  }

  /// Retries the whole page: header, gallery and reviews are one view of one
  /// contractor, and one dead host fails all three.
  void _retry() {
    setState(() {
      _profile = _repo.getWorker(widget.workerId);
      _startSections();
    });
  }

  /// Retries one section, leaving the rest of the page — and its already-good
  /// answers — alone.
  void _retryReviews() {
    setState(() {
      _reviews = _repo.workerReviews(widget.workerId);
      _reviews.ignore();
    });
  }

  void _retryPortfolio() {
    setState(() {
      _portfolio = _repo.portfolioImages(widget.workerId);
      _portfolio.ignore();
    });
  }

  /// Issues both section reads and marks them as observed.
  ///
  /// [FutureBuilder] subscribes to a future only while its section is on
  /// screen, so a read that outlives its own error view has no listener. When
  /// `/workers/:id` fails, `_body()` never runs, no FutureBuilder ever
  /// subscribes to these two, and their rejections went straight to
  /// `PlatformDispatcher.onError` and into the crash log as
  /// «خلل مؤقّت في الخادم» with no stack pointing at anything: every offline
  /// visit wrote three phantom crashes, two of them for requests the user never
  /// saw. The future still fails; it is now observed, so the log names the read
  /// that failed.
  ///
  /// Every attempt goes through here, retries included, so a second header
  /// failure after «إعادة المحاولة» cannot start two more.
  void _startSections() {
    _reviews = _repo.workerReviews(widget.workerId);
    _portfolio = _repo.portfolioImages(widget.workerId);
    _reviews.ignore();
    _portfolio.ignore();
  }

  @override
  void dispose() {
    // This is a pushed route, not an `IndexedStack` child: browse, search and
    // the chat header all push it. An uncancelled timer outlives the trip back
    // and fires `setState` on a dead State, and the nine widget tests that
    // drive this screen without unmounting it inherit the "A Timer is still
    // pending" failure from whoever adds the timer first.
    _ageTimer?.cancel();
    super.dispose();
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
          onRetry: _retryPortfolio,
        ),
        const SectionTitle('التقييمات', icon: Icons.star_rounded),
        _ReviewsSection(
          reviews: _reviews,
          // The count the header **actually printed**, not the raw column.
          // Two reads of one fact, and this is what lets the section notice
          // when they disagree instead of asserting the opposite of the row
          // the customer just read — see `reviews_section_copy.dart`.
          //
          // `w.totalReviews` was wrong here, and it was this loop's own line:
          // the header draws its pill on `hasRating`, so a profile carrying
          // `avg_rating: 0, total_reviews: 24` prints «لا تقييمات بعد» with no
          // stars and no number, and a section told 24 would then announce
          // «يظهر أعلاه 24 تقييماً» about a page that has never shown one.
          // `headerPrintedReviewCount` applies both of the header's own
          // conditions, so the arm can only fire against a claim the customer
          // can see.
          headerReviewCount: headerPrintedReviewCount(
            hasRating: w.hasRating,
            totalReviews: w.totalReviews,
          ),
          onContact: () => _openChat(w),
          onRetry: _retryReviews,
          clock: widget.clock,
        ),
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
                // invisible straight onto the navy cover. A contractor nobody
                // has rated gets the same pill with the fact on it, never
                // «0.0» — see [WorkerProfile.avgRating].
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: worker.hasRating
                      ? RatingStars(
                          rating: worker.avgRating!,
                          count: worker.totalReviews,
                          size: 15)
                      : Text(noRatingAr(),
                          style: AppTheme.caption
                              .copyWith(fontSize: AppTheme.fsMeta)),
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
    // Resolved, not merely non-empty: a code this build does not know used to
    // pass this gate and then print the fallback, so a contractor in
    // Ghardaïa-on-the-server published «الولاية: الجزائر» on his own profile.
    // The row is dropped instead — same rule as the radius row above it.
    final wilayaName = Taxonomy.wilayaNameOrNull(w.wilaya);
    return AppCard(
      child: Column(
        children: [
          InfoRow(
            icon: Icons.workspace_premium_rounded,
            label: 'الخبرة',
            value: experienceYearsAr(w.experienceYears) ?? 'لم يُسجّل بعد',
            color: AppTheme.info,
          ),
          // Dropped whole when there is nothing true to say, and gated on the
          // shared predicate rather than on `min != null` alone, so this row
          // and the browse card beside it cannot disagree about the same man.
          if (priceRangeAr(w.priceRangeMin, w.priceRangeMax) case final range?)
            InfoRow(
              icon: Icons.payments_rounded,
              label: 'نطاق الأسعار',
              value: range,
              color: AppTheme.accentDeep,
            ),
          // Dropped whole when there is nothing true to say: a contractor who
          // never set a radius used to publish «نصف قطر الخدمة: 0 كم» here,
          // which reads as a decision rather than a blank. See
          // [serviceRadiusAr].
          if (serviceRadiusAr(w.serviceRadiusKm) case final radius?) ...[
            InfoRow(
              icon: Icons.radar_rounded,
              label: 'نصف قطر الخدمة',
              value: radius,
              color: AppTheme.navy,
            ),
          ],
          if (wilayaName != null)
            InfoRow(
              icon: Icons.location_on_rounded,
              label: 'الولاية',
              value: wilayaName,
              color: AppTheme.success,
            ),
        ],
      ),
    );
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

  /// Re-reads the gallery after a failure. Without it the section was stuck:
  /// the empty state reads as a fact about the contractor, so a failed fetch
  /// printed that fact and gave the reader nothing to do about it.
  final VoidCallback onRetry;

  const _PortfolioGrid({
    required this.portfolio,
    this.slug,
    required this.onContact,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: portfolio,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Shimmer(child: _PortfolioSkeleton());
        }
        // A failure is not an empty gallery. `snap.data` is null on error
        // exactly as it is on an empty list, and this line conflated them: one
        // dead host printed "لم يضف صوراً بعد" on a contractor with twelve
        // photos, on the one page a customer picks him from. Same class of lie
        // the "نصف قطر الخدمة: 0 كم" row used to publish.
        if (snap.hasError) {
          return AppCard(
            key: const Key('profile-portfolio-error'),
            child: Column(
              children: [
                Row(
                  children: [
                    const IconBubble(
                        icon: Icons.cloud_off_rounded,
                        tint: AppTheme.danger,
                        wash: AppTheme.dangerWash,
                        size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('تعذّر تحميل معرض الأعمال',
                              style: AppTheme.bodySoft),
                          const SizedBox(height: 3),
                          Text(errorCopy(snap.error),
                              style: AppTheme.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  key: const Key('profile-portfolio-retry'),
                  label: S.retry,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ],
            ),
          );
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

  /// The review count the profile header **drew**, and 0 when it drew none.
  ///
  /// Not the raw column: this is [headerPrintedReviewCount], so a profile the
  /// header refused to put a count on arrives here as 0 and cannot make the
  /// arm quote a number that is not on screen.
  ///
  /// Only used to detect a contradiction; never to print a score the section
  /// cannot show. See [reviewsSectionUnbackedAr].
  final int headerReviewCount;

  /// Who can write the first review here? Not the visitor. The review is
  /// written *after* a job is completed, so the only action that leads there is
  /// starting the conversation — the same row idiom the account screen uses,
  /// rather than another full-width button next to the sticky "مراسلة" CTA.
  final VoidCallback onContact;

  /// Re-reads the reviews after a failure. See [_PortfolioGrid.onRetry]: the
  /// same conflation, on the section that carries a man's reputation.
  final VoidCallback onRetry;

  /// See [_ReviewCard.clock].
  final DateTime Function()? clock;

  const _ReviewsSection({
    required this.reviews,
    required this.headerReviewCount,
    required this.onContact,
    required this.onRetry,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Review>>(
      future: reviews,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Shimmer(child: _ReviewsSkeleton());
        }
        // "لا تقييمات بعد" on a 500 is the sharpest version of the
        // same lie: a customer reads it as a rating of zero and picks somebody
        // else, and no amount of scrolling will contradict it.
        if (snap.hasError) {
          return AppCard(
            key: const Key('profile-reviews-error'),
            child: Column(
              children: [
                Row(
                  children: [
                    const IconBubble(
                        icon: Icons.cloud_off_rounded,
                        tint: AppTheme.danger,
                        wash: AppTheme.dangerWash,
                        size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('تعذّر تحميل التقييمات',
                              style: AppTheme.bodySoft),
                          const SizedBox(height: 3),
                          Text(errorCopy(snap.error),
                              style: AppTheme.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SecondaryButton(
                  key: const Key('profile-reviews-retry'),
                  label: S.retry,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ],
            ),
          );
        }
        // Newest first, and the undated rows last — see `review_order.dart`.
        // Drawing the list in whatever order the Worker sent is what let a
        // page with dates on it read «قبل 3 أشهر» above «الآن».
        final list = newestReviewFirst(snap.data ?? const <Review>[]);
        if (list.isEmpty) {
          // The header may already have told this customer the opposite. The
          // aggregate (`/workers/:id`) and the list (`/workers/:id/reviews`)
          // are two reads of one fact and the live API returns both, both 200,
          // disagreeing — `عمر بن علي` is 4.8 over 24 reviews there and the
          // reviews endpoint answers `[]`. Drawing «لا تقييمات بعد» over that
          // is not a smaller version of the 500 lie the arm above exists to
          // prevent; it is the same lie with a success status code.
          //
          // So the contradiction gets its own arm, and it is the one case this
          // section must not resolve on its own: which read is stale is not
          // knowable from here, and a guess in either direction is a claim
          // about a man's reputation.
          final unbacked = reviewsSectionUnbackedAr(
              headerCount: headerReviewCount);
          if (unbacked != null) {
            return AppCard(
              key: const Key('profile-reviews-unbacked'),
              child: Row(
                children: [
                  const IconBubble(
                      icon: Icons.cloud_off_rounded,
                      tint: AppTheme.danger,
                      wash: AppTheme.dangerWash,
                      size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(reviewsSectionUnbackedTitle,
                            style: AppTheme.bodySoft),
                        const SizedBox(height: 3),
                        Text(unbacked, style: AppTheme.caption),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          // The title is read from `noRatingAr()` rather than typed here, and
          // that is why this card is no longer `const`: a const widget cannot
          // hold a value it has to ask a function for. One line of the tree is
          // no longer known at compile time, and in exchange this sentence
          // cannot be edited in `worker_stats_copy.dart` and left stale here.
          return AppCard(
            key: const Key('profile-reviews-empty'),
            onTap: onContact,
            child: Row(
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
                      Text(reviewsSectionEmptyTitle, style: AppTheme.bodySoft),
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
                child: _ReviewCard(review: r, clock: clock),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  /// The wall clock the row's date is measured against.
  ///
  /// `relativeTimeAr` renders from the *difference* to now, so a screen that
  /// always reads `DateTime.now()` ages the same row differently as the hours
  /// pass — which is what pinned `NotificationsScreen` to a fixed clock: the
  /// `15_notifications` golden drifted on an hour boundary and took the whole
  /// `flutter test` gate red with it, roughly 50 minutes after it was
  /// captured. Tests hand in a fixed clock; production leaves it null and reads
  /// the real time, exactly as that screen does.
  final DateTime Function()? clock;

  const _ReviewCard({required this.review, this.clock});

  @override
  Widget build(BuildContext context) {
    final name = review.customerFullName.trim();
    final comment = review.comment;
    // «قبل 3 أشهر» on a card that had no date at all: this row is the evidence
    // a customer reads before choosing this man, and every other dated list in
    // the app says how old it is. Same function, not a fifth copy of the
    // grammar. Empty when the server sent no timestamp — the row then draws
    // exactly as it always did, rather than an invented one.
    final when = relativeTimeAr(review.createdAt, now: clock?.call());
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
              // An unreadable score draws no stars rather than five empty
              // ones. [Review.rating] cannot be 0 in real data — the form is
              // 1-5 — so a 0 is the reader saying it read nothing, and empty
              // stars are the one shape that reads as "this man did badly".
              if (review.ratingIsReal)
                RatingStars(rating: review.rating.toDouble(), size: 13),
            ],
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                when,
                key: const Key('review-when'),
                style: AppTheme.caption
                    .copyWith(color: AppTheme.textMuted),
              ),
            ),
          ],
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
