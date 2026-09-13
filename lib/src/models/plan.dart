/// Billing models — the contractor's subscription, straight off the API.
///
/// The server owns the money: prices, limits and which plan is live all come
/// from `GET /api/mobile/plans` and `GET /api/mobile/subscription`. Nothing is
/// hard-coded here, so a price change is an UPDATE in D1 and every installed
/// app shows it on the next screen open. What this file owns is only how a
/// price reads and what a limit means.
///
/// Two promises are carried as data, not copy: [BillingCatalogue.commissionPercent]
/// and [BillingCatalogue.commissionPerOrder] are both 0, and the model would
/// still parse if they were not — so the app can only ever render what the
/// server actually charges.
library;

import '../core/format/money.dart';

/// Monthly or annual. Algeria pays in cash and by transfer, so the yearly plan
/// is the one that matters most to a contractor who dislikes small recurring
/// payments; it is priced as ten months.
enum BillingPeriod {
  month('month', 'شهري', 1),
  year('year', 'سنوي', 12);

  const BillingPeriod(this.wire, this.labelAr, this.months);

  /// What the API expects in `period`.
  final String wire;

  /// What the toggle says.
  final String labelAr;

  final int months;

  static BillingPeriod fromWire(String? value) =>
      value == 'year' ? BillingPeriod.year : BillingPeriod.month;
}

/// One subscription tier as sold to a مقاول.
class Plan {
  const Plan({
    required this.id,
    required this.nameAr,
    required this.nameFr,
    required this.taglineAr,
    required this.priceMonth,
    required this.priceYear,
    required this.quoteLimit,
    required this.portfolioLimit,
    required this.searchBoost,
    required this.wilayaSpan,
    required this.features,
  });

  final String id;
  final String nameAr;
  final String nameFr;
  final String? taglineAr;
  final int priceMonth;
  final int priceYear;

  /// Quotes allowed per calendar month; negative means unlimited.
  final int quoteLimit;
  final int portfolioLimit;
  final int searchBoost;
  final int wilayaSpan;
  final List<String> features;

  bool get isFree => priceMonth <= 0 && priceYear <= 0;
  bool get hasUnlimitedQuotes => quoteLimit < 0;

  int priceFor(BillingPeriod period) =>
      period == BillingPeriod.year ? priceYear : priceMonth;

  /// Dinars saved by paying for a year up front (0 when there is nothing to save).
  int savingFor(BillingPeriod period) {
    if (period != BillingPeriod.year) return 0;
    final full = priceMonth * 12;
    return full > priceYear ? full - priceYear : 0;
  }

  /// The honest Arabic sentence for the monthly allowance.
  String get quoteAllowanceAr =>
      hasUnlimitedQuotes ? 'عروض أسعار غير محدودة' : 'حتى $quoteLimit عروض في الشهر';

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        id: '${json['id']}',
        nameAr: '${json['name_ar'] ?? json['id']}',
        nameFr: '${json['name_fr'] ?? ''}',
        taglineAr: json['tagline_ar'] as String?,
        priceMonth: _int(json['price_month']),
        priceYear: _int(json['price_year']),
        quoteLimit: json['quote_limit'] == null ? 3 : _int(json['quote_limit']),
        portfolioLimit: _int(json['portfolio_limit']),
        searchBoost: _int(json['search_boost']),
        wilayaSpan: json['wilaya_span'] == null ? 1 : _int(json['wilaya_span']),
        features: [
          for (final f in (json['features'] as List? ?? const [])) '$f',
        ],
      );
}

/// What the contractor is entitled to right now, plus this month's usage.
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.plan,
    required this.nameAr,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
    required this.quoteLimit,
    required this.portfolioLimit,
    required this.quotesUsedThisMonth,
    required this.renewsInDays,
  });

  final String plan;
  final String nameAr;
  final String status;
  final String? startsAt;
  final String? expiresAt;
  final int quoteLimit;
  final int portfolioLimit;
  final int quotesUsedThisMonth;
  final int? renewsInDays;

  bool get isFree => plan == 'free_trial';
  bool get hasUnlimitedQuotes => quoteLimit < 0;

  /// `null` when the plan is unlimited.
  int? get quotesLeft {
    if (hasUnlimitedQuotes) return null;
    final left = quoteLimit - quotesUsedThisMonth;
    return left < 0 ? 0 : left;
  }

  /// True when the free allowance is spent — the moment the upgrade card is
  /// worth showing ahead of everything else.
  bool get isQuotaSpent => !hasUnlimitedQuotes && (quotesLeft ?? 0) == 0;

  /// A paid plan that passes its expiry date is expired even if the row still
  /// says active; the server re-checks, and so does the card.
  bool get isExpired {
    if (isFree || expiresAt == null) return false;
    final end = DateTime.tryParse(expiresAt!.replaceFirst(' ', 'T'));
    if (end == null) return false;
    return end.isBefore(DateTime.now());
  }

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        plan: '${json['plan'] ?? 'free_trial'}',
        nameAr: '${json['name_ar'] ?? ''}',
        status: '${json['status'] ?? 'active'}',
        startsAt: json['starts_at'] as String?,
        expiresAt: json['expires_at'] as String?,
        quoteLimit: json['quote_limit'] == null ? 3 : _int(json['quote_limit']),
        portfolioLimit: _int(json['portfolio_limit']),
        quotesUsedThisMonth: _int(json['quotes_used_this_month']),
        renewsInDays: json['renews_in_days'] == null
            ? null
            : _int(json['renews_in_days']),
      );
}

