// lib/driver_api.dart
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'dart:convert';

class DriverAccount {
  final String? id;
  final String name;
  final String currency;
  final double balance;
  final bool isMain;

  DriverAccount({
    this.id,
    required this.name,
    required this.currency,
    required this.balance,
    this.isMain = false,
  });

  factory DriverAccount.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final type = json['type']?.toString().toLowerCase();
    final idRaw = json['id'] ?? json['account_id'] ?? json['my_account_id'];
    return DriverAccount(
      id: idRaw?.toString(),
      name: name,
      currency: json['currency']?.toString() ?? '',
      balance: (json['balance'] is num)
          ? (json['balance'] as num).toDouble()
          : double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
      isMain: json['is_main'] == true ||
          json['main'] == true ||
          type == 'main' ||
          name.toLowerCase().contains('main'),
    );
  }
}

class DriverDetails {
  final String id;
  final String name;
  final String driverClass;
  final String rating;
  final List<DriverAccount> accounts;
  final String? rejectionReason;
  final String? referal;
  final bool canAddReferal;
  final int? carId;
  final String? number;
  final String? brand;
  final String? model;
  final String? color;
  final String? vehicleType;
  final String? carClass;
  final String? carReason;
  final int? currentDrive;

  DriverDetails({
    required this.id,
    required this.name,
    required this.driverClass,
    required this.rating,
    required this.accounts,
    this.rejectionReason,
    required this.referal,
    this.canAddReferal = false,
    this.carId,
    this.number,
    this.brand,
    this.model,
    this.color,
    this.vehicleType,
    this.carClass,
    this.carReason,
    this.currentDrive,
  });

  factory DriverDetails.fromJson(Map<String, dynamic> json) {
    // ответ может быть сразу payload или обёртка { data: {...} }
    final root = (json['data'] is Map<String, dynamic>) ? json['data'] : json;

    debugPrint('[DriverApi] get_driver_details: $root');

    final dynamic accAny = root['account'] ?? root['accounts'];
    final accList = (accAny is List)
        ? accAny.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];

    return DriverDetails(
      id: root['id']?.toString() ?? '',
      name: root['name']?.toString() ?? '',
      driverClass: root['class']?.toString() ?? '',
      rating: root['rating']?.toString() ?? '',
      accounts: accList.map((m) => DriverAccount.fromJson(m)).toList(),
      rejectionReason: root['reason']?.toString(),
      referal: root['referal']?.toString(),
      canAddReferal: root['can_add_referal'] == true,
      carId: root['car_id'],
      number: root['number'],
      brand: root['brand'],
      model: root['model'],
      color: root['color'],
      vehicleType: root['vehicle_type'],
      carClass: root['car_class'],
      carReason: root['car_reason'],
      currentDrive: root['current_drive_id'],
    );
  }
}

class DriverTransaction {
  final DateTime date;
  final String type;
  final String currency;
  final String service;
  final double amount;
  final String description;
  final double commission;
  final double total;

  DriverTransaction({
    required this.date,
    required this.type,
    required this.currency,
    required this.service,
    required this.amount,
    required this.description,
    required this.commission,
    required this.total,
  });

  factory DriverTransaction.fromJson(Map<String, dynamic> j) {
    DateTime _parseDate(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is num) {
        final ms = v > 1e12 ? v.toInt() : (v * 1000).toInt();
        return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      }
      if (v is String) {
        // ISO-8601 или числовая строка
        final s = v.trim();
        final asNum = double.tryParse(s);
        if (asNum != null) {
          final ms = asNum > 1e12 ? asNum.toInt() : (asNum * 1000).toInt();
          return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
        }
        try {
          return DateTime.parse(s).toLocal();
        } catch (_) {}
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    double _toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
      return 0.0;
    }

    return DriverTransaction(
      date: _parseDate(j['date']),
      type: (j['type'] ?? '').toString(),
      currency: (j['currency'] ?? '').toString(),
      service: (j['service'] ?? '').toString(),
      amount: _toDouble(j['amount']),
      description: (j['description'] ?? '').toString(),
      commission: _toDouble(j['commission']),
      total: _toDouble(j['total']),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'type': type,
        'currency': currency,
        'service': service,
        'amount': amount,
        'description': description,
        'commission': commission,
        'total': total,
      };
}

class DriverDriveHistory {
  final int id;
  final double cost;
  final String currency;
  final int distance;
  final double overprice;
  final DateTime? date;
  final DateTime? started;
  final DateTime? ended;

