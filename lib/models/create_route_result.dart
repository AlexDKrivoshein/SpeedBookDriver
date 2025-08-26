import 'vehicle_type.dart';

class CreateRouteResult {
  final String statusId;     // "OK" либо код ошибки
  final int? routeId;        // если OK
  final List<VehicleType> vehicleTypes;
  final String? errorMessage;

  bool get isOk => statusId.toUpperCase() == 'OK';

  CreateRouteResult({
    required this.statusId,
    this.routeId,
    this.vehicleTypes = const [],
    this.errorMessage,
  });

  factory CreateRouteResult.fromJson(Map<String, dynamic> j) {
    final vt = (j['vehicle_types'] as List?)
        ?.map((e) => VehicleType.fromJson(e as Map<String, dynamic>))
        .toList() ??
        const <VehicleType>[];

    return CreateRouteResult(
      statusId: (j['status_id'] as String? ?? '').trim(),
      routeId: j['route_id'] is int ? j['route_id'] as int : null,
      vehicleTypes: vt,
      errorMessage: j['error'] as String?,
    );
  }
}