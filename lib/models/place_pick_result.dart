import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlacePickResult {
  final LatLng latLng;
  final String title;
  /// int8 из API, null если место не из списка
  final int? placeId;
  PlacePickResult({
     required this.latLng,
     required this.title,
     this.placeId,
   });
}