import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/notification_copy.dart';
import '../../data/repository.dart';
import '../../models/notification.dart';
import '../project/project_detail_screen.dart';

/// Notification centre: every quote, acceptance, message and review the user
/// has received, newest first, with the unread ones marked.
///
/// This screen is why the app can be closed and reopened without losing what
/// happened while it was away: each row says what happened, when, and opens
/// the thing it is about.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.repo});

  /// Injected by tests and by callers that already hold a repository.
  final Repository? repo;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Repository _repo;
  bool _wired = false;

  List<AppNotification> _items = const [];
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) {
      return;
    }
    _wired = true;
    _repo = widget.repo ?? Repository(AppScope.of(context).api);
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.notifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = list;
        _error = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = S.errUnexpected);
    }
  }

  int get _unread => _items.where((n) => n.isRead == 0).length;

  /// Marks [ids] read. The rows flip immediately so the tap feels answered,
  /// then the list is reloaded from the server — so a write that fails cannot
  /// leave the screen claiming something the database does not agree with.
  Future<void> _markRead(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    setState(() {
      _items = [
        for (final n in _items) ids.contains(n.id) ? n.asRead() : n,
      ];
    });
    try {
      await _repo.markNotificationsRead(ids: ids);
    } catch (_) {
      // The reload below puts the row back if the server refused.
    }
    await _load();
  }

  Future<void> _markAllRead() async {
    if (_unread == 0) {
      return;
    }
    setState(() {
      _items = [for (final n in _items) n.asRead()];
    });
    try {
      await _repo.markNotificationsRead();
    } catch (_) {
      // As above: the reload is the source of truth.
    }
    await _load();
  }

  void _open(AppNotification n) {
    _markRead([n.id]);
    final target = _projectTarget(n.link);
    if (target == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => target),
    );
  }

  /// The backend links projects as `/dashboard/projects/<id>` for a project
  /// owner and `/w/projects/<id>` for a contractor. Both open the same screen;
  /// any other link is ignored rather than pushed blindly.
  ProjectDetailScreen? _projectTarget(String? link) {
    if (link == null) {
      return null;
    }
    final id = RegExp(r'projects/(\d+)').firstMatch(link)?.group(1);
    if (id == null) {
      return null;
    }
    return ProjectDetailScreen(projectId: id, repo: _repo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text(S.notifications, style: AppTheme.bar),
        actions: [
          if (_unread > 0)
            TextButton(
              key: const Key('notifications-mark-all'),
              onPressed: _markAllRead,
              child: Text(
                S.markAllRead,
                style: AppTheme.label.copyWith(color: AppTheme.accentDeep),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accentDeep,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      final failed = _error != null;
      return _message(
        icon:
            failed ? Icons.cloud_off_rounded : Icons.notifications_none_rounded,
        title: failed ? _error! : S.noNotifications,
        hint: failed ? S.noNotificationsErrorHint : S.noNotificationsHint,
        actionLabel: failed ? S.retry : S.back,
        onAction: failed ? _load : () => Navigator.of(context).maybePop(),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _tile(_items[i]),
    );
  }

  /// Scrollable on purpose: a pull-to-refresh gesture needs something to pull.
  Widget _message({
    required IconData icon,
    required String title,
    required String hint,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    // Centred in the space that is actually there, but kept a scroll view so
    // pull-to-refresh still has something to pull: a short screen scrolls
    // instead of overflowing.
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 54, color: AppTheme.textMuted),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTheme.h2.copyWith(
                      fontSize: AppTheme.fsH2, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: AppTheme.body.copyWith(
                      fontSize: AppTheme.fsMeta, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 22),
                Center(
                  child: SizedBox(
                    width: 220,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        style: AppTheme.button.copyWith(
                            fontSize: AppTheme.fsSmall,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(AppNotification n) {
    final look = NotificationLook.of(n.type);
    final unread = n.isRead == 0;
    final body = n.body ?? '';
    final when = relativeTimeAr(n.createdAt);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        key: Key('notification-${n.id}'),
        onTap: () => _open(n),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: unread ? AppTheme.accent : AppTheme.line,
              width: unread ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: look.wash,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Icon(look.icon, size: 22, color: look.tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            look.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.h2.copyWith(
                                fontSize: AppTheme.fsLead,
                                color: AppTheme.textPrimary),
                          ),
                        ),
                        if (unread) const _NewTag(),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body.copyWith(
                            fontSize: AppTheme.fsMeta,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        when,
                        style: AppTheme.caption.copyWith(
                            fontSize: AppTheme.fsCaption,
                            color: AppTheme.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold «جديد» pip for a row the user has not opened yet.
class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accentWash,
        borderRadius: BorderRadius.circular(AppTheme.rPill),
      ),
      child: Text(
        S.newTag,
        style: AppTheme.caption
            .copyWith(fontSize: AppTheme.fsBadge, color: AppTheme.accentDeep),
      ),
    );
  }
}
