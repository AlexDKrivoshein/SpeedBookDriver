import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Глобальный экземпляр уведомлений
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

/// Канал для входящих звонков (sbtaxi_icalls)
const AndroidNotificationChannel sbtaxiIncomingChannel = AndroidNotificationChannel(
  'sbtaxi_icalls', // ID канала
  'SpeedBook Incoming Calls',
  description: 'Ringtone + fullscreen notification for incoming SpeedBook calls',
  importance: Importance.max,
  playSound: true,
  // Файл должен лежать в android/app/src/main/res/raw/incoming_call.mp3
  sound: RawResourceAndroidNotificationSound('incoming_call'),
  enableVibration: true,
);

/// Инициализация уведомлений и создание каналов
Future<void> initNotifications() async {
  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initIOS = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
    requestBadgePermission: false,
  );

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initAndroid, iOS: initIOS),
    onDidReceiveNotificationResponse: (response) async {
      // При тапе на уведомление — можно открыть экран звонка.
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        // TODO: распарсить JSON и перейти на экран звонка
        // Например: Navigator.of(navigatorKey.currentContext!).push(...)
      }
    },
  );

  // Создаём канал для Android (если ещё не создан)
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(sbtaxiIncomingChannel);
}

/// Показ входящего звонка (heads-up + рингтон + fullscreen intent)
Future<void> showIncomingCallNotification({
  required String title,
  required String body,
  required String payloadJson,
}) async {
  await flutterLocalNotificationsPlugin.show(
    1001, // ID уведомления (для последующего cancel)
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        sbtaxiIncomingChannel.id,
        sbtaxiIncomingChannel.name,
        channelDescription: sbtaxiIncomingChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,          // висит до принятия/отклонения
        autoCancel: false,
        playSound: true,
        sound: sbtaxiIncomingChannel.sound,
        // При необходимости можно добавить дополнительные опции:
        // ticker: 'Incoming call',
        // enableLights: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        // Если используешь собственный звук на iOS, добавь его в bundle:
        // sound: 'incoming_call.caf',
      ),
    ),
    payload: payloadJson,
  );
}

/// Скрытие уведомления (при ответе/отклонении/таймауте)
Future<void> hideIncomingCallNotification() async {
  await flutterLocalNotificationsPlugin.cancel(1001);
}
