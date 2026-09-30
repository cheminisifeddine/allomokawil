import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/l10n/snack.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/write_outcome.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
import '../../data/pending_request_copy.dart';
import '../../data/redeem_outcome.dart';
import '../../data/subscription_write_outcome.dart';
import '../../data/subscription_ack.dart';
import '../../data/plan_renewal_copy.dart';
import '../../data/plan_reach_copy.dart';
import '../../data/stale_catalogue_copy.dart';
import '../../data/quote_count_copy.dart';
import '../../data/repository.dart';
import '../../models/plan.dart';
import '../../models/notification.dart' show parseServerTime;
import '../../widgets/skeletons.dart';
import '../../widgets/a11y.dart';
import '../../widgets/ui.dart';

/// «اشتراكي» — the contractor's subscription, and the app's revenue surface.
///
/// Why it exists: v1 was free for everyone, so it could never earn. The founder
/// set the model — the **مقاول pays a subscription**, monthly or annual, with
/// **no commission on any order** and **no percentage of a project's total**.
/// This screen is where that offer is shown and where the money is taken.
///
/// Nothing about pricing is hard-coded. Plans, limits, the "no commission"
/// promise and the payment instructions all render from
/// `GET /api/mobile/subscription`, so a price change is one UPDATE in D1 and
/// every installed app shows it on next open.
///
/// Payment is built for Algeria, not for a Stripe-shaped market: cash, BaridiMob
/// and CCP transfers are first-class, a prepaid **activation code** redeems
/// instantly without waiting for a human, and a card gateway (CIB/Edahabia) can
/// be switched on later by publishing its method in the same catalogue.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.clock});

  /// The wall clock, injectable so a test can age the stale band without
  /// waiting a real hour. Defaults to the system clock in the app.
  ///
  /// Same reason `CustomerHomeScreen` has one: the band below is aged by a
  /// once-a-minute tick, and the only frame in which that age is deliberately
  /// silent is the first minute after a read. A test that cannot inject a
  /// clock can only ever photograph the silent case.
  final DateTime Function()? clock;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final Repository _repo;
  bool _scopeReady = false;

  BillingCatalogue? _catalogue;
  bool _loading = true;
  String? _error;

  /// When the figures on screen were last read successfully, and the tick
  /// that ages them.
  ///
  /// The stamp is written where the read *settles*, not where it is issued,
  /// so a request that took forty seconds on a cell network is dated at the
  /// moment it actually landed — the case where the number matters most.
  /// `null` means "nothing has been read yet", and a band over nothing is the
  /// `_LoadFailed` state, which says its own thing.
  DateTime? _catalogueReadAt;
  Timer? _ageTimer;

  /// Monthly by default: it is the smaller decision. The toggle is remembered
  /// for the life of the screen so a contractor comparing prices does not have
  /// to re-pick the period between two taps.
  BillingPeriod _period = BillingPeriod.month;

  bool _busy = false;
  final _codeController = TextEditingController();

  /// The sentence that says the price on this screen and the price D1 just
  /// charged are not the same number.
  ///
  /// It used to be a [SnackBar], which made it the shortest-lived sentence on
  /// the one screen where a man is about to move money: four seconds, and then
  /// the screen reverts to drawing **only** the quoted figure, so the last
  /// thing left standing is the price the app got wrong. See
  /// `subscription_ack.dart` and [planPriceMismatchKey].
  ///
  /// Held as state rather than drawn from the snackbar queue, so it survives
  /// the write, the reload and the four seconds. Cleared only by a fresh
  /// purchase or a re-read that changes the terms.
  ///
  /// The **figures**, not the sentence. The band is one consumer of them; the
  /// other is the price on the plan card, which used to keep drawing the
  /// disputed figure in the same accent as a price it was sure of, so the two
  /// halves of one screen could contradict each other with nothing saying
  /// which one was wrong. See [PlanPriceDispute].
  PlanPriceDispute? _priceDispute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scopeReady) return;
    _scopeReady = true;
    _repo = Repository(AppScope.of(context).api);
    _load();
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  /// The wall clock, injectable for tests. See [SubscriptionScreen.clock].
  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// The dispute that applies to one plan at one term, or null.
  ///
  /// The **one** place the screen decides whether a price on screen is under
  /// question for a given card. The two cards ask this rather than testing the
  /// state themselves, so a third consumer cannot come along with its own
  /// slightly different condition.
  PlanPriceDispute? _disputeFor(String planId, BillingPeriod period) {
    final d = _priceDispute;
    if (d == null) return null;
    return d.appliesTo(planId, period.wire) ? d : null;
  }

  /// The dispute the **band** should draw, or null.
  ///
  /// Scoped by term only, not by plan, and the difference is the whole point:
  /// the band sits above the current-plan card and names no plan, so it is a
  /// statement about the account. But its sentence quotes two figures, and one
  /// of them is "the price displayed" — so it is only true while the term it
  /// was found on is the term being drawn.
  ///
  /// It used to read the state field directly, which made it the **only**
  /// consumer on this screen that did not scope itself: the cards answered
  /// through [_disputeFor] and dropped their strike the moment the toggle
  /// moved, while the band stayed up naming «3000 دج» as the disputed figure
  /// while the screen was quoting «30000 دج» — a number no one had ever
  /// disputed — and telling him to confirm it with support. One fact, two
  /// consumers, two different answers about how long it was true.
  ///
  /// Not scoped by plan on purpose. Hiding the band because he scrolled to
  /// another tier's card would take away the one sentence that says a payment
  /// he already made was for a different number than he was shown, which is
  /// the thing he needs to read about *his account*, not about a card.
  PlanPriceDispute? get _bandDispute {
    final d = _priceDispute;
    if (d == null) return null;
    return d.appliesToTerm(_period.wire) ? d : null;
  }

  /// Starts the once-a-minute tick that ages the band, once there is a stamp
  /// to age.
  ///
  /// Re-armed from the same place the stamp is written, so a re-read that puts
  /// the old stamp back does not leave two live timers. Called from [_load]
  /// rather than from `build`, because a timer created in `build` is a new
  /// timer on every frame and the tick would multiply.
  void _armAgeTick() {
    if (!mounted) return;
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      // Nothing to age yet: a first read that has not landed has no figures,
      // and a band only ever appears over figures that do.
      if (_catalogueReadAt == null) return;
      setState(() {});
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = _catalogue == null;
      _error = null;
    });
    try {
      final data = await _repo.subscription();
      if (!mounted) return;
      setState(() {
        _catalogue = data;
        _loading = false;
        // The clock *now*, not the moment the request was issued, so a read
        // in flight for forty seconds is dated when it actually landed.
        _catalogueReadAt = _now();
      });
      _armAgeTick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorCopy(e);
      });
    }
  }

  /// Every line on this screen replaces one, **including** the validation
  /// ones.
  ///
  /// That is a deliberate non-change: «أدخل رمز التفعيل» is a bare form
  /// complaint, so the obvious reading is [showNote] — but the man reaches it
  /// by tapping «تفعيل» on a form that also carries the previous attempt's
  /// answer («وجدناه في القائمة — الطلب وصل بنجاح»), and leaving that verdict
  /// in the queue behind a form complaint is a line he reads as the state of
  /// his *code*. Hiding it is the same rule the recheck path uses for the same
  /// reason: a stale answer is worse than no answer.
  ///
  /// It is recorded here because the next tick will read
  /// `showNote`/`showVerdict` and assume `_note` is the correct entry for these
  /// four lines. It is not, on this screen, and the reason is above.
  void _say(String message) => showVerdict(context, message);

  /// Declares a payment for [plan] after the contractor picked how to pay.
  ///
  /// [before] is the pending request the catalogue already held when the sheet
  /// was opened, and it is what makes an unconfirmed write answerable: see
  /// `subscription_write_outcome.dart` for why «did it land» cannot be asked by
  /// comparing the plan, and why it is asked by comparing the request id.
  Future<void> _request(
    Plan plan,
    PaymentMethod method,
    String? reference, {
    PendingRequest? before,
  }) async {
    setState(() => _busy = true);
    try {
      // The answer carries the one figure the follow-up read cannot: the server
      // says what to transfer, while the pending row it files carries
      // `amount_paid: 0` until a human confirms. It used to be discarded here
      // and the man was told only that his request arrived.
      final answer = await _repo.requestSubscription(
        plan: plan.id,
        period: _period,
        method: method.id,
        reference: reference,
      );
      final ack = SubscriptionAck.tryParse(answer);
      _say(subscriptionAckAr(ack) ?? S.planRequestOk);
      // The sheet's price is the app's arithmetic over a catalogue fetched
      // earlier; the answer's amount is D1's, computed now. If a price moved in
      // between, both are reported and neither is asserted.
      final dispute = PlanPriceDispute.between(
        planId: plan.id,
        periodWire: _period.wire,
        quotedDzd: plan.priceFor(_period),
        chargedDzd: ack?.amountDzd,
      );
      // A banner, **not** a `_say`. `_say` hides whatever is on screen first,
      // which is the right rule for a verdict replacing the line it contradicts
      // and the wrong one here: this warning is the *second* sentence of the
      // same write, drawn on purpose, and it has nothing above it to replace.
      // As a toast it replaced the acknowledgement carrying the transfer
      // figure and was then replaced by nothing at all, four seconds later,
      // leaving the quoted price alone on the screen as if it were the one to
      // pay. The acknowledgement is kept as a toast; the disagreement is a fact
      // about the account and is held until it changes.
      if (mounted) {
        setState(() => _priceDispute = dispute);
      }
      await _load();
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // The app refused to guess whether this payment request landed, and
        // told the man to check the list. On this screen the list is the
        // pending-request slot, so check it - right now - and answer with what
        // the server actually holds. A contractor told «maybe it did not
        // arrive» who then sees nothing change cannot tell a dropped request
        // from one the server filed, and the next thing he thinks of is
        // paying twice for the same plan.
        _say(recheckNote(notifications: false));
        final outcome = await resolveSubscriptionWriteOutcome(
          before: before,
          fetch: _repo.subscription,
        );
        if (!mounted) return;
        _say(writeOutcomeCopy(outcome));
        await _load();
        return;
      }
      _say(errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The instant path: a code bought in cash (shop, agent, BaridiMob receipt)
  /// activates the plan on the spot, with no human in the loop.
  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _say(S.planCodeHint);
      return;
    }
    // The plan on screen before the tap: the re-read is only meaningful
    // against what the app already believed, and the payment path above
    // already keeps exactly this snapshot.
    final before = _catalogue?.current;
    setState(() => _busy = true);
    try {
      final plan = await _repo.redeemActivationCode(code);
      // The only sentence on this screen that claims money changed hands, and
      // it is now gated on the answer actually naming a plan. A null is not a
      // redemption: it is the absence of one, and it used to be printed as
      // «تم تفعيل اشتراكك» on the strength of a missing field.
      _codeController.clear();
      if (plan == null) {
        // Cannot claim it worked, and must not claim it did not: ask instead.
        _say(S.planCodeNoPlan);
      } else {
        _say('${S.planCodeOk} — ${plan.toUpperCase()}');
      }
      await _load();
    } catch (e) {
      if (isWriteUnconfirmed(e)) {
        // An activation code is **single-use**. The request left the phone and
        // the answer never arrived, so the code may or may not have been
        // burned — and the only safe next step is for the app to find out
        // rather than for the man to type it again into a box that will
        // refuse it.
        _say(recheckNote(notifications: false));
        final outcome = await resolveRedeemWriteOutcome(
          codePlan: null,
          before: before,
          fetch: () async => (await _repo.subscription()).current,
        );
        if (!mounted) return;
        _say(writeOutcomeCopy(outcome));
        await _load();
        return;
      }
      _say(errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPaymentSheet(Plan plan) async {
    final catalogue = _catalogue;
    if (catalogue == null) return;
    final result = await showModalBottomSheet<_PaymentChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (_) => _PaymentSheet(
        plan: plan,
        period: _period,
        priceLabel: catalogue.priceLabel(plan, _period),
        // The dispute is passed **into** the sheet rather than looked up from
        // the screen behind it: the sheet is a separate route, it must survive
        // the screen being rebuilt, and a widget that reaches through a modal
        // barrier for its facts is a widget that disagrees with itself the
        // day the two are edited separately.
        dispute: _disputeFor(plan.id, _period),
        payment: catalogue.payment,
        renewNote: renewalNoteAr(catalogue.renewNoteAr),
        prepaid: catalogue.isPrepaid,
      ),
    );
    if (result == null) return;
    // Snapshotted when the sheet opened, not read at the moment of the POST:
    // the re-read compares this row against the fresh one, so a catalogue the
    // screen happened to re-render in between must not forge it.
    await _request(plan, result.method, result.reference,
        before: catalogue.pendingRequest);
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = _catalogue;
    // Read once, here, and used by the band below. Computed in `build` and not
    // in `_request` because the term the man is looking at can change without
    // any write happening, and the band has to follow the screen rather than
    // the event that created it.
    final bandDispute = _bandDispute;
    // The purchase the pending receipt has already claimed, if any. Read here,
    // in `build`, for the same reason the band is: the term changes with no
    // write happening at all, and the cards have to follow the screen rather
    // than the event that created the receipt.
    final claimed = pendingClaimFor(catalogue?.pendingRequest);
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.planTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: S.planRetry,
          ),
        ],
      ),
      body: _loading
          ? const SkeletonFormPage()
          : catalogue == null
              ? _LoadFailed(message: _error ?? S.planLoadFailed, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppTheme.gutter, AppTheme.s16, AppTheme.gutter, AppTheme.s32),
                    children: [
                      // Said out loud, above the numbers, and only when a
                      // re-read has actually failed. `_load` keeps the previous
                      // catalogue on purpose — discarding a paying
                      // contractor's plan because a cell network blinked
                      // would be worse than showing him last read's truth — but
                      // until this existed, that decision was invisible: the
                      // error it recorded was read only inside the
                      // `catalogue == null` branch, so every failed *refresh*
                      // (the button, the pull, the reload after a payment) left
                      // his real price, his pending payment and his remaining
                      // quota on screen with no statement that a newer read had
                      // failed. See `stale_catalogue_copy.dart`.
                      if (_error != null) ...[
                        _StaleBanner(
                            line: staleCatalogueLineWithAgeAr(
                                _error!, _catalogueReadAt,
                                now: _now())),
                        const SizedBox(height: AppTheme.gap),
                      ],
                      // Above the plan card, not below it: the figure this
                      // disputes is the one drawn on the card, so the warning
                      // has to be read before the number, not after. Same
                      // shape as the stale band above it, and for the same
                      // reason — both are statements about the figures
                      // underneath, not about the account.
                      if (bandDispute != null) ...[
                        _StaleBanner(
                          line: bandDispute.lineAr,
                          key: const Key(planPriceMismatchKey),
                          icon: Icons.price_check_rounded,
                        ),
                        const SizedBox(height: AppTheme.gap),
                      ],
                      _CurrentPlanCard(status: catalogue.current),
                      if (catalogue.pendingRequest != null) ...[
                        const SizedBox(height: AppTheme.gap),
                        _PendingCard(
                          request: catalogue.pendingRequest!,
                          planNameAr:
                              catalogue.planById(catalogue.pendingRequest!.plan)
                                      ?.nameAr,
                          methodLabel: catalogue.payment
                              .labelFor(catalogue.pendingRequest!.method ?? ''),
                        ),
                      ],
                      const SizedBox(height: AppTheme.gap),
                      _PromiseCard(
                        note: catalogue.noteAr.isEmpty
                            ? S.planNoteFallback
                            : catalogue.noteAr,
                        noCommission: catalogue.noCommission,
                        renewNote: renewalNoteAr(catalogue.renewNoteAr),
                        prepaid: catalogue.isPrepaid,
                      ),
                      const SizedBox(height: AppTheme.s24),
                      const SectionTitle(S.planChoose, icon: Icons.workspace_premium_outlined),
                      const SizedBox(height: AppTheme.s12),
                      _PeriodToggle(
                        period: _period,
                        onChanged: (p) => setState(() => _period = p),
                      ),
                      const SizedBox(height: AppTheme.s12),
                      for (final plan in catalogue.purchasable) ...[
                        _PlanCard(
                          plan: plan,
                          period: _period,
                          priceLabel: catalogue.priceLabel(plan, _period),
                          dispute: _disputeFor(plan.id, _period),
                          current: catalogue.current.plan == plan.id,
                          busy: _busy,
                          claimed: claimed,
                          requestId: catalogue.pendingRequest?.id,
                          onChoose: () => _openPaymentSheet(plan),
                        ),
                        const SizedBox(height: AppTheme.s12),
                      ],
                      const SizedBox(height: AppTheme.s8),
                      _CodeCard(
                        controller: _codeController,
                        busy: _busy,
                        onRedeem: _redeem,
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ── Current plan ────────────────────────────────────────────────────────────

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final paid = !status.isFree && !status.isExpired;
    final left = status.quotesLeft;

    return AppCard(
      color: paid ? AppTheme.accentWash : AppTheme.surface,
      borderColor: paid ? AppTheme.accent : AppTheme.cardLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBubble(
                icon: paid ? Icons.verified_rounded : Icons.person_outline_rounded,
                tint: paid ? AppTheme.navy : AppTheme.navy,
                wash: paid ? AppTheme.accent : AppTheme.lineSoft,
              ),
              const SizedBox(width: AppTheme.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.planCurrent,
                        style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.s4),
                    Text(status.nameAr.isEmpty ? status.plan : status.nameAr,
                        style: AppTheme.h2),
                  ],
                ),
              ),
              StatusPill(
                label: paid ? 'مفعّل' : (status.isFree ? S.planFree : 'منتهي'),
                color: paid ? AppTheme.success : AppTheme.info,
                wash: paid ? AppTheme.successWash : AppTheme.infoWash,
                icon: paid ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s16),
          _UsageLine(status: status),
          if (left != null) ...[
            const SizedBox(height: AppTheme.s8),
            LinearProgressIndicator(
              value: status.quoteLimit <= 0
                  ? 1
                  : (status.quotesUsedThisMonth / status.quoteLimit).clamp(0, 1).toDouble(),
              minHeight: AppTheme.s8,
              backgroundColor: AppTheme.lineSoft,
              valueColor: AlwaysStoppedAnimation<Color>(
                  status.isQuotaSpent ? AppTheme.danger : AppTheme.accent),
            ),
          ],
          if (status.expiresAt != null && paid) ...[
            const SizedBox(height: AppTheme.s12),
            Text(
              // Count and date from the same instant, so the two can never
              // disagree the way a server-computed count and a locally-formatted
              // date did. Null only when the expiry is unreadable.
              status.expiryCountdownAr ?? _shortDate(status.expiresAt!),
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final text = status.hasUnlimitedQuotes
        ? unlimitedQuotesUsageAr(status.quotesUsedThisMonth)
        : cappedQuotesUsageAr(status.quotesUsedThisMonth, status.quoteLimit,
            isFree: status.isFree);
    return Text(
      text,
      style: AppTheme.body.copyWith(
        color: status.isQuotaSpent ? AppTheme.danger : AppTheme.textPrimary,
        fontWeight: status.isQuotaSpent ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

// ── The product promise ─────────────────────────────────────────────────────

/// The two sentences that make this offer different from every Houzz-style
/// marketplace: subscription only, never a cut of the job. When the server
/// reports a non-zero commission the sentence changes instead of lying.
class _PromiseCard extends StatelessWidget {
  const _PromiseCard({
    required this.note,
    required this.noCommission,
    required this.renewNote,
    required this.prepaid,
  });

  final String note;
  final bool noCommission;

  /// The founder's own renewal sentence, already trimmed or null.
  final String? renewNote;

  /// True only when the server explicitly said nothing renews itself.
  final bool prepaid;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppTheme.surfaceAlt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBubble(
            icon: Icons.handshake_outlined,
            tint: AppTheme.navy,
            wash: AppTheme.accentWash,
          ),
          const SizedBox(width: AppTheme.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noCommission ? 'بدون عمولة ولا نسبة' : 'سياسة العمولة',
                    style: AppTheme.h2),
                const SizedBox(height: AppTheme.s4),
                Text(
                  note.isEmpty ? S.planNoteFallback : note,
                  style: AppTheme.body.copyWith(
                      color: AppTheme.textSecondary, height: 1.6),
                ),
                if (renewNote != null) ...[
                  const SizedBox(height: AppTheme.s8),
                  _PrepaidBadge(note: renewNote!, prepaid: prepaid),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «الدفع مسبق — لا يوجد خصم تلقائي من البطاقة».
///
/// The sentence the server writes ([BillingCatalogue.renewNoteAr]), shown next
/// to the price on the card a contractor reads before he pays. It sits inside
/// the promise card rather than under the toggle because it is the *other half*
/// of the same promise: that card says «we never take a cut», and this says
/// «and nothing charges you again later» — a man deciding with cash in Algiers
/// needs both, and until this shipped the app said only the first.
///
/// [prepaid] is the server's `auto_renew: false`, not a local constant. When
/// the flag is absent the sentence is still printed — it is the founder's
/// wording, and it is true whenever it was published — but the tick beside it
/// is withheld, because a checkmark that means "we promise" must never be
/// drawn off a field the server did not send.
class _PrepaidBadge extends StatelessWidget {
  const _PrepaidBadge({required this.note, required this.prepaid});

  final String note;
  final bool prepaid;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          prepaid ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: AppTheme.s20,
          color: AppTheme.success,
        ),
        const SizedBox(width: AppTheme.s8),
        Expanded(
          child: Text(
            note,
            style: AppTheme.body.copyWith(
              color: AppTheme.textSecondary,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Period toggle ───────────────────────────────────────────────────────────

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.period, required this.onChanged});

  final BillingPeriod period;
  final ValueChanged<BillingPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.s4),
      decoration: AppTheme.fieldDecorationOf(),
      child: Row(
        children: [
          for (final p in BillingPeriod.values)
            Expanded(
              child: A11y.button(selected: p == period, child: GestureDetector(
                onTap: () => onChanged(p),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  padding: const EdgeInsets.symmetric(vertical: AppTheme.s12),
                  decoration: p == period
                      ? AppTheme.cardDecorationOf(
                          fill: AppTheme.navy,
                          border: AppTheme.navy,
                          radius: AppTheme.rSm,
                          shadow: const [],
                        )
                      : AppTheme.cardDecorationOf(
                          fill: Colors.transparent,
                          border: Colors.transparent,
                          radius: AppTheme.rSm,
                          shadow: const [],
                        ),
                  child: Column(
                    children: [
                      Text(
                        p.labelAr,
                        textAlign: TextAlign.center,
                        style: AppTheme.label.copyWith(
                          color: p == period ? AppTheme.surface : AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // No discount claim here. The hint that used to sit under
                      // this arm was a fixed «سنة كاملة بسعر عشرة أشهر» — one
                      // hand-written sentence about a number the server owns,
                      // printed on every plan. It is now computed per plan and
                      // printed on the card, next to the price it describes, by
                      // `yearlyTermHintAr`.
                    ],
                  ),
                ),
              )),
            ),
        ],
      ),
    );
  }
}

// ── One plan ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.period,
    required this.priceLabel,
    required this.dispute,
    required this.current,
    required this.busy,
    required this.claimed,
    required this.requestId,
    required this.onChoose,
  });

  final Plan plan;
  final BillingPeriod period;
  final String priceLabel;

  /// The price disagreement covering *this* plan at *this* term, or null.
  ///
  /// A `PlanPriceDispute?` rather than a bool, because the card does not merely
  /// grey a number out: it also has to print the figure D1 actually used, and
  /// the only honest source for that is the same four numbers the band is
  /// built from.
  final PlanPriceDispute? dispute;

  final bool current;
  final bool busy;

  /// The purchase a request awaiting payment has already claimed, or null.
  ///
  /// The reason this card is not the place to ask about a pending payment: it
  /// **is** the pending payment's own card, and it used to still offer a live
  /// «ترقية» on it. The receipt is drawn four lines above in the info colour,
  /// saying his request is being reviewed, and the amber button underneath
  /// asks for the same plan and the same term again. D1 files that as a
  /// second request — it has no reason to know they are the same purchase —
  /// and the app is the only thing on this screen that does know.
  ///
  /// [PendingClaim.covers] decides, so the scope is the plan **and** the term:
  /// a monthly request leaves the yearly card of the same plan buyable, because
  /// those are two products and the man filing the month may be deciding on
  /// the year. A term the server filed as something this app cannot name
  /// covers nothing, and the card is left live rather than guessed at.
  final PendingClaim? claimed;

  /// The id of the request that made the claim, so the sentence under the
  /// button can name the same number the receipt names. Null when the row
  /// carries none, which drops the clause rather than printing «رقم الطلب 0».
  final int? requestId;

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    // A pending request for exactly this plan at exactly this term. Named once
    // so the button and the sentence under it cannot be derived separately and
    // drift apart — the two would then say different things about one card.
    final alreadyRequested = claimed?.covers(plan.id, period.wire) ?? false;
    // The sentence is optional even when the button is dead: a row whose id
    // did not parse has nothing quotable to say, and an absent sentence is
    // better than a placeholder number a man would read out to support. The
    // **button is dead either way** — `alreadyRequested` above does not depend
    // on this line, so a missing id can never re-open the payment path.
    final requestedNote = alreadyRequested
        ? planAlreadyRequestedAr(requestId)
        : null;
    final saving = plan.savingFor(period);
    // The yearly discount sentence, read once and dropped when the server's
    // two prices do not divide into a whole number of months. See
    // `yearlyTermHintAr` for why it is not a constant.
    final yearlyHint =
        period == BillingPeriod.year ? yearlyTermHintAr(plan) : null;
    // «وصول في 3 ولايات» — `wilaya_span`, a limit the app parsed and printed
    // nowhere until now. It is the one number that separates two paid tiers
    // apart on the screen that quotes both their prices, and `features` alone
    // promised `gold` «صدارة النتاجات في ولايتك»
    // while the server priced it at three. See `planReachLineAr`.
    final reachLine = planReachLineAr(plan.wilayaSpan);
    return AppCard(
      borderColor: current ? AppTheme.accent : AppTheme.cardLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.nameAr, style: AppTheme.h2),
                        if (current) ...[
                          const SizedBox(width: AppTheme.s8),
                          StatusPill(
                            label: 'خطتك',
                            color: AppTheme.navy,
                            wash: AppTheme.accentWash,
                          ),
                        ],
                      ],
                    ),
                    if (plan.taglineAr != null && plan.taglineAr!.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.s4),
                      Text(plan.taglineAr!,
                          style: AppTheme.caption
                              .copyWith(color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.s12),
              // A price under question is **marked on the figure itself**, not
              // only in a band four lines above it. Until this, the card drew
              // the quoted figure in the same navy as a price it was sure of,
              // on the same screen, at the same moment, as a band saying that
              // figure was wrong — and the number a contractor reads at the
              // bottom of his eye was the wrong one, unmarked.
              //
              // Three marks, and each one earns its place:
              //   · the strike, so the figure is never read as payable;
              //   · the muted accent, so it is not the darkest thing on the
              //     card and stops being what the eye lands on;
              //   · the amount D1 actually used, under the suffix, so the
              //     card is readable **without** the band — the band may be
              //     scrolled off, and a man who read only the card still
              //     learns the figure rather than the error.
              // Bounded, and the bound is load-bearing. The amount line is the
              // longest string that has ever been drawn in this column, and the
              // plan name beside it is `Expanded`, so an unbounded trailing
              // Column pushed the whole Row 53 px past the card edge on a 392 dp
              // phone — measured, not reasoned: the first run of this tick's own
              // test failed on `A RenderFlex overflowed by 53 pixels`. The figure
              // the card exists to mark was the thing that broke the layout.
              // So the column takes only what it needs, up to a share of the
              // card, and the amount wraps onto a second line instead.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppTheme.priceColW),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (dispute != null)
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppTheme.s4, right: AppTheme.s4),
                      child: const Icon(Icons.report_gmailerrorred_rounded,
                          size: AppTheme.s16, color: AppTheme.danger),
                    ),
                  Text(
                    priceLabel,
                    key: Key('plan-price-${plan.id}-${period.wire}'),
                    style: dispute == null
                        ? AppTheme.bar
                        : AppTheme.bar.copyWith(
                            color: AppTheme.danger,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: AppTheme.danger,
                          ),
                  ),
                  Text(
                    period == BillingPeriod.year
                        ? S.planFreeSuffixYearly
                        : S.planFreeSuffixMonthly,
                    style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
                  ),
                  if (dispute != null) ...[
                    const SizedBox(height: AppTheme.s4),
                    Text(
                      dispute!.amountLineAr,
                      key: Key(planDisputedAmountKey(plan.id, period.wire)),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ],
          ),
          if (saving > 0) ...[
            const SizedBox(height: AppTheme.s8),
            Text('توفّر ${Money.dzd(saving)} في السنة',
                style: AppTheme.caption.copyWith(
                    color: AppTheme.success, fontWeight: FontWeight.w700)),
          ],
          // «سنة كاملة بسعر عشرة أشهر» — computed from this plan's two prices,
          // and only when the yearly figure really is a whole number of months
          // of the monthly one. It used to be `S.planYearlyHint`, a constant
          // that claimed ten months on every plan whatever the server had
          // priced; see `yearlyTermHintAr`. Null drops the line rather than
          // printing a discount nobody gets.
          if (yearlyHint != null) ...[
            const SizedBox(height: AppTheme.s4),
            Text(
              yearlyHint,
              key: Key('plan-yearly-hint-${plan.id}'),
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          if (reachLine != null) ...[
            const SizedBox(height: AppTheme.s4),
            Row(
              children: [
                const Icon(Icons.travel_explore_rounded,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    reachLine,
                    key: Key('plan-reach-${plan.id}'),
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppTheme.s16),
          for (final feature in plan.features) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_rounded,
                    size: AppTheme.s20, color: AppTheme.success),
                const SizedBox(width: AppTheme.s8),
                Expanded(
                  child: Text(feature,
                      style: AppTheme.body.copyWith(height: 1.6)),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s8),
          ],
          const SizedBox(height: AppTheme.s8),
          PrimaryButton(
            key: Key('plan-${plan.id}-${period.wire}'),
            label: alreadyRequested
                ? S.planRequestedAwaiting
                : current
                    ? S.planRenew
                    : '${S.planUpgrade} — ${plan.nameAr}',
            icon: alreadyRequested
                ? Icons.hourglass_top_rounded
                : Icons.arrow_upward_rounded,
            loading: busy,
            // Dead, not hidden. The card is still on screen with the price on
            // it, and the price is still true — what is not available is a
            // *second* payment for a request the man has already filed. Hiding
            // the card would hide the price he is comparing, and grey lines
            // everywhere is what a blocked screen looks like when nothing is.
            onPressed: busy || alreadyRequested ? null : onChoose,
          ),
          // Said on the card, not only on the receipt four lines above: the
          // receipt is the small caption-coloured line, and a disabled amber
          // button with no explanation reads as a broken app. One sentence,
          // in the words the receipt uses, naming the number he would quote.
          if (requestedNote != null) ...[
            const SizedBox(height: AppTheme.s4),
            Text(
              requestedNote,
              key: const Key('plan-already-requested'),
              textAlign: TextAlign.center,
              style: AppTheme.caption
                  .copyWith(color: AppTheme.textSecondary, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Activation code ─────────────────────────────────────────────────────────

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.controller,
    required this.busy,
    required this.onRedeem,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              IconBubble(
                icon: Icons.confirmation_number_outlined,
                tint: AppTheme.navy,
                wash: AppTheme.lineSoft,
                size: AppTheme.s32,
              ),
              SizedBox(width: AppTheme.s12),
              Expanded(child: Text(S.planCodeTitle, style: AppTheme.h2)),
            ],
          ),
          const SizedBox(height: AppTheme.s12),
          TextField(
            key: const Key('plan-code'),
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onRedeem(),
            decoration: InputDecoration(
              hintText: S.planCodeHint,
              filled: true,
              fillColor: AppTheme.fieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
                borderSide: const BorderSide(color: AppTheme.fieldLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
                borderSide: const BorderSide(color: AppTheme.fieldLine),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.s12),
          SecondaryButton(
            key: const Key('plan-redeem'),
            label: S.planActivate,
            icon: Icons.bolt_rounded,
            onPressed: busy ? null : onRedeem,
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.request,
    required this.planNameAr,
    required this.methodLabel,
  });

  /// The five facts the server sent. Before this tick the card took **no
  /// arguments at all** — the object was parsed and thrown away, and a
  /// contractor who had transferred 15000 دج was told only that his request
  /// had been received.
  final PendingRequest request;

  /// The plan's Arabic name, resolved against the catalogue the same payload
  /// carries; null when the id is not in it.
  final String? planNameAr;

  /// The operator's own Arabic wording for the method he used.
  final String? methodLabel;

  @override
  Widget build(BuildContext context) {
    // Every clause is conditional on the fact actually arriving. The server
    // owns this payload and may send a bare id, so the line degrades to
    // whatever is known rather than printing empty separators.
    final facts = pendingFactsAr(
      planLabel: request.plan.trim().isEmpty
          ? null
          : pendingPlanLabelAr(request.plan, planNameAr),
      amountLabel: pendingAmountLabelAr(request.amountDzd),
      methodLabel: pendingMethodLabelAr(
        request.method,
        (id) => methodLabel ?? id,
      ),
      dayLabel: formatPendingDay(request.createdAt),
      // The term, read off the row the server actually filed.
      periodLabel: pendingPeriodLabelAr(request.period),
      // The number support asks the man to quote. It leads the receipt because
      // it is the one clause he reads out loud; see `pendingRequestNumberAr`.
      numberLabel: pendingRequestNumberAr(request.id),
    );

    // Only set on a payload whose period is present and is neither arm of
    // [BillingPeriod] — the shape the live Worker returns for every other
    // spelling, having accepted it and filed the request as one month.
    final periodNote = pendingPeriodMismatchNoteAr(request.period);

    return AppCard(
      color: AppTheme.infoWash,
      borderColor: AppTheme.info,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: AppTheme.info),
          const SizedBox(width: AppTheme.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.planPendingTitle, style: AppTheme.h2),
                const SizedBox(height: AppTheme.s4),
                Text(S.planPendingBody,
                    style: AppTheme.body.copyWith(
                        color: AppTheme.textSecondary, height: 1.6)),
                // The receipt. Separated from the prose above so a payload with
                // no usable facts renders exactly the card that shipped before
                // rather than a title and a bare separator.
                if (facts != null) ...[
                  const SizedBox(height: AppTheme.s12),
                  Text(
                    facts,
                    key: const Key('pendingFacts'),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                // The warning sits below the receipt, not inside it: the
                // receipt is a list of facts and this is a claim about them, so
                // joining it with «·» would make it read as another fact.
                if (periodNote != null) ...[
                  const SizedBox(height: AppTheme.s4),
                  Text(
                    periodNote,
                    key: const Key('pendingPeriodNote'),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
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

/// The notice that a failed re-read left last read's numbers on screen.
///
/// Deliberately **not** the `_LoadFailed` state below it. Blanking the screen
/// on a failed refresh would throw away a plan this man has already paid for,
/// and the pull-to-refresh gesture is the first thing anyone tries after a
/// flaky connection — a screen that empties every time the network stutters
/// teaches people never to refresh. So the data stays and the doubt is stated.
///
/// Amber, not danger: nothing is lost and nothing is wrong with his account,
/// and a red banner on a healthy plan card would cry wolf. The app's own
/// staleness tone is the same one `worker_home_screen` ages its header into
/// (`AppTheme.accentDeep` over `accentWash`), so a figure that went quiet
/// looks the same wherever it is found.
class _StaleBanner extends StatelessWidget {
  const _StaleBanner({
    required this.line,
    super.key,
    this.icon = Icons.history_toggle_off_rounded,
  });

  /// The composed sentence from [staleCatalogueLineAr].
  final String line;

  /// What the band is about. One shape for both bands so a new one cannot
  /// arrive as a different-looking card by accident.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('stale-catalogue'),
      color: AppTheme.accentWash,
      borderColor: AppTheme.accent,
      padding: AppTheme.cardPadRail,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.s20, color: AppTheme.accentDeep),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              line,
              key: const Key('stale-catalogue-line'),
              style: AppTheme.body.copyWith(
                color: AppTheme.accentDeep,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Distinct from the stale banner above: this one means there is nothing
      // to show at all, which is the opposite of showing something old. The
      // two states are kept apart in code, not just in wording.
      key: const Key('plan-load-failed'),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: AppTheme.s32, color: AppTheme.textSecondary),
            const SizedBox(height: AppTheme.s12),
            Text(message,
                textAlign: TextAlign.center, style: AppTheme.body),
            const SizedBox(height: AppTheme.s16),
            PrimaryButton(
              label: S.planRetry,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payment sheet ───────────────────────────────────────────────────────────

class _PaymentChoice {
  const _PaymentChoice(this.method, this.reference);

  final PaymentMethod method;
  final String? reference;
}

/// How to pay, and where to send it. The account details come from server
/// configuration: if the operator has not published one, this sheet says
/// "contact us" rather than showing an account that cannot receive money.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.plan,
    required this.period,
    required this.priceLabel,
    required this.dispute,
    required this.payment,
    required this.renewNote,
    required this.prepaid,
  });

  final Plan plan;
  final BillingPeriod period;
  final String priceLabel;

  /// The price disagreement already found for this plan and term, or null.
  ///
  /// The sheet is the **last** thing between a contractor and a transfer, and
  /// it quotes the catalogue price under the title, at the size of a heading,
  /// with the submit button underneath. A dispute discovered before the sheet
  /// was opened has to be repeated here in the same shape, or the one screen
  /// he reads while actually moving the money is the one screen that repeats
  /// the wrong figure with nothing beside it.
  final PlanPriceDispute? dispute;

  final PaymentOptions payment;

  /// Repeated here, under the price, immediately before the money moves.
  ///
  /// Deliberately not "already shown on the card": this sheet is the last thing
  /// between the contractor and a transfer, and a BaridiMob receipt is a
  /// screenshot someone will forward. The sentence has to be in the thing they
  /// screenshot.
  final String? renewNote;
  final bool prepaid;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late PaymentMethod? _method =
      widget.payment.methods.isEmpty ? null : widget.payment.methods.first;
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final method = _method;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.gutter,
          AppTheme.s16,
          AppTheme.gutter,
          MediaQuery.of(context).viewInsets.bottom + AppTheme.s16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${S.planUpgrade} — ${widget.plan.nameAr}', style: AppTheme.h1),
              const SizedBox(height: AppTheme.s4),
              // The same two marks the plan card draws, from the same four
              // numbers, so the two instances of this fact cannot disagree:
              // a strike through the quoted figure and the amount D1 used,
              // printed in the same place under the same heading.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: widget.priceLabel,
                      style: widget.dispute == null
                          ? null
                          : const TextStyle(
                              color: AppTheme.danger,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppTheme.danger,
                            ),
                    ),
                    TextSpan(
                      text: ' · ${widget.period.labelAr}',
                      // Only the figure is disputed. The term beside it is
                      // what the man picked and what D1 filed, and striking
                      // through half the line would impeach a fact that has
                      // never been in question.
                      style: const TextStyle(color: AppTheme.navy),
                    ),
                  ],
                ),
                key: const Key('sheet-price'),
                style: AppTheme.bar.copyWith(color: AppTheme.navy),
              ),
              if (widget.dispute != null) ...[
                const SizedBox(height: AppTheme.s4),
                Text(
                  widget.dispute!.amountLineAr,
                  key: const Key(planDisputedSheetAmountKey),
                  style: AppTheme.bar.copyWith(color: AppTheme.danger),
                ),
              ],
              if (widget.renewNote != null) ...[
                const SizedBox(height: AppTheme.s8),
                _PrepaidBadge(note: widget.renewNote!, prepaid: widget.prepaid),
              ],
              const SizedBox(height: AppTheme.s16),
              Text(S.planPayTitle, style: AppTheme.h2),
              const SizedBox(height: AppTheme.s8),
              for (final m in widget.payment.methods)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.s8),
                  child: A11y.button(selected: m.id == method?.id, child: GestureDetector(
                    onTap: () => setState(() => _method = m),
                    behavior: HitTestBehavior.opaque,
                    child: AppCard(
                      padding: AppTheme.cardPadRail,
                      color: m.id == method?.id ? AppTheme.accentWash : AppTheme.surface,
                      borderColor:
                          m.id == method?.id ? AppTheme.accent : AppTheme.cardLine,
                      child: Row(
                        children: [
                          Icon(
                            m.id == method?.id
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: m.id == method?.id
                                ? AppTheme.navy
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: AppTheme.s12),
                          Expanded(child: Text(m.labelAr, style: AppTheme.body)),
                        ],
                      ),
                    ),
                  )),
                ),
              const SizedBox(height: AppTheme.s8),
              _PayInstructions(
                method: method,
                supportPhone: widget.payment.supportPhone,
              ),
              const SizedBox(height: AppTheme.s16),
              TextField(
                key: const Key('plan-reference'),
                controller: _reference,
                decoration: InputDecoration(
                  hintText: S.planReferenceLabel,
                  filled: true,
                  fillColor: AppTheme.fieldFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.fieldRadius),
                    borderSide: const BorderSide(color: AppTheme.fieldLine),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.s16),
              PrimaryButton(
                key: const Key('plan-submit'),
                label: S.planUpgrade,
                icon: Icons.send_rounded,
                onPressed: method == null
                    ? null
                    : () => Navigator.of(context)
                        .pop(_PaymentChoice(method, _reference.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayInstructions extends StatelessWidget {
  const _PayInstructions({required this.method, required this.supportPhone});

  final PaymentMethod? method;
  final String? supportPhone;

  @override
  Widget build(BuildContext context) {
    final details = method?.instructions;
    final phone = supportPhone;
    final lines = <String>[
      if (details != null) details,
      if (phone != null && phone.isNotEmpty) 'للاستفسار: $phone',
    ];
    if (lines.isEmpty) {
      return AppCard(
        color: AppTheme.surfaceAlt,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.info),
            const SizedBox(width: AppTheme.s12),
            Expanded(
              child: Text(S.planSupportFallback,
                  style: AppTheme.body.copyWith(
                      color: AppTheme.textSecondary, height: 1.6)),
            ),
          ],
        ),
      );
    }
    return AppCard(
      color: AppTheme.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines) ...[
            SelectableText(line, style: AppTheme.body.copyWith(height: 1.6)),
            const SizedBox(height: AppTheme.s4),
          ],
        ],
      ),
    );
  }
}

/// `2026-09-13 12:04:11` -> `2026-09-13`. Server timestamps are UTC SQLite
/// strings; the app only needs the day, so it never pretends to know the hour.
///
/// Read through [parseServerTime] like every other server clock in the app, so
/// the day is the day in **Algiers**. Parsed as bare wall-clock the same string
/// gave a day that is one early for every hour of the day in a UTC+1 country —
/// the card could say «ينتهي في 2026-09-13» about a subscription D1 says runs to
/// the 14th. The raw string is only echoed back when it cannot be read at all,
/// which is better than printing a day nobody can trust.
String _shortDate(String raw) {
  return subscriptionEndDateLabel(parseServerTime(raw)) ?? raw;
}
