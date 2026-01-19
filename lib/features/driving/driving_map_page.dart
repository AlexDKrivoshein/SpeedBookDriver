import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../location_service.dart';
import '../../foreground_location_service.dart';
import '../../driver_api.dart';
import '../../api_service.dart';
import '../../translations.dart';
import '../../chat/chat_dock.dart';
import 'ui/pickup_action_bar.dart';
import 'ui/offer_sheet.dart';
import 'map/route_utils.dart';
import '../../call/call_button.dart';

class DrivingMapPage extends StatefulWidget {
  const DrivingMapPage({super.key, this.driveId});
  final int? driveId;

  @override
  State<DrivingMapPage> createState() => _DrivingMapPageState();
}

class _DrivingMapPageState extends State<DrivingMapPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller = Completer();
  StreamSubscription<Position>? _positionSub;
  final ValueNotifier<Set<Marker>> _mapMarkers =
      ValueNotifier<Set<Marker>>(<Marker>{});
  final ValueNotifier<Set<Polyline>> _mapPolylines =
      ValueNotifier<Set<Polyline>>(<Polyline>{});

  LatLng? _currentLatLng;
  double _heading = 0;
  bool _loading = true;

  bool _followMe = true;
  bool _searching = true;
  bool _stopSent = false; // уже дергали stop_driving
  bool _navigatedHome = false; // уже ушли на home

  late final AnimationController _radarCtrl;
  BitmapDescriptor? _carIcon;

  Timer? _drivePollTimer;
  bool _pickupMode = false;
  int? _driveId;
  Marker? _driverMarker;
  late final Widget _mapView;

  // ===== навигационный режим =====
  bool _navMode = false; // включаем в pickup
  double _navZoom = 17.0; // комфортный зум
  double _navTilt = 45.0; // наклон камеры
  LatLng? _lastDriverPos; // предыдущая позиция для bearing
  bool _actionBusy = false; // блокировка кнопок во время запроса
  bool _canArrived = false;
  bool _canStart = false;
  bool _canCancel = false;
  int? _routeId; // текущий id маршрута из get_driver_drive_details
  bool _camMoveProgrammatic =
      false; // чтобы отличать наши анимации от жестов пользователя
  bool _canFinish = false;
  String? _paymentType;
  bool _paymentTypeAlertShown = false;

  // безопасный флаг демонтирования виджета
  bool _disposed = false;

  // терминальные статусы, при которых прекращаем опрос
  static const Set<String> _terminalStatuses = {
    'DRIVE_CANCELLED_BY_CUSTOMER',
    'DRIVE_CANCELLED_BY_DRIVER',
    'DRIVE_FINISHED'
  };
  static const Set<String> _tripStatuses = {
    'DRIVER_FOUND',
    'DRIVE_ARRIVED',
    'DRIVE_STARTED'
  };

  // оффер/маршрут
  Map<String, dynamic>? _offer; // data из get_offers
  Set<Polyline> _polylines = {};
  Set<Marker> _offerMarkers = {};
  bool _offerPolling = false;
  bool _startSent = false;

  bool get _preferLiteMode {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid ? _isEmulator : false;
    } catch (_) {
      return false;
    }
  }

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

    // пробрасываем driveId, если пришёл через навигацию
    _driveId = widget.driveId;

    // следим за жизненным циклом
    WidgetsBinding.instance.addObserver(this);

    // радар: контроллер анимации
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // изначально мы в режиме поиска → запускаем радар
    if (_searching) {
      _radarCtrl.repeat();
    }

    // Кешируем карту, чтобы не пересоздавать ее при частых rebuild.
    _mapView = _DrivingMapView(
      controller: _controller,
      initialCamera: _initialCamera,
      markers: _mapMarkers,
      polylines: _mapPolylines,
      liteModeEnabled: _preferLiteMode,
      onMapCreated: (c) async {
        if (_currentLatLng != null) {
          await _maybeMoveCamera(_currentLatLng!, animated: false);
        }
      },
      onCameraMoveStarted: _handleCameraMoveStarted,
    );

    // всё, что требует контекста/MediaQuery — после первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // иконка машины под текущий DPR
      _loadCarIcon();

      final args = ModalRoute.of(context)?.settings.arguments;

      // 1) Новый сценарий: пришли из FCM (drive_offer), надо просто начать поиск офферов
      if (args is Map && args['force_offer_refresh'] == true) {
        debugPrint('[Driving] FCM drive_offer → startOfferPolling()');
        _offer = null;
        _searching = true;
        _offerPolling = true;
        _radarCtrl.repeat();
        _startOfferPolling();
        return;
      }

      // 2) Сценарий: в аргументах уже лежит готовый оффер (если где-то так вызываешь)
      if (args is Map && args['offer'] is Map) {
        final o = args['offer'] as Map;

        _offer = Map<String, dynamic>.from(o);

        final fromName = (o['from_name'] ?? '').toString();
        final fromDetails = (o['from_details'] ?? '').toString();
        final toName = (o['to_name'] ?? '').toString();
        final toDetails = (o['to_details'] ?? '').toString();
        final distanceLabel = (o['distance_label'] ?? '').toString();
        final durationLabel = _formatDuration(o['duration']);
        final priceLabel = (o['price_label'] ?? '').toString();
        final offerValid = o['offer_valid'] is int
            ? o['offer_valid'] as int
            : int.tryParse(o['offer_valid']?.toString() ?? '');

        OfferSheet.show(
          context,
          fromName: fromName,
          fromDetails: fromDetails,
          toName: toName,
          toDetails: toDetails,
          distanceLabel: distanceLabel,
          durationLabel: durationLabel,
          priceLabel: priceLabel,
          onAccept: _onAccept,
          onDecline: _onDecline,
          t: (k) => t(context, k),
          offerValidSeconds: offerValid,
        );
        return;
      }

      // 3) Старый сценарий: запуск поиска / поллинга
      _start();
    });
  }

  // ---- Масштабируем PNG в рантайме под DPI ----
  Future<BitmapDescriptor> _bitmapFromAsset(
      String assetPath, int targetWidthPx) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: targetWidthPx);
    final fi = await codec.getNextFrame();
    final bytes = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadCarIcon() async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const logicalWidth = 42.0;
    final px = (logicalWidth * dpr).round();
    final icon = await _bitmapFromAsset('assets/images/car.png', px);
    if (!mounted || _disposed) return;
    _carIcon = icon;
    _refreshMapMarkers();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    LocationService.I.setDeniedForeverCallback(null);
    _radarCtrl.dispose();
    _offerPolling = false;
    _stopDrivePolling();
    _mapMarkers.dispose();
    _mapPolylines.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _start();
  }

  void _onDeniedForever() {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Location permission is permanently denied. Enable it in system settings.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  Future<bool> _startDrivingSafeFromLastPos() async {
    final last = LocationService.I.lastKnownPosition;
    if (last == null) {
      debugPrint('[Driving] no lastKnownPosition, skip start_driving');
      return false;
    }
    final double? heading = (last.heading.isFinite && last.heading >= 0)
        ? (last.heading % 360)
        : null;
    final double? accuracy =
        (last.accuracy.isFinite && last.accuracy > 0) ? last.accuracy : null;

    try {
      final reply = await DriverApi.startDriving(
        lat: last.latitude,
        lng: last.longitude,
        heading: heading,
        accuracy: accuracy,
      ).timeout(const Duration(seconds: 12));

      debugPrint('[Driving] start_driving reply: $reply');

      final ok = (reply['status'] ?? '').toString() == 'OK';
      if (!ok) debugPrint('[Driving] start_driving failed: $reply');
      return ok;
    } catch (e) {
      debugPrint('[Driving] start_driving error: $e');
      return false;
    }
  }

  Future<void> _start() async {
    if (!mounted || _disposed) return;
    setState(() => _loading = true);

    if (_driveId != null) {
      _searching = false; // отключаем поиск
      _offerPolling = false; // перестаём поллить офферы
      _radarCtrl.stop(); // глушим анимацию радара
      if (_drivePollTimer == null) {
        _startDrivePolling(); // начинаем поллинг деталей поездки
      }
    }

    if (!LocationService.I.isRunning) {
      await LocationService.I.start(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // хотим обновления по времени, а не по дистанции
        sendMinDistanceMeters: 0,
        sendMinInterval: const Duration(seconds: 5),
      );
      if (!mounted || _disposed) return;
    }

    final last = LocationService.I.lastKnownPosition;
    if (last != null) {
      _currentLatLng = LatLng(last.latitude, last.longitude);
      _heading = last.heading.isFinite ? last.heading : 0;
      _refreshMapMarkers();
      if (mounted && !_disposed) setState(() {});
      await _tryStartDrivingOnce(last);
      if (!mounted || _disposed) return;
    }

    _positionSub?.cancel();
    _positionSub = LocationService.I.positions.listen((pos) async {
      if (_disposed) return;
      _currentLatLng = LatLng(pos.latitude, pos.longitude);
      _heading = pos.heading.isFinite ? pos.heading : _heading;
      _refreshMapMarkers();
      if (mounted && !_disposed) setState(() {});
      _maybeMoveCamera(_currentLatLng!);
      await _tryStartDrivingOnce(pos);
    });

    if (_searching && !_offerPolling) {
      _startOfferPolling();
    }

    if (mounted && !_disposed) setState(() => _loading = false);
  }

  Future<void> _maybeMoveCamera(LatLng target, {bool animated = true}) async {
    if (!_controller.isCompleted || !_followMe || _disposed) return;
    final map = await _controller.future;
    if (_disposed) return;
    _camMoveProgrammatic = true;
    if (animated && !_preferLiteMode) {
      await map.animateCamera(CameraUpdate.newLatLng(target));
    } else {
      await map.moveCamera(CameraUpdate.newLatLng(target));
    }
    scheduleMicrotask(() => _camMoveProgrammatic = false);
  }

  Future<void> _onAccept() async {
    if (_offer == null || _disposed) return;
    final reqId = ApiService.asInt(_offer!['request_id']);
    final driveId = ApiService.asInt(_offer!['drive_id']);
    try {
      final r = await DriverApi.acceptDrive(requestId: reqId, driveId: driveId)
          .timeout(const Duration(seconds: 10));

      debugPrint('[Driving] accept drive result: $r');

      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted || _disposed) return;
        Navigator.of(context).pop(); // закрыть шит

        _driveId = driveId;
        _startDrivePolling();
        if (!mounted || _disposed) return;
        setState(() {
          _pickupMode = true;
          _navMode = true;
          _followMe = true;
        });
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Accept failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    }
  }

  Future<void> _onDecline() async {
    _routeId = null;
    if (_offer == null || _disposed) return;
    final reqId = ApiService.asInt(_offer!['request_id']);
    final driveId = ApiService.asInt(_offer!['drive_id']);
    try {
      final r = await DriverApi.declineDrive(requestId: reqId, driveId: driveId)
          .timeout(const Duration(seconds: 10));
      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted || _disposed) return;
        Navigator.of(context).pop(); // закрыть шит
        _offer = null;
        _polylines.clear();
        _offerMarkers.clear();
        _refreshMapPolylines();
        _refreshMapMarkers();
        _searching = true;
        _radarCtrl.repeat();
        if (!_offerPolling) _startOfferPolling();
        if (mounted && !_disposed) setState(() {});
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Decline failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    }
  }

  /// Однократный вызов start_driving с координатами; при ошибке — возврат на главную
  Future<void> _tryStartDrivingOnce(Position pos) async {
    if (_startSent || _driveId != null || _disposed) return;

    final double? heading =
        (pos.heading.isFinite && pos.heading >= 0) ? (pos.heading % 360) : null;
    final double? accuracy =
        (pos.accuracy.isFinite && pos.accuracy > 0) ? pos.accuracy : null;

    try {
      final reply = await DriverApi.startDriving(
        lat: pos.latitude,
        lng: pos.longitude,
        heading: heading,
        accuracy: accuracy,
      ).timeout(const Duration(seconds: 12));

      debugPrint('[Driving] start_driving reply: $reply');

      if (_disposed) return;

      final status = (reply['status'] ?? '').toString();
      if (status != 'OK') {
        if (!mounted || _disposed) return;
        final msg = reply['message']?.toString() ?? 'Start driving failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
        _goHome();
        return;
      }

      _startSent = true;
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
      _goHome();
    }
  }

  // ========= ПУЛЛИНГ ОФФЕРОВ =========

  void _startOfferPolling() {
    _offerPolling = true;
    _pollOffers();
  }

  Future<void> _pollOffers() async {
    while (mounted &&
        !_disposed &&
        _offerPolling &&
        _searching &&
        _offer == null) {
      try {
        final reply =
            await DriverApi.getOffers().timeout(const Duration(seconds: 10));
        debugPrint('[pollOffers] reply: $reply');

        if (_disposed) return;

        if (_isDriveSpoiled(reply)) {
          await _startDrivingSafeFromLastPos();
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        // error: REQUEST_NOT FOUND -> сразу на главную
        final err = reply['error']?.toString();
        if (err == 'REQUEST_NOT FOUND') {
          if (!mounted || _disposed) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'common.error'))),
          );
          _goHome();
          return;
        }

        final status = (reply['status'] ?? '').toString();
        final data = reply['data'];

        if (status == 'OK') {
          if (data is Map && (data['result']?.toString() == 'NOT_FOUND')) {
            await Future.delayed(const Duration(seconds: 10));
            continue;
          }

          if (data is Map) {
            final reqId = ApiService.asInt(data['request_id']);
            if (reqId > 0) {
              // нашли оффер
              _offer = Map<String, dynamic>.from(data as Map);
              _offerPolling = false;
              _searching = false;
              _radarCtrl.stop();

              final fromName = ApiService.asString(data['from_name']);
              final fromDetails = ApiService.asString(data['from_details']);
              final toName = ApiService.asString(data['to_name']);
              final toDetails = ApiService.asString(data['to_details']);

              // Рендер маршрута оффера (polyline + маркеры)
              _renderOfferRoute(
                encoded: ApiService.asString(data['waypoint']),
                fromName: fromName,
                fromDetails: fromDetails,
                toName: toName,
                toDetails: toDetails,
              );

              if (mounted && !_disposed) {
                setState(() {});
                // Покажем модалку оффера
                final distanceM = ApiService.asNum(data['distance']);
                final durationStr = _formatDuration(_offer!['duration']);
                final cost = ApiService.asString(data['cost']);
                final currency = ApiService.asString(data['currency']);
                final offerValid = ApiService.asInt(data['offer_valid']);

                OfferSheet.show(
                  context,
                  fromName: fromName,
                  fromDetails: fromDetails,
                  toName: toName,
                  toDetails: toDetails,
                  distanceLabel: '${(distanceM / 1000).toStringAsFixed(1)} km',
                  durationLabel: durationStr,
                  priceLabel: '$currency $cost',
                  onAccept: _onAccept,
                  onDecline: _onDecline,
                  t: (k) => t(context, k),
                  offerValidSeconds: offerValid,
                );
              }
              return;
            }
          }
        }

        await Future.delayed(const Duration(seconds: 3));
      } catch (_) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  bool _isDriveSpoiled(Map<String, dynamic> reply) {
    final status = (reply['status'] ?? '').toString();
    final err = reply['error']?.toString();
    if (status == 'DRIVE_IS_SPOILED' || err == 'DRIVE_IS_SPOILED') {
      return true;
    }
    final data = reply['data'];
    if (data is Map && data['result']?.toString() == 'DRIVE_IS_SPOILED') {
      return true;
    }
    return false;
  }

  void _renderOfferRoute({
    required String? encoded,
    required String fromName,
    required String fromDetails,
    required String toName,
    required String toDetails,
  }) async {
    _polylines.clear();
    _offerMarkers.clear();
    _refreshMapPolylines();
    _refreshMapMarkers();

    if (encoded == null || encoded.isEmpty) {
      if (mounted && !_disposed) setState(() {});
      return;
    }

    final pts = decodePolyline(encoded);
    if (pts.isEmpty) {
      if (mounted && !_disposed) setState(() {}); // ничего не рисуем
      return;
    }

    // 1) единственная линия маршрута
    _setRoutePolyline(pts);

    // 2) маркеры начала/конца
    final start = pts.first;
    final end = pts.last;
    _offerMarkers.add(Marker(
      markerId: const MarkerId('from'),
      position: start,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: fromName, snippet: fromDetails),
    ));
    _offerMarkers.add(Marker(
      markerId: const MarkerId('to'),
      position: end,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: toName, snippet: toDetails),
    ));

    // 3) камера по границам
    try {
      final map = await _controller.future;
      if (_disposed) return;
      final bounds = computeBounds(pts);
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
    } catch (_) {
      await _maybeMoveCamera(start, animated: true);
    }

    _refreshMapMarkers();
    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _callStopDriving({bool navigate = true}) async {
    if (_stopSent) return;
    _stopSent = true;

    try {
      await DriverApi.stopDriving().timeout(const Duration(seconds: 8));
    } catch (_) {
      // игнорим сетевые ошибки — главное корректно завершить локально
    } finally {
      // локальная остановка циклов
      _offerPolling = false;
      _stopDrivePolling();

      if (navigate && mounted && !_disposed) {
        await _goHome(); // безопасная навигация (см. ниже)
      }
    }
  }

  // ========= ПОЛЛИНГ ДЕТАЛЕЙ ПОЕЗДКИ =========

  void _startDrivePolling() {
    _stopDrivePolling(); // на всякий пожарный
    _drivePollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _disposed) return;
      _fetchDriveDetails();
    });
    // сделаем первый запрос сразу
    _fetchDriveDetails();
  }

  void _stopDrivePolling() {
    _drivePollTimer?.cancel();
    _drivePollTimer = null;
  }

  Future<void> _fetchDriveDetails() async {
    if (_disposed) return;
    final did = _driveId;
    if (did == null) return;

    // берём актуальные координаты: сначала из _currentLatLng, иначе — lastKnown
    LatLng? pos = _currentLatLng;
    pos ??= (() {
      final last = LocationService.I.lastKnownPosition;
      return last != null ? LatLng(last.latitude, last.longitude) : null;
    })();

    if (pos == null) {
      debugPrint('[DrivePoll] skip: no location yet');
      return;
    }

    final payload = {
      'drive_id': did,
      // важно: ключи именно в таком виде и порядке
      'lng': pos.longitude,
      'lat': pos.latitude,
    };

    try {
      final reply = await ApiService.callAndDecode(
        'get_driver_drive_details',
        payload,
      ).timeout(const Duration(seconds: 10));

      if (_disposed) return;

      if (reply['status'] != 'OK') {
        debugPrint('[DrivePoll] bad status: $reply');
        return;
      }

      final data = reply['data'] as Map<String, dynamic>?;
      debugPrint('[DrivePoll] data: $data');
      if (data == null || _disposed) return;

      await _applyDriveDetails(data);
    } catch (e, st) {
      if (_disposed) return;
      debugPrint('[DrivePoll] error: $e\n$st');
    }
  }

  Future<void> _goHome() async {
    if (!mounted || _disposed || _navigatedHome) return;
    _navigatedHome = true;

    final rootNav = Navigator.of(context, rootNavigator: true);

    await Future.delayed(const Duration(milliseconds: 10));
    if (!mounted || _disposed) return;

    rootNav.popUntil((route) => route.isFirst);
  }

  Future<void> _applyDriveDetails(Map<String, dynamic> data) async {
    if (_disposed) return;

    final status = (data['status'] ?? '').toString().toUpperCase();
    final driveId = data['drive_id'];
    final paymentType = data['payment_type']?.toString();

    _canArrived = ApiService.asBool(data['can_arrived']);
    _canStart = ApiService.asBool(data['can_start']);
    _canCancel = ApiService.asBool(data['can_cancel']);
    _canFinish = ApiService.asBool(data['can_finish']);

    if (driveId is int && _driveId != driveId) {
      _driveId = driveId;
    }

    if (paymentType != null && paymentType.isNotEmpty) {
      if (_paymentType == null) {
        _paymentType = paymentType;
      } else if (_paymentType != paymentType && !_paymentTypeAlertShown) {
        _paymentType = paymentType;
        _paymentTypeAlertShown = true;
        if (mounted && !_disposed) {
          try {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: Text(t(context, 'drive.payment_type_changed_title')),
                content: Text(
                  t(context, 'drive.payment_type_changed_body')
                      .replaceAll('{type}', paymentType),
                  style: const TextStyle(fontSize: 18),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(t(context, 'common.ok')),
                  ),
                ],
              ),
            );
          } finally {
            _paymentTypeAlertShown = false;
          }
        } else {
          _paymentTypeAlertShown = false;
        }
      }
    }

    debugPrint('[Driving] status: $status');

    await ForegroundLocationService.I
        .setTripActive(_tripStatuses.contains(status));

    // ===== 1. Клиент отменил поездку =====
    if (status == 'DRIVE_CANCELLED_BY_CUSTOMER' && !_stopSent) {
      debugPrint('[DrivePoll] cancelled by customer');

      await _callStopDriving(navigate: false);

      _driveId = null;
      _routeId = null;
      _pickupMode = false;
      _navMode = false;
      _startSent = false;
      _offer = null;
      _polylines.clear();
      _offerMarkers.clear();
      _refreshMapPolylines();
      _refreshMapMarkers();

      _canArrived = false;
      _canStart = false;
      _canCancel = false;
      _canFinish = false;

      if (mounted && !_disposed) {
        setState(() {
          _searching = true; // остаёмся на странице и снова ищем
          _radarCtrl.repeat();
        });
      }

      await _goHome();
      return;
    }

    // ===== 2. Поездка завершена =====
    if (status == 'DRIVE_FINISHED') {
      _stopDrivePolling();
      _routeId = null;
      _canArrived = _canStart = _canCancel = _canFinish = false;
      await _callStopDriving(); // navigate=true по умолчанию
      if (mounted && !_disposed) setState(() {});
      return;
    }

    // ===== 3. Переключение UI-режимов (pickup / drive) =====
    if (status == 'DRIVER_FOUND' || status == 'DRIVE_ARRIVED') {
      _enterPickupMode();
    } else if (status == 'DRIVE_STARTED' || (!_navMode && _canFinish)) {
      // если почему-то не переключились в навигацию, но canFinish уже true — дожимаем
      _enterDriveMode();
    }

    // ===== 4. Позиция машины с бэка =====
    final pos = data['position'] as Map<String, dynamic>?;
    if (pos != null) {
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _updateDriverMarker(LatLng(lat, lng));
      }
    }

    // ===== 5. Текущий маршрут =====
    final route = data['route'] as Map<String, dynamic>?;
    if (route != null) {
      final rid = ApiService.asInt(route['id']);
      final enc = route['polyline']?.toString();
      if (rid > 0 && rid != _routeId && enc != null && enc.isNotEmpty) {
        final pts = decodePolyline(enc);

        _polylines = {};
        _refreshMapPolylines();

        _setRoutePolyline(pts);
        _routeId = rid;
      }
    }

    // ===== 6. Отмена поездки водителем (пуш с бэкенда) =====
    if (status == 'DRIVE_CANCELLED_BY_DRIVER') {
      _stopDrivePolling();
      _routeId = null;
      _pickupMode = false;
      _canArrived = _canStart = _canCancel = _canFinish = false;
    }

    if (mounted && !_disposed) setState(() {});
  }

  Future<void> _onArrivedPressed() async {
    final did = _driveId;
    if (did == null || _actionBusy || _disposed) return;

    if (mounted && !_disposed) setState(() => _actionBusy = true);
    try {
      final r =
          await ApiService.callAndDecode('driver_arrived', {'drive_id': did})
              .timeout(const Duration(seconds: 15));

      if (_disposed) return;

      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted || _disposed) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'driving.arrived_done'))),
        );
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Arrived failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted && !_disposed) setState(() => _actionBusy = false);
    }
  }

  Future<void> _onStartDrivePressed() async {
    final did = _driveId;
    if (did == null || _actionBusy || _disposed) return;
    if (mounted && !_disposed) setState(() => _actionBusy = true);
    try {
      final r = await ApiService.callAndDecode('start_drive', {'drive_id': did})
          .timeout(const Duration(seconds: 15));
      if (_disposed) return;
      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted || _disposed) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'driving.started'))),
        );
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Start failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted && !_disposed) setState(() => _actionBusy = false);
    }
  }

  Future<void> _onFinishDrivePressed() async {
    final did = _driveId;
    if (did == null || _actionBusy || _disposed) return;

    final confirmed = await _confirmFinishDrive();
    if (!confirmed || _disposed) return;

    if (mounted && !_disposed) setState(() => _actionBusy = true);
    try {
      final r =
          await ApiService.callAndDecode('finish_drive', {'drive_id': did})
              .timeout(const Duration(seconds: 20));

      if (_disposed) return;

      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted || _disposed) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'driving.finished'))),
        );
        await _callStopDriving(); // navigate=true по умолчанию
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Finish failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted && !_disposed) setState(() => _actionBusy = false);
    }
  }

  Future<bool> _confirmFinishDrive() async {
    if (!mounted || _disposed) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t(context, 'driving.finish_confirm_title')),
          content: Text(t(context, 'driving.finish_confirm_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, 'common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, 'common.ok')),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _onCancelDrivePressed() async {
    final did = _driveId;
    if (did == null || _actionBusy || _disposed) return;
    if (mounted && !_disposed) setState(() => _actionBusy = true);
    try {
      final r =
          await ApiService.callAndDecode('cancel_drive', {'drive_id': did})
              .timeout(const Duration(seconds: 15));

      if (_disposed) return;

      if ((r['status'] ?? '').toString() == 'OK') {
        await _callStopDriving(navigate: false);

        _driveId = null;
        _routeId = null;
        _pickupMode = false;
        _navMode = false;
        _startSent = false;
        _offer = null;
        _polylines.clear();
        _offerMarkers.clear();
        _refreshMapPolylines();
        _refreshMapMarkers();

        if (mounted && !_disposed) {
          setState(() {
            _searching = true;
            _radarCtrl.repeat();
          });
        }
        if (!_offerPolling) _startOfferPolling();

        await _startDrivingSafeFromLastPos();

        await _goHome();
      } else {
        if (!mounted || _disposed) return;
        final msg = r['message']?.toString() ?? 'Cancel failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted && !_disposed) setState(() => _actionBusy = false);
    }
  }

  void _enterPickupMode() {
    if (!mounted || _disposed) return;
    setState(() {
      _offer = null;
      _offerMarkers.clear();
      _navMode = true;
      _followMe = true;
      _pickupMode = true;
    });
    _refreshMapMarkers();
  }

  void _enterDriveMode() {
    if (!mounted || _disposed) return;
    setState(() {
      _offer = null;
      _offerMarkers.clear();
      _searching = false;
      _offerPolling = false;
      _radarCtrl.stop();
      _navMode = true;
      _followMe = true;
      _pickupMode = false;
    });
    _refreshMapMarkers();
  }

  void _updateDriverMarker(LatLng p) async {
    if (_disposed) return;
    _lastDriverPos ??= p;

    final marker = Marker(
      markerId: const MarkerId('driver'),
      position: p,
      anchor: const Offset(0.5, 0.5),
      rotation:
          _heading, // визуальный поворот иконки (можно заменить на bearing)
      flat: true,
      icon: _carIcon ?? BitmapDescriptor.defaultMarker,
    );
    _driverMarker = marker;
    _refreshMapMarkers();

    // в навигации — ведём камеру за машиной с поворотом по курсу
    if (_navMode && _followMe) {
      final br = _computeBearing(_lastDriverPos!, p);
      await _moveNavCamera(p, bearing: br);
    }
    _lastDriverPos = p;
  }

  void _refreshMapMarkers() {
    if (_disposed) return;
    final markers = <Marker>{..._offerMarkers};
    if (_driverMarker != null) {
      markers.add(_driverMarker!);
    } else if (_currentLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: _currentLatLng!,
        icon: _carIcon ?? BitmapDescriptor.defaultMarker,
        rotation: _heading,
        anchor: const Offset(0.5, 0.6),
        flat: true,
      ));
    }
    _mapMarkers.value = markers;
  }

  void _refreshMapPolylines() {
    if (_disposed) return;
    _mapPolylines.value = Set<Polyline>.from(_polylines);
  }

  void _handleCameraMoveStarted() {
    if (_camMoveProgrammatic) {
      _camMoveProgrammatic = false; // это мы сами двигали — игнорируем
      return;
    }
    // Пользователь двинул карту: отключаем автоследование даже в наврежиме
    if (_followMe) setState(() => _followMe = false);
  }

  void _setRoutePolyline(List<LatLng> points) {
    if (_disposed) return;
    const id = PolylineId('route'); // один фиксированный id
    final poly = Polyline(
      polylineId: id,
      points: points,
      width: 6,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    _polylines = {};
    _refreshMapPolylines();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _polylines = {poly};
      _refreshMapPolylines();
    });
  }

  // ========= Утилиты навигации =========
  double _computeBearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
    return brng;
  }

  Future<void> _moveNavCamera(LatLng pos, {double? bearing}) async {
    if (_disposed || !_controller.isCompleted) return;
    final map = await _controller.future;
    if (_disposed) return;

    final usedBearing = bearing ??
        (_lastDriverPos != null
            ? _computeBearing(_lastDriverPos!, pos)
            : _heading);

    final cam = CameraPosition(
      target: pos,
      zoom: _navZoom,
      tilt: _navTilt,
      bearing: usedBearing,
    );

    _camMoveProgrammatic = true;
    await map.animateCamera(CameraUpdate.newCameraPosition(cam));
    scheduleMicrotask(() => _camMoveProgrammatic = false);
  }

  /// Превращаем interval/строку в "xh ym"
  String _formatDuration(dynamic raw) {
    // если число — считаем как секунды
    if (raw is num) return _fmtSeconds(raw.toInt());

    final s = ApiService.asString(raw).trim();
    // HH:MM:SS
    final hms = RegExp(r'^(\d+):([0-5]\d):([0-5]\d)$');
    final m = hms.firstMatch(s);
    if (m != null) {
      final h = int.parse(m.group(1)!);
      final mi = int.parse(m.group(2)!);
      return _fmtHM(h, mi);
    }

    // MM:SS
    final ms = RegExp(r'^([0-5]?\d):([0-5]\d)$').firstMatch(s);
    if (ms != null) {
      final h = 0;
      final mi = int.parse(ms.group(1)!);
      return _fmtHM(h, mi);
    }

    // ISO8601-ish PT#H#M#S
    final iso =
        RegExp(r'P(T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)', caseSensitive: false)
            .firstMatch(s);
    if (iso != null) {
      final h = int.tryParse(iso.group(2) ?? '') ?? 0;
      final mi = int.tryParse(iso.group(3) ?? '') ?? 0;
      return _fmtHM(h, mi);
    }

    // Postgres text "1 hour 20 mins"
    final pg =
        RegExp(r'(?:(\d+)\s*hour[s]?)?\s*(?:(\d+)\s*min)', caseSensitive: false)
            .firstMatch(s);
    if (pg != null) {
      final h = int.tryParse(pg.group(1) ?? '0') ?? 0;
      final mi = int.tryParse(pg.group(2) ?? '0') ?? 0;
      return _fmtHM(h, mi);
    }

    // fallback
    return s;
  }

  String _fmtSeconds(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return _fmtHM(h, m);
  }

  String _fmtHM(int h, int m) {
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final bool _showActionBar = _driveId != null &&
        (_canArrived || _canStart || _canFinish || _canCancel);

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'driving.title')),
        actions: [
          IconButton(
            tooltip: _searching ? 'Stop searching' : 'Start searching',
            onPressed: () {
              if (_disposed) return;
              setState(() {
                _searching = !_searching;
                if (_searching) {
                  _radarCtrl.repeat();
                  if (!_offerPolling && _offer == null) _startOfferPolling();
                } else {
                  _radarCtrl.stop();
                  _offerPolling = false;
                }
              });
            },
            icon: Icon(_searching ? Icons.radar : Icons.radar_outlined),
          ),
          IconButton(
            tooltip: _followMe ? 'Following' : 'Follow me',
            onPressed: () async {
              if (_disposed) return;
              setState(() => _followMe = !_followMe);
              if (_followMe && _currentLatLng != null) {
                if (_navMode) {
                  await _moveNavCamera(_currentLatLng!);
                } else {
                  await _maybeMoveCamera(_currentLatLng!, animated: true);
                }
              }
            },
            icon:
                Icon(_followMe ? Icons.location_searching : Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          _mapView,

          if (_searching && _offer == null)
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

          if (_searching && _offer == null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.9),
                    shape: StadiumBorder(
                      side: BorderSide(
                          color: theme.colorScheme.primary.withOpacity(0.25)),
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
                      Icon(Icons.radar,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        t(context, 'driving.searching'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // === ChatDock при ожидании пассажира (pickup) ===
          if (_pickupMode && _driveId != null)
            Positioned(
              right: 16,
              bottom: 16 +
                  MediaQuery.of(context).padding.bottom +
                  ((_driveId != null &&
                          (_canArrived ||
                              _canStart ||
                              _canFinish ||
                              _canCancel))
                      ? 72
                      : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChatDock(driveId: _driveId!),
                  const SizedBox(width: 12),
                  CallButton(driveId: _driveId!),
                ],
              ),
            ),

          // === Pickup-Action Bar ===
          if (_showActionBar)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: PickupActionBar(
                  canArrived: _canArrived,
                  canStart: _canStart,
                  canFinish: _canFinish,
                  canCancel: _canCancel,
                  busy: _actionBusy,
                  onArrived: _onArrivedPressed,
                  onStart: _onStartDrivePressed,
                  onFinish: _onFinishDrivePressed,
                  onCancel: _onCancelDrivePressed,
                  t: (k) => t(context, k),
                ),
              ),
            ),

          Positioned(
            right: 16,
            bottom: 16 +
                MediaQuery.of(context).padding.bottom +
                (_showActionBar ? 96 : 0),
            child: FloatingActionButton(
              tooltip: 'Center',
              onPressed: () async {
                if (_currentLatLng != null) {
                  if (!mounted || _disposed) return;
                  setState(() => _followMe = true);
                  if (_navMode) {
                    await _moveNavCamera(_currentLatLng!);
                  } else {
                    await _maybeMoveCamera(_currentLatLng!, animated: true);
                  }
                }
              },
              child: const Icon(Icons.center_focus_strong),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrivingMapView extends StatelessWidget {
  const _DrivingMapView({
    required this.controller,
    required this.initialCamera,
    required this.markers,
    required this.polylines,
    required this.liteModeEnabled,
    required this.onMapCreated,
    required this.onCameraMoveStarted,
  });

  final Completer<GoogleMapController> controller;
  final CameraPosition initialCamera;
  final ValueListenable<Set<Marker>> markers;
  final ValueListenable<Set<Polyline>> polylines;
  final bool liteModeEnabled;
  final Future<void> Function(GoogleMapController) onMapCreated;
  final VoidCallback onCameraMoveStarted;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: markers,
      builder: (context, mapMarkers, _) {
        return ValueListenableBuilder<Set<Polyline>>(
          valueListenable: polylines,
          builder: (context, mapPolylines, __) {
            return GoogleMap(
              initialCameraPosition: initialCamera,
              myLocationEnabled: false,
              myLocationButtonEnabled: true,
              markers: mapMarkers,
              polylines: mapPolylines,
              compassEnabled: true,
              zoomControlsEnabled: false,
              liteModeEnabled: liteModeEnabled,
              onMapCreated: (c) async {
                if (!controller.isCompleted) {
                  controller.complete(c);
                }
                await onMapCreated(c);
              },
              onCameraMoveStarted: onCameraMoveStarted,
            );
          },
        );
      },
    );
  }
}

/// Радар: расходящиеся круги + вращающаяся «щётка»
class _RadarPainter extends CustomPainter {
  final double progress; // 0..1
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
    final maxR = shortest * 0.35;

    final bgPaint = Paint()
      ..color = background
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxR, bgPaint);

    const waves = 3;
    for (int i = 0; i < waves; i++) {
      final t = (progress + i / waves) % 1.0;
      final r = _lerp(maxR * 0.05, maxR, t);
      final a = (1.0 - t) * 0.6;
      final wavePaint = Paint()
        ..color = color.withOpacity(a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, r, wavePaint);
    }

    final sweep = math.pi / 6;
    final angle = progress * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: maxR);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + sweep,
        colors: [color.withOpacity(0.35), color.withOpacity(0.0)],
      ).createShader(rect);
    canvas.drawArc(rect, angle, sweep, true, sweepPaint);

    final dot = Paint()..color = color.withOpacity(0.9);
    canvas.drawCircle(center, 3, dot);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) {
    return old.progress != progress ||
        old.color != color ||
        old.background != background;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
