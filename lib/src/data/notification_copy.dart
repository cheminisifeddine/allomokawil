import 'package:flutter/material.dart';

import '../core/l10n/arabic_agreement.dart';
import 'chat_time.dart';
import '../core/theme/app_theme.dart';
import '../models/plan.dart';

/// Presentation for one API notification type.
///
/// The backend stores a developer key (`new_quote`, `quote_accepted`, …).
/// That key must never reach the screen: a user reading "new_quote" learns
/// nothing. Every type maps to Arabic copy here, and an unknown type falls
/// back to a neutral look instead of leaking the raw key.
class NotificationLook {
  const NotificationLook({
    required this.label,
    required this.icon,
    required this.tone,
    required this.wash,
  });

  /// Short Arabic headline for the event, e.g. «عرض سعر جديد».
  final String label;

  final IconData icon;

  /// Ink for [icon] drawn on top of [wash].
  final Color tone;
  final Color wash;

  static const NotificationLook _fallback = NotificationLook(
    label: 'إشعار',
    icon: Icons.notifications_rounded,
    tone: AppTheme.info,
    wash: AppTheme.infoWash,
  );

  static const Map<String, NotificationLook> _byType = {
    'new_quote': NotificationLook(
      label: 'عرض سعر جديد',
      icon: Icons.request_quote_rounded,
      tone: AppTheme.accentDeep,
      wash: AppTheme.accentWash,
    ),
    'quote_accepted': NotificationLook(
      label: 'تم قبول عرضك',
      icon: Icons.handshake_rounded,
      tone: AppTheme.success,
      wash: AppTheme.successWash,
    ),
    'new_message': NotificationLook(
      label: 'رسالة جديدة',
      icon: Icons.chat_bubble_rounded,
      tone: AppTheme.info,
      wash: AppTheme.infoWash,
    ),
    'review_received': NotificationLook(
      label: 'تقييم جديد',
      icon: Icons.star_rounded,
      tone: AppTheme.accentDeep,
      wash: AppTheme.accentWash,
    ),
    'project_update': NotificationLook(
      label: 'تحديث على المشروع',
      icon: Icons.campaign_rounded,
      tone: AppTheme.navy,
      wash: AppTheme.surfaceAlt,
    ),
  };

  /// Known types render their own copy; anything else renders «إشعار».
  static NotificationLook of(String type) => _byType[type] ?? _fallback;

  /// Every type the backend can send, for tests and guards.
  static List<String> get knownTypes => _byType.keys.toList(growable: false);
}

/// Arabic relative time for a notification timestamp.
///
/// Returns an empty string when the timestamp is missing: a row with no time
/// must render nothing, never «null» and never a raw ISO string.
String relativeTimeAr(DateTime? at, {DateTime? now}) {
  if (at == null) {
    return '';
  }
  final today = now ?? DateTime.now();
  final diff = today.difference(at);
  if (diff.isNegative || diff.inMinutes < 1) {
    return 'الآن';
  }
  if (diff.inMinutes < 60) {
    return _ago(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق');
  }
  if (diff.inHours < 24) {
    return _ago(diff.inHours, 'ساعة', 'ساعتين', 'ساعات');
  }
  // From here the answer is a **calendar** day count, not a 24-hour period
  // count. `diff.inDays` is a period count and is wrong on both sides of
  // midnight: it calls a 20-minute-old message from 23:50 «0 days» — a day old
  // by the calendar, and «أمس» in `chatDayLabel` on the same instant — and it
  // calls a 27-hour-old message «1 day» — two calendar days old — yesterday.
  // The app therefore dated one message two ways: the chat divider said «أمس»
  // while the chat list row beside it said «قبل 20 دقيقة».
  final days = calendarDaysBetween(at, today);
  if (days <= 1) {
    return 'أمس';
  }
  if (days < 30) {
    return _ago(days, 'يوم', 'يومين', 'أيام');
  }
  if (days < 60) {
    return 'قبل شهر';
  }
  // Past a year the month count stops being information and becomes an
  // artefact of the division. This arm had no upper bound, so it went on
  // dividing forever: a conversation from 2015 printed **«قبل 133 شهر»** in the
  // chat list, and the same string appeared on any old notification. Beside it
  // the chat divider on the very same thread already read «16/10/2015» — one
  // thread, two answers, which is the defect this whole file exists to stop.
  //
  // So a year and beyond is **dated**, not counted, and the date is the one
  // [chatDayLabel] already prints, reused rather than written a second time.
  // The threshold is [SubscriptionStatus.maxCountedDays], read from there
  // rather than re-declared, so the two surfaces cannot drift apart: the
  // subscription card adopted this rule on 26 Sep for the same stated reason —
  // «a count like «بعد 26560 يوماً» is a number no contractor can read as
  // time».
  //
  // The bound is `>=` here and `>` in [SubscriptionStatus.expiryCountdownAr], so
  // the two differ by one day — 365 days of age is dated here, a 365-day
  // remaining term is still counted there. That is deliberate rather than an
  // oversight, and the two directions are not mirrors: a message exactly a year
  // old is «قبل 12 شهر», a count accurate enough to be worth printing, whereas
  // a year of prepaid cover is the longest thing the founder sells and is
  // exactly the value a contractor reads a day count for. The shared constant
  // keeps the *rule* identical — nothing is described in months or days past a
  // year — without forcing one row's arithmetic onto another.
  if (days >= SubscriptionStatus.maxCountedDays) return chatDayLabel(at, now: today);
  return _ago(days ~/ 30, 'شهر', 'شهرين', 'أشهر');
}

/// Arabic count agreement: 1 → «قبل دقيقة», 2 → «قبل دقيقتين»,
/// 3–10 → «قبل 5 دقائق», 11 and up → «قبل 15 دقيقة».
///
/// The rule itself belongs to [arabicCounted]; this only supplies the nouns and
/// the «قبل » that goes in front of them. It was the first copy of this rule in
/// the app and it was right, which is exactly why the subscription card was
/// written as a fourth one and got it wrong — same nouns, same thresholds, two
/// different implementations, one of them unchecked.
String _ago(int n, String one, String two, String few) =>
    'قبل ${arabicCounted(n, one, two: two, few: few)}';
