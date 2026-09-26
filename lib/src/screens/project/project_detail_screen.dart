import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/text/dz_number.dart';
import '../../core/theme/app_theme.dart';
import '../../data/quote_duration_copy.dart';
import '../../data/repository.dart';
import '../../data/taxonomy.dart';
import '../../data/worker_stats_copy.dart';
import '../../models/enums.dart';
import '../../models/project.dart';
import '../../models/quote_review.dart';
import '../../widgets/net_image.dart';
import '../../widgets/quote_worker_trust.dart';
import '../../widgets/number_field.dart';
import '../../widgets/ui.dart';
import '../browse/browse_screen.dart';
import '../auth/auth_screen.dart';
import '../chat/chat_screen.dart';
import '../review/review_screen.dart';
import '../worker/subscription_screen.dart';
import 'project_new_screen.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/l10n/strings.dart';
import '../../core/network/api_client.dart';
import '../../widgets/skeletons.dart';

/// Full project view: info, photos, and the quotes workflow.
/// - customer/owner: browse quotes, accept one (rejects the rest), complete.
/// - worker: submit a quote or chat with the owner.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;
  final Repository repo;

  const ProjectDetailScreen(
      {super.key, required this.projectId, required this.repo});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Future<Project> _project;
  late Future<List<Quote>> _quotes;

  UserRole get _role => AppScope.of(context).auth.role;

  /// Guests read a project; they own nothing.
  ///
  /// `AuthState.role` answers `customer` when nobody is signed in, so without
  /// this a visitor browsing from the first page was handed the owner's
  /// actions — accept a quote, close the job — and every one of them answered
  /// 401. The public half of this screen is the quote list, not the controls.
  bool get _isOwner =>
      AppScope.of(context).auth.isAuthenticated && _role == UserRole.customer;

  /// Sends a signed-out visitor to the form that makes him a user, and reports
  /// whether it did. Reading is public; acting is not.
  bool _requireAccount(UserRole role) {
    if (AppScope.of(context).auth.isAuthenticated) return false;
    _openAuth(role);
    return true;
  }

  void _openAuth(UserRole role) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthScreen(mode: AuthMode.signUp, role: role)));
  }

  @override
  void initState() {
    super.initState();
    _project = widget.repo.getProject(widget.projectId);
    _quotes = widget.repo.projectQuotes(widget.projectId);
  }

  void _reload() {
    setState(() {
      _project = widget.repo.getProject(widget.projectId);
      _quotes = widget.repo.projectQuotes(widget.projectId);
    });
  }

  /// Owner accepts a quote — the backend rejects every other one.
  Future<void> _accept(Quote q) async {
    await widget.repo.acceptQuote(widget.projectId, q.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم قبول العرض، سيتم رفض باقي العروض')));
      _reload();
    }
  }

  /// Owner closes the job, then rates the contractor.
  ///
  /// Two repairs in the review flow live here. The call is inside a `try` now:
  /// it used to run bare, so a failed close (offline, project already closed by
  /// the web app) surfaced as an unhandled error *and* still pushed the rating
  /// form — whose submit the API then refuses with «المشروع لم يكتمل بعد».
  /// And the detail screen reloads afterwards, so its own status flips to
  /// «منجز» instead of still claiming the job is running behind the form.
  Future<void> _complete(Project project) async {
    try {
      await widget.repo.completeProject(project.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorCopy(e))));
      }
      return;
    }
    if (!mounted) return;
    _openReview(project);
    _reload();
  }

  /// Owner edits his own project. The form is the publish form in edit mode,
  /// so the create-time validation is not duplicated: it is the same fields,
  /// the same budget rules and the same required title/category/wilaya. It
  /// answers `true` when it actually saved, and the project is re-read only
  /// then — a form the user backed out of must not repaint the page.
  Future<void> _edit(Project project) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ProjectNewScreen(initial: project),
    ));
    if (saved == true && mounted) _reload();
  }

  /// Owner cancels his own project. Destructive and irreversible from the app,
  /// so it asks first, in Arabic, and says what happens to the bids.
  Future<void> _cancel(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء المشروع؟'),
        content: const Text(
            'سيتم إلغاء المشروع وسحب كل العروض المنتظرة، ولن يستطيع الحرفيون التقديم عليه. لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('نعم، ألغِ المشروع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.cancelProject(project.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorCopy(e))));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم إلغاء المشروع')));
    _reload();
  }

  /// Opens the rating form for this project's chosen contractor.
  ///
  /// The review POST upserts on (project, customer), so opening this twice can
  /// only ever edit the one rating — never add a second, invented one.
  void _openReview(Project project) {
    final workerId = project.selectedWorkerId;
    if (workerId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReviewScreen(
            projectId: project.id, workerId: workerId, repo: widget.repo)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(_isOwner ? 'تفاصيل مشروعك' : 'تفاصيل المشروع')),
      body: FutureBuilder<Project>(
        future: _project,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonDetailPage();
          }
          if (snap.hasError) {
            return EmptyView(
              icon: Icons.error_outline_rounded,
              title: 'تعذّر تحميل المشروع',
              message: errorCopy(snap.error),
              actionLabel: 'إعادة المحاولة',
              onAction: _reload,
              danger: true,
            );
          }
          final project = snap.data!;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: ListView(
                      padding: AppTheme.pagePad,
                      children: [
                        // A project with photos opens on the work itself.
                        // A project *without* them used to open on a 180 dp
                        // grey slab reading «لا توجد صور» — the biggest thing
                        // on the money screen said nothing. So the scan order
                        // is: what the job is, then where/when, then media.
                        if (project.images.isNotEmpty) ...[
                          _Photos(images: project.images),
                          const SizedBox(height: 18),
                        ],
                        Text(project.title,
                            style: AppTheme.display),
                        const SizedBox(height: 12),
                        _StatusRow(project: project),
                        if (project.images.isEmpty) ...[
                          const SizedBox(height: 16),
                          _Photos(images: project.images),
                        ],
                        if (project.description != null) ...[
                          const SectionTitle('وصف المشروع',
                              icon: Icons.notes_rounded),
                          AppCard(
                            padding: AppTheme.cardPad,
                            child: Text(project.description!,
                                style: AppTheme.body),
                          ),
                        ],
                        const SectionTitle('تفاصيل المشروع',
                            icon: Icons.fact_check_outlined),
                        AppCard(
                          padding: AppTheme.cardPadRows,
                          child: Column(
                            children: [
                              InfoRow(
                                icon: Icons.payments_outlined,
                                label: 'الميزانية',
                                value: project.budgetLabel,
                                color: AppTheme.accentDeep,
                              ),
                              const Divider(
                                  height: 1, color: AppTheme.lineSoft),
                              InfoRow(
                                icon: Icons.schedule_rounded,
                                label: 'الاستعجال',
                                value: _urgencyLabel(project.urgency),
                                color: AppTheme.info,
                              ),
                              const Divider(
                                  height: 1, color: AppTheme.lineSoft),
                              InfoRow(
                                icon: Icons.place_outlined,
                                label: 'البلدية',
                                value: _locationLabel(project),
                                color: AppTheme.navy,
                              ),
                            ],
                          ),
                        ),
                        const SectionTitle('العروض',
                            icon: Icons.handshake_outlined),
                        _QuotesSection(
                          quotesFuture: _quotes,
                          project: project,
                          isOwner: _isOwner,
                          onAccept: _accept,
                          onBid: () => _showBidSheet(project),
                        ),
                        if (_isOwner) ...[
                          const SizedBox(height: 16),
                          _OwnerActions(
                            project: project,
                            onEdit: () => _edit(project),
                            onCancel: () => _cancel(project),
                          ),
                        ],
                        if (!_isOwner) ...[
                          const SizedBox(height: 16),
                          SecondaryButton(
                            label: 'مراسلة صاحب المشروع',
                            icon: Icons.chat_outlined,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  projectId: project.id,
                                  otherUserId: project.customerId,
                                  repo: widget.repo,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              // Primary action always reachable at the bottom of the screen.
              _stickyCta(project),
            ],
          );
        },
      ),
    );
  }

  /// The single primary action for the current role/state, pinned at the
  /// bottom. States with no primary action render nothing.
  Widget _stickyCta(Project project) {
    if (_isOwner && project.status == ProjectStatus.inProgress) {
      return StickyCta(
        child: PrimaryButton(
          label: 'أكمل المشروع وتقييم',
          icon: Icons.task_alt_rounded,
          onPressed: () => _complete(project),
        ),
      );
    }
    // A finished job used to be a dead end for its owner: the only door into
    // the rating form was the tap that closed the job. Back out of that screen
    // once (or close the job from the web app) and the project offered no
    // primary action at all — the review the entire trust model rests on could
    // never be written. This is also the "change my rating" path, because the
    // endpoint updates the row it already has for this project and customer.
    if (_isOwner &&
        project.status == ProjectStatus.completed &&
        project.selectedWorkerId != null) {
      return StickyCta(
        child: PrimaryButton(
          label: 'قيّم المقاول',
          icon: Icons.star_rounded,
          onPressed: () => _openReview(project),
        ),
      );
    }
    if (!_isOwner && project.status == ProjectStatus.open) {
      return StickyCta(
        child: PrimaryButton(
          label: 'قدّم عرضك',
          icon: Icons.request_quote_outlined,
          onPressed: () => _showBidSheet(project),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _locationLabel(Project project) {
    final commune = project.commune;
    if (commune == null || commune.isEmpty) {
      return Taxonomy.wilayaName(project.wilaya);
    }
    return '${Taxonomy.wilayaName(project.wilaya)} — $commune';
  }

  String _urgencyLabel(UrgencyLevel u) {
    switch (u) {
      case UrgencyLevel.urgent:
        return 'عاجل';
      case UrgencyLevel.withinWeek:
        return 'خلال أسبوع';
      case UrgencyLevel.withinMonth:
        return 'خلال شهر';
      case UrgencyLevel.flexible:
        return 'بدون استعجال';
    }
  }

  /// Quote form. Same fields, same validation (>= 1000 DZD), same call.
  Future<void> _showBidSheet(Project project) async {
    // A guest can read the project; the form that cannot be submitted is
    // replaced by the form that turns him into a contractor.
    if (_requireAccount(UserRole.worker)) return;
    final amount = TextEditingController();
    final message = TextEditingController();
    final days = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('قدّم عرضك', style: AppTheme.h1),
            const SizedBox(height: 14),
            NumberField(
              controller: amount,
              labelText: 'المبلغ (دج)',
              suffixText: 'دج',
            ),
            const SizedBox(height: 12),
            NumberField(
              controller: days,
              labelText: 'مدة الإنجاز (أيام)',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: message,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'رسالتك (اختياري)'),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'إرسال العرض',
              icon: Icons.send_rounded,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      if (!mounted) return;
      // Folded parse: a contractor who typed `٢٥٠٠٠` on an Arabic keypad, or
      // pasted `25.000 دج` out of a note, means 25000 — not "no amount".
      final amt = DzNumber.tryParse(amount.text, min: 1000);
      final rawDays = days.text.trim();
      final dayCount = DzNumber.tryParse(rawDays, min: 1);
      if (amt == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('المبلغ يجب أن يكون 1000 دج على الأقل')));
      } else if (rawDays.isNotEmpty && dayCount == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('مدة الإنجاز يجب أن تكون عدداً من الأيام')));
      } else {
        try {
          await widget.repo.submitQuote(
            projectId: project.id,
            amount: amt,
            message: message.text.trim().isEmpty ? null : message.text.trim(),
            estimatedDays: dayCount,
          );
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('تم إرسال عرضك')));
            _reload();
          }
        } catch (e) {
          if (!mounted) return;
          // A 402 here is not a failure to retry — it is the paywall: the plan's
          // monthly quote allowance is spent. Offer the one action that unblocks
          // him (increase the plan) instead of a sentence he cannot act on.
          if (e is ApiException && e.statusCode == 402) {
            await _offerUpgrade();
            return;
          }
          if (isWriteUnconfirmed(e)) {
            // The bid may already be in the list. Re-read it instead of leaving
            // the contractor to wonder whether he sent two.
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(S.writeUnconfirmedRecheck)));
            final outcome = await resolveWriteOutcome(
              recheck: () async {
                // The bid is identified by what this worker asked for on this
                // job, not by an id the phone never received. Any later bid with
                // the same amount is the same one as far as the user is
                // concerned: what he must learn is whether *a* bid from him is
                // in the list he is looking at.
                int mine = -1;
                try {
                  mine = (await widget.repo.myProfile()).id;
                } catch (_) {
                  // A failed identity read is not a failed bid. Fall back to
                  // matching on the amount alone rather than telling the user
                  // his bid is missing because we could not read his profile.
                }
                final rows = await widget.repo.projectQuotes(project.id);
                return rows.any((q) =>
                    q.amount == amt && (mine <= 0 || q.workerId == mine));
              },
            );
            if (!mounted) return;
            // Either way the quotes list on screen is now the server's.
            _reload();
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(writeOutcomeCopy(outcome))));
            return;
          }
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(errorCopy(e))));
        }
      }
    }
  }

  /// The paywall turned into a next step: the dialog states the limit, and the
  /// button opens «اشتراكي» where a month or a year can be chosen.
  Future<void> _offerUpgrade() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.planQuotaTitle),
        content: const Text(S.planQuotaBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('لاحقاً'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(S.planUpgrade),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
    _reload();
  }
}