  DriverDriveHistory({
    required this.id,
    required this.cost,
    required this.currency,
    required this.distance,
    required this.overprice,
    required this.date,
    required this.started,
    required this.ended,
  });

  factory DriverDriveHistory.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return null;
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return null;
      }
    }

    double parseDouble(dynamic v) =>
        double.tryParse((v ?? '0').toString()) ?? 0.0;

    return DriverDriveHistory(
      id: (json['id'] is int)
          ? json['id'] as int
          : int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      cost: parseDouble(json['cost']),
      currency: (json['currency'] ?? '').toString(),
      distance: (json['distance'] is int)
          ? json['distance'] as int
          : int.tryParse((json['distance'] ?? '0').toString()) ?? 0,
      overprice: parseDouble(json['overprice']),
      date: parseDt(json['date']),
      started: parseDt(json['started']),
      ended: parseDt(json['ended']),
    );
  }
}

class CarModel {
  final int id;
  final String name;
  CarModel({required this.id, required this.name});
  factory CarModel.fromJson(Map<String, dynamic> j) => CarModel(
      id: (j['id'] as num).toInt(), name: (j['name'] ?? '').toString());
}

class CarBrand {
  final int id;
  final String name;
  final List<CarModel> models;
  CarBrand({required this.id, required this.name, required this.models});
  factory CarBrand.fromJson(Map<String, dynamic> j) {
    final ms = (j['models'] is List)
        ? (j['models'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CarModel.fromJson)
            .toList()
        : <CarModel>[];
    return CarBrand(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
      models: ms,
    );
  }
}

class CarType {
  final int id;
  final String name;
  final List<CarBrand> brands;
  CarType({required this.id, required this.name, required this.brands});
  factory CarType.fromJson(Map<String, dynamic> j) {
    final bs = (j['brands'] is List)
        ? (j['brands'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CarBrand.fromJson)
            .toList()
        : <CarBrand>[];
    return CarType(
      id: (j['id'] as num).toInt(),
      name: (j['name'] ?? '').toString(),
      brands: bs,
    );
  }
}

class CarColor {
  final String hex;
  final String name;
  CarColor({required this.hex, required this.name});
  factory CarColor.fromJson(Map<String, dynamic> j) => CarColor(
      hex: (j['hex'] ?? '#000000').toString(),
      name: (j['name'] ?? '').toString());
}

class VerificationPreData {
  final List<CarType> cars;
  final List<CarColor> colors;
  VerificationPreData({required this.cars, required this.colors});
  factory VerificationPreData.fromJson(Map<String, dynamic> json) {
    final root = (json['data'] is Map<String, dynamic>) ? json['data'] : json;
    final types = (root['cars'] is List)
        ? (root['cars'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CarType.fromJson)
            .toList()
        : <CarType>[];
    final cols = (root['colors'] is List)
        ? (root['colors'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CarColor.fromJson)
            .toList()
        : <CarColor>[];
    return VerificationPreData(cars: types, colors: cols);
  }
}

class CarDocUpload {
  final String filename;
  final String base64; // содержимое файла в base64
  final String mime; // 'image/jpeg'/'image/png'
  CarDocUpload(
      {required this.filename, required this.base64, required this.mime});

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'content_base64': base64,
        'mime': mime,
      };
}

class DriverApi {
  /// Возвращает подробности водителя (JWT-полезная нагрузка)
  static Future<DriverDetails> getDriverDetails() async {
    debugPrint('[DriverApi] get_driver_details');
    final payload =
        await ApiService.callAndDecode('get_driver_details', const {});
    return DriverDetails.fromJson(payload);
  }

