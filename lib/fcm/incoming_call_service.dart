// lib/fcm/incoming_call_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


typedef CallScreenBuilder = Route<void> Function(BuildContext ctx, Map<String, dynamic> data);

class IncomingCallService {
  IncomingCallService._();
  static final _ln = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navKey;
  static CallScreenBuilder? _routeBuilder;

  static const int _notifId = 7001;
  static Map<String, dynamic>? _lastInviteData; // хранит payload для тапа/терминированного старта
  static bool _callScreenOpen = false;

  /// Регистрируй в main():
  /// FirebaseMessaging.onBackgroundMessage(IncomingCallService.backgroundHandler);
  @pragma('vm:entry-point')
  static Future<void> backgroundHandler(RemoteMessage msg) async {
    // В бекграунде/терминате UI открыть нельзя — показываем fullScreen уведомление
    final data = msg.data;
    final type = (data['type'] ?? '').toString().toLowerCase();
    if (type == 'call_invite') {
      _lastInviteData = Map<String, dynamic>.from(data);
      await _ensurePluginInitialized();
      await _showIncomingNotification(data);
    } else if (type == 'end_call') {
      await _ensurePluginInitialized();
      await _ln.cancel(_notifId);
      // Закрыть экран из бекграунда мы не можем, это выполнится при возобновлении приложения
    }
  }

  static Future<void> init(
      GlobalKey<NavigatorState> navKey,
      CallScreenBuilder routeBuilder,
      ) async {
    _navKey = navKey;
    _routeBuilder = routeBuilder;

    // Разрешения (Android 13+, iOS)
    await _requestPermissions();

    // Канал уведомлений
    const androidChannel = AndroidNotificationChannel(
      'sb_call',
      'Incoming Calls',
      description: 'Incoming call alerts',
      importance: Importance.max,
      playSound: true,
      showBadge: false,
      enableVibration: true,
    );

    await _ln.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTapNotification,
      onDidReceiveBackgroundNotificationResponse: _onTapNotification, // Android 14
    );

    await _ln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Фронтграунд входящие
    FirebaseMessaging.onMessage.listen(_onFcm);

    // Тап по push в бекграунде
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      // Если приложение возобновлено из тапа по системному пушу — откроем экран
      final data = msg.data;
      final type = (data['type'] ?? '').toString().toLowerCase();
      if (type == 'call_invite') {
        _openCallFromFcm(data.isNotEmpty ? data : (_lastInviteData ?? const {}));
      } else if (type == 'end_call') {
        closeCallUi();
      }
    });

    // Старт из терминированного состояния по пушу
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      final data = initial.data;
      final type = (data['type'] ?? '').toString().toLowerCase();
      if (type == 'call_invite') {
        _openCallFromFcm(data.isNotEmpty ? data : (_lastInviteData ?? const {}));
      }
    }
  }

  static Future<void> _onFcm(RemoteMessage msg) async {
    final data = msg.data;
    final type = (data['type'] ?? '').toString().toLowerCase();

    if (type == 'call_invite') {
      _lastInviteData = Map<String, dynamic>.from(data);
      await _showIncomingNotification(data);
      // Покажем только heads-up. Если нужно авто-открывать — убери previewOnly
      _bringToFrontAndMaybeOpen(data, previewOnly: false);
    } else if (type == 'end_call') {
      await _ln.cancel(_notifId);
      closeCallUi();
    }
  }

  static Future<void> _showIncomingNotification(Map<String, dynamic> data) async {
    final title = (data['title'] ?? 'Incoming call').toString();
    final body  = (data['body']  ?? 'Tap to answer').toString();

    final android = AndroidNotificationDetails(
      'sb_call',
      'Incoming Calls',
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      channelShowBadge: false,
      priority: Priority.max,
      importance: Importance.max,
      ongoing: true,
      autoCancel: true,
      timeoutAfter: int.tryParse('${data['ring_ms'] ?? '60000'}'),
    );

    final ios = const DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.critical,
      presentSound: true,
      presentAlert: true,
      presentBadge: false,
    );

    await _ln.show(
      _notifId,
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
      payload: 'call', // маркер
    );
  }

  static void _onTapNotification(NotificationResponse resp) {
    // Пользователь тапнул по локальному уведомлению
    final payload = _lastInviteData ?? const <String, dynamic>{'type': 'call_invite'};
    _openCallFromFcm(payload);
  }

  static void _bringToFrontAndMaybeOpen(Map<String, dynamic> data, {bool previewOnly = false}) {
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;
    if (previewOnly) return; // оставить только heads-up
    _openCallFromFcm(data);
  }

  static void _openCallFromFcm(Map<String, dynamic> data) {
    final nav = _navKey;
    final builder = _routeBuilder;
    if (nav == null || builder == null) return;

    final ctx = nav.currentContext;
    if (ctx == null) return;

    if (_callScreenOpen) {
      // уже открыто — не дублируем
      return;
    }

    // Закрываем возможные диалоги/оверлеи
    while (Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }

    _callScreenOpen = true;
    Navigator.of(ctx).push(builder(ctx, data)).whenComplete(() {
      _callScreenOpen = false;
      // При закрытии экрана уберём и уведомление, если висит
      _ln.cancel(_notifId);
    });
  }

  /// Вспомогательная функция: закрыть экран и уведомление программно.
  static Future<void> closeCallUi() async {
    await _ln.cancel(_notifId);
    final ctx = _navKey?.currentContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
    _callScreenOpen = false;
  }

  // ===== helpers =====

  static Future<void> _ensurePluginInitialized() async {
    // no-op: вызовы _ln.* требуют, чтобы initialize уже был сделан;
    // в backgroundHandler мы повторно не инициализируем, чтобы избежать конфликтов.
  }

  static Future<void> _requestPermissions() async {
    // Android 13+ runtime permission
    await _ln
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // iOS permissions
    await _ln
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true, badge: false);

    // FCM foreground presentation options (iOS/Android unified)
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );
  }
}
