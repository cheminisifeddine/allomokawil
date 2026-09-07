import 'package:flutter/material.dart';

/// Large, high-contrast primary button with a >= 56px touch target —
/// the backbone of the app's friendly, low-literacy UX.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  const BigButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22),
                  const SizedBox(width: 10),
                ],
                Text(label),
              ],
            ),
    );
  }
}

/// Subtle text-outline secondary button (same touch target).
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const OutlineButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        foregroundColor: Theme.of(context).colorScheme.primary,
        side: const BorderSide(color: appThemeNavy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

const Color appThemeNavy = Color(0xFF16213E);