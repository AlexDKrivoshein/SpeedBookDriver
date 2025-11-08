import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chat_controller.dart';
import 'chat_sheet.dart';

/// Плавающая кнопка чата с бейджем непрочитанных (внутри FAB).
class ChatDock extends StatefulWidget {
  final int driveId;
  const ChatDock({super.key, required this.driveId});

  @override
  State<ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends State<ChatDock> {
  ChatController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ChatController(driveId: widget.driveId)..init();
  }

  @override
  void didUpdateWidget(covariant ChatDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driveId != widget.driveId) {
      _ctrl?.disposeAsync();
      _ctrl = ChatController(driveId: widget.driveId)..init();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ctrl?.disposeAsync();
    super.dispose();
  }

  Future<void> _openChat() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return ChangeNotifierProvider.value(
          value: ctrl,
          child: const Material(
            type: MaterialType.transparency,
            child: ChatSheet(),
          ),
        );
      },
    ).whenComplete(() {
      ctrl.markAllRead(); // синкнём прочитанное
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox.shrink();

    return ChangeNotifierProvider.value(
      value: ctrl,
      child: Consumer<ChatController>(
        builder: (_, c, __) {
          final unread = c.unreadCount;

          // Фиксированный контейнер под FAB (Material FAB по умолчанию 56x56)
          return SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.hardEdge, // ничего не вылазит наружу
              children: [
                // сам FAB по центру
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.center,
                    child: FloatingActionButton(
                      heroTag: 'chat_fab_${widget.driveId}',
                      tooltip: 'Chat',
                      onPressed: _openChat,
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),

                // бейдж — только если unread > 0, ВНУТРИ контура FAB
                if (unread > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _UnreadBadge(count: unread),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}
