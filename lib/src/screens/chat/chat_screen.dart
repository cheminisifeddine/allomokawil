import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repository.dart';
import '../../models/chat.dart';
import '../../widgets/ui.dart';

/// Thread chat: text + image (queue-on-retry when offline).
class ChatScreen extends StatefulWidget {
  final int? conversationId;
  final String? projectId;
  final int otherUserId;
  final String otherName;
  final Repository repo;

  const ChatScreen({
    super.key,
    this.conversationId,
    this.projectId,
    required this.otherUserId,
    this.otherName = '',
    required this.repo,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  int get _me => AppScope.of(context).auth.user?.id ?? 0;

  int? _convId;
  List<Message> _messages = [];
  bool _loading = true;
  bool _error = false;
  // Stashed sends when offline — retried with the send button.
  final List<Message> _pending = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      var convId = widget.conversationId;
      convId ??= await widget.repo.openConversation(
        projectId: widget.projectId,
        otherUserId: widget.otherUserId,
      );
      _convId = convId;
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _load() async {
    if (_convId == null) return;
    final msgs = await widget.repo.messages(_convId!);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
      _error = false;
    });
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    _input.clear();
    final isOffline = _pending.isNotEmpty;
    if (isOffline) {
      // Retry queued messages first.
      for (final p in List.of(_pending)) {
        await _retry(p);
      }
    }
    if (text.isEmpty) return;
    try {
      final msg = await widget.repo.sendText(_convId!, text);
      setState(() => _messages = [..._messages, msg]);
    } catch (_) {
      // Offline: queue locally so the user's text isn't lost.
      setState(() {
        _messages = [
          ..._messages,
          Message.fromJson({
            'id': DateTime.now().millisecondsSinceEpoch,
            'conversation_id': _convId ?? 0,
            'sender_id': _me,
            'content': text,
            'message_type': 'text',
            'is_read': 0,
          }),
        ];
        _pending.add(Message.fromJson({
          'id': DateTime.now().millisecondsSinceEpoch,
          'conversation_id': _convId ?? 0,
          'sender_id': _me,
          'content': text,
          'message_type': 'text',
          'is_read': 0,
        }));
      });
      _toast('أنت غير متصل — سيتم إرسال الرسالة لاحقاً');
    }
    _jumpToBottom();
  }

