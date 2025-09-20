import 'package:flutter/material.dart';

class HomeBackground extends StatelessWidget {
  /// Прозрачность «вуали» над паттерном, чтобы фон не спорил с контентом.
  final double opacity;

  /// Выравнивание паттерна (на всех экранах используем topLeft).
  final Alignment alignment;

  const HomeBackground({
    super.key,
    this.opacity = 0.05,
    this.alignment = Alignment.topLeft,
  });

  static const _assetPattern = 'assets/brand/background.png';

  @override
  Widget build(BuildContext context) {
    // Виджет рассчитан на использование внутри Stack.
    return Positioned.fill(
      child: IgnorePointer(
        child: Image.asset(
          _assetPattern,
          repeat: ImageRepeat.repeat, // плитка повторяется
          fit: BoxFit.none,           // не масштабируем (как в phone_input)
          alignment: alignment,
          filterQuality: FilterQuality.low,
          // лёгкая белая «вуаль», чтобы фон не был навязчивым
          color: Colors.white.withOpacity(opacity),
          colorBlendMode: BlendMode.srcATop,
        ),
      ),
    );
  }
}