import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/l10n/error_copy.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion.dart';
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
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final Repository _repo;
  bool _scopeReady = false;

  BillingCatalogue? _catalogue;
  bool _loading = true;
  String? _error;

  /// Monthly by default: it is the smaller decision. The toggle is remembered
  /// for the life of the screen so a contractor comparing prices does not have
  /// to re-pick the period between two taps.
  BillingPeriod _period = BillingPeriod.month;

  bool _busy = false;
  final _codeController = TextEditingController();

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
    _codeController.dispose();
    super.dispose();
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorCopy(e);
      });
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Declares a payment for [plan] after the contractor picked how to pay.
  Future<void> _request(Plan plan, PaymentMethod method, String? reference) async {
    setState(() => _busy = true);
    try {
      await _repo.requestSubscription(
        plan: plan.id,
        period: _period,
        method: method.id,
        reference: reference,
      );
      _say(S.planRequestOk);
      await _load();
    } catch (e) {
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
    setState(() => _busy = true);
    try {
      final plan = await _repo.redeemActivationCode(code);
      _codeController.clear();
      _say(plan == null ? S.planCodeOk : '${S.planCodeOk} — ${plan.toUpperCase()}');
      await _load();
    } catch (e) {
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
        payment: catalogue.payment,
      ),
    );
    if (result == null) return;
    await _request(plan, result.method, result.reference);
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = _catalogue;
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
                      _CurrentPlanCard(status: catalogue.current),
                      if (catalogue.pendingRequest != null) ...[
                        const SizedBox(height: AppTheme.gap),
                        const _PendingCard(),
                      ],
                      const SizedBox(height: AppTheme.gap),
                      _PromiseCard(
                        note: catalogue.noteAr.isEmpty
                            ? S.planNoteFallback
                            : catalogue.noteAr,
                        noCommission: catalogue.noCommission,
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
                          current: catalogue.current.plan == plan.id,
                          busy: _busy,
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
              status.renewsInDays != null
                  ? 'ينتهي الاشتراك بعد ${status.renewsInDays} يوماً'
                  : 'ينتهي الاشتراك في ${_shortDate(status.expiresAt!)}',
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
        ? 'عروض أسعار غير محدودة — أرسلت ${status.quotesUsedThisMonth} هذا الشهر'
        : status.isFree
            ? 'استعملت ${status.quotesUsedThisMonth} من ${status.quoteLimit} عروض مجانية هذا الشهر'
            : 'استعملت ${status.quotesUsedThisMonth} من ${status.quoteLimit} عرضاً هذا الشهر';
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
  const _PromiseCard({required this.note, required this.noCommission});

  final String note;
  final bool noCommission;

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
              ],
            ),
          ),
        ],
      ),
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
                      if (p == BillingPeriod.year) ...[
                        const SizedBox(height: AppTheme.s4),
                        Text(
                          S.planYearlyHint,
                          textAlign: TextAlign.center,
                          style: AppTheme.caption.copyWith(
                            color: p == period
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
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
    required this.current,
    required this.busy,
    required this.onChoose,
  });

  final Plan plan;
  final BillingPeriod period;
  final String priceLabel;
  final bool current;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final saving = plan.savingFor(period);
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(priceLabel, style: AppTheme.bar),
                  Text(
                    period == BillingPeriod.year
                        ? S.planFreeSuffixYearly
                        : S.planFreeSuffixMonthly,
                    style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          if (saving > 0) ...[
            const SizedBox(height: AppTheme.s8),
            Text('توفّر ${Money.dzd(saving)} في السنة',
                style: AppTheme.caption.copyWith(
                    color: AppTheme.success, fontWeight: FontWeight.w700)),
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
            label: current ? S.planRenew : '${S.planUpgrade} — ${plan.nameAr}',
            icon: Icons.arrow_upward_rounded,
            loading: busy,
            onPressed: busy ? null : onChoose,
          ),
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
  const _PendingCard();

  @override
  Widget build(BuildContext context) {
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
              ],
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
    required this.payment,
  });

  final Plan plan;
  final BillingPeriod period;
  final String priceLabel;
  final PaymentOptions payment;

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
              Text(
                '${widget.priceLabel} · ${widget.period.labelAr}',
                style: AppTheme.bar.copyWith(color: AppTheme.navy),
              ),
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
