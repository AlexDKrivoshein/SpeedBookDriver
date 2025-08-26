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
  LocationService({this.onDeniedForever}) {
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthChange);
  }

  /// Вызывается, если доступ к гео навсегда запрещён — можно открыть экран с инструкцией.
  final VoidCallback? onDeniedForever;

  // Настройки фильтров
  static const int _minDistanceMeters = 25; // отправляем только при сдвиге >= 25 м
  static const Duration _minInterval = Duration(seconds: 10); // не чаще 1 раза в 10 сек

  StreamSubscription<Position>? _posSub;
  StreamSubscription<User?>? _authSub;

  Position? _lastSentPosition;
  DateTime? _lastSentAt;

  bool _tracking = false;

  bool get isRunning => _tracking;

  Future<void> _handleAuthChange(User? user) async {
    if (user == null) {
      // logout
      stop();
      _lastSentPosition = null;
      _lastSentAt = null;
      return;
    }
    // login
    await start();
  }

  Future<void> start() async {
    if (_tracking) return;

    // Проверяем сервисы и разрешения
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // можно показать пользователю тост/диалог, но не ломаем поток
      debugPrint('[Location] Location service is disabled.');
      // Не стартуем, пока не включат — иначе будет поток с ошибками.
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      debugPrint('[Location] Permission denied forever.');
      onDeniedForever?.call();
      return;
    }
    if (perm == LocationPermission.denied) {
      debugPrint('[Location] Permission denied.');
      return;
    }

    // Быстрый старт: отправим последнюю известную позицию (если есть)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        await _maybeSend(last);
      }
    } catch (e) {
      debugPrint('[Location] getLastKnownPosition() failed: $e');
    }

    // Основной поток позиций
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // предварительный фильтр от платформы
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

  void stop() {
    _posSub?.cancel();
    _posSub = null;
    _tracking = false;
    notifyListeners();
    debugPrint('[Location] Tracking stopped.');
  }

  Future<void> _onPosition(Position pos) async {
    await _maybeSend(pos);
  }

  Future<void> _maybeSend(Position pos) async {
    if (!_shouldSend(pos)) {
      // пропускаем — слишком близко к прошлой точке или слишком рано
      return;
    }

    try {
      await ApiService.setCurrentLocation(pos.latitude, pos.longitude);
      _lastSentPosition = pos;
      _lastSentAt = DateTime.now();
      // debugPrint('[Location] Sent: ${pos.latitude},${pos.longitude}');
    } catch (e) {
      debugPrint('[Location] send failed: $e');
    }
  }

  bool _shouldSend(Position current) {
    // Троттлинг по времени
    final now = DateTime.now();
    if (_lastSentAt != null && now.difference(_lastSentAt!) < _minInterval) {
      return false;
    }

    // Первый запуск — отправляем
    if (_lastSentPosition == null) return true;

    // Фильтр по дистанции
    final d = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    return d >= _minDistanceMeters;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}