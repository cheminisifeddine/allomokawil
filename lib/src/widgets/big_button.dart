import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'motion.dart';

/// Large, high-contrast primary button with a >= 56px touch target —
/// the backbone of the app's friendly, low-literacy UX.
///
/// Kept as a thin wrapper over the shared kit so every call site in the app
/// inherits the new look without being touched.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  const BigButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return _KitPrimary(
      label: label,
      icon: icon,
      loading: loading,
      onPressed: onPressed,
      expanded: expanded,
    );
  }
}

class _KitPrimary extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;
  final bool expanded;

  const _KitPrimary({
    required this.label,
    this.icon,
    required this.loading,
    this.onPressed,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final btn = ElevatedButton(
      onPressed: loading ? null : onPressed,
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
                  child: Text(label,
                      style: AppTheme.button,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
    );
    // Filled key, and the visual half of "my thumb landed": the button
    // shrinks 3% while a finger is on it (see Pressable).
    final pressable = Pressable(enabled: !loading && onPressed != null, child: btn);
    return expanded
        ? SizedBox(width: double.infinity, child: pressable)
        : pressable;
  }
}

/// Subtle outlined secondary button (same touch target).
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const OutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      // Same press answer as BigButton — a screen never mixes the two.
      child: Pressable(
        enabled: onPressed != null,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppTheme.tapMin),
            foregroundColor: AppTheme.navy,
            side: const BorderSide(color: AppTheme.controlLine, width: 1.5),
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
                    style: AppTheme.button.copyWith(fontSize: AppTheme.fsLead),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const Color appThemeNavy = AppTheme.navy;
