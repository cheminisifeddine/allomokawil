import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/text/dz_number.dart';
import '../../core/theme/app_theme.dart';
import '../../data/notification_copy.dart';
import '../../data/project_commit_outcome.dart';
import '../../data/quote_duration_copy.dart';
import '../../data/quote_status_copy.dart';
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
import '../../core/l10n/snack.dart';
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

  /// The wall clock the bids' ages are measured against.
  ///
  /// `relativeTimeAr` renders from the *difference* to now, so a screen that
  /// reads the real clock is a screen whose pixels depend on when the test
  /// ran: «الآن» on one run and «قبل 3 دقائق» on the next, which is how a
  /// golden test comes to fail for no reason a reader can see. This is the
  /// same seam `NotificationsScreen` and `WorkerProfileScreen` already carry,
  /// added here for the same reason. Production leaves it null; the tests hand
  /// in a fixed instant.
  final DateTime Function()? clock;

  const ProjectDetailScreen(
      {super.key,
      required this.projectId,
      required this.repo,
      this.clock});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late Future<Project> _project;
  late Future<List<Quote>> _quotes;

  /// The quote being accepted right now, or null when the owner is not
  /// mid-commit. Set before the POST is issued and cleared in a `finally`, so
  /// the guard cannot outlive the request it was written for.
  ///
  /// Holding the id rather than a bool is what lets the right button show the
  /// spinner and the *other* buttons simply go dead: the quotes are a
  /// `ListView`, and a plain `loading` flag on every card would flash spinners
  /// on bids the owner never touched.
  int? _acceptingQuoteId;

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
    _project = _observe(widget.repo.getProject(widget.projectId));
    _quotes = _observe(widget.repo.projectQuotes(widget.projectId));
  }

  void _reload() {
    setState(() {
      _project = _observe(widget.repo.getProject(widget.projectId));
      _quotes = _observe(widget.repo.projectQuotes(widget.projectId));
    });
  }

  /// Marks a read as observed from the moment it is issued, not from the moment
  /// it is watched.
  ///
  /// Dart reports a future as an *unhandled* error when it completes with one
  /// and no listener was attached in time. The quote read is started in
  /// [initState], but the `FutureBuilder` that displays it does not exist yet:
  /// it lives inside the body of the *project's* `FutureBuilder`, so it is not
  /// even constructed until the project read resolves. A 500 on the quotes call
  /// that lands first — the likelier of the two on a flaky mobile connection,
  /// and the one that happens when both are racing the same dead network —
  /// therefore completed with nobody listening and was reported as an uncaught
  /// async error.
  ///
  /// That is not a cosmetic warning. An unhandled async error in the root zone
  /// is exactly what the crash reporter records, so a routine server blip on
  /// the quotes call was being filed as a *crash* — and on the one screen the
  /// owner of a job is looking at while deciding whether to trust the platform.
  ///
  /// This attaches a no-op error listener immediately, which is what makes the
  /// future handled. The error is not swallowed: [FutureBuilder] still sees
  /// `hasError` and still renders the state below, because this listener runs
  /// alongside the builder's rather than instead of it.
  ///
  /// Generic because both reads on this screen need it. The quote read was
  /// given one; the *project* read was not, and it is the one that fires on the
  /// path this screen is judged by — `_accept` calls `_reload()`, and a server
  /// that answers the accept but not the re-read left a failed future with no
  /// listener, so the owner got a red screen in release *after* a successful
  /// commit instead of the error state the screen can already draw.
  static Future<T> _observe<T>(Future<T> f) {
    f.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return f;
  }

  /// Owner accepts a quote — the backend rejects every other one.
  ///
  /// This is the only write in the product that commits a contract, and it was
  /// the only one shipping with no `catch`. `_complete` and `_cancel`, twenty
  /// lines below, were repaired in earlier ticks and both wrap the call and
  /// report through `errorCopy`; this one ran bare, so a refused accept — 409
  /// because the web app already accepted a different bid, 500, a dropped
  /// connection — escaped as an *unhandled* async error. In release that is a
  /// red screen plus a crash report, and the owner never learns whether the
  /// contractor he just hired is hired: the button looks tapped, nothing
  /// happens, forever. It now answers in the same Arabic as its siblings.
  ///
  /// The `_acceptingQuoteId` guard is the half a `catch` cannot fix. The button
  /// used to stay enabled for the whole round-trip, so a second tap on a slow
  /// connection — which is what everyone does, and what a stalled POST
  /// provokes — fired a second accept at a project the backend has already
  /// committed to somebody else. The guard clears in `finally`, never in the
  /// success path, so a failure does not leave the owner with a dead button
  /// and no way to retry the one action on this screen he cannot walk back.
  Future<void> _accept(Quote q) async {
    if (_acceptingQuoteId != null) return; // a commit is already in flight
    setState(() => _acceptingQuoteId = q.id);
    try {
      await widget.repo.acceptQuote(widget.projectId, q.id);
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // «تحقّق من القائمة» with no re-read is an instruction the owner cannot
        // follow: the project on screen is the one from before the tap. The
        // accept is the only write in the product that signs a contract, so
        // this is the one place where a stalled request must be resolved
        // rather than reported. See `project_commit_outcome.dart`.
        //
        // The raw sentence is **not** shown first. `errorCopy(e)` returns
        // `errWriteUnconfirmed` verbatim here, and queueing it ahead of the
        // answer would make the client read «لم يصل... أعد المحاولة» — a
        // retry that may hire a second contractor — four seconds before the
        // toast that says the first one won. One failure, one line: the
        // recheck line goes up, and the answer replaces it.
        if (mounted) _showRechecking();
        final r = await _resolveCommit(ProjectCommit.accept, workerId: q.workerId);
        if (!mounted) return;
        _reload();
        _showCommitResult(projectCommitCopy(r, ProjectCommit.accept));
      } else if (mounted) {
        showNote(context, errorCopy(e));
      }
      return;
    } finally {
      if (mounted) setState(() => _acceptingQuoteId = null);
    }
    if (!mounted) return;
    showNote(context, 'تم قبول العرض، سيتم رفض باقي العروض');
    // Re-read after confirming. If this read fails the screen now shows its
    // failed-read state, which is the honest answer: the quotes still listed
    // below belong to a project the server has already reassigned, and their
    // accept buttons would now all be refused.
    _reload();
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
      if (isWriteUnconfirmed(e)) {
        // This is the only door into the review form, so a stall that is not
        // resolved leaves the owner unable to rate the job he paid for. Same
        // one-line rule as `_accept`: the raw sentence is replaced, not queued
        // behind the answer.
        if (mounted) _showRechecking();
        final r = await _resolveCommit(ProjectCommit.complete);
        if (!mounted) return;
        _reload();
        _showCommitResult(projectCommitCopy(r, ProjectCommit.complete));
      } else if (mounted) {
        showNote(context, errorCopy(e));
      }
      return;
    }
    if (!mounted) return;
    _openReview(project);
    _reload();
  }

  /// «نتحقّق الآن من القائمة…» — the line that replaces the one sentence it is
  /// about to contradict.
  ///
  /// It is a recheck line, not an error line, because the failure has not been
  /// classified yet and the user is owed an answer rather than an apology.
  void _showRechecking() {
    showNote(context, recheckNote(notifications: false));
  }

  /// The classified answer, drawn in place of the recheck line.
  ///
  /// `ScaffoldMessenger` **queues** by default: a second `showSnackBar` while
  /// one is visible waits for the first to time out, so the client would read
  /// the stale line for its full four seconds before the true one arrived. On
  /// this screen the stale line is not a harmless placeholder — it is a
  /// contract he may have already signed — so the queue is removed first and
  /// only the answer is left on screen.
  void _showCommitResult(String copy) => showVerdict(context, copy);

  /// Re-reads the project after a commit whose answer never arrived, and
  /// classifies what the server now holds.
  ///
  /// The re-read is a bare `getProject`. It must never throw, so a second
  /// network failure while we are already reporting one is caught here and read
  /// as [WriteOutcome.unknown] — never as «not saved», which is the one answer
  /// that would send an owner pressing a button the server may already have
  /// honoured.
  ///
  /// Deliberately does **not** call `_reload()`: the caller does that once it
  /// knows it is still mounted, so a screen torn down mid-probe does not call
  /// `setState` on a dead [State].
  Future<ProjectCommitResult> _resolveCommit(
    ProjectCommit what, {
    int? workerId,
  }) async {
    try {
      final fresh = await widget.repo.getProject(widget.projectId);
      return classifyProjectCommit(fresh, what, workerId: workerId);
    } catch (_) {
      return (outcome: WriteOutcome.unknown, stall: null);
    }
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
      if (isWriteUnconfirmed(e)) {
        if (mounted) _showRechecking();
        final r = await _resolveCommit(ProjectCommit.cancel);
        if (!mounted) return;
        _reload();
        _showCommitResult(projectCommitCopy(r, ProjectCommit.cancel));
      } else if (mounted) {
        showNote(context, errorCopy(e));
      }
      return;
    }
    if (!mounted) return;
    showNote(context, 'تم إلغاء المشروع');
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
                          onRetry: _reload,
                          acceptingQuoteId: _acceptingQuoteId,
                          clock: widget.clock,
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

  /// «الجزائر — حسين داي» on the details card, or the wilaya alone.
  ///
  /// **The em dash is the whole point of the null branch.** This is server
  /// data, so the wilaya can be absent (`Project.fromJson` turns a missing
  /// field into `''`) or be a code this build does not know. The old body
  /// resolved both through the fallback and printed «الجزائر», so a project
  /// with no location at all was filed under the capital — and a commune alone
  /// with no wilaya printed «الجزائر — X» on a row the client had no evidence
  /// for. Now an unknown wilaya keeps the commune it does have, and a row with
  /// neither prints nothing rather than inventing a place.
  String _locationLabel(Project project) {
    final wilaya = Taxonomy.wilayaNameOrNull(project.wilaya);
    final commune = project.commune;
    final hasCommune = commune != null && commune.isNotEmpty;
    if (wilaya == null) return hasCommune ? commune : '—';
    if (!hasCommune) return wilaya;
    return '$wilaya — $commune';
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
  ///
  /// The three fields are built and owned by [_BidSheet], which disposes their
  /// controllers when the route goes away. They used to be built *here*, as
  /// locals of this method, and nothing disposed them: a local is not cleaned up
  /// by the framework, so every tap of «قدّم عرضك» stranded three
  /// `TextEditingController`s — each holding a native input connection and a
  /// listener list — for the life of the process. This function has **five**
  /// exits (cancel, the auth wall, a below-minimum amount, a bad duration, and
  /// the 402 upgrade branch), so a single `dispose` bolted on at the end would
  /// have missed every one of them but the last. Ownership is the fix, not a
  /// cleanup call: a `StatefulWidget` holding the controllers disposes them in
  /// one place the framework runs on *every* route exit, however the sheet
  /// closed.
  Future<void> _showBidSheet(Project project) async {
    // A guest can read the project; the form that cannot be submitted is
    // replaced by the form that turns him into a contractor.
    if (_requireAccount(UserRole.worker)) return;
    final submitted = await showModalBottomSheet<_BidDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BidSheet(),
    );
    if (submitted != null) {
      if (!mounted) return;
      // Folded parse: a contractor who typed `٢٥٠٠٠` on an Arabic keypad, or
      // pasted `25.000 دج` out of a note, means 25000 — not "no amount".
      final amt = DzNumber.tryParse(submitted.amount, min: 1000);
      final rawDays = submitted.days.trim();
      final dayCount = DzNumber.tryParse(rawDays, min: 1);
      if (amt == null) {
        showNote(context, 'المبلغ يجب أن يكون 1000 دج على الأقل');
      } else if (rawDays.isNotEmpty && dayCount == null) {
        showNote(context, 'مدة الإنجاز يجب أن تكون عدداً من الأيام');
      } else {
        try {
          await widget.repo.submitQuote(
            projectId: project.id,
            amount: amt,
            message: submitted.message.trim().isEmpty
                ? null
                : submitted.message.trim(),
            estimatedDays: dayCount,
          );
          if (mounted) {
            showNote(context, 'تم إرسال عرضك');
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
            //
            // `_showRechecking` rather than a bare `showSnackBar`: this is the
            // same recheck line the owner-facing commits draw, and the answer
            // that follows it is the only sentence that tells this contractor
            // whether he sent one bid or two.
            _showRechecking();
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
            // `_showCommitResult`, not a bare `showSnackBar`. `ScaffoldMessenger`
            // **queues** by default, so the verdict used to wait behind the
            // recheck line's full four-second duration and reach the screen
            // last — the one message that answers «did my bid arrive?» is the
            // one the contractor reads after being told, for four more seconds,
            // that the app is still checking. `_accept` and `_complete` on this
            // same screen have always removed the line first.
            _showCommitResult(writeOutcomeCopy(outcome));
            return;
          }
          showNote(context, errorCopy(e));
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

/// What the contractor typed in the bid sheet, handed back to the screen.
///
/// Plain strings, read at the moment «إرسال العرض» is pressed. They are
/// deliberately *not* the controllers: returning the live objects would put
/// the screen back in the very position this class exists to end — holding a
/// reference to something whose lifetime it does not own, and reading it after
/// the route that built it has already been torn down.
class _BidDraft {
  const _BidDraft({
    required this.amount,
    required this.days,
    required this.message,
  });

  final String amount;
  final String days;
  final String message;
}

/// The bid form itself, and the owner of its three controllers.
///
/// A `StatefulWidget` rather than the locals the screen used to build, because
/// ownership *is* the fix. A controller created inside a method has no owner:
/// nothing disposes it, no linter can see it, and the sheet closes five
/// different ways. Held as fields here, they are disposed in one place the
/// framework runs on every exit from the route — the barrier tap, the back
/// gesture, the send button, a validation failure, even a throw — so there is
/// no path that leaks and no second exit to remember to add a `dispose` to.
class _BidSheet extends StatefulWidget {
  const _BidSheet();

  @override
  State<_BidSheet> createState() => _BidSheetState();
}

class _BidSheetState extends State<_BidSheet> {
  final _amount = TextEditingController();
  final _days = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _days.dispose();
    _message.dispose();
    super.dispose();
  }

  /// Hands back the three strings, not the controllers — see [_BidDraft].
  void _send() {
    Navigator.of(context).pop(
      _BidDraft(
        amount: _amount.text,
        days: _days.text,
        message: _message.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            controller: _amount,
            labelText: 'المبلغ (دج)',
            suffixText: 'دج',
          ),
          const SizedBox(height: 12),
          NumberField(
            controller: _days,
            labelText: 'مدة الإنجاز (أيام)',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'رسالتك (اختياري)'),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'إرسال العرض',
            icon: Icons.send_rounded,
            onPressed: _send,
          ),
        ],
      ),
    );
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
    // Same rule as `_locationLabel`, read off the payload rather than off the
    // project object: an unknown wilaya leaves the commune it does have, and
    // neither field means the chip is dropped instead of named wrong.
    final wilaya = Taxonomy.wilayaNameOrNull(project.wilaya);
    final hasCommune = commune != null && commune.isNotEmpty;
    final place = wilaya == null
        ? (hasCommune ? commune : null)
        : (hasCommune ? '$wilaya — $commune' : wilaya);
    if (place == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusPill.project(project.status.wire),
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

  /// The quote with an accept POST in flight, or null. Every accept button is
  /// disabled while this is set, and the matching one shows the spinner.
  final int? acceptingQuoteId;

  /// Re-issues the quote read. The screen's own `_reload`, so the retry is a
  /// real request and not a redraw of the same failure.
  ///
  /// `snap.hasError` and this callback are the two halves of the fix, and they
  /// were both already here: the FutureBuilder could tell the states apart
  /// since it was written, and `_reload` has always re-issued the read. What
  /// was missing was the branch between them.
  final VoidCallback onRetry;

  /// The wall clock the bid ages are measured against.
  /// See [ProjectDetailScreen.clock].
  final DateTime Function()? clock;

  const _QuotesSection({
    required this.quotesFuture,
    required this.project,
    required this.isOwner,
    required this.onAccept,
    required this.onBid,
    required this.onRetry,
    required this.acceptingQuoteId,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Quote>>(
      future: quotesFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _QuotesSkeleton();
        }
        // **A failed read is not an empty quote list.**
        //
        // The line below used to be `final quotes = snap.data ?? const
        // <Quote>[];`. `snap.data` is null on an error exactly as it is on a
        // genuinely empty list, and this builder never asked which one it was,
        // so the two were indistinguishable from here: one 500 — one dropped
        // connection, one host not answering, one captive portal on hotel wifi
        // — and the owner of a posted project was shown «لا عروض بعد» with a
        // button that sends him to the contractor directory to fish for pros
        // himself.
        //
        // This is the third screen in that family, and it is the worst of the
        // three. The other two hid a photo count («لم يضف صوراً بعد», «أضف
        // صوراً»). This one makes a false claim about *demand*: that nobody
        // bid on the job he paid to advertise. The owner's rational response
        // is to distrust the platform, lower the price, or repost elsewhere —
        // all more expensive than one retry button.
        //
        // The screen's own project read one widget up already does this, with
        // `snap.hasError` and the same `_reload`; the quote list was the one
        // section that never did.
        if (snap.hasError) {
          return EmptyView(
            icon: Icons.error_outline_rounded,
            title: 'تعذّر تحميل العروض',
            message: errorCopy(snap.error),
            actionLabel: 'أعد المحاولة',
            onAction: onRetry,
            danger: true,
            titleColor: AppTheme.danger,
          );
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
                clock: clock,
                // Any accept in flight disables every button: the server
                // rejects all other bids the moment one lands, so offering
                // them as tappable is offering a dead end.
                accepting: acceptingQuoteId != null,
                isThisAccepting: acceptingQuoteId == q.id,
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

  /// An accept POST is in flight somewhere on this project.
  final bool accepting;

  /// This card's quote is the one being accepted — the only card that spins.
  final bool isThisAccepting;

  /// The wall clock the bid's age is measured against; see
  /// [ProjectDetailScreen.clock].
  final DateTime Function()? clock;

  const _QuoteCard({
    required this.quote,
    required this.isOwner,
    required this.onAccept,
    this.accepting = false,
    this.isThisAccepting = false,
    this.clock,
  });

  @override
  Widget build(BuildContext context) {
    // Built once: the row's visibility and its text are the same value, and
    // asking the copy file twice to reach the same answer is the kind of
    // drift this file exists to stop.
    final durationLine = quoteDurationLineAr(quote.estimatedDays);
    final statusLabel = quoteStatusAr(quote.status);
    // A bid the server has already decided is a past fact, so it gets a date
    // line as well as a stamp. The same two rows the review card prints, from
    // the same two functions — not a fourth grammar.
    final sentLine = relativeTimeAr(quote.createdAt, now: clock?.call());
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
                    // «مقبول» / «مرفوض», and nothing at all while the bid is
                    // still live — a stamp on every card would be noise on the
                    // only case that needs no explanation.
                    if (statusLabel.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: StatusPill.quote(quote.status),
                      ),
                    if (statusLabel.isNotEmpty) const SizedBox(height: 6),
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
                if (sentLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sentLine,
                      style: AppTheme.bodySoft
                          .copyWith(fontSize: AppTheme.fsMeta)),
                ],
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
          // The action row, and the sentence under it, are drawn for the owner
          // **only while his decision is real**.
          //
          // This is the defect this card was rebuilt for. The Worker rejects
          // every other bid at the moment one is accepted, and it sends that
          // verdict back on each row as `status`. The model dropped the field,
          // so the losing card kept a live «قبول العرض» button: the owner taps
          // it, the server answers `{"ok":true}`, the screen reloads and the
          // card is byte-for-byte identical to the one before the tap — while
          // the project reads a `selected_worker_id` that names the bid that
          // *won*. The one write in this product that signs a contract appeared
          // to work while committing nothing, and the sentence under the button
          // («بالقبول تُرفض باقي العروض تلقائياً») then told him the rejection
          // was still ahead of him when it had already happened.
          //
          // So the button and its sentence are removed together, and replaced
          // by the verdict: which bid won, and that this one did not. A decided
          // bid is not an error and not an empty state — it is the outcome of a
          // competitive marketplace, and the owner deserves to read it rather
          // than to be left tapping a card that cannot change anything.
          if (isOwner) ...[
            const SizedBox(height: 14),
            if (!quote.isDecided) ...[
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
                      // `loading` is what disables it, so the in-flight card and
                      // its siblings are gated by the same flag.
                      loading: isThisAccepting,
                      onPressed: accepting ? null : onAccept,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('بالقبول تُرفض باقي العروض تلقائياً.',
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.textSecondary)),
            ] else
              Text(
                quoteStatusNoteAr(quote.status),
                style: AppTheme.caption.copyWith(
                  color: quote.status == QuoteStatus.accepted
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
