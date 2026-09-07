import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../models/chat.dart';
import '../../widgets/empty_state.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  final Repository repo;
  const ChatListScreen({super.key, required this.repo});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late Future<List<Conversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.conversations();
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
              return const LoadingList(count: 4);
            }
            if (snap.hasError) {
              return EmptyState(
                  icon: Icons.wifi_off,
                  title: 'تعذّر جلب الرسائل',
                  action: TextButton(
                      onPressed: _reload,
                      child: const Text('إعادة المحاولة')));
            }
            final convs = snap.data ?? const [];
            if (convs.isEmpty) {
              return const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'لا محادثات بعد',
                  subtitle: 'ستظهر هنا رسائلك مع المقاولين وأصحاب المشاريع');
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
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
}

class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final VoidCallback onTap;

  const _ConversationTile({required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E7E3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFE0E5F0),
              backgroundImage: conv.otherUserAvatar != null
                  ? NetworkImage(conv.otherUserAvatar!)
                  : null,
              child: conv.otherUserAvatar == null
                  ? const Icon(Icons.person_outline)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.otherUserName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (conv.lastMessageContent != null)
                    Text(conv.lastMessageContent!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF6E6E73))),
                ],
              ),
            ),
            if (conv.unreadCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0A458),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${conv.unreadCount}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}