import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api_service.dart'; // используем ApiService.callAndDecode(...)
import 'package:speedbookdriver/call/call_payload.dart';
import 'package:speedbookdriver/call/incoming_call_page.dart';
import 'package:speedbookdriver/call/call_in_progress_screen.dart';
import 'package:speedbookdriver/call/agora_controller.dart';

/// Синглтон для FCM: запрос разрешений, токен, onTokenRefresh + обработка call_invite.
class MessagingService {
  MessagingService._();
  static final MessagingService _instance = MessagingService._();
  static MessagingService get I => _instance;

  bool _inited = false;
  static int? _activeCallId;
  static bool _incomingOpen = false;

  GlobalKey<NavigatorState>? _navKey;

  /// Привязать navigatorKey.
  void attachNavigator(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;
  }

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

    // 4) Обработка входящих (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      debugPrint('[FCM] foreground: ${m.notification?.title} / ${m.notification?.body}');
      _handleFcm(m, source: 'foreground');
    });

    // 5) Пользователь ткнул по пушу из шторки (приложение в фоне)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
      _handleFcm(m, source: 'openedFromTray');
    });

    // 6) Приложение было убито и открыто по пушу
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleFcm(initial, source: 'initialMessage');
    }
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
      // Android 13+: runtime-разрешение POST_NOTIFICATIONS
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      // подставь свой вызов на бэкенд
      // await ApiService.setPushToken(token);
      debugPrint('[FCM] Token sent to server');
    } catch (e) {
      debugPrint('[FCM] send token failed: $e');
    }
  }

  // ------------ FCM handling ------------

  void _handleFcm(RemoteMessage m, {required String source}) {
    final data = m.data;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();

    if (type == 'call_invite') {
      _handleCallInvite(data, source: source);
      return;
    }

    // прочие типы — пока лог, твоя текущая логика не теряется
    debugPrint('[FCM] $source data: $data');
  }

  /// Пришёл инвайт на звонок. Если не просрочен — показываем IncomingCallPage (ручной приём).
  Future<void> _handleCallInvite(Map<String, dynamic> data, {required String source}) async {
    try {
      // 1) проверим экспирацию. Сервер шлёт expires_at как timestamptz (ISO8601).
      final expiresAtStr = (data['expires_at'] ?? '').toString().trim();
      if (expiresAtStr.isNotEmpty) {
        final expiresAt = _parseTimestamptz(expiresAtStr); // toUtc внутри
        if (DateTime.now().toUtc().isAfter(expiresAt)) {
          debugPrint('[FCM] call_invite expired: now >= $expiresAt');
          return;
        }
      }

      // 2) вытащим параметры для звонка
      final appId   = (data['agora_app_id'] ?? '').toString();
      final token   = (data['agora_token'] ?? '').toString();
      final channel = (data['channel'] ?? '').toString();
      final uid     = int.tryParse((data['agora_uid'] ?? '0').toString()) ?? 0;
      final callId  = int.tryParse((data['call_id'] ?? '').toString());
      final ringMs  = int.tryParse((data['ring_ms'] ?? '30000').toString()) ?? 30000;

      if (appId.isEmpty || token.isEmpty || channel.isEmpty || callId == null) {
        debugPrint('[FCM] call_invite payload is incomplete: $data');
        return;
      }

      // 3) антидубли
      if (_activeCallId == callId || _incomingOpen) {
        debugPrint('[FCM] duplicate incoming UI ignored for callId=$callId');
        return;
      }
      _activeCallId = callId;
      _incomingOpen = true;

      final nav = _navKey?.currentState;
      if (nav == null) {
        debugPrint('[FCM] No navigator attached; call invite ignored');
        _incomingOpen = false;
        _activeCallId = null;
        return;
      }

      // 4) соберём payload
      final payload = CallPayload(
        callId: callId,
        channel: channel,
        appId: appId,
        token: token,
        uid: uid,
        initiatorName: (data['initiator_name'] ?? '').toString(),
        initiatorAvatar: (data['initiator_avatar'] ?? '').toString(),
        ringMs: ringMs,
        expiresAtIso: expiresAtStr,
      );

      // 5) показать экран входящего
      nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => IncomingCallPage(
          payload: payload,
          onAccept: (p) async {
            // сообщаем бэку, что приняли
            await ApiService.callAndDecode('answer_call', {'call_id': p.callId});

            // входим в канал
            await AgoraController.instance.join(
              appId: p.appId,
              token: p.token,
              channel: p.channel,
              uid: p.uid,
            );

            // открываем экран разговора
            if (ctx.mounted) {
              Navigator.of(ctx).pushReplacement(CallInProgressScreen.route(p));
            }
          },
          onDecline: (p) async {
            // сообщаем бэку об отказе
            await ApiService.callAndDecode('end_call', {
              'call_id': p.callId,
              'reason': 'declined',
            });
            if (ctx.mounted) {
              Navigator.of(ctx).maybePop();
            }
          },
        ),
      )).then((_) {
        _incomingOpen = false;
        _activeCallId = null;
      });

      debugPrint('[FCM] call_invite → IncomingCallPage (source=$source)');
    } catch (e) {
      debugPrint('[FCM] handle call_invite failed: $e');
      final callId = int.tryParse((data['call_id'] ?? '').toString());
      if (callId != null) {
        try {
          await ApiService.callAndDecode('end_call', {
            'call_id': callId,
            'reason': 'fail_show_incoming',
          });
        } catch (_) {}
      }
      _incomingOpen = false;
      _activeCallId = null;
    }
  }

  /// Парсер timestamptz (ISO8601 с таймзоной или без). Возвращает UTC.
  DateTime _parseTimestamptz(String s) {
    final dt = DateTime.parse(s); // понимает ISO 8601
    return dt.isUtc ? dt : dt.toUtc();
    // при необходимости можно сдвигать на локаль
  }
}
