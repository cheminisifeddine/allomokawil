import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_scope.dart';
import '../../data/repository.dart';
import '../../models/chat.dart';

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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.otherName.isEmpty ? 'الرسائل' : widget.otherName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: TextButton(
                      onPressed: _bootstrap,
                      child: const Text('إعادة المحاولة')),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) => _Bubble(
                          message: _messages[i],
                          mine: _messages[i].senderId == _me,
                        ),
                      ),
                    ),
                    _pending.isNotEmpty
                        ? Material(
                            color: const Color(0xFFFFF3D6),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  const Icon(Icons.cloud_off, size: 16),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                      child: Text(
                                          'رسائل غير مرسلة — اضغط لإعادة المحاولة',
                                          style: TextStyle(fontSize: 12))),
                                  TextButton(
                                      onPressed: _sendText,
                                      child: const Text('إرسال')),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    _inputBar(),
                  ],
                ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _pickImage,
            ),
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة...',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _sendText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final align = mine ? Alignment.centerLeft : Alignment.centerRight;
    final color = mine ? const Color(0xFF16213E) : Colors.white;
    final fg = mine ? Colors.white : const Color(0xFF1C1C1E);
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: message.imageUrl != null
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: const Color(0xFFE8E7E3)),
        ),
        child: message.imageUrl != null && !message.imageUrl!.startsWith('http')
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(message.imageUrl!),
                    width: 220, fit: BoxFit.cover),
              )
            : message.imageUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(message.imageUrl!,
                        width: 220, fit: BoxFit.cover),
                  )
                : Text(message.content ?? '',
                    style: TextStyle(color: fg, fontSize: 15)),
      ),
    );
  }
}