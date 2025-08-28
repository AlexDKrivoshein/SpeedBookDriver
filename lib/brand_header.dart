import 'package:flutter/material.dart';
import 'brand.dart';

class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  const BrandHeader({
    super.key,
    this.title,
    this.logoAsset = 'assets/brand/speedbook.png',
    this.showBack = false,
  });

  final String? title;
  final String logoAsset;
  final bool showBack;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.yellow,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: preferredSize.height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Brand.border),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showBack)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Brand.textDark),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                )
              else
                const SizedBox(width: 48), // баланс для центрирования

              // центр — эмблема + опциональный заголовок
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // эмблема (как на phone_input_page)
                    Image.asset(
                      logoAsset,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
                    if (title != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Brand.textDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 48), // симметрия справа
            ],
          ),
        ),
      ),
    );
  }
}
