import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
void foregroundLocationTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

class _LocationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class ForegroundLocationService {
  ForegroundLocationService._();
  static final ForegroundLocationService I = ForegroundLocationService._();

  bool _initialized = false;
  bool _active = false;

  Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sbdriver_location',
        channelName: 'Location tracking',
        channelDescription:
            'Foreground service for sending driver location',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
  }

  Future<void> setTripActive(bool active) async {
    if (!Platform.isAndroid) return;
    if (_active == active) return;
    _active = active;

    if (_active) {
      await _start();
    } else {
      await _stop();
    }
  }

  Future<void> _start() async {
    await init();
    if (await FlutterForegroundTask.isRunningService) return;

    try {
      await ApiService.loadPreloginTranslations();
      final text = ApiService.getTranslation(
        'ForegroundLocationService',
        'foreground.location_during_trip',
      );
      await FlutterForegroundTask.startService(
        notificationTitle: 'SpeedBook Driver',
        notificationText: text,
        callback: foregroundLocationTaskStartCallback,
      );
    } catch (e) {
      debugPrint('[ForegroundLocation] start failed: $e');
    }
  }

  Future<void> _stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        debugPrint('[ForegroundLocation] stop failed: $e');
      }
    }
  }
}
