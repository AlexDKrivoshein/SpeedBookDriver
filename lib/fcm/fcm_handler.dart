import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../notifications/notification_service.dart';
import 'package:flutter/material.dart';

/// Инициализация FCM и локальных обработчиков
Future<void> initFCM(BuildContext context) async {
  // Запрашиваем разрешения (особенно важно для iOS и Android 13+)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    sound: true,
    badge: false,
    provisional: false,
  );

  // Получаем FCM-токен (можно отправить на сервер)
  final fcmToken = await FirebaseMessaging.instance.getToken();
  debugPrint('🔥 FCM Token: $fcmToken');

  // Обработка сообщения, когда приложение на переднем плане
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    await _handleMessage(context, message, fromBackground: false);
  });

  // Когда юзер тапает по уведомлению (приложение в фоне или завершено)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    await _handleMessage(context, message, fromBackground: true);
  });

  // Для background handler (обязательно вне main()!)
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
}

/// Обработка push-сообщения
Future<void> _handleMessage(BuildContext context, RemoteMessage message,
    {bool fromBackground = false}) async {
  final data = message.data;
  final type = data['type'] ?? '';

  switch (type) {
  // === ВХОДЯЩИЙ ЗВОНОК ===
    case 'call_invite':
      final driveId = int.tryParse(data['drive_id'] ?? '');
      final callId = int.tryParse(data['call_id'] ?? '');
      final callerName = data['caller_name'] ?? 'Driver is calling...';
      final body = data['body'] ?? 'Tap to answer';

      // Если приложение на переднем плане — покажем heads-up и звук
      await showIncomingCallNotification(
        title: callerName,
        body: body,
        payloadJson: jsonEncode({
          'drive_id': driveId,
          'call_id': callId,
          'caller_name': callerName,
          'type': 'call_invite',
        }),
      );

      // Можно добавить автооткрытие UI звонка, если хочешь
      if (!fromBackground && context.mounted) {
        // Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(...)));
      }
      break;

  // === ЗАКОНЧИЛСЯ ЗВОНОК / ОТКЛОНЁН ===
    case 'call_end':
      await hideIncomingCallNotification();
      break;

  // === ДРУГИЕ PUSH-ТИПЫ ===
    default:
    // Показываем обычное уведомление (sbtaxi_channel)
      final title = data['title'] ?? 'SpeedBook';
      final bodyText = data['body'] ?? '';
      await flutterLocalNotificationsPlugin.show(
        9999,
        title,
        bodyText,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'sbtaxi_channel',
            'SpeedBook Notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
  }
}

/// Обработчик фоновых сообщений (вне контекста Flutter)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // FCM требует @pragma для корректного вызова при закрытом приложении
  await showIncomingCallNotification(
    title: message.data['caller_name'] ?? 'Incoming call',
    body: message.data['body'] ?? 'Driver is calling...',
    payloadJson: jsonEncode(message.data),
  );
}
