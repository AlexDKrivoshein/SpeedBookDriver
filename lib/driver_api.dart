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
