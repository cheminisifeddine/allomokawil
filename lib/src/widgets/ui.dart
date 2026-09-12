import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/taxonomy.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  Shared UI kit for Allo Mokawil.
///
///  HARD RULE for this whole kit: no widget may leave a `color` unset and hope
///  to inherit it. The old specialty tiles did exactly that inside a Material 3
///  `ChoiceChip` and rendered white-on-white. Every text style below names its
///  colour. Keep it that way.
/// ─────────────────────────────────────────────────────────────────────────

/// Circular icon on a soft wash — the visual anchor of every card/tile.
class IconBubble extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color wash;
  final double size;

  const IconBubble({
    super.key,
    required this.icon,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: wash, shape: BoxShape.circle),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// White, rounded, hairline-bordered surface. The app's basic building block.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = AppTheme.rLg,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppTheme.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// Arabic section heading with an optional trailing action ("عرض الكل").
class SectionTitle extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  final IconData? icon;

  const SectionTitle(
    this.text, {
    super.key,
    this.actionText,
    this.onAction,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: AppTheme.navy),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTheme.h2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionText != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Text(actionText!,
                        style: AppTheme.label.copyWith(
                            fontSize: 13.5, color: AppTheme.info)),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 12, color: AppTheme.info),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single big amber call-to-action, with an inline loading state.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final btn = ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.navy,
        disabledBackgroundColor: AppTheme.line,
        disabledForegroundColor: AppTheme.textMuted,
        elevation: 0,
        minimumSize: const Size.fromHeight(AppTheme.tapMin),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd)),
      ),
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: AppTheme.navy),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 21, color: AppTheme.navy),
                  const SizedBox(width: 9),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: AppTheme.button,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Outlined, quieter action that sits next to [PrimaryButton].
class SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;

  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final btn = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.navy,
        minimumSize: const Size.fromHeight(AppTheme.tapMin),
        side: const BorderSide(color: AppTheme.line, width: 1.5),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rMd)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppTheme.navy),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(label,
                style: AppTheme.button.copyWith(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// Compact icon + name pill — replaces bare emoji strings in list rows.
class CategoryBadge extends StatelessWidget {
  final String slug;
  final String? label;

  const CategoryBadge({super.key, required this.slug, this.label});

  @override
  Widget build(BuildContext context) {
    final tint = Taxonomy.categoryTint(slug);
    final wash = Taxonomy.categoryWash(slug);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Taxonomy.categoryIcon(slug), size: 14, color: tint),
          const SizedBox(width: 6),
          // Flexible + ellipsis: a bare Text takes its intrinsic width inside a
          // Row, which pushed long Arabic category names past the card edge.
          Flexible(
            child: Text(
              label ?? Taxonomy.categoryName(slug),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.label.copyWith(fontSize: 12.5, color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable tile used by every picker (specialty, urgency, filters).
/// This is what was rendering white-on-white before: now every colour here is
/// written down, so it is impossible for the label to vanish.
class SelectableTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color tint;
  final Color wash;
  final double height;

  const SelectableTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
    this.tint = AppTheme.navy,
    this.wash = AppTheme.lineSoft,
    this.height = 104,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accentWash : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: selected ? AppTheme.navy : AppTheme.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.navy : wash,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 19, color: selected ? AppTheme.onNavy : tint),
              ),
              const SizedBox(height: 6),
              // Flexible, not a fixed box: a two-line Arabic label must be able
              // to shrink instead of overflowing the tile.
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Explicit colour — this is the bug fix.
                  style: AppTheme.label.copyWith(
                    fontSize: 12,
                    height: 1.25,
                    color: selected ? AppTheme.navy : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured status badge for project/quote states.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color wash;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    this.color = AppTheme.info,
    this.wash = AppTheme.infoWash,
    this.icon,
  });

  factory StatusPill.project(String status) {
    // Accept both wire style ('in_progress') and Dart enum-name ('inProgress').
    switch (status.replaceAll('_', '').toLowerCase()) {
      case 'inprogress':
        return const StatusPill(
            label: 'قيد التنفيذ',
            color: AppTheme.info,
            wash: AppTheme.infoWash,
            icon: Icons.play_circle_fill_rounded);
      case 'completed':
        return const StatusPill(
            label: 'منتهي',
            color: AppTheme.success,
            wash: AppTheme.successWash,
            icon: Icons.check_circle_rounded);
      case 'cancelled':
        return const StatusPill(
            label: 'ملغى',
            color: AppTheme.danger,
            wash: AppTheme.dangerWash,
            icon: Icons.cancel_rounded);
      default:
        return const StatusPill(
            label: 'مفتوح',
            color: AppTheme.accentDeep,
            wash: AppTheme.accentWash,
            icon: Icons.bolt_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: AppTheme.label.copyWith(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}

/// Star rating row (read-only display).
class RatingStars extends StatelessWidget {
  final double rating;
  final int? count;
  final double size;

  const RatingStars({
    super.key,
    required this.rating,
    this.count,
    this.size = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating.round()
                ? Icons.star_rounded
                : (i - 0.5 <= rating
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded),
            size: size,
            color: AppTheme.star,
          ),
        const SizedBox(width: 6),
        Text(
          rating.toStringAsFixed(1),
          style: AppTheme.label.copyWith(fontSize: size - 2, color: AppTheme.textPrimary),
        ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text('($count)',
              style: AppTheme.caption.copyWith(fontSize: size - 3)),
        ],
      ],
    );
  }
}

/// Round initial avatar — used where we have no profile photo.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InitialAvatar({super.key, required this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '؟'
        : String.fromCharCode(trimmed.runes.first);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppTheme.navy,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: AppTheme.onNavy,
        ),
      ),
    );
  }
}

/// Friendly empty / error state with an icon, message and optional action.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: danger ? AppTheme.dangerWash : AppTheme.lineSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 44,
                  color: danger ? AppTheme.danger : AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTheme.bodySoft,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              PrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
                icon: Icons.refresh_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom action bar so the primary action is never below the fold.
class StickyCta extends StatelessWidget {
  final Widget child;

  const StickyCta({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// Label + value row with a leading icon (worker profile, project facts).
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppTheme.navy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.lineSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTheme.caption.copyWith(fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    style: AppTheme.label.copyWith(fontSize: 14.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grey shimmer block used while lists load.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppTheme.lineSoft,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

