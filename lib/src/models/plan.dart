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
import '../core/l10n/arabic_agreement.dart';
import '../data/chat_time.dart' show calendarDaysBetween;
import 'notification.dart' show parseServerTime;
import 'plan_id.dart' show PlanId;

/// Monthly or annual. Algeria pays in cash and by transfer, so the yearly plan
/// is the one that matters most to a contractor who dislikes small recurring
/// payments; the server prices it, and the app reads the ratio off the two
/// prices rather than assuming one.
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

  // There is deliberately no `quoteAllowanceAr` here any more.
  //
  // It was a fourth hand-written copy of the quote nouns, it carried the same
  // fixed plural the three screens did, and — the reason it was worth deleting
  // rather than fixing — **nothing ever called it**. The plan card renders
  // `features`, which D1 sends in Arabic, so the getter was a sentence no user
  // could see and no test could catch drifting. The nouns that are actually
  // printed live in `data/quote_count_copy.dart`, next to the screens that
  // print them.

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        id: '${json['id']}',
        nameAr: '${json['name_ar'] ?? json['id']}',
        nameFr: '${json['name_fr'] ?? ''}',
        taglineAr: _text(json['tagline_ar']),
        priceMonth: _int(json['price_month']),
        priceYear: _int(json['price_year']),
        quoteLimit: json['quote_limit'] == null ? 3 : _int(json['quote_limit']),
        portfolioLimit: _int(json['portfolio_limit']),
        searchBoost: _int(json['search_boost']),
        wilayaSpan: json['wilaya_span'] == null ? 1 : _int(json['wilaya_span']),
        features: [
          for (final f in _list(json['features'])) '$f',
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

  /// The server's own day count. Parsed and deliberately **not displayed**.
  ///
  /// Kept so the field still lands if the Worker grows one, but the app prints
  /// [expiryCountdownAr] instead: a count computed in UTC from a date the user
  /// reads in Algiers disagrees at the day boundary, and it arrived at the card
  /// without a floor, so `0` read "بعد 0 يوماً" and a negative read "بعد -3
  /// يوماً". Nothing in the UI may print this again.
  final int? renewsInDays;

  /// Whether this row is the one nobody pays for.
  ///
  /// Through [PlanId.fromWire] rather than a bare `plan == 'free_trial'`,
  /// which is what this line was. Two reasons, and the second is the one that
  /// mattered.
  ///
  /// The first is trimming: this column is compared **raw** here while every
  /// other reader in the app trims it first — `redeem_outcome.dart`,
  /// `pending_request_copy.dart`, `quote_worker_trust.dart`. A row carrying
  /// ` free_trial` was therefore read as a *paid* plan here while being read as
  /// the trial everywhere else.
  ///
  /// The second is what the answer controls. `isFree` is not a label, it is the
  /// switch on [expiresAtLocal]: a paid row is the only kind allowed to have a
  /// readable end date. So a plan id that arrived padded, or one this app does
  /// not know, made a paying contractor's card drop its expiry date entirely —
  /// the plan reads «مفعّل», no date, no countdown, and nothing on the screen
  /// says why. [PlanId.fromWire] returning null for an unknown id is deliberate:
  /// an unreadable id must not be filed under the trial, which is the one
  /// answer that would *also* strip a real expiry.
  bool get isFree => PlanId.fromWire(plan)?.isFree ?? false;
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

  /// The moment the paid plan stops being paid for, in the phone's own timezone.
  ///
  /// D1 stores `expires_at` the way SQLite's `CURRENT_TIMESTAMP` writes it —
  /// `YYYY-MM-DD HH:MM:SS`, in **UTC with no zone marker** — so it must be read
  /// through [parseServerTime], the app's single server-clock parser, exactly as
  /// every chat and notification timestamp already is. Parsing it as bare
  /// wall-clock (`DateTime.tryParse` with no `Z`) read an instant that is one
  /// hour early in Algiers, which is the whole width of the bug below.
  ///
  /// Null when the plan is free or the server sent no date: a plan whose
  /// expiry cannot be read is not *known* to be over, and claiming otherwise
  /// would take a paying contractor's features away on a formatting guess.
  DateTime? get expiresAtLocal => isFree
      ? null
      : parseServerTime(expiresAt);

  /// Longest remaining run still described as a day count.
  ///
  /// A year of prepaid cover is the longest thing the founder sells, so past
  /// 365 days the number stops being information the user can use and becomes
  /// an artefact of a date nobody set. Above it the date alone is printed, which
  /// is true whatever the row says.
  static const int maxCountedDays = 365;

  /// Whole calendar days from today to the day this plan ends, in the phone's
  /// own timezone. Null when there is no readable expiry.
  ///
  /// Calendar days, not elapsed hours: the user is asking "how many days do I
  /// still have", and the answer has to be the number of midnights he crosses.
  ///
  /// **Counted on the calendar, not on a 24-hour period.** This used to be
  /// `lastDay.difference(today).inDays` over two midnight-normalised dates, and
  /// stripping the clock is necessary but not sufficient: on a spring-forward
  /// day that span is **23 hours**, and `.inDays` truncates towards zero, so a
  /// contractor with three midnights left was told he had **two**. Measured on
  /// `TZ=Europe/Paris`, 28 Mar -> 31 Mar 2026: `inDays` = 2 where the calendar
  /// says 3. [expiryCountdownArAt] printed that number straight onto the
  /// subscription card, which is the one number deciding how much paid cover a
  /// man believes he has left.
  ///
  /// `chat_time.dart` already answered this exact question, in the other
  /// direction, and named DST as the reason its own hand-rolled index was thrown
  /// away for a Julian Day Number. This is that file's rule, so the two do not
  /// drift: one rule for "how many calendar days", held once.
  int? daysUntilExpiryAt(DateTime now) {
    final end = expiresAtLocal;
    if (end == null) return null;
    // Both are local, and both are stripped of their time, so the answer cannot
    // be pushed off by the hour the raw timestamps disagree about.
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(end.year, end.month, end.day);
    return calendarDaysBetween(today, lastDay);
  }

  /// [daysUntilExpiryAt] against the wall clock.
  ///
  /// **A screen that can age its own readings must not use this.** Every
  /// caller that renders is handed one (`SubscriptionScreen.clock`), and the
  /// screen's once-a-minute ageing timer means the two answers can be live on
  /// one screen at the same time — a band that moved to «قبل دقيقة» above a
  /// card still holding the count computed at build time. Keep this for code
  /// with no clock of its own; prefer [daysUntilExpiryAt] the moment there is
  /// one to pass.
  int? get daysUntilExpiry => daysUntilExpiryAt(DateTime.now());

  /// The Arabic sentence that says when the paid months run out, or null when
  /// there is nothing to say.
  ///
  /// This replaces printing the server's own `renews_in_days` count. Two
  /// reasons, both about trusting a computed number over a real timestamp:
  ///
  ///   * The app already holds the exact instant (`expires_at`) and a parser
  ///     proven correct in Algiers, so a server-side day count is a rounded
  ///     second opinion about data we have exactly. D1 computes it in UTC, the
  ///     date the user reads is local, and the two disagree by a day at every
  ///     boundary.
  ///   * The count is only as sane as its rounding, and it reached the card
  ///     unguarded: `0` printed "ينتهي الاشتراك بعد 0 يوماً" and a stale
  ///     negative printed "بعد -3 يوماً" — Arabic that means nothing, on the
  ///     one card whose job is to tell a paying man how long he has paid for.
  ///
  /// The count and the date are printed together so they cannot contradict
  /// each other, and the count is only claimed when it means something to a
  /// person: below a day, the date alone; beyond [maxCountedDays], the date
  /// alone again, because a plan that long is not sold here and a count like
  /// «بعد 26560 يوماً» is a number no contractor can read as time.
  ///
  /// The count takes the form the number calls for (see [arabicCounted]): one
  /// day is «يوم», two are «يومين», three to ten «أيام», and eleven and up
  /// are counted singular again. Printing one fixed noun for every count is
  /// the mistake this line used to make.
  String? expiryCountdownArAt(DateTime now) {
    final end = subscriptionEndDateLabel(expiresAtLocal);
    if (end == null) return null;
    final days = daysUntilExpiryAt(now);
    if (days == null || days < 1 || days > maxCountedDays) {
      return 'ينتهي الاشتراك في $end';
    }
    // The count takes the noun's form: one day is «يوم», two are «يومين»,
    // three to ten are «أيام», and eleven and up are counted singular again —
    // «بعد 100 يوم», not «بعد 100 أيام». The previous line printed one fixed
    // «يوماً» for all four, so a contractor one day from renewal read
    // «بعد 1 يوماً» and one two days out read «بعد 2 يوماً».
    return 'ينتهي الاشتراك بعد ${arabicCounted(days, 'يوم', two: 'يومين', few: 'أيام')} — $end';
  }

  /// [expiryCountdownArAt] against the wall clock. See [daysUntilExpiry].
  String? get expiryCountdownAr => expiryCountdownArAt(DateTime.now());

  /// `انتهى الاشتراك في 2026-01-01` — the day a paid plan ran out, or null
  /// when there is nothing to say.
  ///
  /// **Not [expiryCountdownAr], and the tense is the whole reason.** That getter
  /// is written in the future — «ينتهي» — because it describes cover the man
  /// still holds, and its own sub-day arm falls back to a future-tense date for
  /// the same reason. Reusing it for a plan that is *already over* would print
  /// «ينتهي الاشتراك في 2020-01-01» directly under a pill reading «منتهي», on
  /// the one screen whose entire job is renewal, disagreeing with itself inside
  /// one card about whether the plan is running or over.
  ///
  /// Null for the free plan and for an expiry that cannot be read — the two
  /// cases [expiresAtLocal] already declines to guess at, and a date invented
  /// for a payment that never happened is the one number this card must not
  /// print.
  String? get expiryEndedAr {
    final end = subscriptionEndDateLabel(expiresAtLocal);
    if (end == null) return null;
    return 'انتهى الاشتراك في $end';
  }

  /// A paid plan that passes its expiry date is expired even if the row still
  /// says active; the server re-checks, and so does the card.
  bool isExpiredAt(DateTime now) {
    final end = expiresAtLocal;
    if (end == null) return false;
    return end.isBefore(now);
  }

  /// [isExpiredAt] against the wall clock. See [daysUntilExpiry] — this is the
  /// one that decides whether a man is told his paid plan still runs, so a
  /// screen that was handed a clock must ask the question against it.
  bool get isExpired => isExpiredAt(DateTime.now());

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) =>
      SubscriptionStatus(
        plan: '${json['plan'] ?? 'free_trial'}',
        nameAr: '${json['name_ar'] ?? ''}',
        status: '${json['status'] ?? 'active'}',
        // An epoch integer is a shape D1 can perfectly well answer with, and
        // `expires_at` is the field the renewal card is built from. Read as
        // null, it degrades to "no end date to print" — which is true of a
        // date the app cannot read — rather than taking the screen down.
        startsAt: _text(json['starts_at']),
        expiresAt: _text(json['expires_at']),
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
    this.period,
  });

  final int id;
  final String plan;
  final int? amountDzd;
  final String? method;
  final DateTime? createdAt;

  /// The billing period **the server stored**, exactly as it came back.
  ///
  /// Kept as the raw wire string and never coerced into a [BillingPeriod].
  /// `BillingPeriod.fromWire` maps anything it does not recognise to
  /// [BillingPeriod.month], and the live Worker does exactly that: probing
  /// `POST /api/mobile/subscription` with `6month`, `quarter`, `3m`, `durations`
  /// and ten other spellings all came back `{"ok":true}` and all were stored as
  /// `period: "month"` (requests 12-24, 26 Sep). So a client that sent a term
  /// the server did not understand gets a green answer and a one-month row.
  ///
  /// Holding the string lets the card say what is actually on file, which is
  /// the only number that survives the round trip. Null when the server sent
  /// no period at all.
  final String? period;

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
        id: _int(json['id']),
        plan: '${json['plan'] ?? ''}',
        // Null rather than 0: a payment with no amount on the payload is an
        // unknown amount, and printing «0 دج» on money a man already handed
        // over is a claim the app has no evidence for.
        amountDzd: json.containsKey('amount_paid') || json.containsKey('amount_dzd')
            ? _nullableInt(json['amount_paid'] ?? json['amount_dzd'])
            : null,
        method: _text(json['payment_method']),
        // The server's own word for the term, kept verbatim: the Worker answers
        // an unrecognised period with `ok` and files the request as a month,
        // so this string is the record of what the money actually bought.
        period: _text(json['period']),
        // Through the app's single server-clock parser, so the card and the
        // expiry countdown on the card above it cannot disagree about the day.
        createdAt: parseServerTime(json['created_at']),
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
        // Read, not cast. A nullable cast throws a TypeError on anything that
        // is not a String, and every one of these three fields is one the
        // payload may legitimately re-type: a CCP number is the obvious one,
        // because a number is the obvious way to send one. The cost of the cast
        // is the whole subscription screen, not the account number.
        //
        // The id was `'${json['id']}'`, which prints the literal «null» for an
        // absent id — and that string is what the write path POSTs back as the
        // payment method. `_wireText` keeps it empty instead.
        id: _wireText(json['id']),
        // `_text` and not `_wireText` on the left: the label is *copy*, and an
        // absent one must fall back to the id. `_wireText` returns '' rather
        // than null, so `?? _wireText(json['id'])` beside it would never fire.
        labelAr: _text(json['label_ar']) ?? _wireText(json['id']),
        instructions: _text(json['instructions']),
      );
}

