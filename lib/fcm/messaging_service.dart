// lib/fcm/messaging_service.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api_service.dart';
import '../call/call_payload.dart';
import '../call/agora_controller.dart';
import '../call/permissions.dart';
import '../call/incoming_call_page.dart';            // единый экран звонка
import '../fcm/incoming_call_service.dart';         // стримы call_accepted / call_ended
import '../chat/chat_controller.dart';              // <<< добавили

/// Единая точка FCM + звонки.
/// - foreground: слушает onMessage / onMessageOpenedApp / getInitialMessage и управляет UI
/// - background: статический firebaseBackgroundHandler БЕЗ UI (никаких Navigator/BuildContext)
class MessagingService {
  MessagingService._();
  static final MessagingService _instance = MessagingService._();
  static MessagingService get I => _instance;

  bool _inited = false;

  static int? _activeCallId;      // выставляется ТОЛЬКО после Accept
  static bool _incomingOpen = false;

  // дедупликация пушей по messageId/стабильному ключу
  final Set<String> _handledMessageIds = <String>{};
  String? _initialMessageId; // чтобы не ловить дубль getInitialMessage + onMessageOpenedApp

  // дедупликация инвайтов по call_id на коротком окне (ретраи сети/FCM)
  static const Duration _inviteDedupWindow = Duration(seconds: 15);
  final Map<int, DateTime> _recentInvites = <int, DateTime>{};

  // === Навигатор/контекст (UI-изолят) ===
  GlobalKey<NavigatorState>? _navKey;
  void attachNavigator(GlobalKey<NavigatorState> navKey) => _navKey = navKey;

  BuildContext? get _ctx =>
      _navKey?.currentState?.overlay?.context ?? _navKey?.currentContext;

  void _showSnack(String msg) {
    final ctx = _ctx;
    if (ctx == null) return; // нет UI (бэкграунд/ранний старт) — пропускаем
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  // === Активный ChatController (один чат на всё приложение) ==================

  ChatController? _chatController;                           // <<<

  /// Привязать активный контроллер чата (вызывается из UI, когда чат монтируется).
  void attachChatController(ChatController controller) {     // <<<
    _chatController = controller;
  }

  /// Отвязать контроллер чата (когда виджет/контроллер уничтожается).
  void detachChatController(ChatController controller) {     // <<<
    if (identical(_chatController, controller)) {
      _chatController = null;
    }
  }

  // ======== Local Notifications (каналы + показ входящего) ========

  static final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _icallChannel = AndroidNotificationChannel(
    'sbtaxi_icalls', // ID канала
    'SpeedBook Incoming Calls',
    description: 'Ringtone + fullscreen notification for incoming SpeedBook calls',
    importance: Importance.max,
    playSound: true,
    // Файл: android/app/src/main/res/raw/incoming_call.mp3
    sound: RawResourceAndroidNotificationSound('incoming_call'),
    enableVibration: true,
  );


  static const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
    'sbtaxi_chats',                      // ID канала
    'SpeedBook Chat Messages',           // Название канала в настройках Android
    description: 'Notifications for chat messages',
    importance: Importance.defaultImportance,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('notification'), // твой обычный звук
    enableVibration: true,
  );

  static const int _icallNotifId = 1001;

  Future<void> _initLocalNotifications() async {
    const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: false,
    );

