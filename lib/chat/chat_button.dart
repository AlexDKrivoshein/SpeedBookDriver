// lib/chat/chat_button.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_service.dart';
import 'chat_controller.dart';
import 'chat_sheet.dart';

class ChatButton extends StatelessWidget {
  final ChatController controller;
  const ChatButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatController>.value(
      value: controller,
      child: Consumer<ChatController>(
        builder: (context, c, _) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) => ChangeNotifierProvider<ChatController>.value(
                      value: c,
                      // Ваш ChatSheet без явного параметра controller
                      child: const ChatSheet(),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(ApiService.getTranslationForWidget(context, 'chat.title')),
              ),

              // Бейдж непрочитанных
              if (c.unreadCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26)],
                    ),
                    child: Text(
                      '${c.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
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
