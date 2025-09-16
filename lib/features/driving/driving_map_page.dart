import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../location_service.dart';

class DrivingMapPage extends StatefulWidget {
  const DrivingMapPage({super.key});

  @override
  State<DrivingMapPage> createState() => _DrivingMapPageState();
}

class _DrivingMapPageState extends State<DrivingMapPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller = Completer();
  StreamSubscription<Position>? _positionSub;

  LatLng? _currentLatLng;
  bool _loading = true;

  // follow-режим: автоцентрирование на водителе
  bool _followMe = true;

  // индикатор «идёт поиск заказов»
  bool _searching = true;

  // анимация радара
  late final AnimationController _radarCtrl;

  // Эмулятор? — включим liteMode, чтобы снизить нагрузку на CPU/SwiftShader
  bool get _preferLiteMode {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid ? _isEmulator : false;
    } catch (_) {
      return false;
    }
  }

  // Простой флаг из --dart-define=flutter.emulator=true (можно расширить через device_info_plus)
  static bool get _isEmulator {
    const env = String.fromEnvironment('flutter.emulator', defaultValue: '');
    return env.isNotEmpty;
  }

  CameraPosition get _initialCamera => const CameraPosition(
    target: LatLng(55.751244, 37.618423),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Сообщим об eternal-deny и закроем страницу
    LocationService.I.setDeniedForeverCallback(_onDeniedForever);

    // радар: плавная бесконечная анимация
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    LocationService.I.setDeniedForeverCallback(null);
    _radarCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _start();
  }

  void _onDeniedForever() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Location permission is permanently denied. Enable it in system settings.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _start() async {
    setState(() => _loading = true);

    // Запускаем общий сервис (он сам проверит сервисы/права и отправляет координаты с троттлингом)
    if (!LocationService.I.isRunning) {
      await LocationService.I.start(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // платформенный фильтр
        sendMinDistanceMeters: 25,
        sendMinInterval: const Duration(seconds: 10),
      );
      // Если здесь случился deniedForever — _onDeniedForever уже вызван и экран закроется.
    }

    // Поставим стартовую точку из кеша сервиса
    final last = LocationService.I.lastKnownPosition;
    if (last != null) {
      _currentLatLng = LatLng(last.latitude, last.longitude);
      if (mounted) setState(() {});
    }

    // Подпишемся на поток позиций
    _positionSub?.cancel();
    _positionSub = LocationService.I.positions.listen((pos) {
      _currentLatLng = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() {});
      _maybeMoveCamera(_currentLatLng!);
    });

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _maybeMoveCamera(LatLng target, {bool animated = true}) async {
    if (!_controller.isCompleted || !_followMe) return;
    final map = await _controller.future;

    // На эмуляторе — без анимации, чтобы снизить нагрузку
    if (animated && !_preferLiteMode) {
      await map.animateCamera(CameraUpdate.newLatLng(target));
    } else {
      await map.moveCamera(CameraUpdate.newLatLng(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = _currentLatLng == null
        ? <Marker>{}
        : {
      Marker(
        markerId: const MarkerId('me'),
        position: _currentLatLng!,
        infoWindow: const InfoWindow(title: 'You are here'),
      ),
    };

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driving'),
        actions: [
          // Переключатель «идёт поиск» (если захочешь вручную управлять)
          IconButton(
            tooltip: _searching ? 'Stop searching' : 'Start searching',
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (_searching) {
                  _radarCtrl.repeat();
                } else {
                  _radarCtrl.stop();
                }
              });
            },
            icon: Icon(_searching ? Icons.radar : Icons.radar_outlined),
          ),
          IconButton(
            tooltip: _followMe ? 'Following' : 'Follow me',
            onPressed: () async {
              setState(() => _followMe = !_followMe);
              if (_followMe && _currentLatLng != null) {
                await _maybeMoveCamera(_currentLatLng!, animated: true);
              }
            },
            icon: Icon(_followMe ? Icons.location_searching : Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCamera,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: markers,
            compassEnabled: true,
            zoomControlsEnabled: false,
            liteModeEnabled: _preferLiteMode,
            onMapCreated: (c) async {
              _controller.complete(c);
              if (_currentLatLng != null) {
                await _maybeMoveCamera(_currentLatLng!, animated: false);
              }
            },
            onCameraMoveStarted: () {
              // пользователь начал двигать карту — отключаем follow
              if (_followMe) {
                setState(() => _followMe = false);
              }
            },
          ),

          // Радар-оверлей (центр по экрану — при follow как раз совпадает с позицией)
          if (_searching)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _radarCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _RadarPainter(
                        progress: _radarCtrl.value,
                        color: theme.colorScheme.primary,
                        background: theme.colorScheme.primary.withOpacity(0.05),
                      ),
                    );
                  },
                ),
              ),
            ),

          // Чип «Searching orders…»
          if (_searching)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: _SearchingChip(),
              ),
            ),

          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Center',
        onPressed: () async {
          if (_currentLatLng != null) {
            setState(() => _followMe = true);
            await _maybeMoveCamera(_currentLatLng!, animated: true);
          }
        },
        child: const Icon(Icons.center_focus_strong),
      ),
    );
  }
}

/// Небольшой чип с «пульсом» для статуса поиска
class _SearchingChip extends StatefulWidget {
  @override
  State<_SearchingChip> createState() => _SearchingChipState();
}

class _SearchingChipState extends State<_SearchingChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: ShapeDecoration(
          color: theme.colorScheme.surface.withOpacity(0.9),
          shape: StadiumBorder(
            side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.25)),
          ),
          shadows: [
            BoxShadow(
              blurRadius: 12,
              spreadRadius: 1,
              color: Colors.black.withOpacity(0.08),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Searching orders…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рисует расходящиеся круги и вращающуюся «щётку» как у радара.
/// Привязан к центру экрана (при follow совпадает с текущей позицией).
class _RadarPainter extends CustomPainter {
  final double progress; // 0..1, крутится по кругу
  final Color color;
  final Color background;

  _RadarPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shortest = math.min(size.width, size.height);
    final maxR = shortest * 0.35; // радиус эффекта (35% меньшей стороны)

    // фон чуть тоним, чтобы круги на любом фоне были видны
    final bgPaint = Paint()
      ..color = background
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxR, bgPaint);

    // расходящиеся круги (3 волны), прозрачность по затуханию
    final waves = 3;
    for (int i = 0; i < waves; i++) {
      final t = (progress + i / waves) % 1.0; // фаза волны
      final r = lerpDouble(maxR * 0.05, maxR, t)!;
      final a = (1.0 - t) * 0.6; // затухание
      final wavePaint = Paint()
        ..color = color.withOpacity(a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, r, wavePaint);
    }

    // вращающаяся «щётка»
    final sweep = math.pi / 6; // 30°
    final angle = progress * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: maxR);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + sweep,
        colors: [
          color.withOpacity(0.35),
          color.withOpacity(0.0),
        ],
      ).createShader(rect);
    // сектор
    canvas.drawArc(rect, angle, sweep, true, sweepPaint);

    // центральная точка
    final dot = Paint()..color = color.withOpacity(0.9);
    canvas.drawCircle(center, 3, dot);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.background != background;
  }

  double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
