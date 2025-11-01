// lib/chat/chat_dock.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Импорты вашего чата (оставь как у тебя): ChatController, ChatSheet
import 'index.dart' show ChatController, ChatSheet;

class ChatDock extends StatefulWidget {
  const ChatDock({
    super.key,
    required this.driveId,
    this.tooltip = 'Chat',
    this.icon = Icons.chat_bubble_outline,
    this.badgeColor = Colors.red,
    this.badgeTextColor = Colors.white,
  });

  final int driveId;
  final String tooltip;
  final IconData icon;
  final Color badgeColor;
  final Color badgeTextColor;

  @override
  State<ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends State<ChatDock> {
  late final ChatController _cc = ChatController(driveId: widget.driveId);

  @override
  void dispose() {
    _cc.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeNotifierProvider<ChatController>.value(
        value: _cc,
        child: DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          initialChildSize: 0.85,
          builder: (_, scrollController) {
            return Material(
              elevation: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              // ВАЖНО: ваш ChatSheet без параметров контроллера
              child: ChatSheet(),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatController>.value(
      value: _cc,
      child: Consumer<ChatController>(
        builder: (context, cc, _) {
          // Если у вас нет unreadCount — можно показать просто FAB без бейджа
          final int unread =
          (cc as dynamic?)?.unreadCount is int ? (cc as dynamic).unreadCount as int : 0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: widget.tooltip,
                child: FloatingActionButton(
                  heroTag: 'chat_dock_fab',
                  onPressed: _openChat,
                  child: Icon(widget.icon),
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.badgeColor,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: widget.badgeTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