    await _ln.initialize(
      const InitializationSettings(android: initAndroid, iOS: initIOS),
      onDidReceiveNotificationResponse: (resp) async {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;

        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final type = (data['type'] ?? '').toString().toLowerCase();
          if (type == 'call_invite') {
            _handleCallInvite(data, source: 'local_notification_tap');
          } else if (type == 'call_accepted') {
            final callId = int.tryParse('${data['call_id']}');
            if (callId != null) {
              debugPrint('[Call] call accepted for id=$callId');
              IncomingCallService.markCallAccepted(callId);
            }
          } else if (type == 'call_end' || type == 'call_cancelled') {
            final callId = int.tryParse('${data['call_id']}');
            final reason = (data['reason'] ?? type).toString();
            if (callId != null) IncomingCallService.markCallEnded(callId, reason: reason);
          }
        } catch (_) {/* ignore */}
      },
    );

    await _ln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_icallChannel);

    await _ln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_chatChannel);
  }

  Future<void> showIncomingCallNotification({
    required String title,
    required String body,
    required String payloadJson,
  }) async {
    await _ln.show(
      _icallNotifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _icallChannel.id,
          _icallChannel.name,
          channelDescription: _icallChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          ongoing: true,     // пока не ответили/не отклонили
          autoCancel: false,
          playSound: true,
          sound: _icallChannel.sound,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: payloadJson,
    );
  }

  Future<void> hideIncomingCallNotification() async {
    await _ln.cancel(_icallNotifId);
  }

  // ======== Background handler (headless изолят) ========

  /// ВАЖНО: вызывать из top-level handler (main.dart), после Firebase.initializeApp().
  @pragma('vm:entry-point')
  static Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
    try {
      final data = message.data;
      final type = (data['type'] ?? '').toString().trim().toLowerCase();
      debugPrint('[FCM][bg] type=$type data=$data');

      // В фоне — лёгкая логика (никакого UI)
      if (type == 'call_end' || type == 'call_cancelled') {
        final callId = int.tryParse('${data['call_id'] ?? ''}');
        final reason = (data['reason'] ?? type).toString();
        if (callId != null) {
          try { await ApiService.callAndDecode('ack_call_end', {'call_id': callId}); } catch (_) {}
          IncomingCallService.markCallEnded(callId, reason: reason);
        }
      }
    } catch (e, st) {
      debugPrint('[FCM][bg] error: $e\n$st');
    }
  }

  // ======== Инициализация (foreground) ========

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    await _ensureNotificationPermission();
    await _initLocalNotifications();

    // Токен → на сервер
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _sendToken(token);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((t) => _sendToken(t));

    // Foreground сообщения
    FirebaseMessaging.onMessage.listen((m) => _handleFcm(m, source: 'onMessage'));

    // Клик по пушу (из шторки/бэкграунда)
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      if (_initialMessageId != null && m.messageId == _initialMessageId) {
        debugPrint('[FCM] skip onMessageOpenedApp (already handled as initial)');
        return;
      }
      _handleFcm(m, source: 'onMessageOpenedApp');
    });

    // Cold start (приложение было убито)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _initialMessageId = initial.messageId;
      _handleFcm(initial, source: 'getInitialMessage');
    }
  }

  Future<void> _ensureNotificationPermission() async {
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
        announcement: false, carPlay: false, criticalAlert: false, provisional: false,
      );
      debugPrint('[FCM] iOS permission: ${settings.authorizationStatus}');
      return;
    }
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      // await ApiService.setPushToken(token);
      debugPrint('[FCM] token sent to server');
    } catch (e) {
      debugPrint('[FCM] send token failed: $e');
    }
  }

  // === Mic permission helper ===
  Future<bool> _ensurePermissions() async {
    return await CallPermissions.ensure();
  }

  // ======== Разбор входящих ========

  void _handleFcm(RemoteMessage m, {required String source}) {
    // дедуп по messageId/стабильному ключу
    final id = m.messageId ?? _stableIdFromData(m.data);
    if (_handledMessageIds.contains(id)) {
      debugPrint('[FCM] $source duplicate message, skip (id=$id)');
      return;
    }
    _handledMessageIds.add(id);

    final data = m.data;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    debugPrint('[FCM] $source type=$type data=$data');


    switch (type) {
      case 'drive_offer': // 🔹 Офферы обрабатываются в main.dart / OfferNotifications
        debugPrint('[FCM] $source drive_offer → handled in main/OfferNotifications, skip in MessagingService');
        return;

      case 'call_invite':
        _handleCallInvite(data, source: source);
        return;

      case 'call_end':
      case 'call_cancelled':
        _handleCallEnded(data, source: source);
        return;

      case 'call_accepted':
        final callId = int.tryParse('${data['call_id']}');
        if (callId != null) {
          IncomingCallService.markCallAccepted(callId);
        }
        return;

      case 'chat_message':
        _handleChatMessage(data, source: source);
        return;

      default:
        _handleOtherTypes(data, source: source);
        return;
    }
  }

  void _handleOtherTypes(Map<String, dynamic> data, {required String source}) {
    debugPrint('[FCM] $source other: $data');
  }

  void _handleChatMessage(Map<String, dynamic> data, {required String source}) {
    final chatId  = int.tryParse('${data['chat_id'] ?? ''}');
    final driveId = int.tryParse('${data['drive_id'] ?? ''}');

    debugPrint('[FCM] $source chat_message: chat_id=$chatId drive_id=$driveId data=$data');

    // 1) Если есть активный ChatController для этого drive_id — сразу подтягиваем новые сообщения
    final controller = _chatController;
    if (controller != null && driveId != null &&
        controller.driveId == driveId) {
      debugPrint('[FCM] $source chat_message → ChatController.pullNow()');
      controller.pullNow();
    }

    final nav = _navKey?.currentState;
    if (nav == null || driveId == null) {
      debugPrint('[FCM] $source chat_message: no navigator or driveId, skip navigation');
      return;
    }

    // 2) Навигацию делаем ТОЛЬКО для случаев, когда приложение открывают по пушу,
    //    а не когда оно уже на экране (onMessage).
    if (source == 'onMessageOpenedApp' || source == 'getInitialMessage') {
      debugPrint('[FCM] $source chat_message → navigate to /drive (open_chat=true)');
      nav.pushNamed(
        '/drive',
        arguments: {
          'drive_id': driveId,
          'open_chat': true,
        },
      );
    }
  }

  // ======== Звонки ========

  /// Показать входящее (foreground/cold-start).
  Future<void> _handleCallInvite(Map<String, dynamic> data, {required String source}) async {
    try {
      // 0) не просрочен ли инвайт?
      final expiresAtStr = (data['expires_at'] ?? '').toString().trim();
      if (expiresAtStr.isNotEmpty) {
        final expiresAt = _parseTimestamptz(expiresAtStr);
        if (DateTime.now().toUtc().isAfter(expiresAt)) {
          debugPrint('[FCM] call_invite expired: now >= $expiresAt');
          return;
        }
      }

      // 1) параметры
      final appId   = (data['agora_app_id'] ?? data['appId'] ?? '').toString();
      final token   = (data['agora_token'] ?? data['token'] ?? '').toString();
      final channel = (data['channel'] ?? '').toString();
      final uid     = int.tryParse((data['agora_uid'] ?? data['uid'] ?? '0').toString()) ?? 0;
      final callId  = int.tryParse((data['call_id'] ?? '').toString());
      final ringMs  = int.tryParse((data['ring_ms'] ?? '30000').toString()) ?? 30000;

      if (appId.isEmpty || token.isEmpty || channel.isEmpty || callId == null) {
        debugPrint('[FCM] call_invite payload incomplete');
        return;
      }

      // 2) антидубли UI: уже открыто окно входящего?
      if (_incomingOpen) {
        debugPrint('[FCM] incoming UI already open, ignore invite callId=$callId');
        return;
      }

      // 3) краткосрочная дедупликация инвайтов по call_id (ретраи FCM/сети)
      final now = DateTime.now();
      final last = _recentInvites[callId];
      if (last != null && now.difference(last) < _inviteDedupWindow) {
        debugPrint('[FCM] invite dedup: callId=$callId (within $_inviteDedupWindow)');
        return;
      }
      _recentInvites[callId] = now;

      final nav = _navKey?.currentState;

      // Фоллбек: если навигатора пока нет — покажем локальное heads-up (foreground)
      if (nav == null) {
        await showIncomingCallNotification(
          title: 'Incoming SpeedBook call',
          body: 'Tap to answer',
          payloadJson: jsonEncode(data),
        );
        debugPrint('[FCM] call_invite → local heads-up (no navigator yet)');
        return;
      }

      // ✅ foreground: попробуем запросить микрофон ДО показа экрана
      final micOk = await CallPermissions.ensure();

      if (!micOk) {
        _showSnack('Microphone permission is required to answer');
        // экран всё равно покажем: вторую проверку сделаем на кнопке Accept
      }

      _incomingOpen = true;
      // ВАЖНО: _activeCallId НЕ трогаем до Accept!

      final payload = CallPayload(
        callId: callId,
        channel: channel,
        appId: appId,
        token: token,
        uid: uid,
        initiatorName: (data['initiator_name'] ?? data['caller_name'] ?? '').toString(),
        initiatorAvatar: (data['initiator_avatar'] ?? data['caller_avatar'] ?? '').toString(),
        ringMs: ringMs,
        expiresAtIso: expiresAtStr,
      );

      bool accepted = false;

      nav.push(
        IncomingCallPage.route(
          payload: payload,
          mode: CallUIMode.incoming,

          // ✅ дубль-проверка на кнопке Accept
          onAccept: (p) async {
            final ok = await CallPermissions.ensure();
            if (!ok) {
              _showSnack('Microphone permission denied');
              return; // не входим в канал без разрешения
            }

            try {
              await ApiService.callAndDecode('answer_call', {'call_id': p.callId});
            } catch (_) {}

            _incomingOpen = false;
            _activeCallId = p.callId;
            accepted = true;

            await hideIncomingCallNotification();
            try {
              debugPrint('[Agora] join start: channel=${payload.channel} uid=${payload.uid}');
              await AgoraController.instance.join(
                appId: p.appId,
                token: p.token,
                channel: p.channel,
                uid: p.uid,
                callId: p.callId,
              );
              debugPrint('[Agora] join awaited OK');
            } catch (e, st) {
              debugPrint('[Agora] join error: $e\n$st');
              _showSnack('Call failed to start: $e');
            }

            // Заменяем входящий на "идёт звонок"
            final ctx = _ctx;
            if (ctx != null) {
              Navigator.of(ctx).pushReplacement(
                IncomingCallPage.route(
                  payload: p,
                  mode: CallUIMode.inProgress,
                  onHangup: (pp) async {
                    try {
                      await ApiService.callAndDecode('end_call', {
                        'call_id': pp.callId,
                        'reason': 'hangup',
                      });
                    } catch (_) {} finally {
                      await AgoraController.instance.leave();
                      if (Navigator.of(ctx).canPop()) {
                        Navigator.of(ctx).pop();
                      }
                    }
                  },
                ),
              );
            }
          },

          onDecline: (p) async {
            try {
              await ApiService.callAndDecode('end_call', {
                'call_id': p.callId,
                'reason': 'declined',
              });
            } catch (_) {}

            final ctx = _ctx;
            if (ctx != null) {
              Navigator.of(ctx).maybePop();
            }

            _incomingOpen = false;
            _activeCallId = null;

            await hideIncomingCallNotification();
          },
        ),
      ).then((_) {
        if (!accepted) {
          _incomingOpen = false;
          _activeCallId = null;
        }
      });

      debugPrint('[FCM] call_invite → IncomingCallPage (source=$source)');
    } catch (e, st) {
      debugPrint('[FCM] handle call_invite failed: $e\n$st');
      final callId = int.tryParse('${data['call_id'] ?? ''}');
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

      // На всякий — уберём локалку
      await hideIncomingCallNotification();
    }
  }

  /// Закрыть экраны звонка при `call_end` / `call_cancelled`.
  void _handleCallEnded(Map<String, dynamic> data, {required String source}) {
    final ctx = _ctx;
    final endedId = int.tryParse('${data['call_id'] ?? ''}');
    final reason  = (data['reason'] ?? data['type'] ?? 'remote_hangup').toString();

    // 1) Всегда уведомляем подписчиков (UI и контроллеры)
    if (endedId != null) {
      IncomingCallService.markCallEnded(endedId, reason: reason);
    }

    // 2) Если прилетел end для другого звонка — UI не трогаем
    if (endedId != null && _activeCallId != null && endedId != _activeCallId) {
      debugPrint('[FCM] $source call_end for other call (ended=$endedId, active=$_activeCallId)');
      return;
    }

    // 3) Если контекста нет — просто сбрасываем состояния
    if (ctx == null) {
      debugPrint('[FCM] $source call_end/cancelled: no context');
      _incomingOpen = false;
      _activeCallId = null;
      hideIncomingCallNotification();
      return;
    }

    // 4) Закрываем возможные экраны звонков (по именованным маршрутам!)
    Navigator.of(ctx).popUntil((route) {
      final name = route.settings.name;
      final isCall = name == 'IncomingCallPage' || name == 'CallInProgressScreen';
      return !isCall; // остановиться на первом не-call экране
    });

    _incomingOpen = false;
    _activeCallId = null;
    hideIncomingCallNotification();
    debugPrint('[FCM] $source call ended → closed call screens (reason=$reason)');
  }

  // ======== Utils ========

  DateTime _parseTimestamptz(String s) {
    final dt = DateTime.parse(s);
    return dt.isUtc ? dt : dt.toUtc();
  }

  String _stableIdFromData(Map<String, dynamic> data) {
    // стабильный ключ на случай отсутствия messageId
    final t = (data['type'] ?? '').toString();
    final cid = (data['call_id'] ?? '').toString();
    final exp = (data['expires_at'] ?? '').toString();
    return 't:$t|c:$cid|e:$exp';
  }
}