  /// Получить настройки водителя (JWT-полезная нагрузка: payout_account, status)
  static Future<Map<String, dynamic>> getDriverSettings({
    bool onlyConfirmed = false,
  }) async {
    debugPrint('[DriverApi] get_driver_settings');
    final payload = await ApiService.callAndDecode(
      'get_driver_settings',
      {'only_confirmed': onlyConfirmed},
    );
    return payload;
  }

  /// Сохранить настройки водителя
  static Future<void> setDriverSettings({
    required String payoutAccount,
  }) async {
    await ApiService.callAndDecode('set_driver_settings', {
      'payout_account': payoutAccount,
    });
  }

  /// Установка реферала. Возвращает {status, message?}
  static Future<Map<String, dynamic>> setReferal(String referalId) async {
    final res =
        await ApiService.callAndDecode('set_referal', {'referal': referalId});
    // ожидаем {status: 'OK'|'ERROR', message?: '...'}
    return res;
  }

  /// Получить список транзакций водителя
  static Future<List<DriverTransaction>> getDriverTransactions({
    DateTime? from, // опциональные фильтры
    DateTime? to,
    int? limit,
    int? offset,
  }) async {
    final payload = <String, dynamic>{
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
    };

    dynamic res;
    try {
      res = await ApiService.callAndDecode('get_driver_transactions', payload);
    } catch (e, st) {
      debugPrint('[DriverApi] get_driver_transactions call failed: $e\n$st');
      rethrow;
    }

    // Универсальный извлекатель списка транзакций
    List<Map<String, dynamic>> _extractList(dynamic x) {
      if (x == null) return const <Map<String, dynamic>>[];

      // Если сразу пришёл список
      if (x is List) {
        return x.whereType<Map<String, dynamic>>().toList();
      }

      if (x is Map) {
        // Если сервер завернул в статус
        final status = x['status']?.toString().toUpperCase();
        if (status == 'ERROR') {
          final msg = x['message'] ?? x['error'] ?? 'unknown_error';
          throw Exception('get_driver_transactions: $msg');
        }

        // Частые ключи
        final keys = [
          'transactions',
          'rows',
          'items',
          'result',
          'list',
        ];

        for (final k in keys) {
          final v = x[k];
          if (v is List) {
            return v.whereType<Map<String, dynamic>>().toList();
          }
        }

        // Иногда данные внутри data: {...} или data: [...]
        final data = x['data'];
        if (data is List) {
          return data.whereType<Map<String, dynamic>>().toList();
        }
        if (data is Map) {
          for (final k in keys) {
            final v = data[k];
            if (v is List) {
              return v.whereType<Map<String, dynamic>>().toList();
            }
          }
          // Иногда data сама — это одна запись
          if (data.isNotEmpty) {
            return [data.cast<String, dynamic>()];
          }
        }

        // Если корнем является одна запись
        if (x.isNotEmpty) {
          return [x.cast<String, dynamic>()];
        }
      }

      return const <Map<String, dynamic>>[];
    }

    final list = _extractList(res);
    if (list.isEmpty && kDebugMode) {
      debugPrint(
          '[DriverApi] get_driver_transactions: empty or unexpected shape: $res');
    }

    return list.map((e) => DriverTransaction.fromJson(e)).toList();
  }

