import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/l10n/strings.dart';
import '../core/theme/app_theme.dart';
import '../data/repository.dart';
import '../screens/notifications/notifications_screen.dart';

/// Bell plus unread pip for the two home headers.
///
/// The count comes from the same `/api/unread` endpoint the message tab
/// already trusts. A failed call keeps the last known count instead of
/// painting an error on the header, and the count is refreshed on the way back
/// from the centre, so opening a notification clears the pip.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key, this.repo, this.onNavy = false});

  /// Injected by tests and by callers that already hold a repository.
  final Repository? repo;

  /// Draw for a navy header instead of a white app bar.
  final bool onNavy;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  late final Repository _repo;
  bool _wired = false;
  int _unread = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) {
      return;
    }
    _wired = true;
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final n = await _repo.unreadCount();
      if (!mounted) {
        return;
      }
      setState(() => _unread = n);
    } catch (_) {
      // Keep the last known count: a dropped request is not a broken header.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NotificationsScreen(repo: _repo)),
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.onNavy ? AppTheme.onNavy : AppTheme.navy;
    return Semantics(
      button: true,
      label: S.notifications,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            key: const Key('notifications-bell'),
            icon: Icon(Icons.notifications_none_rounded, color: ink),
            tooltip: S.notifications,
            onPressed: _open,
          ),
          if (_unread > 0)
            PositionedDirectional(
              top: 4,
              end: 2,
              child: IgnorePointer(
                child: Container(
                  key: const Key('notifications-badge'),
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                    border: Border.all(color: AppTheme.surface, width: 1.5),
                  ),
                  child: Text(
                    _unread > 99 ? '99+' : '$_unread',
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      fontSize: AppTheme.fsBadge,
                      color: AppTheme.onNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
