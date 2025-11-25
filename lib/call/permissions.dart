// call/permissions.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CallPermissions {
  /// Проверяет и запрашивает:
  /// - микрофон
  /// - уведомления (Android 13+)
  /// - bluetoothConnect (Android 12+)
  static Future<bool> ensure() async {
    // === 1. Микрофон ===
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      return false;
    }

    // === 2. Уведомления (Android 13+) ===
    // Даже если юзер отказал — продолжаем работу звонка,
    // но heads-up может не появиться.
    final notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      await Permission.notification.request();
    }

    // === 3. Bluetooth (для работы аудиомаршрутизации на API 31+) ===
    final info = await DeviceInfoPlugin().androidInfo;
    if (info.version.sdkInt >= 31) {
      final bt = await Permission.bluetoothConnect.request();
      if (!bt.isGranted) {
        // всё еще продолжаем — система сама выберет маршрут.
        // Но можно залогировать для отладки.
      }
    }

    return true;
  }
}
