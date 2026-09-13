import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// One destination in [AppTabBar].
class AppTabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const AppTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// The centre action of [AppTabBar] — the raised gold button.
class AppTabAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AppTabAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Bottom navigation in the approved board's style: a white hairline bar with
/// four labelled destinations and one **raised gold button** in the middle for
/// the single thing this role does most. The selected destination is navy ink:
/// gold on white measures ~2:1 and would fail the low-literacy legibility bar.
///
/// The button is drawn inside this widget's own box (88dp, of which the lower
/// 60dp is the bar) instead of being translated upwards, so nothing depends on
/// the Scaffold allowing an overflow to paint.
class AppTabBar extends StatelessWidget {
  /// Index into [items] of the visible destination.
  final int index;

  /// Called with the tapped destination's index. The centre action is separate.
  final ValueChanged<int> onSelect;

  /// Exactly four destinations — two either side of the centre action.
  final List<AppTabItem> items;

  final AppTabAction action;

  const AppTabBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.items,
    required this.action,
  }) : assert(items.length == 4, 'AppTabBar is designed for four destinations');

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 88,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // The bar itself.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 60,
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(
                    top: BorderSide(color: AppTheme.line, width: 1),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _tab(items[0], 0),
                    _tab(items[1], 1),
                    // Room for the raised button and the label beneath it.
                    const SizedBox(width: 84),
                    _tab(items[2], 2),
                    _tab(items[3], 3),
                  ],
                ),
              ),
            ),

            // The raised centre button.
            Positioned(
              top: 0,
              child: Semantics(
                button: true,
                label: action.label,
                child: GestureDetector(
                  key: const Key('tab-action'),
                  behavior: HitTestBehavior.opaque,
                  onTap: action.onTap,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surface, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.30),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(action.icon,
                        size: 27, color: AppTheme.navy),
                  ),
                ),
              ),
            ),

            // The centre label, on the same baseline as the destinations'.
            Positioned(
              bottom: 11,
              child: IgnorePointer(
                child: SizedBox(
                  width: 84,
                  child: Text(
                    action.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: AppTheme.fsBadge,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: AppTheme.accentDeep,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(AppTabItem item, int i) {
    final selected = index == i;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        child: GestureDetector(
          key: Key('tab-$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                size: 23,
                color: selected ? AppTheme.navy : AppTheme.textMuted,
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: AppTheme.fsBadge,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.1,
                    color: selected ? AppTheme.navy : AppTheme.textMuted,
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
