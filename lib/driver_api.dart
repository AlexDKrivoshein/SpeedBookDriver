// lib/driver_api.dart
import 'package:flutter/foundation.dart';
import 'api_service.dart';

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

  DriverDetails({
    required this.id,
    required this.name,
    required this.driverClass,
    required this.rating,
    required this.accounts,
    this.rejectionReason,
    required this.referal,
    this.canAddReferal = false,
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
}
