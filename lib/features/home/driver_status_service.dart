// lib/features/home/driver_status_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../driver_api.dart';

typedef DriveIdListener = void Function(int? driveId);

class DriverStatusService extends ChangeNotifier {
  DriverStatusService._();
  static final DriverStatusService I = DriverStatusService._();

  Timer? _t;
  bool _running = false;

  int? _lastDriveId;
  int? get lastDriveId => _lastDriveId;

  final _listeners = <DriveIdListener>{};

  void addListenerFn(DriveIdListener f) => _listeners.add(f);
  void removeListenerFn(DriveIdListener f) => _listeners.remove(f);

  void start({Duration interval = const Duration(seconds: 3)}) {
    if (_running) return;
    _running = true;
    _tick(); // первый запрос сразу
    _t = Timer.periodic(interval, (_) => _tick());
    debugPrint('[DriverStatusService] start; interval=${interval.inSeconds}s');
  }

  void stop() {
    _t?.cancel();
    _t = null;
    _running = false;
    debugPrint('[DriverStatusService] stop');
  }

  Future<void> forceRefresh() => _tick();

  Future<void> _tick() async {
    try {
      final id = await DriverApi.getCurrentDriveId();
      if (id != _lastDriveId) {
        _lastDriveId = id;
        for (final f in _listeners) {
          f(id);
        }
        notifyListeners();
      }
      // для диагностики можно логировать редко:
      // debugPrint('[DriverStatusService] tick -> $id');
    } catch (e, st) {
      debugPrint('[DriverStatusService] tick error: $e\n$st');
      // ошибок не боимся, на следующем тике попробуем снова
    }
  }
}
