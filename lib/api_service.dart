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
import 'package:firebase_app_check/firebase_app_check.dart';

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

  static const MethodChannel _channel = MethodChannel('com.speedbook.taxidriver/config');

  static Map<String, String> _translations = {};        // сетевые переводы
  static Map<String, String> _translationsLocal = {};   // локальные из assets (prelogin)
  static bool _preloginLoaded = false;
  static String? _appSystemName;

  static Future<String?> _getAppCheckToken() async {
    if (!kReleaseMode) {
      return null;
    }

    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (e) {
      debugPrint('[ApiService] AppCheck token error: $e');
      return null;
    }
  }

  // ===== Проверка токена =====
  static Future<String> _ensureValidToken({bool validateOnline = false}) async {
    final prefs  = await SharedPreferences.getInstance();
    final token  = prefs.getString('token');
    final secret = prefs.getString('secret');

    debugPrint('[ApiService] Ensure token, validate: $validateOnline');
    debugPrint('[ApiService] Token: $token, secret: $secret');

    final missing = token == null || token.isEmpty || secret == null || secret.isEmpty;
    if (missing) {
      debugPrint('[ApiService] Token not found, validate: $validateOnline');
      if (validateOnline) {
        debugPrint('[ApiService] Handle invalid token');
        await _handleInvalidToken('Missing token or secret');
      }
      throw AuthException('Missing token or secret');
    }

    if (validateOnline) {
      final apiUrl = await _channel.invokeMethod<String>('getApiUrl');
      if (apiUrl == null) {
        await _handleInvalidToken('API URL not available');
      }

      final _appCheck = await _getAppCheckToken();

      final resp = await http.post(
        Uri.parse('$apiUrl/api/validate_token'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          if (_appCheck != null) 'X-Firebase-AppCheck': _appCheck,
        },
      );

      // 1) Проверяем HTTP-статус
      if (resp.statusCode != 200) {
        debugPrint('[ApiService] Token not valid! HTTP ${resp.statusCode}');
        await _handleInvalidToken('Token validation failed (HTTP ${resp.statusCode})');
      }

      // 2) Парсим JSON и требуем status == "OK"
      try {
        final dynamic parsed = jsonDecode(resp.body);
        if (parsed is! Map<String, dynamic>) {
          await _handleInvalidToken('Invalid validation response format');
        }
        final map = parsed as Map<String, dynamic>;
        final status = (map['status'] ?? '').toString().toUpperCase();

        if (status != 'OK') {
          // Достаём человекочитаемое сообщение
          String message =
          (map['message']?.toString() ?? '').trim();
          if (message.isEmpty) {
            final data = map['data'];
            if (data is Map<String, dynamic>) {
              message = (data['message']?.toString() ??
                  data['error']?.toString() ??
                  '').trim();
            }
          }
          if (message.isEmpty) {
            message = (map['error']?.toString() ?? 'Token validation failed').trim();
          }

          debugPrint('[ApiService] Token not valid! status=$status, message="$message"');
          await _handleInvalidToken(message);
        } else {
          debugPrint('[ApiService] Token valid (status=OK)');
        }
      } catch (e) {
        debugPrint('[ApiService] Token validation parse error: $e');
        await _handleInvalidToken('Token validation parse error');
      }
    }

    return token!;
  }

  static Future<Map<String, dynamic>> checkTokenOnline({bool validateOnline = true}) async {

    debugPrint('[ApiService] Check token, validate: $validateOnline');
    await _ensureValidToken(validateOnline: validateOnline);

    if (!validateOnline) return {};

    final decoded = await callAndDecode('check_customer', const {}, validateOnline: true);

    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid check_customer response');
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
    final _appCheck = await _getAppCheckToken();

    final apiUrl = await _channel.invokeMethod<String>('getApiUrl');
    if (apiUrl == null) {
      throw StateError('API URL not available');
    }

    final jwt = JWT(body).sign(SecretKey(secret));
    final url = Uri.parse('$apiUrl/mapi/$apiName');

    debugPrint('[ApiService] call url: $url');

    http.Response? response;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        response = await http
            .post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            if (_appCheck != null) 'X-Firebase-AppCheck': _appCheck,
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

  static bool _logMissingTranslations = true;

  static String getTranslation(String widgetName, String key) {
    // 1) локальные prelogin
    final vLocal = _translationsLocal[key];
    if (vLocal != null) return vLocal;

    // 2) сетевые переводы
    final vNet = _translations[key];
    if (vNet != null) return vNet;
/*
    _getAppSystemName().then((module) async {
      try {
        await callPlain('add_translation', {
          'module': module,
          'widget_name': widgetName,
          'key': key,
        }, validateOnline: false);
      } catch (_) {}
    }).catchError((_) {});
*/
    if (_logMissingTranslations) {
      // один раз на ключ (не заспамить логи)
      _missingKeys ??= <String>{};
      if (_missingKeys!.add(key)) {
        debugPrint('[i18n] missing: "$key" (widget: $widgetName)');
      }
    }
    return key;
  }

  static Set<String>? _missingKeys;

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

  static Future<void> switchLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_lang', lang.toLowerCase());

    _preloginLoaded = false;

    await loadPreloginTranslations(lang: lang);
  }

  /// Safe int parser: int | num | "123" -> int, иначе 0
  static int asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
    // если где-то нужно отличать отсутствие от 0 — можно сделать asIntOrNull
  }

  /// Safe bool parser: bool | 1/0 | "true"/"1"/"yes" -> bool
  static bool asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v?.toString() ?? '').trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  // (опционально, если тебе часто нужно)
  static num asNum(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String asString(dynamic v) => v?.toString() ?? '';

}

