import 'package:flutter/material.dart';
import 'brand.dart';

class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  const BrandHeader({
    super.key,
    this.showBack = false,
    this.headerHeight = 88,
    this.logoHeight = 72,
    this.logoMaxWidthFraction = 0.9,
  });

  final bool showBack;
  final double headerHeight;
  final double logoHeight;
  final double logoMaxWidthFraction;

  @override
  Size get preferredSize => Size.fromHeight(headerHeight);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.yellow,
      child: SafeArea(
        bottom: false,
        child: Container(
          // ...
          child: Row(
            children: [
              // ...
              Expanded(
                child: Center(
                  child: Image.asset(
                    'assets/brand/speedbook.png', // ← фиксированно
                    height: logoHeight,
                    fit: BoxFit.fitHeight,
                  ),
                ),
              ),
              // ...
            ],
          ),
        ),
      ),
    );
  }
}
