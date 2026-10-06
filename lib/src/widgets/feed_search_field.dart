import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// One search box, used by every feed that filters what it already loaded.
///
/// Deliberately [StatelessWidget] + an externally owned [controller]: the screen
/// needs to clear the box from the outside too (the "مسح البحث" button inside
/// the empty state), and a widget that hides its controller makes that
/// impossible without a GlobalKey.
///
/// Filtering is live — there is no submit round trip, because the rows are
/// already in memory. That is what makes the feed feel native: type one letter,
/// the list answers. The keyboard's own action just gets out of the way.
class FeedSearchField extends StatelessWidget {
  final TextEditingController controller;

  /// Arabic hint, e.g. 'ابحث في مشاريعك...'.
  final String hint;

  /// Fires on every keystroke *and* on clear, so the screen always holds the
  /// same string the box displays.
  final ValueChanged<String> onChanged;

  /// The horizontal inset, which the caller owns.
  ///
  /// The field used to hardcode `18` and the feed under it hardcoded its own,
  /// so the two could not be kept aligned by construction — they only matched
  /// because two writers happened to type the same number. `worker_home` is
  /// still on 18 and has not been swept; `projects_screen` has moved to
  /// `AppTheme.s16`. Passing the number the list uses makes the shared left
  /// edge a decision of the screen instead of a coincidence, and a screen that
  /// moves its list without moving this steps in and out under the customer.
  final double horizontalInset;

  const FeedSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.horizontalInset = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalInset, 6, horizontalInset, 2),
      // Rebuilds only this subtree when the text changes, so the clear button
      // appears/disappears without repainting the list behind it.
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final empty = value.text.isEmpty;
          return TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            style: AppTheme.body.copyWith(color: AppTheme.textPrimary),
            onChanged: onChanged,
            // Hiding the keyboard is the whole submit action: results are
            // already on screen behind it.
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.body.copyWith(color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.navy),
              suffixIcon: empty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textSecondary),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          );
        },
      ),
    );
  }
}
