// lib/chat/chat_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chat_controller.dart';
import 'chat_message.dart';
import '../translations.dart';
import '../fcm/messaging_service.dart';   // <<< добавлено

class ChatSheet extends StatefulWidget {
  const ChatSheet({super.key});
  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _inited = false;

  ChatController? _attachedChat;   // <<< чтобы корректно detech в dispose

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_inited) {
      _inited = true;

      // 1) Берём ChatController из Provider
      final chat = context.read<ChatController>();

      // 2) Запоминаем и прикрепляем его к MessagingService
      _attachedChat = chat;
      MessagingService.I.attachChatController(chat);   // <<< важно

      // 3) Делаем init() в post-frame, чтобы не вызвать notify во время build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        chat.init();
      });
    }
  }

  @override
  void dispose() {
    // аккуратно отвязываем контроллер, если мы его прикрепляли
    if (_attachedChat != null) {
      MessagingService.I.detachChatController(_attachedChat!);
      _attachedChat = null;
    }

    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();

    // автоскролл вниз
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 12,
          right: 12,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // header
            Row(
              children: [
                Text(
                  t(context, 'chat.with'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.person, size: 18),
                const Spacer(),
                IconButton(
                  tooltip: t(context, 'chat.refresh'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await chat.loadInitial();
                    _jumpToBottom();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // messages
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                itemCount: chat.items.length,
                itemBuilder: (context, index) {
                  final ChatMessage msg =
                  chat.items[chat.items.length - 1 - index];
                  return _Bubble(msg: msg, isMine: msg.isMine);
                },
              ),
            ),
            const SizedBox(height: 8),

            // input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: t(context, 'chat.placeholder'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (v) async => _send(chat, v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async => _send(chat, _controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(ChatController chat, String v) async {
    final text = v.trim();
    if (text.isEmpty) return;
    await chat.send(text);
    _controller.clear();
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMine;
  const _Bubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? Colors.yellow.shade200 : Colors.grey.shade200;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isMine
          ? const Radius.circular(16)
          : const Radius.circular(4),
      bottomRight: isMine
          ? const Radius.circular(4)
          : const Radius.circular(16),
    );

    final String? senderLabel = msg.isMine
        ? null
        : (msg.fromName ?? (msg.from != null ? 'ID ${msg.from}' : null));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (senderLabel != null) ...[
            Text(
              senderLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: bg, borderRadius: radius),
            child: Text(msg.text),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTime(msg.ts),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime ts) {
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
