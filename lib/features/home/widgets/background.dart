import 'package:flutter/material.dart';

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key});

  static const _assetPattern = 'assets/brand/background_alpha.png';
  static const double _bgScale = 1.15;
  static const double _bgOpacityLight = 0.18;
  static const double _bgOpacityDark = 0.10;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? _bgOpacityDark : _bgOpacityLight;

    return Positioned.fill(
      child: Transform.scale(
        scale: _bgScale,
        alignment: Alignment.topLeft,
        child: Image.asset(
          _assetPattern,
          fit: BoxFit.none,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
          opacity: AlwaysStoppedAnimation(opacity),
        ),
      ),
    );
  }
}