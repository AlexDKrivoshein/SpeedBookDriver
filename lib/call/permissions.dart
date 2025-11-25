// permissions.dart (или рядом)
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CallPermissions {
  static Future<bool> ensure() async {
    // Микрофон — обязателен
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    // Нотификации — чтобы показать входящий call на Android 13+ (опц.)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Андроид 12+ может требовать BT CONNECT, если Agora пытается рулить аудиомаршрутом через BT
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.version.sdkInt >= 31) {
        final bt = await Permission.bluetoothConnect.request();
        // не блокируем звонок, но логируем
        if (!bt.isGranted) {
          // ignore: avoid_print
          print('[Perm] BLUETOOTH_CONNECT not granted (will continue)');
        }
      }
    }
    return true;
  }
}