class PaymentOptions {
  const PaymentOptions({required this.methods, required this.supportPhone});

  final List<PaymentMethod> methods;
  final String? supportPhone;

  /// The operator's own Arabic wording for a method id, or null when the
  /// catalogue does not carry it.
  ///
  /// Exists so the pending-payment card can name the method the contractor
  /// actually used without hand-writing a map of ids the server owns. An id
  /// the app has not been rebuilt for still comes back null, and the caller
  /// falls back to the raw id rather than dropping the fact.
  String? labelFor(String id) {
    final key = id.trim();
    for (final m in methods) {
      if (m.id == key) return m.labelAr;
    }
    return null;
  }

  factory PaymentOptions.fromJson(Map<String, dynamic>? json) {
    final raw = json ?? const <String, dynamic>{};
    return PaymentOptions(
      // `m as Map` took the whole sheet down when one entry was not a map. A
      // malformed row now costs that row alone: the list comprehension skips
      // what it cannot read, so the methods the operator did publish are still
      // on screen and still payable.
      // A row that is not a map is a payload we cannot read, so that row is
      // skipped and the methods the operator did publish stay on screen — the
      // malformed one used to take the whole sheet with it.
      //
      // An id that is empty is skipped for a different reason: `labelAr`
      // falls back to the id, so a row with neither leaves the sheet offering
      // a pay button labelled with **nothing**, and posting that row sends an
      // empty `method` to the server. A payment option the app cannot name is
      // not a payment option.
      methods: [
        for (final m in _list(raw['methods']))
          if (_payable(m)) PaymentMethod.fromJson(Map<String, dynamic>.from(m)),
      ],
      supportPhone: _text(raw['support_phone']),
    );
  }
}

