// lib/driver_api.dart
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'dart:convert';

class DriverAccount {
  final String name;
  final String currency;
  final double balance;

  DriverAccount({
    required this.name,
    required this.currency,
    required this.balance,
  });

  factory DriverAccount.fromJson(Map<String, dynamic> json) {
    return DriverAccount(
      name: json['name']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      balance: (json['balance'] is num)
          ? (json['balance'] as num).toDouble()
          : double.tryParse(json['balance']?.toString() ?? '0') ?? 0.0,
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
  final int? carId;     // id машины
  final String? number; // номерной знак
  final String? brand;  // марка
  final String? model;  // модель
  final String? carClass;
  final String? carReason;


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
    this.carClass,
    this.carReason,
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
      carClass: root['car_class'],
      carReason: root['car_reason'],
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

class CarModel {
  final int id;
  final String name;
  CarModel({required this.id, required this.name});
  factory CarModel.fromJson(Map<String, dynamic> j) =>
      CarModel(id: (j['id'] as num).toInt(), name: (j['name'] ?? '').toString());
}

class CarBrand {
  final int id;
  final String name;
  final List<CarModel> models;
  CarBrand({required this.id, required this.name, required this.models});
  factory CarBrand.fromJson(Map<String, dynamic> j) {
    final ms = (j['models'] is List)
        ? (j['models'] as List).whereType<Map<String, dynamic>>().map(CarModel.fromJson).toList()
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
        ? (j['brands'] as List).whereType<Map<String, dynamic>>().map(CarBrand.fromJson).toList()
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
  factory CarColor.fromJson(Map<String, dynamic> j) =>
      CarColor(hex: (j['hex'] ?? '#000000').toString(), name: (j['name'] ?? '').toString());
}

class VerificationPreData {
  final List<CarType> cars;
  final List<CarColor> colors;
  VerificationPreData({required this.cars, required this.colors});
  factory VerificationPreData.fromJson(Map<String, dynamic> json) {
    final root = (json['data'] is Map<String, dynamic>) ? json['data'] : json;
    final types = (root['cars'] is List)
        ? (root['cars'] as List).whereType<Map<String, dynamic>>().map(CarType.fromJson).toList()
        : <CarType>[];
    final cols = (root['colors'] is List)
        ? (root['colors'] as List).whereType<Map<String, dynamic>>().map(CarColor.fromJson).toList()
        : <CarColor>[];
    return VerificationPreData(cars: types, colors: cols);
  }
}

class CarDocUpload {
  final String filename;
  final String base64; // содержимое файла в base64
  final String mime;   // 'image/jpeg'/'image/png'
  CarDocUpload({required this.filename, required this.base64, required this.mime});

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
      res = await ApiService.callAndDecode(
          'get_driver_transactions', payload);
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
      debugPrint('[DriverApi] get_driver_transactions: empty or unexpected shape: $res');
    }

    return list.map((e) => DriverTransaction.fromJson(e)).toList();
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
    required Uint8List carDocFile, // один обязательный файл
  }) async {
    String b64(Uint8List f) => base64Encode(f);

    final payload = {
      'vehicle_type_id': vehicleTypeId,
      'brand_id': brandId,
      'model_id': modelId,
      'color_hex': colorHex,
      'number': number,
      'year': year,
      'docs': {
        'car_doc': b64(carDocFile),
      },
    };

    final res = await ApiService.callAndDecode('submit_car_verification', payload)
        .timeout(const Duration(seconds: 30));
    return (res is Map<String, dynamic>) ? res : <String, dynamic>{'status': 'ERROR'};
  }

  static Future<Map<String, dynamic>> startDriving({
    required double lat,
    required double lng,
    double? heading,   // градусы 0..359 (если есть)
    double? accuracy,  // метры (если есть)
  }) {
    return ApiService.callAndDecode('start_driving', {
      'lat': lat,
      'lng': lng,
      if (heading != null)  'heading': heading,
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
}

