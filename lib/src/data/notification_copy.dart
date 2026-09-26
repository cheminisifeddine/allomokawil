import 'package:flutter/material.dart';

import '../core/l10n/arabic_agreement.dart';
import '../core/theme/app_theme.dart';

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
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.isNegative || diff.inMinutes < 1) {
    return 'الآن';
  }
  if (diff.inMinutes < 60) {
    return _ago(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق');
  }
  if (diff.inHours < 24) {
    return _ago(diff.inHours, 'ساعة', 'ساعتين', 'ساعات');
  }
  if (diff.inDays == 1) {
    return 'أمس';
  }
  if (diff.inDays < 30) {
    return _ago(diff.inDays, 'يوم', 'يومين', 'أيام');
  }
  if (diff.inDays < 60) {
    return 'قبل شهر';
  }
  return _ago(diff.inDays ~/ 30, 'شهر', 'شهرين', 'أشهر');
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
