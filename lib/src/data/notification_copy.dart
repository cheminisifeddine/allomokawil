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
  // The one-hour window, 60 through 119 minutes, and the reason this arm is
  // not the hour arm any more.
  //
  // `diff.inHours` **floors**: it answered «قبل ساعة» for 60 *and* for 90
  // *and* for 119 minutes, and threw the minutes away. Probed on 29 Sep, on
  // this exact function: 1 -> «قبل دقيقة», 59 -> «قبل 59 دقيقة», 60/90/119 ->
  // «قبل ساعة», 120 -> «قبل ساعتين». A price read an hour ago and a price
  // read an hour and a half ago were the same sentence, in the stale-band
  // copy the founder reads when deciding whether a number is safe to quote.
  //
  // **Why compound here and not below.** The obvious fix — widen the minute
  // band to 119 — is wrong in a way only the grammar can tell you: it makes
  // «قبل ساعة» unreachable. 119 minutes would read «قبل 119 دقيقة» and 120
  // already reads «قبل ساعتين», so the singular hour would become dead code in
  // a function whose entire job is Arabic count agreement. The hour arm is
  // kept for **exactly one** duration: the first minute of the hour, 60.
  //
  // **Why compound at all.** Past the first hour the bare count is enough
  // (2h05m is «قبل ساعتين» and nobody re-reads the 5), but inside the first
  // hour the bare count is a lie about resolution: «قبل ساعة» claims the value
  // is under 120 minutes when it may be 119, and the difference between a read
  // 60 minutes old and one 119 minutes old is nearly double. That is the only
  // window in this function where the discarded remainder can change the
  // decision, so it is the only window that carries it.
  //
  // The compound is scoped to this arm on purpose. `stale_catalogue_test` pins
  // «قبل ساعتين» with `isNot(contains('و '))` — 2h05m must stay bare, because
  // a figure dated two ways inside one app is the exact defect
  // `readAgeAr` exists to stop. So «قبل ساعة و 30 دقيقة» appears here and
  // nowhere else, and it never attaches to 2 or more hours.
  if (diff.inMinutes < 120) {
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    // 60 minutes exactly: the bare «قبل ساعة», which is the correct and only
    // answer for a read that is precisely one hour old. «قبل ساعة و 0 دقيقة»
    // would be a real sentence about a number nobody can picture.
    if (mins == 0) {
      return _ago(hours, 'ساعة', 'ساعتين', 'ساعات');
    }
    // **The preposition is written once, for the whole phrase.** The first
    // version of this line built both halves with [_ago], which is
    // «قبل ‹noun›» — and printed «قبل ساعة و قبل دقيقة» on screen. Caught by
    // probing this function at 61 minutes, not by the analyzer and not by any
    // test: the string is a valid Dart expression either way, it is simply the
    // wrong Arabic, and only rendering the number can tell you that. So the
    // halves are built with [arabicCounted], which owns the agreement and
    // writes no preposition, and «قبل » is written once here.
    return 'قبل ${arabicCounted(hours, 'ساعة', two: 'ساعتين', few: 'ساعات')}'
        ' و ${arabicCounted(mins, 'دقيقة', two: 'دقيقتين', few: 'دقائق')}';
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