/// Status / category / place, laid out with [Wrap] so a long wilaya name or a
/// large font scale can never overflow the row.
class _StatusRow extends StatelessWidget {
  final Project project;
  const _StatusRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final commune = project.commune;
    final place = (commune == null || commune.isEmpty)
        ? Taxonomy.wilayaName(project.wilaya)
        : '${Taxonomy.wilayaName(project.wilaya)} — $commune';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusPill.project(project.status.name),
        // One job can carry several trades; the badge row is a Wrap already, so
        // every trade it needs is visible without a second screen.
        for (final slug in project.allCategories) CategoryBadge(slug: slug),
        _MetaChip(icon: Icons.place_outlined, text: place),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lineSoft,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(text,
              style: AppTheme.caption
                  .copyWith(fontSize: AppTheme.fsCaption, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// Photo carousel: swipeable pages with a dot indicator underneath.
class _Photos extends StatefulWidget {
  final List<String> images;
  const _Photos({required this.images});

  @override
  State<_Photos> createState() => _PhotosState();
}

class _PhotosState extends State<_Photos> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      // Compact and inline, not a 180 dp slab: an empty media slot is a note,
      // not a headline. It sits under the project title instead of above it.
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s16, vertical: AppTheme.s12),
        decoration: BoxDecoration(
          color: AppTheme.lineSoft,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.image_not_supported_outlined,
                size: 20, color: AppTheme.textSecondary),
            const SizedBox(width: AppTheme.s12),
            Expanded(
              child: Text('لا توجد صور لهذا المشروع',
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.textSecondary)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          child: SizedBox(
            height: 220,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => NetImage(
                widget.images[i],
                semanticLabel: 'صورة المشروع ${i + 1}',
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PhotoFallback(),
              ),
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 10),
          // Wrap: a project can carry many photos, dots must be able to wrap.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < widget.images.length; i++)
                Container(
                  width: i == _index ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? AppTheme.accent : AppTheme.line,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.lineSoft,
      alignment: Alignment.center,
      child:
          const Icon(Icons.image_outlined, size: 36, color: AppTheme.textMuted),
    );
  }
}

/// Quotes list. The accept + bid + complete actions live in
/// [_ProjectDetailScreenState] so the sticky bottom CTA can reuse them.
class _QuotesSection extends StatelessWidget {
  final Future<List<Quote>> quotesFuture;
  final Project project;
  final bool isOwner;
  final ValueChanged<Quote> onAccept;
  final VoidCallback onBid;

