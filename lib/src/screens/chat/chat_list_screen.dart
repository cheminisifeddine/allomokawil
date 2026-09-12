import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/ui.dart';
import '../../widgets/skeletons.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final Repository repo;

  /// A conversations future the caller already holds.
  ///
  /// The client home needs the same list to decide whether its first-run guide
  /// is still needed, so it hands its future over instead of making every
  /// app-open pay for this endpoint twice.
  final Future<List<Conversation>>? initial;

  /// What an empty inbox does next.
  ///
  /// A conversation is never created *here* — it starts in the marketplace,
  /// either by messaging a contractor or by quoting a project. The inbox lives
  /// in a tab inside two different shells, so the shell hands in the switch
  /// instead of this screen guessing where the marketplace is.
  final VoidCallback? onDiscover;

  const ChatListScreen({
    super.key,
    required this.repo,
    this.initial,
    this.onDiscover,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.initial ?? widget.repo.conversations();
  }

  void _reload() {
    setState(() => _future = widget.repo.conversations());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('الرسائل')),
        body: FutureBuilder<List<Conversation>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Shimmer(child: LoadingList(count: 4));
            }
            if (snap.hasError) {
              return EmptyView(
                icon: Icons.wifi_off_rounded,
                title: 'تعذّر جلب الرسائل',
                message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                actionLabel: 'إعادة المحاولة',
                onAction: _reload,
              );
            }
            final convs = snap.data ?? const [];
            if (convs.isEmpty) {
              return _emptyInbox(context);
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                itemCount: convs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ConversationTile(
                  conv: convs[i],
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => ChatScreen(
                                conversationId: convs[i].id,
                                otherUserId: 0,
                                otherName: convs[i].otherUserName,
                                repo: widget.repo,
                              )))
                      .then((_) => _reload()),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The dead end the second tab used to be: an explanation a user cannot act
  /// on. Both roles now get the sentence that says what creates a conversation
  /// and the button that starts one — a client browses contractors, a
  /// contractor browses the open projects.
  Widget _emptyInbox(BuildContext context) {
    final isCustomer = AppScope.of(context).auth.role == UserRole.customer;
    final canDiscover = widget.onDiscover != null;
    return EmptyView(
      icon: Icons.forum_outlined,
      title: 'لا محادثات بعد',
      message: isCustomer
          ? 'اختر مقاولاً من دليل المقاولين وراسله، أو انشر مشروعك ليصلك عرضه هنا.'
          : 'تصفّح المشاريع المفتوحة وقدّم عرضك؛ تُفتح المحادثة مع صاحب المشروع هنا.',
      actionLabel: !canDiscover
          ? null
          : (isCustomer ? 'تصفّح المقاولين' : 'تصفّح المشاريع المفتوحة'),
      actionIcon: Icons.search_rounded,
      onAction: widget.onDiscover,
    );
  }
}

/// One conversation row: avatar, name, one-line preview, relative time and
/// the unread badge on the trailing edge (left in RTL).
class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;

  const _ConversationTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasUnread = conv.unreadCount > 0;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          _Avatar(conv: conv),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  conv.otherUserName.isEmpty ? 'محادثة' : conv.otherUserName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.h2.copyWith(fontSize: 15.5),
                ),
                if (conv.lastMessageContent != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    conv.lastMessageContent!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySoft.copyWith(fontSize: 13.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (conv.lastMessageAt != null)
                Text(
                  _relativeTime(conv.lastMessageAt!),
                  style: AppTheme.caption.copyWith(
                      fontSize: 11.5, color: AppTheme.textMuted),
                ),
              if (hasUnread) ...[
                if (conv.lastMessageAt != null) const SizedBox(height: 7),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    // Accent is the app's single highlight colour.
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                    textAlign: TextAlign.center,
                    style: AppTheme.label.copyWith(
                        fontSize: 12, height: 1.2, color: AppTheme.navy),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Conversation conv;
  const _Avatar({required this.conv});

  @override
  Widget build(BuildContext context) {
    final url = conv.otherUserAvatar;
    if (url == null || url.isEmpty) {
      return InitialAvatar(name: conv.otherUserName, size: 52);
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            InitialAvatar(name: conv.otherUserName, size: 52),
      ),
    );
  }
}

/// Short, low-literacy-friendly relative time in Arabic.
String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 7) return 'قبل ${diff.inDays} ي';
  final dd = time.day.toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}