  Future<void> _retry(Message msg) async {
    try {
      final sent = msg.type == MessageType.image
          ? await widget.repo.sendImage(_convId!, File(msg.imageUrl!))
          : await widget.repo.sendText(_convId!, msg.content ?? '');
      setState(() {
        _pending.remove(msg);
        _messages = [..._messages, sent];
      });
    } catch (_) {
      // still offline, keep queued
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final tmp = File(file.path);
    setState(() {
      _messages = [
        ..._messages,
        Message.fromJson({
          'id': DateTime.now().millisecondsSinceEpoch,
          'conversation_id': _convId ?? 0,
          'sender_id': _me,
          'image_url': tmp.path,
          'message_type': 'image',
          'is_read': 0,
        }),
      ];
    });
    try {
      final sent = await widget.repo.sendImage(_convId!, tmp);
      setState(() {
        _messages = [..._messages, sent];
      });
    } catch (_) {
      _pending.add(Message.fromJson({
        'id': DateTime.now().millisecondsSinceEpoch,
        'conversation_id': _convId ?? 0,
        'sender_id': _me,
        'image_url': tmp.path,
        'message_type': 'image',
        'is_read': 0,
      }));
      _toast('أنت غير متصل — سترسل الصورة لاحقاً');
    }
    _jumpToBottom();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Tap-to-view fullscreen preview for an image message.
  void _openImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ImageViewer(url: url),
    ));
  }

  /// True when a day separator should be printed above message [index].
  bool _needsDateDivider(int index) {
    final current = _messages[index].createdAt;
    if (current == null) return false;
    if (index == 0) return true;
    final previous = _messages[index - 1].createdAt;
    if (previous == null) return true;
    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(widget.otherName.isEmpty ? 'الرسائل' : widget.otherName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? EmptyView(
                  icon: Icons.wifi_off_rounded,
                  title: 'تعذّر جلب الرسائل',
                  message: 'تحقّق من اتصالك بالإنترنت ثم أعد المحاولة',
                  actionLabel: 'إعادة المحاولة',
                  onAction: _bootstrap,
                )
              : Column(
                  children: [
                    Expanded(child: _thread()),
                    if (_pending.isNotEmpty) _pendingBanner(),
                    _composer(),
                  ],
                ),
    );
  }

  // ── Thread ──────────────────────────────────────────────────────────────
  Widget _thread() {
    // A conversation nobody has written in yet used to be a blank page above
    // the composer — no explanation, so a user who just tapped "راسل" could
    // believe the app had lost the message. The action is the composer, so the
    // copy points at it instead of inventing a second button.
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined,
                  size: 42, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                'لا رسائل بعد',
                textAlign: TextAlign.center,
                style: AppTheme.h2.copyWith(color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'اكتب رسالتك الأولى في الخانة أسفله وستصل مباشرة.',
                textAlign: TextAlign.center,
                style: AppTheme.bodySoft,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final url = m.imageUrl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_needsDateDivider(i)) _DateDivider(date: m.createdAt!),
            _Bubble(
              message: m,
              mine: m.senderId == _me,
              onImageTap: url == null ? null : () => _openImage(url),
            ),
          ],
        );
      },
    );
  }

  // ── Offline banner ──────────────────────────────────────────────────────
  Widget _pendingBanner() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.accentWash,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: AppTheme.accentDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'رسائل غير مرسلة — اضغط لإعادة المحاولة',
              style: AppTheme.label
                  .copyWith(fontSize: 12.5, color: AppTheme.accentDeep),
            ),
          ),
          TextButton(
            onPressed: _sendText,
            style: TextButton.styleFrom(
              minimumSize: const Size(64, 44),
              foregroundColor: AppTheme.navy,
            ),
            child: Text('إرسال',
                style: AppTheme.label.copyWith(fontSize: 14, color: AppTheme.navy)),
          ),
        ],
      ),
    );
  }

  // ── Composer ────────────────────────────────────────────────────────────
  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _CircleAction(
                icon: Icons.add_photo_alternate_outlined,
                background: AppTheme.lineSoft,
                foreground: AppTheme.navy,
                tooltip: 'إرسال صورة',
                onTap: _pickImage,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendText(),
                  minLines: 1,
                  maxLines: 4,
                  style: AppTheme.body,
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة...',
                    hintStyle:
                        AppTheme.bodySoft.copyWith(color: AppTheme.textMuted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.send_rounded,
                background: AppTheme.accent,
                foreground: AppTheme.navy,
                tooltip: 'إرسال',
                onTap: _sendText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56x56 round action — the app's minimum tap target.
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleAction({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppTheme.tapMin,
            height: AppTheme.tapMin,
            child: Icon(icon, size: 24, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Pill date separator between days.
class _DateDivider extends StatelessWidget {
  final DateTime date;

  const _DateDivider({required this.date});

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final days = today.difference(that).inDays;
    if (days == 0) return 'اليوم';
    if (days == 1) return 'أمس';
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$dd/$mm/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.lineSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _label,
            style: AppTheme.label
                .copyWith(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final VoidCallback? onImageTap;

  const _Bubble({required this.message, required this.mine, this.onImageTap});

  @override
  Widget build(BuildContext context) {
    // Existing alignment logic kept as-is: in this RTL app own messages sit
    // on the left (start-mirrored) and the other party on the right.
    final align = mine ? Alignment.centerLeft : Alignment.centerRight;
    // Asymmetric corners: outer bottom corner is the tighter one.
    final radius = mine
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rLg),
            topRight: Radius.circular(AppTheme.rLg),
            bottomLeft: Radius.circular(AppTheme.rSm),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rLg),
            topRight: Radius.circular(AppTheme.rLg),
            bottomRight: Radius.circular(AppTheme.rSm),
          );

    final Widget body = message.imageUrl != null
        ? _ImageBubble(
            url: message.imageUrl!,
            radius: BorderRadius.circular(AppTheme.rLg),
            onTap: onImageTap,
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? AppTheme.navy : AppTheme.surface,
              borderRadius: radius,
              border: mine ? null : Border.all(color: AppTheme.line),
            ),
            child: Text(
              message.content ?? '',
              style: AppTheme.body.copyWith(
                fontSize: 15,
                color: mine ? AppTheme.onNavy : AppTheme.textPrimary,
              ),
            ),
          );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: body,
        ),
      ),
    );
  }
}

/// Rounded frame around an image message; tapping opens the fullscreen view.
class _ImageBubble extends StatelessWidget {
  final String url;
  final BorderRadius radius;
  final VoidCallback? onTap;

  const _ImageBubble({
    required this.url,
    required this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Local (queued) files are not remote URLs — same split as before.
    final isRemote = url.startsWith('http');
    final Widget image = isRemote
        ? Image.network(
            url,
            width: 220,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const SkeletonBox(height: 170, width: 220, radius: 0),
            errorBuilder: (_, __, ___) => const _ImageFallback(),
          )
        : Image.file(
            File(url),
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _ImageFallback(),
          );

    return Material(
      color: AppTheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppTheme.line),
          ),
          child: ClipRRect(borderRadius: radius, child: image),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 150,
      alignment: Alignment.center,
      color: AppTheme.lineSoft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 32, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Text('تعذّر عرض الصورة',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// Fullscreen image preview (pinch to zoom, tap the app bar back to close).
class _ImageViewer extends StatelessWidget {
  final String url;

  const _ImageViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    final isRemote = url.startsWith('http');
    return Scaffold(
      backgroundColor: AppTheme.navyDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.navyDeep,
        foregroundColor: AppTheme.onNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.onNavy),
        title: const Text(
          'الصورة',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.onNavy,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: isRemote
              ? Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _ViewerFallback())
              : Image.file(File(url),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const _ViewerFallback()),
        ),
      ),
    );
  }
}

class _ViewerFallback extends StatelessWidget {
  const _ViewerFallback();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 44, color: AppTheme.onNavyMuted),
          const SizedBox(height: 12),
          Text('تعذّر عرض الصورة',
              textAlign: TextAlign.center,
              style: AppTheme.bodySoft.copyWith(color: AppTheme.onNavyMuted)),
        ],
      ),
    );
  }
}