  const _QuotesSection({
    required this.quotesFuture,
    required this.project,
    required this.isOwner,
    required this.onAccept,
    required this.onBid,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Quote>>(
      future: quotesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _QuotesSkeleton();
        }
        final quotes = snap.data ?? const <Quote>[];
        if (quotes.isEmpty) {
          // A worker must be able to bid from the empty state even when the
          // sticky CTA is not shown (i.e. the project is no longer open).
          final offerFromEmptyState =
              !isOwner && project.status != ProjectStatus.open;
          // An owner staring at "شارك مشروعك ليصل إلى المقاولين" had no way to
          // share anything: the app has no share action, and quotes arrive from
          // the contractor directory. So the empty state hands him the one step
          // he can actually take — go find a pro and talk to him.
          if (isOwner && !offerFromEmptyState) {
            return EmptyView(
              icon: Icons.request_quote_outlined,
              title: 'لا عروض بعد',
              message: 'لم يتقدّم أي مقاول بعرض على مشروعك بعد.\n'
                  'راسل مقاولاً موثوقاً من دليل المقاولين وسيصل عرضه هنا.',
              actionLabel: 'ابحث عن مقاول',
              actionIcon: Icons.search_rounded,
              onAction: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BrowseScreen(customerSide: true))),
            );
          }
          return EmptyView(
            icon: Icons.request_quote_outlined,
            title: 'لا عروض بعد',
            message: isOwner ? 'شارك مشروعك ليصل إلى المقاولين' : null,
            actionLabel: offerFromEmptyState ? 'قدّم عرضك' : null,
            onAction: offerFromEmptyState ? onBid : null,
          );
        }
        return Column(
          children: [
            for (final q in quotes) ...[
              _QuoteCard(
                quote: q,
                isOwner: isOwner,
                onAccept: () => onAccept(q),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _QuotesSkeleton extends StatelessWidget {
  const _QuotesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        children: [
          Row(
            children: [
              SkeletonBox(height: 46, width: 46, radius: 23, color: SkeletonTone.base),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 14, width: 150, color: SkeletonTone.base),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 96, color: SkeletonTone.base),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(height: 52, radius: 12, color: SkeletonTone.base),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final Quote quote;
  final bool isOwner;
  final VoidCallback onAccept;

  const _QuoteCard(
      {required this.quote, required this.isOwner, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    // Built once: the row's visibility and its text are the same value, and
    // asking the copy file twice to reach the same answer is the kind of
    // drift this file exists to stop.
    final durationLine = quoteDurationLineAr(quote.estimatedDays);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              QuoteWorkerTrust(quote: quote, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(quote.workerFullName,
                        style: AppTheme.h2.copyWith(fontSize: AppTheme.fsLead),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    // Gated on the score, not on the review count. The count
                    // is a different field: a payload can say "he has reviews"
                    // and still omit the score, and then the old guard drew five
                    // empty stars and «0.0» for a man somebody did rate. Same
                    // sentinel, same fix as [WorkerProfile.avgRating].
                    if (quote.hasRating)
                      RatingStars(
                          rating: quote.workerAvgRating!,
                          count: quote.workerTotalReviews,
                          size: 14)
                    else
                      Text(noRatingAr(),
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.accentWash,
              borderRadius: BorderRadius.circular(AppTheme.rSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المبلغ: ${Money.dzd(quote.amount)}',
                    style: AppTheme.h2
                        .copyWith(fontSize: AppTheme.fsBar, color: AppTheme.navy)),
                if (durationLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 15, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(durationLine,
                            style: AppTheme.bodySoft.copyWith(fontSize: AppTheme.fsMeta)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (quote.message != null) ...[
            const SizedBox(height: 12),
            Text(quote.message!, style: AppTheme.bodySoft),
          ],
          if (isOwner) ...[
            const SizedBox(height: 14),
            // Wrap, not Row: the action row reflows instead of overflowing on
            // a narrow phone, and a second action can be added safely.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'قبول العرض',
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: onAccept,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('بالقبول تُرفض باقي العروض تلقائياً.',
                style:
                    AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Secondary helper kept for reuse — same signature, now built on the UI kit.
/// The owner's two management actions, under his own project.
///
/// Both are gated on the state the API actually accepts: editing is only
/// possible while `open` (after a contractor is chosen the job is a contract
/// he bid on), and cancelling only while the job is not already finished or
/// cancelled. Rendering a button the server would refuse is how the app
/// teaches users that its buttons lie, so a state with no allowed action
/// renders nothing at all.
class _OwnerActions extends StatelessWidget {
  final Project project;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  const _OwnerActions({
    required this.project,
    required this.onEdit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final status = project.status;
    if (status == ProjectStatus.completed ||
        status == ProjectStatus.cancelled) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == ProjectStatus.open)
          SecondaryButton(
            label: 'عدّل المشروع',
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
        if (status == ProjectStatus.open) const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onCancel,
          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('إلغاء المشروع'),
        ),
      ],
    );
  }
}

class OutlineButtonOnly extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const OutlineButtonOnly(
      {super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(label: label, onPressed: onPressed);
  }
}
