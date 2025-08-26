import 'package:flutter/material.dart';
import '../brand.dart';
import '../models.dart';
import 'vehicle_image.dart';

class OrderPanel extends StatelessWidget {
  final String currentText;
  final String destinationText;
  final List<RouteVehicle> vehicles;
  final RouteVehicle? selected;
  final VoidCallback onTapCurrent;
  final VoidCallback onTapDestination;
  final void Function(RouteVehicle) onSelectVehicle;
  final String paymentLabel;
  final VoidCallback onTapPayment;
  final String orderText;
  final VoidCallback onTapOrder;
  final VoidCallback onTapSettings;

  const OrderPanel({
    super.key,
    required this.currentText,
    required this.destinationText,
    required this.vehicles,
    required this.selected,
    required this.onTapCurrent,
    required this.onTapDestination,
    required this.onSelectVehicle,
    required this.paymentLabel,
    required this.onTapPayment,
    required this.orderText,
    required this.onTapOrder,
    required this.onTapSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Colors.white,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
            ),
            _OrderRow(icon: Icons.radio_button_checked, iconColor: kBrandYellowDark, text: currentText, onTap: onTapCurrent),
            const Divider(height: 14),
            _OrderRow(icon: Icons.flag_outlined, iconColor: kBrandYellow, text: destinationText, onTap: onTapDestination, bold: true, trailing: const Icon(Icons.add, size: 20)),
            const SizedBox(height: 12),

            if (vehicles.isNotEmpty)
              SizedBox(
                height: 130, // стабильная высота под карточки
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vehicles.length,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final v = vehicles[i];
                    final isSel = selected?.key == v.key;
                    return _VehicleCard(
                      v: v,
                      selected: isSel,
                      onTap: () => onSelectVehicle(v),
                    );
                  },
                ),
              ),

            const SizedBox(height: 12),
            Row(
              children: [
                _SquareButton(
                  bg: kBrandYellow,
                  onTap: onTapPayment,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.attach_money, color: Colors.black87),
                    const SizedBox(width: 6),
                    Text(paymentLabel, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      onPressed: onTapOrder,
                      child: Text(orderText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _SquareButton(
                  bg: Colors.white,
                  border: const BorderSide(color: kBrandYellow, width: 2),
                  onTap: onTapSettings,
                  child: const Icon(Icons.tune, color: Colors.black87),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final VoidCallback onTap;
  final bool bold;
  final Widget? trailing;

  const _OrderRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.onTap,
    this.bold = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 16),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final Color? bg;
  final BorderSide? border;

  const _SquareButton({required this.onTap, required this.child, this.bg, this.border});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg ?? Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: border ?? BorderSide.none),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: child),
      ),
    );
  }
}

/// Карточка тарифа: тексты слева, картинка справа (крупнее), фиксированная высота.
/// Так мы избегаем переполнения по высоте на разных размерах шрифта/экранах.
class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.v,
    required this.selected,
    required this.onTap,
  });

  final RouteVehicle v;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const double cardW = 164;
    const double cardH = 120;

    return SizedBox(
      width: cardW,
      height: cardH,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? kBrandYellowDark : Colors.black12,
                width: selected ? 2 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Тексты слева
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        v.cost > 0 ? '${v.cost} ${v.currency}' : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: Colors.black87,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        v.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Картинка справа — крупнее и без искажений
                VehicleImage(
                  vehicleKey: v.key,
                  size: 72, // увеличенная иконка
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
