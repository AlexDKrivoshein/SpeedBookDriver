// lib/location_service.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

/// Отслеживание геопозиции через поток с фильтрами:
/// - Пропускаем отправку, если точка почти не изменилась (по расстоянию)
/// - Троттлинг по минимальному интервалу между отправками
/// - Автостарт при логине и автостоп при логауте
/// - Быстрый старт с getLastKnownPosition()
class LocationService extends ChangeNotifier {
  // ==== Синглтон ====
  LocationService._internal({this.onDeniedForever}) {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_handleAuthChange);
  }

  factory LocationService({VoidCallback? onDeniedForever}) => I;

  static final LocationService I = LocationService._internal();

  // ==== Колбэки ====
  /// Старый колбэк, если навсегда запрещено (можно использовать в верхнем уровне)
  final VoidCallback? onDeniedForever;

  /// Новый настраиваемый колбэк (UI может подписаться, например DrivingMapPage)
  VoidCallback? _deniedForeverCallback;
  void setDeniedForeverCallback(VoidCallback? cb) {
    _deniedForeverCallback = cb;
  }

  // ==== Настройки фильтров ====
  int minDistanceMeters = 25; // отправляем только при сдвиге >= 25 м
  Duration minInterval = const Duration(seconds: 10); // не чаще 1 раза в 10 сек

  // ==== Внутренние поля ====
  StreamSubscription<Position>? _posSub;
  StreamSubscription<User?>? _authSub;

  Position? _lastSentPosition;
  DateTime? _lastSentAt;

  bool _tracking = false;
  bool get isRunning => _tracking;

  // ==== Публичный стрим для UI ====
  final _uiController = StreamController<Position>.broadcast();
  Stream<Position> get positions => _uiController.stream;
  Position? lastKnownPosition;

  // ==== Реакция на логин/логаут ====
  Future<void> _handleAuthChange(User? user) async {
    if (user == null) {
      stop();
      _lastSentPosition = null;
      _lastSentAt = null;
      lastKnownPosition = null;
      return;
    }
    await start();
  }

  // ==== Запуск сервиса ====
  Future<void> start({
    int? distanceFilter,
    LocationAccuracy accuracy = LocationAccuracy.high,
    int? sendMinDistanceMeters,
    Duration? sendMinInterval,
  }) async {
    if (_tracking) return;

    if (sendMinDistanceMeters != null) minDistanceMeters = sendMinDistanceMeters;
    if (sendMinInterval != null) minInterval = sendMinInterval;

    // Проверяем сервисы и разрешения
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[Location] Location service is disabled.');
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      debugPrint('[Location] Permission denied forever.');
      onDeniedForever?.call();
      _deniedForeverCallback?.call();
      return;
    }
    if (perm == LocationPermission.denied) {
      debugPrint('[Location] Permission denied.');
      return;
    }

    // Быстрый старт: отдадим в UI и попробуем отправить
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        lastKnownPosition = last;
        if (!_uiController.isClosed) _uiController.add(last);
        await _maybeSend(last);
      }
    } catch (e) {
      debugPrint('[Location] getLastKnownPosition() failed: $e');
    }

    // Основной поток позиций
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter ?? 15,
      ),
    ).listen(
          (pos) => _onPosition(pos),
      onError: (e, st) => debugPrint('[Location] stream error: $e'),
      cancelOnError: false,
    );

    _tracking = true;
    notifyListeners();
    debugPrint('[Location] Tracking started.');
  }

  // ==== Остановка ====
  void stop() {
    _posSub?.cancel();
    _posSub = null;
    _tracking = false;
    notifyListeners();
    debugPrint('[Location] Tracking stopped.');
  }

  // ==== Внутренние обработчики ====
  Future<void> _onPosition(Position pos) async {
    lastKnownPosition = pos;
    if (!_uiController.isClosed) _uiController.add(pos);
    await _maybeSend(pos);
  }

  Future<void> _maybeSend(Position pos) async {
    if (!_shouldSend(pos)) return;

    try {
      await ApiService.setCurrentLocation(pos.latitude, pos.longitude);
      _lastSentPosition = pos;
      _lastSentAt = DateTime.now();
    } catch (e) {
      debugPrint('[Location] send failed: $e');
    }
  }

  bool _shouldSend(Position current) {
    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!) < minInterval) {
      return false;
    }

    if (_lastSentPosition == null) return true;

    final d = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    return d >= minDistanceMeters;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _authSub?.cancel();
    _uiController.close();
    _deniedForeverCallback = null;
    super.dispose();
  }
}
