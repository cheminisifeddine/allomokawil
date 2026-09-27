import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/auth_gate.dart';
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
///
/// **The count is also refreshed when the app comes back to the foreground**,
/// which is the moment it actually goes stale. Before this, `_refresh` ran
/// once from `didChangeDependencies` and the bell was then correct only until
/// the phone was locked — and nothing in the app observed the lifecycle at all
/// (`WidgetsBindingObserver` appears nowhere in `lib/`), so a quote that landed
/// while the contractor was in another app left a header that said «nothing
/// new» until he happened to open the centre. The pip is the one line on the
/// home screen that claims something arrived, so a pip that cannot go up is the
/// worst possible failure for it: it does not look broken, it looks like a
/// quiet day.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key, this.repo, this.onNavy = false});

  /// Injected by tests and by callers that already hold a repository.
  final Repository? repo;

  /// Draw for a navy header instead of a white app bar.
  final bool onNavy;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell>
    with WidgetsBindingObserver {
  late final Repository _repo;
  bool _wired = false;
  int _unread = 0;

  /// One read in flight at a time.
  ///
  /// A phone can resume, background and resume again in the time one request
  /// takes on a 3G bar, and each of those starts another. Without this the
  /// slower answer wins the `setState`, so the pip can end up showing the
  /// count from *before* the newer read — a badge that goes backwards on
  /// resume, which is worse than a stale one.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Registered here rather than in `didChangeDependencies` because the
    // observer is about the engine, not about this screen's dependencies.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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

  /// Android delivers this on every return to the foreground, and iOS too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed`. `inactive` fires when a dialog, the app switcher or a
    // permission sheet comes over the top, and the app is still not usable —
    // asking the network there spends the user's data to draw the same number
    // they will see a moment later anyway.
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // `_repo` is assigned in `didChangeDependencies`, which the engine can
    // reach before it delivers the first lifecycle message. Reading a `late
    // final` then throws inside a framework callback, where it is swallowed
    // as a red-screen report about a bug the user never caused.
    if (!_wired) {
      return;
    }
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final n = await _repo.unreadCount();
      if (!mounted) {
        return;
      }
      setState(() => _unread = n);
    } catch (_) {
      // Keep the last known count: a dropped request is not a broken header.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _open() async {
    // Signed out there is no inbox to open; the bell is still drawn so the app
    // looks the same either way, and the tap leads to the account form.
    if (!await AuthGate.requireAuth(context, what: 'لقراءة إشعاراتك')) return;
    if (!mounted) return;
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
