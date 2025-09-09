import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BrandHeader extends StatefulWidget implements PreferredSizeWidget {
  const BrandHeader({
    super.key,
    this.maxHeight,                              // опциональный потолок по высоте
    this.showBack = false,
    this.onBack,
    this.overlayStyle = SystemUiOverlayStyle.dark,
  });

  // Одна общая картинка на всё приложение
  static const String _assetPath = 'assets/brand/brand_header.png';

  final double? maxHeight;
  final bool showBack;
  final VoidCallback? onBack;
  final SystemUiOverlayStyle overlayStyle;

  @override
  State<BrandHeader> createState() => _BrandHeaderState();

  // Возвращаем актуальную высоту (обновляется после вычисления)
  @override
  Size get preferredSize => const Size.fromHeight(120); // значение по умолчанию, реальное задаём из state
}

class _BrandHeaderState extends State<BrandHeader> {
  double _preferredHeight = 120;                 // fallback, пока не знаем размер
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 1) Готовим ImageProvider и узнаём его исходный размер
    final provider = const AssetImage(BrandHeader._assetPath);
    final config = createLocalImageConfiguration(context);
    final stream = provider.resolve(config);

    // Убираем старый листенер, если был
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }

    _listener = ImageStreamListener((ImageInfo info, _) {
      final imgW = info.image.width.toDouble();
      final imgH = info.image.height.toDouble();
      if (imgW > 0 && mounted) {
        final screenW = MediaQuery.of(context).size.width;
        double desired = screenW * (imgH / imgW);         // высота по аспект-рейшо
        if (widget.maxHeight != null) {
          desired = desired.clamp(0.0, widget.maxHeight!);
        }
        setState(() => _preferredHeight = desired);
      }
    });

    stream.addListener(_listener!);
    _stream = stream;

    // прогреем ассет, чтобы не моргнул
    precacheImage(provider, context);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // пересoberдим preferredSize через InheritedWidget (Scaffold перечитает)
    final appBar = _AppBarSize(_preferredHeight, _buildContent(context));
    return appBar;
  }

  Widget _buildContent(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: widget.overlayStyle,
      child: Material(
        color: Colors.transparent, // никаких заливок
        elevation: 0,
        child: SizedBox(
          height: _preferredHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Картинка целиком по ширине без обрезаний
              Image.asset(
                BrandHeader._assetPath,
                fit: BoxFit.fitWidth,             // вписываем по ширине
                alignment: Alignment.topCenter,
              ),

              if (widget.showBack)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Вспомогательный инхеритед, чтобы передать динамическую высоту в PreferredSizeWidget
class _AppBarSize extends InheritedWidget implements PreferredSizeWidget {
  const _AppBarSize(this.height, Widget child, {Key? key})
      : super(key: key, child: child);

  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  bool updateShouldNotify(_AppBarSize oldWidget) => oldWidget.height != height;
}
