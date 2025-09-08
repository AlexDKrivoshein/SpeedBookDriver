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

class DriverApi {
  /// Возвращает подробности водителя (JWT-полезная нагрузка)
  static Future<DriverDetails> getDriverDetails() async {
    debugPrint('[DriverApi] get_driver_details');
    final payload = await ApiService.callAndDecode('get_driver_details', const {});
    return DriverDetails.fromJson(payload);
  }

  /// Установка реферала. Возвращает {status, message?}
  static Future<Map<String, dynamic>> setReferal(String referalId) async {
    final res = await ApiService.callPlain('set_referal', {'referal': referalId});
    // ожидаем {status: 'OK'|'ERROR', message?: '...'}
    return res;
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
      if (v is int) {
        // сек/мс
        return DateTime.fromMillisecondsSinceEpoch(v > 1e12 ? v : v * 1000, isUtc: true).toLocal();
      }
      if (v is String) {
        try { return DateTime.parse(v).toLocal(); } catch (_) {}
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