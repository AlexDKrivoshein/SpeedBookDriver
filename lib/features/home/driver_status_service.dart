// lib/features/home/driver_status_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../driver_api.dart';
import '../../api_service.dart' show ApiService, AuthException;

typedef DriveIdListener = void Function(int? driveId);

class DriverStatusService extends ChangeNotifier {
  DriverStatusService._();
  static final DriverStatusService I = DriverStatusService._();

  Timer? _t;
  bool _running = false;
  bool _disposed = false;

  // Базовый интервал и мягкий бэкофф при ошибках (кроме AuthException)
  Duration _baseInterval = const Duration(seconds: 3);
  Duration _currentInterval = const Duration(seconds: 3);
  static const Duration _maxInterval = Duration(seconds: 20);

  int? _lastDriveId;
  int? get lastDriveId => _lastDriveId;

  final _listeners = <DriveIdListener>{};

  void addListenerFn(DriveIdListener f) => _listeners.add(f);
  void removeListenerFn(DriveIdListener f) => _listeners.remove(f);

  void start({Duration interval = const Duration(seconds: 3)}) {
    if (_running || _disposed) return;

    _baseInterval = interval;
    _currentInterval = interval;

    // Нет авторизации — не стартуем таймер (избегаем spam’а ошибками)
    if (!(ApiService.isAuthenticated)) {
      debugPrint('[DriverStatusService] start skipped: not authenticated');
      _running = false;
      return;
    }

    _running = true;
    debugPrint('[DriverStatusService] start; interval=${_baseInterval.inSeconds}s');

    // Первый тик сразу
    _tick();

    // Периодический таймер
    _t = Timer.periodic(_currentInterval, _onTick);
  }

  void stop() {
    _t?.cancel();
    _t = null;
    _running = false;
    _currentInterval = _baseInterval;
    debugPrint('[DriverStatusService] stop');
  }

  /// Рекомендуется вызывать из вашего обработчика authStateChanges()
  /// при логине — start(), при логауте — stop().
  void onAuthStateMaybeChanged() {
    if (_disposed) return;
    if (ApiService.isAuthenticated) {
      if (!_running) start(interval: _baseInterval);
    } else {
      stop();
    }
  }

  Future<void> forceRefresh() => _tick();

  void _onTick(Timer _) {
    // Если авторизация пропала между тиками — гасим сервис.
    if (!ApiService.isAuthenticated) {
      debugPrint('[DriverStatusService] tick skipped: not authenticated → stopping');
      stop();
      return;
    }
    _tick();
  }

  Future<void> _tick() async {
    if (_disposed) return;

    try {
      final id = await DriverApi.getCurrentDriveId();

      // Успех — сбрасываем бэкофф, если он увеличивался
      if (_currentInterval != _baseInterval && _t != null) {
        _currentInterval = _baseInterval;
        _t!.cancel();
        _t = Timer.periodic(_currentInterval, _onTick);
      }

      if (id != _lastDriveId) {
        _lastDriveId = id;
        for (final f in _listeners) {
          // защищаем от ConcurrentModificationError
          try { f(id); } catch (_) {}
        }
        notifyListeners();
      }
      // debugPrint('[DriverStatusService] tick -> $id'); // для редкой диагностики

    } on AuthException catch (e) {
      // Токен отсутствует/протух. Прекращаем поллинг до повторной авторизации.
      debugPrint('[DriverStatusService] auth error: ${e.message ?? 'auth lost'} → stop');
      stop();

    } catch (e, st) {
      // Любая иная ошибка — мягкий бэкофф, чтобы не молотить API.
      debugPrint('[DriverStatusService] tick error: $e\n$st');

      if (_t != null && _currentInterval < _maxInterval) {
        _currentInterval = Duration(
          seconds: (_currentInterval.inSeconds * 2).clamp(
            _baseInterval.inSeconds,
            _maxInterval.inSeconds,
          ),
        );
        _t!.cancel();
        _t = Timer.periodic(_currentInterval, _onTick);
        debugPrint('[DriverStatusService] backoff → ${_currentInterval.inSeconds}s');
      }
      // На следующем тике попробуем снова.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    _listeners.clear();
    super.dispose();
  }
}