/// Everything the subscription screen renders, in one object.
class BillingCatalogue {
  const BillingCatalogue({
    required this.currency,
    required this.noteAr,
    required this.renewNoteAr,
    required this.autoRenew,
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

  /// How the plan is paid for, in the founder's own words, or empty.
  ///
  /// The server publishes this next to [noteAr] on the same payload and the app
  /// dropped it on the floor: `renew_note_ar` and `auto_renew` were read by
  /// nothing, so **«الدفع مسبق» — prepaid, no automatic charge — was never
  /// stated to the man about to hand over money**. [noteAr] promises no
  /// commission and is printed on the screen; this is the sentence that tells
  /// him what happens to his card when the plan runs out, and it was the one
  /// nobody could read.
  ///
  /// Null rather than empty when the server sent nothing, so a catalogue with no
  /// renewal note can never be confused with one whose note is blank.
  final String? renewNoteAr;

  /// True only when the server itself says a plan charges itself again.
  ///
  /// The flag is the part that can be relied on; [renewNoteAr] is prose. An
  /// **absent** flag is not a promise that nothing renews, so [isPrepaid] only
  /// claims what was actually sent — see there.
  final bool? autoRenew;

  final int commissionPercent;
  final int commissionPerOrder;
  final List<Plan> plans;
  final SubscriptionStatus current;
  final PendingRequest? pendingRequest;
  final PaymentOptions payment;

  /// True only when the server itself says there is no commission anywhere.
  bool get noCommission => commissionPercent == 0 && commissionPerOrder == 0;

  /// True only when the server **explicitly** said it does not auto-charge.
  ///
  /// A missing `auto_renew` is not a `false`: the parser cannot tell an older
  /// server that predates the field from one that genuinely renews, and
  /// claiming «لن يُخصم تلقائياً» off an absent flag is exactly the sort of
  /// promise this model exists not to invent. Null is therefore carried all the
  /// way to the screen, and the sentence is written by the server
  /// ([renewNoteAr]) rather than derived from the flag — the flag only decides
  /// whether the *badge* is shown, and a badge nobody can trust is worse than
  /// no badge.
  bool get isPrepaid => autoRenew == false;

  /// The plan whose id is [id], or null when the catalogue does not carry it.
  ///
  /// **Trimmed, because every other reader of this column in the app trims
  /// and this one did not** — the same law [PlanId.fromWire] was written to
  /// keep, and the exception to it is what this line was.
  ///
  /// Three readers of `plan` already called `.trim()` before comparing:
  /// `pendingClaimFor` ([pending_request_copy.dart:245]), the pending card's
  /// own label ([subscription_screen.dart:1214]) and `PaymentOptions.labelFor`
  /// ([plan.dart:396]) — which does `final key = id.trim()` before the very same
  /// `m.id == key` shape used here. This loop was handed the sibling line.
  ///
  /// **What the untrimmed compare cost.** The only caller is the pending-payment
  /// card, which passes `catalogue.pendingRequest!.plan` straight through to
  /// name the plan the contractor is paying for. A row arriving as `" pro"`
  /// missed every catalogue entry and `planById` returned null, so the label
  /// fell to `pendingPlanLabelAr`'s own fallback and the receipt — the one
  /// document a man screenshots to support — printed the **raw wire id**
  /// `pro` where the Arabic name «محترف» should be, next to the amount he just
  /// transferred. Every other reader of the same column had already decided
  /// the padded id is the plan `pro`; this one contradicted them on the only
  /// screen where the answer is a receipt.
  Plan? planById(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    for (final p in plans) {
      if (p.id == key) return p;
    }
    return null;
  }

  /// Whether [plan] is the tier this subscription is currently on.
  ///
  /// Exists so the card's "your plan" marking asks the catalogue rather than
  /// comparing two strings inline. Written by hand it was
  /// `catalogue.current.plan == plan.id` — the **fourth** reader of the plan
  /// id on this screen, and the second one that did not trim, after
  /// [planById].
  ///
  /// **What the untrimmed compare cost.** This is not a label, it is the state
  /// of the card. `current` decides the accent border, the «خطتك» pill, and — at
  /// [subscription_screen.dart:1089] — whether the button reads «تجديد» (*renew*) instead
  /// of «ترقية — محترف» (*upgrade*). A `current.plan` of `" pro"` left the
  /// contractor on his **pro** plan looking at a card that says *upgrade*, not
  /// *renew*: his own tier offered back to him for money, on the money screen,
  /// one tap from a second 15000 دج transfer for a plan he already owns.
  bool isCurrentPlan(Plan plan) =>
      current.plan.trim() == plan.id.trim() && plan.id.trim().isNotEmpty;

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
      for (final p in _list(json['plans']))
        if (p is Map) Plan.fromJson(Map<String, dynamic>.from(p)),
    ];
    final current = Map<String, dynamic>.from(
        json['current'] is Map ? json['current'] as Map : const {});
    final pending = json['pending_request'];
    return BillingCatalogue(
      currency: '${json['currency'] ?? 'DZD'}',
      noteAr: '${json['note_ar'] ?? ''}',
      renewNoteAr: _text(json['renew_note_ar']),
      autoRenew: json['auto_renew'] is bool ? json['auto_renew'] as bool : null,
      commissionPercent: _int(json['commission_percent']),
      commissionPerOrder: _int(json['commission_per_order']),
      plans: plans,
      current: SubscriptionStatus.fromJson(current),
      pendingRequest: pending is Map
          ? PendingRequest.fromJson(Map<String, dynamic>.from(pending))
          : null,
      payment: PaymentOptions.fromJson(
          json['payment'] is Map ? json['payment'] as Map<String, dynamic> : null),
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
          for (final p in _list(json['plans']))
            if (p is Map) Plan.fromJson(Map<String, dynamic>.from(p)),
        ],
        noteAr: '${json['note_ar'] ?? ''}',
      );
}

