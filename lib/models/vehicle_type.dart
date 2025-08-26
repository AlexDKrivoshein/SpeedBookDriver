class VehicleType {
  final String name;
  final String memo;

  VehicleType({
    required this.name,
    required this.memo,
  });

  factory VehicleType.fromJson(Map<String, dynamic> j) => VehicleType(
    name: j['name']?.toString() ?? '',
    memo: j['memo']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'memo': memo,
  };
}