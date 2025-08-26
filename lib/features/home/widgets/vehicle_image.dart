import 'package:flutter/material.dart';

class VehicleImage extends StatelessWidget {
  final String vehicleKey;
  final double size;
  const VehicleImage({super.key, required this.vehicleKey, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final px = (size * dpr).round();
    final provider = ResizeImage.resizeIfNeeded(px, px, AssetImage('assets/images/$vehicleKey.png'));

    return Image(
      image: provider,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => Icon(Icons.local_taxi_outlined, size: size, color: Colors.black45),
    );
  }
}