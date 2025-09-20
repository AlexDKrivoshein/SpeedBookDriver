import 'package:flutter/material.dart';

class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  final double height;
  final String asset;                 // картинка по умолчанию всегда есть
  final bool showBack;
  final VoidCallback? onBackTap;
  final VoidCallback? onMenuTap;      // если showBack=false — показываем меню
  final List<Widget>? actions;

  static const String _kDefaultAsset = 'assets/brand/brand_header.png';

  const BrandHeader({
    super.key,
    this.height = 64,
    String? asset,
    this.showBack = false,
    this.onBackTap,
    this.onMenuTap,
    this.actions,
  }) : asset = asset ?? _kDefaultAsset;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // фон-баннер
          DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // слева: back или меню
                  if (showBack)
                    _circleBtn(
                      icon: Icons.arrow_back,
                      onTap: onBackTap ?? () => Navigator.maybePop(context),
                    )
                  else if (onMenuTap != null)
                    _circleBtn(
                      icon: Icons.menu,
                      onTap: onMenuTap!,
                    )
                  else
                    const SizedBox(width: 44, height: 44),

                  const Spacer(),

                  if (actions != null) ...actions!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({required IconData icon, required VoidCallback onTap}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(icon, color: Colors.black87, size: 22),
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