/// `2026-09-13 12:04:11` (UTC, as D1 writes it) -> `2026-09-13`, the day in the
/// phone's own timezone. Null when the string cannot be read.
///
/// One formatter for the two places that print a subscription's end date, so
/// the subscription card and the account row cannot drift into disagreeing
/// about when the paid months run out. The conversion is the whole point: read
/// as bare wall-clock, a UTC day is an hour early in Algiers, and a plan that
/// ends at `2026-10-01 00:00:00` UTC ends on the 30th for the man paying for it.
String? subscriptionEndDateLabel(DateTime? local) {
  if (local == null) return null;
  final d = local.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A trimmed string, or null when the field is absent, empty or not a string.
///
/// The difference from `'${json['x'] ?? ''}'` matters for a promise: an absent
/// renewal note must be *missing*, so the screen can fall back, and never a
/// blank line the user reads as a message that failed to load.
String? _text(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  return v.isEmpty ? null : v;
}

/// A wire id as text, for a column the API is obliged to send.
///
/// [json['id']`'${}'`] prints the literal «null» for an absent id and throws
/// for nothing, because interpolation accepts any object. But an id is a
/// *key*, not prose: the write path POSTs it back, `labelFor` compares against
/// it, and «null» is neither the operator's id nor an id at all — it is a
/// string that will be sent to the server as though a man had chosen it.
///
/// So the value is read as a string and anything else is flattened by its own
/// text, which is exactly what interpolation did, minus the null. `null` and an
/// absent key both give ''.
String _wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return '$value';
}

/// Whether a `methods` entry is a payment row worth drawing.
///
/// Two rejections, each for a reason the sheet would otherwise show. An entry
/// that is not a map is unreadable — it used to throw and take the whole sheet
/// with it. An entry with no id is nameless: `labelAr` falls back to that id, so
/// the button would carry an empty label and the write would POST an empty
/// `method`. Neither is a payment option the app can offer.
bool _payable(Object? entry) {
  if (entry is! Map) return false;
  return _wireText(entry['id']).trim().isNotEmpty;
}

/// The entries of a JSON list, or nothing when the field is absent or is not a
/// list.
///
/// `json['x'] as List?` is safe against a missing key and unsafe against a
/// string — and D1 answering `"methods": "baridimob"` costs the app the payment
/// sheet rather than one bad row. This is the same "?" the cast was reaching
/// for, written so the wrong type returns empty instead of throwing.
Iterable<dynamic> _list(Object? value) =>
    value is List ? value : const <dynamic>[];

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// An int that stays null when the field is absent or unreadable, so a
/// missing amount never becomes a printed zero.
int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
