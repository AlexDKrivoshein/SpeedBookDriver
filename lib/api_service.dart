import 'dart:convert';
import 'dart:async';
import 'dart:io'; // SocketException
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart'; // MethodChannel, rootBundle
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models/create_route_result.dart';
import 'models/vehicle_type.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

class ApiService {
  static void Function()? onAuthFailed;

  // ==== сетевые ретраи ====
  static const int _maxAttempts = 5;
  static const int _timeoutSeconds = 8;

  static bool _isTransient(Object e) =>
      e is SocketException || e is TimeoutException;

  /// Ретрай по 429 и любым 5xx
  static bool _shouldRetryStatus(int code) =>
      code == 429 || (code >= 500 && code < 600);

  /// 300,600,900,1200,1500 (макс ~2s)
  static Duration _retryDelay(int attempt) {
    final ms = 300 * (attempt + 1);
    return Duration(milliseconds: ms > 2000 ? 2000 : ms);
  }

  static void setOnAuthFailed(void Function() callback) {
    onAuthFailed = callback;
  }

  // ==== каналы/переводы/состояние ====
  static const MethodChannel _channel = MethodChannel('com.speedbook.taxi/config');

  static Map<String, String> _translations = {};        // сетевые переводы
  static Map<String, String> _translationsLocal = {};   // локальные из assets (prelogin)
  static bool _translationsLoaded = false;
  static bool _loadingTranslationsNow = false;
  static bool _preloginLoaded = false;
  static String? _appSystemName;

  // ===== Проверка токена =====
  static Future<String> _ensureValidToken({bool validateOnline = false}) async {
    final prefs  = await SharedPreferences.getInstance();
    final token  = prefs.getString('token');
    final secret = prefs.getString('secret');

    //debugPrint('[ApiService] Ensure token');

    final missing = token == null || token.isEmpty || secret == null || secret.isEmpty;
    if (missing) {
      // В «мягком» режиме(по умолчанию) не вызываем onAuthFailed, чтобы не зациклиться (например, при загрузке переводов)
      if (validateOnline) {
        await _handleInvalidToken('Missing token or secret');
      }
      throw AuthException('Missing token or secret');
    }

    if (validateOnline) {
      final apiUrl = await _channel.invokeMethod<String>('getApiUrl');
      if (apiUrl == null) {
        await _handleInvalidToken('API URL not available');
      }
      final resp = await http.post(
        Uri.parse('$apiUrl/mapi/auth/check_token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode != 200) {
        await _handleInvalidToken('Token validation failed');
      }
    }
    return token!;
  }

  static Future<Map<String, dynamic>> checkTokenOnline({bool validateOnline = true}) async {
    // Локальная проверка
    await _ensureValidToken(validateOnline: false);
    //debugPrint('[ApiService] Check token');

    if (!validateOnline) return {};

    // Через общий слой (ретраи+timeout)
    final decoded = await callPlain('auth/check_token', const {}, validateOnline: true);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid /auth/check_token response');
    }
    return decoded;
  }

  static Future<void> _handleInvalidToken(String reason) async {
    debugPrint('[ApiService] Invalid token: $reason');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('secret');
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (onAuthFailed != null) {
      try {
        onAuthFailed!();
      } catch (e) {
        debugPrint('[ApiService] onAuthFailed callback error: $e');
      }
    }
    throw AuthException(reason);
  }

  static Future<String> _getAppSystemName() async {
    if (_appSystemName != null) return _appSystemName!;
    final info = await PackageInfo.fromPlatform();
    _appSystemName = info.packageName;
    return _appSystemName!;
  }

