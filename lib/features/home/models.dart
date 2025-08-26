import 'package:google_maps_flutter/google_maps_flutter.dart';

class QuickPlace {
  final String title;
  final LatLng? latLng;
  const QuickPlace(this.title, this.latLng);
}

class RouteVehicle {
  final String key;
  final String name;
  final int cost;
  final String currency;
  const RouteVehicle({required this.key, required this.name, required this.cost, required this.currency,});
}

class RouteDetails {
  final int waypoint;
  final int distance;
  final int duration;
  final String? encodedPolyline;
  final List<RouteVehicle> vehicles;
  const RouteDetails({
    required this.waypoint,
    required this.distance,
    required this.duration,
    required this.encodedPolyline,
    required this.vehicles,
  });
}