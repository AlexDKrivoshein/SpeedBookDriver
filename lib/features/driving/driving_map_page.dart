import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../location_service.dart';
import '../../driver_api.dart';
import '../../api_service.dart';

String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

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
  double _heading = 0;
  bool _loading = true;

  bool _followMe = true;
  bool _searching = true;
  bool _stopSent = false;       // уже дергали stop_driving
  bool _navigatedHome = false;  // уже ушли на home

  late final AnimationController _radarCtrl;
  BitmapDescriptor? _carIcon;

  Timer? _drivePollTimer;
  int? _driveId;
  Marker? _driverMarker;

  // ===== навигационный режим (добавлено) =====
  bool _navMode = false;     // включаем в pickup
  double _navZoom = 17.0;    // комфортный зум
  double _navTilt = 45.0;    // наклон камеры
  LatLng? _lastDriverPos;    // предыдущая позиция для bearing
  bool _actionBusy = false; // блокировка кнопок во время запроса


  // терминальные статусы, при которых прекращаем опрос
  static const Set<String> _terminalStatuses = {
    'DRIVE_CANCELLED_BY_CUSTOMER', 'DRIVE_CANCELLED_BY_DRIVER', 'DRIVE_FINISHED'
  };

  // оффер/маршрут
  Map<String, dynamic>? _offer;     // data из get_offers
  final Set<Polyline> _polylines = {};
  final Set<Marker> _offerMarkers = {};
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
    WidgetsBinding.instance.addObserver(this);

    LocationService.I.setDeniedForeverCallback(_onDeniedForever);

    _radarCtrl =
    AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCarIcon());

    _start();
  }

  // ---- Масштабируем PNG в рантайме под DPI ----
  Future<BitmapDescriptor> _bitmapFromAsset(
      String assetPath, int targetWidthPx) async {
    final data = await rootBundle.load(assetPath);
    final codec =
    await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: targetWidthPx);
    final fi = await codec.getNextFrame();
    final bytes = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadCarIcon() async {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const logicalWidth = 42.0;
    final px = (logicalWidth * dpr).round();
    final icon = await _bitmapFromAsset('assets/images/car.png', px);
    if (mounted) setState(() => _carIcon = icon);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    LocationService.I.setDeniedForeverCallback(null);
    _radarCtrl.dispose();
    _offerPolling = false;
    _callStopDriving(navigate: false);
    _stopDrivePolling();
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

    if (!LocationService.I.isRunning) {
      await LocationService.I.start(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        sendMinDistanceMeters: 25,
        sendMinInterval: const Duration(seconds: 10),
      );
    }

    final last = LocationService.I.lastKnownPosition;
    if (last != null) {
      _currentLatLng = LatLng(last.latitude, last.longitude);
      _heading = last.heading.isFinite ? last.heading : 0;
      if (mounted) setState(() {});
      await _tryStartDrivingOnce(last);
    }

    _positionSub?.cancel();
    _positionSub = LocationService.I.positions.listen((pos) async {
      _currentLatLng = LatLng(pos.latitude, pos.longitude);
      _heading = pos.heading.isFinite ? pos.heading : _heading;
      if (mounted) setState(() {});
      _maybeMoveCamera(_currentLatLng!);
      await _tryStartDrivingOnce(pos);
    });

    if (_searching && !_offerPolling) {
      _startOfferPolling();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _maybeMoveCamera(LatLng target, {bool animated = true}) async {
    if (!_controller.isCompleted || !_followMe) return;
    final map = await _controller.future;
    if (animated && !_preferLiteMode) {
      await map.animateCamera(CameraUpdate.newLatLng(target));
    } else {
      await map.moveCamera(CameraUpdate.newLatLng(target));
    }
  }

  /// Однократный вызов start_driving с координатами; при ошибке — возврат на главную
  Future<void> _tryStartDrivingOnce(Position pos) async {
    if (_startSent) return;

    final double? heading =
    (pos.heading.isFinite && pos.heading >= 0) ? (pos.heading % 360) : null;
    final double? accuracy =
    (pos.accuracy.isFinite && pos.accuracy > 0) ? pos.accuracy : null;

    try {
      final reply = await DriverApi.startDriving(
        lat: pos.latitude,
        lng: pos.longitude, // отправляем lng
        heading: heading,
        accuracy: accuracy,
      ).timeout(const Duration(seconds: 12));

      final status = (reply['status'] ?? '').toString();
      if (status != 'OK') {
        if (!mounted) return;
        final msg = reply['message']?.toString() ?? 'Start driving failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
        _goHome();
        return;
      }

      _startSent = true;
    } catch (_) {
      if (!mounted) return;
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
    while (mounted && _offerPolling && _searching && _offer == null) {
      try {
        final reply =
        await DriverApi.getOffers().timeout(const Duration(seconds: 10));

        // error: REQUEST_NOT FOUND -> сразу на главную
        final err = reply['error']?.toString();
        if (err == 'REQUEST_NOT FOUND') {
          if (!mounted) return;
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
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          if (data is Map) {
            final reqId = _asInt(data['request_id']);
            if (reqId > 0) {
              // нашли оффер
              _offer = Map<String, dynamic>.from(data as Map);
              _offerPolling = false;
              _searching = false;
              _radarCtrl.stop();

              final fromName    = _asString(data['from_name']);
              final fromDetails = _asString(data['from_details']);
              final toName      = _asString(data['to_name']);
              final toDetails   = _asString(data['to_details']);

              _buildOfferRoutePolyline(
                _asString(data['waypoint']),
                fromName: fromName,
                fromDetails: fromDetails,
                toName: toName,
                toDetails: toDetails,
              );

              if (mounted) {
                setState(() {});
                _showOfferSheet();
              }
              return;
            }
          }
        }

        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  void _buildOfferRoutePolyline(
      String? encoded, {
        required String fromName,
        required String fromDetails,
        required String toName,
        required String toDetails,
      }) async {
    _polylines.clear();
    _offerMarkers.clear();

    if (encoded == null || encoded.isEmpty) {
      setState(() {});
      return;
    }
    final pts = _decodePolyline(encoded);
    if (pts.isNotEmpty) {
      // линия маршрута
      _polylines.add(Polyline(
        polylineId: const PolylineId('offer_route'),
        points: pts,
        width: 5,
        color: Colors.blueAccent,
        geodesic: true,
      ));

      // маркеры начала/конца
      final start = pts.first;
      final end   = pts.last;
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

      // подвинем камеру — по границам маршрута
      try {
        final map = await _controller.future;
        final bounds = _computeBounds(pts);
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
      } catch (_) {
        await _maybeMoveCamera(start, animated: true);
      }
      setState(() {});
    }
  }

  LatLngBounds _computeBounds(List<LatLng> pts) {
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Google polyline decoder -> List<LatLng>
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
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

      if (navigate) {
        await _goHome(); // безопасная навигация (см. ниже)
      }
    }
  }
  // ========= UI =========

  void _showOfferSheet() {
    if (!mounted || _offer == null) return;
    final data = _offer!;
    final fromName    = _asString(data['from_name']);
    final fromDetails = _asString(data['from_details']);
    final toName      = _asString(data['to_name']);
    final toDetails   = _asString(data['to_details']);
    final distanceM   = _asNum(data['distance']);
    final durationStr = _formatDuration(_offer!['duration']); // форматировано
    final cost        = _asString(data['cost']);
    final currency    = _asString(data['currency']);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    const Icon(Icons.location_pin, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fromName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (fromDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fromDetails,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),

                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (toDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        toDetails,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _pill(icon: Icons.straighten, label: '${(distanceM / 1000).toStringAsFixed(1)} km'),
                    _pill(icon: Icons.schedule,   label: durationStr),
                    _pill(icon: Icons.payments,   label: '$cost $currency'),
                  ],
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _onDecline,
                        icon: const Icon(Icons.close),
                        label: Text(t(context, 'common.decline')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _onAccept,
                        icon: const Icon(Icons.check),
                        label: Text(t(context, 'common.ok')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ShapeDecoration(
        color: Colors.black.withOpacity(0.04),
        shape: const StadiumBorder(
          side: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _onAccept() async {
    if (_offer == null) return;
    final reqId  = _asInt(_offer!['request_id']);
    final driveId= _asInt(_offer!['drive_id']);
    try {
      final r = await DriverApi.acceptDrive(requestId: reqId, driveId: driveId)
          .timeout(const Duration(seconds: 10));
      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted) return;
        Navigator.of(context).pop(); // закрыть шит

        _driveId = driveId;
        _startDrivePolling();

      } else {
        if (!mounted) return;
        final msg = r['message']?.toString() ?? 'Accept failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    }
  }

  Future<void> _onDecline() async {
    if (_offer == null) return;
    final reqId  = _asInt(_offer!['request_id']);
    final driveId= _asInt(_offer!['drive_id']);
    try {
      final r = await DriverApi.declineDrive(requestId: reqId, driveId: driveId)
          .timeout(const Duration(seconds: 10));
      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted) return;
        Navigator.of(context).pop(); // закрыть шит
        _offer = null;
        _polylines.clear();
        _offerMarkers.clear();
        _searching = true;
        _radarCtrl.repeat();
        if (!_offerPolling) _startOfferPolling();
        setState(() {});
      } else {
        if (!mounted) return;
        final msg = r['message']?.toString() ?? 'Decline failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'common.error')}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    }
  }

  // ========= ПОЛЛИНГ ДЕТАЛЕЙ ПОЕЗДКИ =========

  void _startDrivePolling() {
    _stopDrivePolling(); // на всякий пожарный
    _drivePollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
      ).timeout(const Duration(seconds: 30));

      if (reply['status'] != 'OK') {
        debugPrint('[DrivePoll] bad status: $reply');
        return;
      }

      final data = reply['data'] as Map<String, dynamic>?;
      debugPrint('[DrivePoll] data: $data');
      if (data == null) return;

      _applyDriveDetails(data);
    } catch (e, st) {
      debugPrint('[DrivePoll] error: $e\n$st');
    }
  }

  Future<void> _goHome() async {
    if (!mounted || _navigatedHome) return;
    _navigatedHome = true;

    // Закрыть нижние листы/диалоги на корневом навигаторе
    final rootNav = Navigator.of(context, rootNavigator: true);

    // Небольшая пауза, чтобы закрытия отработали и контекст стабилизировался
    await Future.delayed(const Duration(milliseconds: 10));
    if (!mounted) return;

    // Полная замена стека на '/', даже если висит sheet/диалог
    rootNav.pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _applyDriveDetails(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toUpperCase();
    final driveId = data['drive_id'];
    if (driveId is int && _driveId != driveId) {
      _driveId = driveId;
    }

    if (status == 'DRIVE_CANCELLED_BY_CUSTOMER' && !_stopSent) {
      debugPrint('[DrivePoll] cancelled');
      _callStopDriving(); // fire-and-forget
    }

    // позиция машины из backend
    final pos = data['position'] as Map<String, dynamic>?;
    if (pos != null) {
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _updateDriverMarker(LatLng(lat, lng)); // рисуем иконку машины
      }
    }

    // маршрут к подхвату
    final pickup = data['pickup'] as Map<String, dynamic>?;
    if (pickup != null) {
      final enc = pickup['pickup_route']?.toString();
      if (enc != null && enc.isNotEmpty) {
        final pts = _decodePolyline(enc);
        _setPickupPolyline(pts);
      }
    }

    // === PICKUP MODE ===
    if (status == 'DRIVER_FOUND') {
      _enterPickupMode(); // убрать основной маршрут и маркеры оффера, включить навигацию
    }

    if (_terminalStatuses.contains(status)) {
      _stopDrivePolling();
    }

    setState(() {});
  }

  Future<void> _onArrivedPressed() async {
    final did = _driveId;
    if (did == null || _actionBusy) return;

    setState(() => _actionBusy = true);
    try {
      final r = await ApiService.callAndDecode('driver_arrived', {'drive_id': did})
          .timeout(const Duration(seconds: 15));

      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'driving.arrived_done'))),
        );
        // дальше едем по обычной логике — поллинг сам подхватит смену статуса
      } else {
        if (!mounted) return;
        final msg = r['message']?.toString() ?? 'Arrived failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _onStartDrivePressed() async {
    final did = _driveId;
    if (did == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final r = await ApiService.callAndDecode('start_drive', {'drive_id': did})
          .timeout(const Duration(seconds: 15));
      if ((r['status'] ?? '').toString() == 'OK') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'driving.started') /* или 'Drive started' */)),
        );
        // остаёмся в навигации; сервер начнёт отдавать следующий статус,
        // поллинг продолжает работать
      } else {
        if (!mounted) return;
        final msg = r['message']?.toString() ?? 'Start failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _onCancelDrivePressed() async {
    final did = _driveId;
    if (did == null || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final r = await ApiService.callAndDecode('cancel_drive', {'drive_id': did})
          .timeout(const Duration(seconds: 15));
      if ((r['status'] ?? '').toString() == 'OK') {
        // корректно завершаем локально, останавливаем поллинг и уходим на home
        await _callStopDriving(); // navigate=true по умолчанию (если ты добавил ранее)
      } else {
        if (!mounted) return;
        final msg = r['message']?.toString() ?? 'Cancel failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, "common.error")}: $msg')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.network_error'))),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _enterPickupMode() {
    setState(() {
      // скрыть офферные маркеры и основной маршрут
      _offer = null;            // оффер больше не нужен на экране
      _offerMarkers.clear();    // убрать точки from/to

      // оставить только линию 'pickup'
      const pickupId = PolylineId('pickup');
      _polylines.removeWhere((p) => p.polylineId != pickupId);

      // включаем навигацию (добавлено)
      _navMode = true;
      _followMe = true;
    });
  }

  // ========= Маркеры/полилинии =========

  void _updateDriverMarker(LatLng p) async {
    _lastDriverPos ??= p;

    final marker = Marker(
      markerId: const MarkerId('driver'),
      position: p,
      anchor: const Offset(0.5, 0.5),
      rotation: _heading, // визуальный поворот иконки (можно заменить на bearing)
      flat: true,
      icon: _carIcon ?? BitmapDescriptor.defaultMarker,
    );
    setState(() {
      _driverMarker = marker;
    });

    // в навигации — ведём камеру за машиной с поворотом по курсу
    if (_navMode) {
      final br = _computeBearing(_lastDriverPos!, p);
      await _moveNavCamera(p, bearing: br);
    }

    _lastDriverPos = p;
  }

  void _setPickupPolyline(List<LatLng> points) {
    const id = PolylineId('pickup');
    final poly = Polyline(
      polylineId: id,
      points: points,
      width: 6,
      geodesic: true,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );
    setState(() {
      _polylines
        ..removeWhere((p) => p.polylineId == id)
        ..add(poly);
    });
  }

  // ========= Утилиты навигации (добавлено) =========

  // курс из A в B в градусах 0..360
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
    if (!_controller.isCompleted) return;
    final map = await _controller.future;

    final usedBearing =
        bearing ?? (_lastDriverPos != null ? _computeBearing(_lastDriverPos!, pos) : _heading);

    final cam = CameraPosition(
      target: pos,
      zoom: _navZoom,
      tilt: _navTilt,
      bearing: usedBearing,
    );

    await map.animateCamera(CameraUpdate.newCameraPosition(cam));
  }

  // ---------- безопасные парсеры ----------
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  num _asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _asString(dynamic v) => v?.toString() ?? '';

  /// Превращаем interval/строку в "xh ym"
  String _formatDuration(dynamic raw) {
    // если число — считаем как секунды
    if (raw is num) return _fmtSeconds(raw.toInt());

    final s = _asString(raw).trim();
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
    final iso = RegExp(r'P(T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)', caseSensitive: false)
        .firstMatch(s);
    if (iso != null) {
      final h = int.tryParse(iso.group(2) ?? '') ?? 0;
      final mi = int.tryParse(iso.group(3) ?? '') ?? 0;
      return _fmtHM(h, mi);
    }

    // Postgres text "1 hour 20 mins"
    final pg = RegExp(r'(?:(\d+)\s*hour[s]?)?\s*(?:(\d+)\s*min)', caseSensitive: false)
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
    // объединяем маркеры: машина + оффер
    final Set<Marker> markers = {..._offerMarkers};

    if (_driverMarker != null) {
      markers.add(_driverMarker!);          // приоритет — серверная позиция машины
    } else if (_currentLatLng != null) {
      // fallback: локальная позиция устройства (как было)
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: _currentLatLng!,
        icon: _carIcon ?? BitmapDescriptor.defaultMarker,
        rotation: _heading,
        anchor: const Offset(0.5, 0.6),
        flat: true,
      ));
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, 'driving.title')),
        actions: [
          IconButton(
            tooltip: _searching ? 'Stop searching' : 'Start searching',
            onPressed: () {
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
              setState(() => _followMe = !_followMe);
              if (_followMe && _currentLatLng != null) {
                if (_navMode) {
                  await _moveNavCamera(_currentLatLng!);
                } else {
                  await _maybeMoveCamera(_currentLatLng!, animated: true);
                }
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
            myLocationEnabled: false,
            myLocationButtonEnabled: true,
            markers: markers,
            polylines: _polylines,
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
              if (_navMode) return; // в навигации не трогаем follow
              if (_followMe) setState(() => _followMe = false);
            },
          ),

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
                        background:
                        theme.colorScheme.primary.withOpacity(0.05),
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
                        t(context, 'driving.searching'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600),
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
          // === Pickup-Action Bar ===
          if (_navMode && _driveId != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // ARRIVED — слева (Filled)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _actionBusy ? null : _onArrivedPressed,
                        icon: const Icon(Icons.flag_circle),
                        label: Text(t(context, 'driving.arrived')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // CANCEL — справа (Outlined)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _actionBusy ? null : _onCancelDrivePressed,
                        icon: const Icon(Icons.close),
                        label: Text(t(context, 'driving.cancel_drive')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Center',
        onPressed: () async {
          if (_currentLatLng != null) {
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