  static Future<List<DriverDriveHistory>> getDriversDrivesHistory({
    required String from,
    required String to,
  }) async {
    final res = await ApiService.callAndDecode(
      'get_drivers_drives_history',
      {
        'from': from,
        'to': to,
      },
      timeoutSeconds: 300,
    ).timeout(const Duration(seconds: 300));

    final raw = (res['data'] is Map<String, dynamic>)
        ? (res['data'] as Map<String, dynamic>)['drives']
        : null;
    final list = (raw is List) ? raw : const [];
    return list
        .whereType<Map>()
        .map((e) => DriverDriveHistory.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Возвращает lookup-данные для формы (vehicle types/brands/models/colors)
  static Future<VerificationPreData> getVerificationPreData() async {
    final res = await ApiService.callAndDecode('get_verification_pre_data', {})
        .timeout(const Duration(seconds: 120));
    return VerificationPreData.fromJson(res);
  }

  static Future<Map<String, dynamic>> submitCarVerification({
    required int vehicleTypeId,
    required int brandId,
    required int modelId,
    required String colorHex,
    required String number,
    required int year,
    required Uint8List carDocFile, // front
    required Uint8List carDocFile2, // back
    required List<Uint8List> carPhotos, // минимум 4 фото автомобиля
    Uint8List? vehicleInspectionFile,
    Uint8List? vehicleInspectionFile2,
    void Function(int done, int total)? onProgress,
  }) async {
    String b64(Uint8List f) => base64Encode(f);

    final payload = {
      'vehicle_type_id': vehicleTypeId,
      'brand_id': brandId,
      'model_id': modelId,
      'color_hex': colorHex,
      'number': number,
      'year': year,
    };

    final images = <Map<String, Object>>[
      {'type': 'VEHICLE_IMAGE', 'file': carDocFile},
      {'type': 'VEHICLE_IMAGE2', 'file': carDocFile2},
      for (int i = 0; i < carPhotos.length; i++)
        {'type': 'CAR${i + 1}_IMAGE', 'file': carPhotos[i]},
      if (vehicleInspectionFile != null)
        {'type': 'VEHICLE_INSPECTION_IMAGE', 'file': vehicleInspectionFile},
      if (vehicleInspectionFile2 != null)
        {
          'type': 'VEHICLE_INSPECTION_IMAGE2',
          'file': vehicleInspectionFile2,
        },
    ];
    final totalSteps = images.length + 1;
    onProgress?.call(0, totalSteps);

    final res = await ApiService.callAndDecode(
      'submit_car_verification',
      payload,
    ).timeout(const Duration(seconds: 30));

    final status = (res['status'] ?? '').toString().toUpperCase();
    if (status != 'OK') {
      return (res is Map<String, dynamic>)
          ? res
          : <String, dynamic>{'status': 'ERROR'};
    }

    onProgress?.call(1, totalSteps);

    for (var i = 0; i < images.length; i++) {
      final item = images[i];
      final type = item['type'] as String;
      final file = item['file'] as Uint8List;
      await ApiService
          .callAndDecode('add_car_verification_image', {
        'type': type,
        'base64': b64(file),
      }, timeoutSeconds: 300)
          .timeout(const Duration(seconds: 300));
      onProgress?.call(i + 2, totalSteps);
    }

    return (res is Map<String, dynamic>)
        ? res
        : <String, dynamic>{'status': 'ERROR'};
  }

  static Future<Map<String, dynamic>> startDriving({
    required double lat,
    required double lng,
    double? heading, // градусы 0..359 (если есть)
    double? accuracy, // метры (если есть)
  }) {
    return ApiService.callAndDecode('start_driving', {
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  static Future<Map<String, dynamic>> stopDriving() {
    return ApiService.callAndDecode('stop_driving', const {});
  }

  static Future<Map<String, dynamic>> getOffers() {
    return ApiService.callAndDecode('get_offers', const {});
  }

  static Future<Map<String, dynamic>> acceptDrive({
    required int requestId,
    required int driveId,
  }) {
    return ApiService.callAndDecode('accept_drive', {
      'request_id': requestId,
      'drive_id': driveId,
    });
  }

  static Future<Map<String, dynamic>> declineDrive({
    required int requestId,
    required int driveId,
  }) {
    return ApiService.callAndDecode('decline_drive', {
      'request_id': requestId,
      'drive_id': driveId,
    });
  }

  static Future<void> endCall(Map<String, dynamic> body) async {
    await ApiService.callAndDecode('end_call', body);
  }

  static Future<void> answerCall(int callId) async {
    await ApiService.callAndDecode('answer_call', {'call_id': callId});
  }

  static Future<int?> getCurrentDriveId() async {
    final resp = await ApiService.callAndDecode('get_current_drive_id', {});

    if (resp is Map<String, dynamic>) {
      final data = resp['data'];
      if (data is Map<String, dynamic>) {
        return ApiService.asInt(data['current_drive_id']);
      }
    }

    return null;
  }
}
