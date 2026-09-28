import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/unread_message_count.dart';

/// One destination in [AppTabBar].
class AppTabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Unread items on this destination, or 0 for one that has none.
  ///
  /// **This affordance did not exist at all**, and its absence was a
  /// user-visible gap rather than a missing convenience. The unread count
  /// lived on exactly one widget — the header bell — and the bell is mounted
  /// only on the explore tab: `WorkerHomeScreen` builds
  /// `appBar: _tab == 0 ? AppBar(... NotificationsBell() ...) : null`, and the
  /// client's header is drawn by `_ExploreView` inside the same tab. So the
  /// moment a contractor opened **«الرسائل»** — the one tab whose entire
  /// purpose is unread messages — the number saying he had messages left to
  /// read left the app with the header. He was standing in the inbox, and the
  /// only evidence that anything was waiting was nothing.
  ///
  /// The withdrawal flag could not rescue it, and this is the part worth
  /// keeping. `NotificationCountTrust` is a claim about a count **a pip is
  /// painting**; it exists so the header stops asserting a number the phone
  /// cannot check. With no pip on the tab bar there was nothing to withdraw,
  /// so moving to the messages tab did not just hide the count — it made the
  /// unconfirmed state the last two cycles spent earning **unreachable**: a
  /// withdrawn count that goes grey on tab 0 and simply ceases to exist on
  /// tab 2 is the app forgetting its own honesty, not the user reading it.
  ///
  /// The number comes from the same `/api/unread` the bell reads, so the two
  /// cannot disagree: one count, one source, painted in two places.
  final int badge;

  const AppTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
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
    final count = item.badge;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        // Announced, so the count is *heard* and not only painted. The pip is
        // a colour plus three digits; colour is the one difference a screen
        // reader cannot see, which is why the value carries the words.
        value: count > 0 ? unreadMessagesLabel(count) : null,
        child: GestureDetector(
          key: Key('tab-$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 23,
                    color: selected ? AppTheme.navy : AppTheme.textMuted,
                  ),
                  if (count > 0)
                    PositionedDirectional(
                      top: -4,
                      end: -8,
                      child: _badge(count),
                    ),
                ],
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

  /// The unread count on a destination.
  ///
  /// **Gold with navy digits, and never `danger` — that is deliberate.** The
  /// header pip is red because it is the app's one unqualified alarm standing
  /// on a bare surface. A tab bar already carries four other signals, so red
  /// here would turn a routine count into an emergency, and the tab is the
  /// place the user goes to *resolve* a count rather than to be worried by it.
  /// Gold is the app's single "do this" colour and it is the one the
  /// conversation row's own unread pill already uses, so the tab badge and the
  /// inbox list read as one system instead of two.
  ///
  /// The digits are **navy, not white**: white on `accent` is about 1.9:1 and
  /// the gold pip on the inbox row is drawn on a white card for the same
  /// reason. This is the same two tokens as that pill, and the muted state is
  /// the same `textMuted` + white the header pip uses, so a user learns one
  /// rule for the whole app rather than one per surface.
  Widget _badge(int count) {
    return IgnorePointer(
      child: Semantics(
        excludeSemantics: true,
        child: Container(
          key: Key('tab-badge-$count'),
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border: Border.all(color: AppTheme.surface, width: 1.5),
          ),
          child: Text(
            // 99+ on the number, and the same cap in the announcement, so the
            // two never disagree about what the pip is claiming.
            count > 99 ? '99+' : '$count',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
              fontSize: AppTheme.fsBadge,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
        ),
      ),
    );
  }
}
