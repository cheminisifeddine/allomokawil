import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/l10n/strings.dart';
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
  /// **This badge is NOT the bell's number, and a comment that said it was is
  /// how the two tables were nearly merged.** An earlier version of this line
  /// claimed the count came from the same `/api/unread` the bell reads. It did
  /// not, and it cannot:
  ///
  ///   `/api/unread`              -> the **notifications** row count, cleared by
  ///                                 `/api/notifications/read`.
  ///   `/api/mobile/conversations` -> per-thread `unread_count`, cleared by
  ///                                 reading the thread.
  ///
  /// `AppTabItem.badge` is fed from `unreadMessageTotal(...)` on the
  /// conversations list (`worker_home_screen.dart:231` / `customer_home_screen
  /// .dart:356`, both `badge: _unreadMessages`). Different tables, different
  /// clear-actions, so the two pips are **meant** to differ, and the badge is
  /// the sum of the rows the inbox draws beneath it, so the tab and the list
  /// agree by construction. `unread_message_count.dart` states this at length.
  ///
  /// The consequence is the whole reason this badge cannot borrow the bell's
  /// withdrawal flag: `NotificationCountTrust` is about `/api/unread`, and a
  /// failed *conversations* read would not move it, while a notification
  /// withdrawal would grey a number that has nothing to do with notifications.
  /// Keep the flag and the pips separate.
  ///
  /// **It has a state of its own now**, and it is [AppScope.messages]. A failed
  /// conversations read withdraws it and the pip goes muted — same digits,
  /// same weight, same size, `textMuted` instead of the action colour — so the
  /// number survives as the phone's best estimate while the app stops claiming
  /// it is fresh. The alternative, zeroing the badge, is **worse than the
  /// bug**: 0 is «أنت على اطّلاع», a claim, and a 0 that appears because a
  /// request dropped is a message the user was told he does not have.
  final int badge;

  /// Whether [badge] is the messages count, and so the one that can be
  /// withdrawn by a failed conversations read.
  ///
  /// **An explicit flag, never `label == 'الرسائل'`.** Matching the Arabic
  /// string would put the mutable state of a data flag in a user-facing label:
  /// a copy edit, a translation swap, or a plural that does not match the
  /// three-letter word would silently stop muting the pip, and it would fail
  /// silently — the badge would just go gold again, which is the exact bug.
  /// The two shells are the only callers that set it, and both set it on the
  /// one destination whose count comes from the conversations table.
  final bool countsMessages;

  const AppTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge = 0,
    this.countsMessages = false,
  });
}

/// A [Listenable] that never fires, for a tab bar pumped with no scope.
///
/// `Listenable.empty()` is the natural name for this and is not available in
/// the pinned SDK, so it is spelled out. It must stay silent forever: a bar
/// with no scope above it has no flag anyone can withdraw, and a builder that
/// fired would repaint on nothing.
class _NeverListenable implements Listenable {
  const _NeverListenable();

  @override
  void addListener(VoidCallback _) {}

  @override
  void removeListener(VoidCallback _) {}
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
                    _tab(context, items[0], 0),
                    _tab(context, items[1], 1),
                    // Room for the raised button and the label beneath it.
                    const SizedBox(width: 84),
                    _tab(context, items[2], 2),
                    _tab(context, items[3], 3),
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
                      fontWeight: AppTheme.wStrong,
                      height: AppTheme.lhTightest,
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

  /// Whether the messages badge is currently the phone's guess.
  ///
  /// `AppScope.maybeOf` rather than `AppScope.of` on purpose: a tab bar
  /// pumped on its own — a widget test, a design shot — has no scope above it,
  /// and a screen that must work both in the app and alone asks this way
  /// instead of asserting. No scope means no claim, and no claim means the
  /// confirmed gold, which is the right answer for a flag nobody has withdrawn.
  bool _messagesUnconfirmed(BuildContext context) =>
      AppScope.maybeOf(context)?.messages.unconfirmed ?? false;

  /// The flag the pip listens to, or an empty list when there is no scope.
  ///
  /// `Listenable.empty` is the honest answer for a bar pumped on its own: it
  /// never fires, which is correct, because nothing in that tree can withdraw
  /// a count it never had.
  Listenable _messagesListenable(BuildContext context) =>
      AppScope.maybeOf(context)?.messages ??
      const _NeverListenable();

  Widget _tab(BuildContext context, AppTabItem item, int i) {
    final selected = index == i;
    final count = item.badge;
    // Only the messages count can be unconfirmed, and only the shell that fed
    // it from the conversations table has earned that claim — so the scope is
    // read lazily and only when this destination is one that asked for it.
    // The confirmation state is read inside the `ListenableBuilder` below, not
    // here, so that a withdrawal repaints the pip without rebuilding the bar.
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
                      // **A `ListenableBuilder`, and the reason is a bug this
                      // would otherwise ship.** `AppTabBar` is a
                      // `StatelessWidget`, so reading `unconfirmed` during
                      // build and painting it would show the value at the
                      // moment the tab bar happened to rebuild — and nothing
                      // here rebuilds it. The failure is silent and total: a
                      // failed read withdraws the flag, the flag notifies, no
                      // widget is listening, and the pip stays gold forever.
                      // That is precisely the lie the flag was added to stop,
                      // arrived at through the new code. The bell gets this for
                      // free because it is a `StatefulWidget` that
                      // `addListener`s and `setState`s.
                      child: ListenableBuilder(
                        listenable: _messagesListenable(context),
                        builder: (context, _) => _badge(
                          count,
                          unconfirmed: item.countsMessages
                              ? _messagesUnconfirmed(context)
                              : false,
                        ),
                      ),
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
  Widget _badge(int count, {required bool unconfirmed}) {
    return IgnorePointer(
      child: Semantics(
        excludeSemantics: true,
        // Announced, because colour is the one difference a screen reader
        // cannot see. Same words as the header pip uses for the same state,
        // so the app teaches one rule for both pips rather than two.
        label: unconfirmed ? S.notifCountUnconfirmed : null,
        child: Container(
          key: Key('tab-badge-$count'),
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            // Muted, not gone, and not zero: the last number the phone read
            // is still the best estimate it has. Only the colour changes.
            color: unconfirmed ? AppTheme.textMuted : AppTheme.accent,
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            border:
                Border.all(color: AppTheme.surface, width: AppTheme.hairline),
          ),
          child: Text(
            // 99+ on the number, and the same cap in the announcement, so the
            // two never disagree about what the pip is claiming.
            count > 99 ? '99+' : '$count',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(
              fontSize: AppTheme.fsBadge,
              height: AppTheme.lhBadge,
              fontWeight: AppTheme.wStrong,
              color: AppTheme.navy,
            ),
          ),
        ),
      ),
    );
  }
}