  // ==== общий вызов c JWT и ретраями ====
  static Future<http.Response> call(
      String apiName,
      Map<String, dynamic> body, {
        bool validateOnline = false,
      }) async {
    final prefs = await SharedPreferences.getInstance();
    final token  = await _ensureValidToken(validateOnline: validateOnline);
    final secret = prefs.getString('secret')!;

    final apiUrl = await _channel.invokeMethod<String>('getApiUrl');
    if (apiUrl == null) {
      throw StateError('API URL not available');
    }

    final jwt = JWT(body).sign(SecretKey(secret));
    final url = Uri.parse('$apiUrl/mapi/$apiName');

    http.Response? response;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        response = await http
            .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'jwt': jwt}),
        )
            .timeout(Duration(seconds: _timeoutSeconds));

        if (response.statusCode == 200) break;

        if (_shouldRetryStatus(response.statusCode) && attempt < _maxAttempts - 1) {
          await Future.delayed(_retryDelay(attempt));
          continue;
        }
        throw StateError('HTTP ${response.statusCode}');
      } on TimeoutException catch (_) {
        if (attempt == _maxAttempts - 1) rethrow;
        await Future.delayed(_retryDelay(attempt));
      } on SocketException catch (_) {
        if (attempt == _maxAttempts - 1) rethrow;
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (response == null || response.statusCode != 200) {
      throw StateError('Connection ERROR');
    }
    return response;
  }

  // ==== вызов без JWT, с ретраями ====
  static Future<Map<String, dynamic>> callPlain(
      String apiName,
      Map<String, dynamic> body, {
        bool validateOnline = false,
      }) async {
    final token  = await _ensureValidToken(validateOnline: validateOnline);

    final apiUrl = await _channel.invokeMethod<String>('getApiUrl');
    if (apiUrl == null) {
      throw StateError('API URL not available');
    }

    final url = Uri.parse('$apiUrl/mapi/$apiName');

    http.Response? resp;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        resp = await http
            .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
            .timeout(Duration(seconds: _timeoutSeconds));

        if (resp.statusCode == 200) break;

        if (_shouldRetryStatus(resp.statusCode) && attempt < _maxAttempts - 1) {
          await Future.delayed(_retryDelay(attempt));
          continue;
        }
        throw StateError('HTTP ${resp.statusCode}');
      } on TimeoutException catch (_) {
        if (attempt == _maxAttempts - 1) rethrow;
        await Future.delayed(_retryDelay(attempt));
      } on SocketException catch (_) {
        if (attempt == _maxAttempts - 1) rethrow;
        await Future.delayed(_retryDelay(attempt));
      }
    }

    if (resp == null || resp.statusCode != 200) {
      throw StateError('Connection ERROR');
    }

    final dynamic parsed = jsonDecode(resp.body);
    if (parsed is! Map<String, dynamic>) {
      throw StateError('Invalid response format');
    }
    return parsed;
  }

  // ==== call + decode JWT-полезной нагрузки ====
  static Future<Map<String, dynamic>> callAndDecode(
      String apiName,
      Map<String, dynamic> body, {
        Future<http.Response> Function(String apiName, Map<String, dynamic> body)? caller,
        bool validateOnline = false,
      }) async {
    final response = await (caller ??
        ((name, data) => call(name, data, validateOnline: validateOnline)))(apiName, body);

    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }

    final dynamic parsed = jsonDecode(response.body);
    if (parsed is! Map<String, dynamic>) {
      throw StateError('Invalid response format');
    }
    if (parsed['status'] != 'OK') {
      throw StateError("Unexpected status: ${parsed['status']}");
    }

    final jwtStr = parsed['data']?['jwt'];
    if (jwtStr is! String) {
      throw StateError('JWT not found in response');
    }

    final prefs  = await SharedPreferences.getInstance();
    final secret = prefs.getString('secret');
    if (secret == null) {
      throw StateError('Secret not available');
    }

    final jwt = JWT.verify(jwtStr, SecretKey(secret));
    final payload = jwt.payload;
    if (payload is Map<String, dynamic>) {
      return payload;
    } else {
      return {'data': payload};
    }
  }

  // ==== prelogin-переводы из assets ====
  static Future<void> loadPreloginTranslations({String? lang}) async {
    if (_preloginLoaded) return;
    _preloginLoaded = true;

    final prefs  = await SharedPreferences.getInstance();
    final saved  = prefs.getString('user_lang');
    final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final code   = (lang ?? saved ?? system).toLowerCase();
    final normalized = (code == 'ru' || code == 'km' || code == 'en') ? code : 'en';

    final path = 'assets/i18n/prelogin.$normalized.json';
    try {
      final raw = await rootBundle.loadString(path);
      final Map<String, dynamic> map = jsonDecode(raw);
      _translationsLocal = map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      debugPrint('[ApiService] prelogin translations not found for $normalized: $e');
      _translationsLocal = {};
    }
  }

  // ==== сетевые переводы (после логина) ====
  static Future<void> loadTranslations({String? lang}) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) поднимаем кэш
    final cached = prefs.getString('translations_cache_${lang ?? 'default'}');
    if (cached != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cached);
        _translations = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    // 2) нет токена/секрета — не лезем в сеть (разрыв циклов до авторизации)
    final hasToken  = (prefs.getString('token')  ?? '').isNotEmpty;
    final hasSecret = (prefs.getString('secret') ?? '').isNotEmpty;
    if (!hasToken || !hasSecret) {
      _translationsLoaded = true;
      return;
    }

    // 3) anti-reentry
    if (_loadingTranslationsNow) { _translationsLoaded = true; return; }
    _loadingTranslationsNow = true;

    try {
      final module  = await _getAppSystemName();
      final payload = <String, dynamic>{'module': module};
      if (lang != null) payload['lang'] = lang;

      final decodedJson  = await callPlain('get_translations', payload);
      final translations = decodedJson['data'];

      if (translations is Map<String, dynamic>) {
        _translations = translations.map((k, v) => MapEntry(k.toString(), v.toString()));
        await prefs.setString('translations_cache_${lang ?? 'default'}', jsonEncode(_translations));
      } else if (translations is List) {
        final Map<String, String> map = {};
        for (final item in translations) {
          if (item is Map && item['key'] != null && item['value'] != null) {
            map[item['key'].toString()] = item['value'].toString();
          }
        }
        if (map.isNotEmpty) {
          _translations = map;
          await prefs.setString('translations_cache_${lang ?? 'default'}', jsonEncode(_translations));
        } else {
          await prefs.remove('translations_cache_${lang ?? 'default'}');
        }
      }
    } catch (e) {
      debugPrint('Failed to load translations: $e');
    } finally {
      _loadingTranslationsNow = false;
      _translationsLoaded = true;
    }
  }

  static String getTranslation(String widgetName, String key) {
    // 1) локальные prelogin
    final vLocal = _translationsLocal[key];
    if (vLocal != null) return vLocal;

    // 2) сетевые переводы
    final vNet = _translations[key];
    if (vNet != null) return vNet;

    // 3) авто-регистрация ключа на бэке — пробуем мягко (может выбросить AuthException до логина)
    _getAppSystemName().then((module) async {
      try {
        await callPlain('add_translation', {
          'module': module,
          'widget_name': widgetName,
          'key': key,
        }, validateOnline: false);
      } catch (_) {}
    }).catchError((_) {});

    return key;
  }

  static String getTranslationForWidget(BuildContext context, String key) {
    final widgetName = context.widget.runtimeType.toString();
    return getTranslation(widgetName, key);
  }

  // ==== логи ====
  static Future<void> sendLog(
      String type,
      String message, {
        BuildContext? context,
        String? widgetName,
      }) async {
    try {
      final data = {'type': type, 'message': message};
      if (widgetName != null) {
        data['widget_name'] = widgetName;
      } else if (context != null) {
        data['widget_name'] = context.widget.runtimeType.toString();
      }
      await callAndDecode('send_log', data);
    } catch (e) {
      debugPrint('Failed to send log: $e');
    }
    if (kDebugMode) {
      debugPrint("$type: $message");
    }
    if (type.toUpperCase() == "ERROR" && context != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ==== локация ====
  static Future<void> setCurrentLocation(double lat, double lng) async {
    debugPrint('Sending location');
    await callAndDecode('send_current_location', {
      'lat': lat,
      'lng': lng,
    });
  }

  // ==== поиск мест ====
  static Future<Map<String, dynamic>> searchPlace(String query, {bool isFinal = false, int? placeId}) async {
    const int maxAttempts = 5;
    int attempt = 0;

    Map<String, dynamic> parsePlace(dynamic item) {
      if (item is! Map) throw StateError('Invalid place entry');
      final placeId = item['id'];
      final lat = item['lat'];
      final lng = item['lng'];
      final name = item['name'];
      if (placeId is! int || lat is! num || lng is! num || name is! String) {
        throw StateError('Invalid place data');
      }
      return {
        'place_id': placeId,
        'lat': (lat as num).toDouble(),
        'lng': (lng as num).toDouble(),
        'name': name,
      };
    }

    while (attempt < maxAttempts) {
      final reply = await callAndDecode('search_place', {
        'query': query,
        'final': isFinal,
        if (placeId != null) 'place_id': placeId,
      });

      if (reply['status'] != 'OK') {
        throw StateError("Unexpected status: ${reply['status']}");
      }

      final data   = reply['data'];
      final count  = data['count'];
      final places = data['places'];

      if (count is int && count > 0) {
        if (places is! List) throw StateError('Invalid "places" list');
        return {'count': count, 'places': places.map(parsePlace).toList()};
      } else if (count is int && count == 0) {
        return {'count': 0, 'places': null};
      }

      attempt++;
      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return {'count': 0, 'places': null};
  }

  /// add_customer_place: регистрирует точку клиента и возвращает found/name/details
  static Future<Map<String, dynamic>> addCustomerPlace(double lat, double lng, {int? placeId}) async {
    final reply = await callAndDecode('add_customer_place', {
      'lat': lat,
      'lng': lng,
      if (placeId != null) 'place_id': placeId,
    });

    if (reply['status'] != 'OK') {
      throw StateError("Unexpected status: ${reply['status']}");
    }

    final data = reply['data'];
    if (data is! Map) {
      throw StateError('Invalid response data');
    }

    final found   = data['found'];
    final name    = data['name'];
    final details = data['details'];
    final pid     = data['place_id'];

    if (found is! int) {
      throw StateError('Invalid "found" field');
    }

    return {
      'found': found,
      'name': name is String ? name : null,
      'details': details is String ? details : null,
      'place_id': pid is int ? pid : (pid is String ? int.tryParse(pid) : null),
    };
  }

  /// Повтор до 3 раз, если found < 0
  static Future<Map<String, dynamic>> addCustomerPlaceWithRetry(
      double lat, double lng, {
        int? placeId,
        int maxExtraAttempts = 3,
      }) async {
    int attempt = 0;

    Map<String, dynamic> result = await addCustomerPlace(lat, lng, placeId: placeId);
    int found = result['found'] as int;

    while (found < 0 && attempt < maxExtraAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      result = await addCustomerPlace(lat, lng, placeId: placeId);
      found = result['found'] as int;
      attempt++;
    }
    return result;
  }

  // ==== Маршруты ====
  static Future<CreateRouteResult> createRoute({
    required int currentPlaceId,
    required int destinationPlaceId,
  }) async {
    try {
      final reply = await callAndDecode('create_route', {
        'current': currentPlaceId,
        'destination': destinationPlaceId,
      });

      debugPrint('[ApiService] Create route reply: $reply');

      final statusId = (reply['status_id'] as String? ?? reply['status'] as String? ?? '').toUpperCase();
      if (statusId != 'OK') {
        final err = reply['error']?.toString();
        return CreateRouteResult(statusId: statusId.isEmpty ? 'ERROR' : statusId, errorMessage: err);
      }

      final data = reply['data'];

      int? routeId;
      final r = data['route_id'];
      if (r is int) routeId = r; else if (r is String) routeId = int.tryParse(r);

      final List<VehicleType> vehicleTypes = (data['vehicle_types'] is List)
          ? (data['vehicle_types'] as List)
          .whereType<Map>()
          .map((e) => VehicleType(
        name: e['name']?.toString() ?? '',
        memo: e['memo']?.toString() ?? '',
      ))
          .toList()
          : const <VehicleType>[];

      return CreateRouteResult(statusId: 'OK', routeId: routeId, vehicleTypes: vehicleTypes);
    } catch (e) {
      return CreateRouteResult(statusId: 'ERROR', errorMessage: e.toString());
    }
  }

  /// Детали маршрута
  static Future<Map<String, dynamic>> getRouteDetails(int routeId) async {
    final reply = await callAndDecode('get_route_details', {'route_id': routeId});

    final statusId = (reply['status_id'] as String? ?? reply['status'] as String? ?? 'OK').toUpperCase();
    if (statusId != 'OK') {
      final err = reply['error']?.toString();
      throw StateError('get_route_details status: $statusId ${err ?? ""}'.trim());
    }

    final data = reply['data'];
    if (data is! Map) throw StateError('Invalid get_route_details.data');

    int waypoint = _asInt(data['waypoint']) ?? 0;
    int distance = _asInt(data['distance']) ?? 0;
    int duration = _asInt(data['duration']) ?? 0;
    String currency = data['currency'].toString();

    final String? encodedPolylineRaw = (data['encodedPolyline'] ?? data['encoded_polyline'])?.toString();

    final List<Map<String, dynamic>> vehicles = [];
    final vv = data['vehicles'];
    if (vv is List) {
      for (final it in vv) {
        if (it is Map) {
          final key  = it['key']?.toString();
          final name = it['name']?.toString();
          final cost = _asInt(it['cost']) ?? 0;
          if ((key ?? '').isNotEmpty && (name ?? '').isNotEmpty) {
            vehicles.add({'key': key, 'name': name, 'cost': cost});
          }
        }
      }
    }

    return {
      'waypoint': waypoint,
      'distance': distance,
      'duration': duration,
      'encodedPolyline': encodedPolylineRaw ?? '',
      'vehicles': vehicles,
      'currency': currency,
    };
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ==== История мест ====
  static Future<Map<String, dynamic>> getLastPlaces({
    required int months,
    int limit = 20,
    int offset = 0,
    int? skipPlaceId,
  }) async {
    if (months <= 0) throw ArgumentError.value(months, 'months', 'months must be > 0');
    if (limit  <  0) throw ArgumentError.value(limit,  'limit',  'limit must be >= 0');
    if (offset <  0) throw ArgumentError.value(offset, 'offset', 'offset must be >= 0');

    final reply = await callAndDecode('get_last_places', {
      'months': months,
      'limit': limit,
      'offset': offset,
      if (skipPlaceId != null) 'skip_place_id': skipPlaceId,
    });

    final status = (reply['status']?.toString() ?? reply['status_id']?.toString() ?? 'OK').toUpperCase();
    if (status != 'OK') {
      final err = reply['error']?.toString();
      throw StateError("get_last_places status: $status ${err ?? ''}".trim());
    }

    final data = reply['data'];
    List placesList = const [];
    int? count;

    if (data is Map) {
      final rawPlaces = data['places'] ?? data['items'] ?? data['data'];
      if (rawPlaces is List) placesList = rawPlaces;
      final rawCount = data['count'] ?? data['total'] ?? data['total_count'];
      if (rawCount is int) count = rawCount;
      if (rawCount is String) count = int.tryParse(rawCount);
    } else if (data is List) {
      placesList = data;
    }

    final List<Map<String, dynamic>> places = [];
    for (final item in placesList) {
      if (item is Map) {
        final pid     = item['id'] ?? item['place_id'];
        final lat     = item['lat'];
        final lng     = item['lng'];
        final name    = item['name'] ?? item['title'] ?? item['label'];
        final details = item['details'] ?? item['subtitle'] ?? item['address'];

        int? placeId;
        if (pid is int) placeId = pid; else if (pid is String) placeId = int.tryParse(pid);

        if (skipPlaceId != null && placeId != null && placeId == skipPlaceId) {
          continue;
        }

        double? dlat, dlng;
        if (lat is num) dlat = lat.toDouble();
        if (lng is num) dlng = lng.toDouble();

        if (dlat != null && dlng != null && name is String) {
          places.add({
            'place_id': placeId,
            'lat': dlat,
            'lng': dlng,
            'name': name,
            if (details is String) 'details': details,
          });
        }
      }
    }

    count ??= places.length;
    return {'count': count, 'places': places};
  }

  // ==== Поездка ====
  static Future<Map<String, dynamic>> createDrive({
    required int routeId,
    required String vehicleType,
    required String paymentType, // CASH|CARD
  }) async {
    final reply = await callAndDecode('create_drive', {
      'route_id': routeId,
      'vehicle_type': vehicleType,
      'payment_type': paymentType.toUpperCase(),
    });
    final status = (reply['status']?.toString() ?? reply['status_id']?.toString() ?? 'OK').toUpperCase();
    if (status != 'OK') {
      final err = reply['error']?.toString();
      throw StateError("create_drive status: $status ${err ?? ""}".trim());
    }
    final data = reply['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return {'data': data};
  }

  static Future<Map<String, dynamic>> getDriveDetails({required int driveId}) async {
    final reply = await callAndDecode('get_drive_details', {'drive_id': driveId});
    final status = (reply['status']?.toString() ?? reply['status_id']?.toString() ?? 'OK').toUpperCase();
    if (status != 'OK') {
      final err = reply['error']?.toString();
      throw StateError("get_drive_details status: $status ${err ?? ""}".trim());
    }
    final data = reply['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return {'data': data};
  }

  static Future<Map<String, dynamic>> cancelDrive({required int driveId}) async {
    final reply = await callAndDecode('cancel_drive', {'drive_id': driveId});
    final status = (reply['status']?.toString() ?? reply['status_id']?.toString() ?? 'OK').toUpperCase();
    if (status != 'OK') {
      final err = reply['error']?.toString();
      throw StateError("cancel_drive status: $status ${err ?? ""}".trim());
    }
    final data = reply['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return {'data': data};
  }

  // Сменить язык приложения: сохранить, перезагрузить локальные prelogin и сетевые переводы
  static Future<void> switchLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_lang', lang.toLowerCase());

    _preloginLoaded = false;

    // безопасно: загрузим локальные и сетевые переводы под новый язык
    await loadPreloginTranslations(lang: lang);
    await loadTranslations(lang: lang);
  }
}
