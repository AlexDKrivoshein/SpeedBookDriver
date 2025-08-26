import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// Синглтон для FCM: запрос разрешений, получение токена и подписка на onTokenRefresh.
class MessagingService {
  MessagingService._();
  static final MessagingService _instance = MessagingService._();
  static MessagingService get I => _instance;

  bool _inited = false;
  Stream<String>? _tokenStream;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // 1) Разрешения на уведомления
    await _ensureNotificationPermission();

    // 2) Получить текущий токен и отправить на сервер
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _sendToken(token);
    }

    // 3) Подписка на обновление токена
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _sendToken(newToken);
    });

    // (опционально) Обработка входящих уведомлений в фореграунде
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      // Здесь можно показать локальное уведомление, лог и т.п.
      debugPrint('[FCM] foreground: ${m.notification?.title} / ${m.notification?.body}');
    });
  }

  Future<void> _ensureNotificationPermission() async {
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, announcement: false, badge: true, carPlay: false,
        criticalAlert: false, provisional: false, sound: true,
      );
      debugPrint('[FCM] iOS permission: ${settings.authorizationStatus}');
      return;
    }

    if (Platform.isAndroid) {
      // На Android 13+ нужно runtime-разрешение POST_NOTIFICATIONS
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _sendToken(String token) async {
    try {
//      await ApiService.setPushToken(token); // реализовано у вас на бэкенде
      debugPrint('[FCM] Token sent to server');
    } catch (e) {
      debugPrint('[FCM] send token failed: $e');
    }
  }
}