/// A subscription request already submitted and awaiting payment confirmation.
class PendingRequest {
  const PendingRequest({
    required this.id,
    required this.plan,
    required this.amountDzd,
    required this.method,
    required this.createdAt,
  });

  final int id;
  final String plan;
  final int amountDzd;
  final String? method;
  final String? createdAt;

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
        id: _int(json['id']),
        plan: '${json['plan'] ?? ''}',
        amountDzd: _int(json['amount_paid'] ?? json['amount_dzd']),
        method: json['payment_method'] as String?,
        createdAt: json['created_at'] as String?,
      );
}

/// One way to pay. [instructions] is the account to send money to, read from
/// server configuration — when the operator has not published one yet this is
/// null and the screen says so instead of printing a placeholder nobody can
/// actually pay into.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.labelAr,
    required this.instructions,
  });

  final String id;
  final String labelAr;
  final String? instructions;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: '${json['id']}',
        labelAr: '${json['label_ar'] ?? json['id']}',
        instructions: (json['instructions'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['instructions'] as String).trim(),
      );
}

class PaymentOptions {
  const PaymentOptions({required this.methods, required this.supportPhone});

  final List<PaymentMethod> methods;
  final String? supportPhone;

  factory PaymentOptions.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    return PaymentOptions(
      methods: [
        for (final m in (raw['methods'] as List? ?? const []))
          PaymentMethod.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      supportPhone: raw['support_phone'] as String?,
    );
  }
}

/// Everything the subscription screen renders, in one object.
class BillingCatalogue {
  const BillingCatalogue({
    required this.currency,
    required this.noteAr,
    required this.commissionPercent,
    required this.commissionPerOrder,
    required this.plans,
    required this.current,
    required this.pendingRequest,
    required this.payment,
  });

  final String currency;

  /// The product promise in the founder's own words, rendered as-is.
  final String noteAr;
  final int commissionPercent;
  final int commissionPerOrder;
  final List<Plan> plans;
  final SubscriptionStatus current;
  final PendingRequest? pendingRequest;
  final PaymentOptions payment;

  /// True only when the server itself says there is no commission anywhere.
  bool get noCommission => commissionPercent == 0 && commissionPerOrder == 0;

  Plan? planById(String id) {
    for (final p in plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The paid plans a contractor can buy, cheapest first.
  List<Plan> get purchasable => [
        for (final p in plans)
          if (!p.isFree) p,
      ];

  /// `15 ألف دج` — the yearly figure the toggle shows.
  String priceLabel(Plan plan, BillingPeriod period) =>
      plan.isFree ? 'مجاناً' : Money.dzd(plan.priceFor(period));

  factory BillingCatalogue.fromJson(Map<String, dynamic> json) {
    final plans = [
      for (final p in (json['plans'] as List? ?? const []))
        Plan.fromJson(Map<String, dynamic>.from(p as Map)),
    ];
    final current = Map<String, dynamic>.from(
        (json['current'] as Map?) ?? const <String, dynamic>{});
    final pending = json['pending_request'];
    return BillingCatalogue(
      currency: '${json['currency'] ?? 'DZD'}',
      noteAr: '${json['note_ar'] ?? ''}',
      commissionPercent: _int(json['commission_percent']),
      commissionPerOrder: _int(json['commission_per_order']),
      plans: plans,
      current: SubscriptionStatus.fromJson(current),
      pendingRequest: pending is Map
          ? PendingRequest.fromJson(Map<String, dynamic>.from(pending))
          : null,
      payment: PaymentOptions.fromJson(json['payment'] as Map<String, dynamic>?),
    );
  }
}

/// The plans list without an account attached — what the public catalogue
/// endpoint returns, used by the pricing surface before sign-in.
class PlanCatalogue {
  const PlanCatalogue({required this.plans, required this.noteAr});

  final List<Plan> plans;
  final String noteAr;

  factory PlanCatalogue.fromJson(Map<String, dynamic> json) => PlanCatalogue(
        plans: [
          for (final p in (json['plans'] as List? ?? const []))
            Plan.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        noteAr: '${json['note_ar'] ?? ''}',
      );
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
