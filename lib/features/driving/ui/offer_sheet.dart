import 'package:flutter/material.dart';

typedef AsyncAction = Future<void> Function();

class OfferSheet {
  static Future<void> show(
      BuildContext context, {
        // тексты
        required String fromName,
        required String fromDetails,
        required String toName,
        required String toDetails,
        required String distanceLabel,
        required String durationLabel,
        required String priceLabel,
        // колбэки
        required AsyncAction onAccept,
        required AsyncAction onDecline,
        // локализация
        required String Function(String key) t,
      }) {
    return showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // drag-handle
                Container(
                  width: 46,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),

                // FROM
                Row(
                  children: [
                    const Icon(Icons.location_pin, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fromName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (fromDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        fromDetails,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),

                // TO
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (toDetails.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, top: 2, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        toDetails,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Плашки
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Pill(icon: Icons.straighten, label: distanceLabel),
                    _Pill(icon: Icons.schedule,   label: durationLabel),
                    _Pill(icon: Icons.payments,   label: priceLabel),
                  ],
                ),

                const SizedBox(height: 14),

                // Кнопки
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async => onDecline(),
                        icon: const Icon(Icons.close),
                        label: Text(t('common.decline')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async => onAccept(),
                        icon: const Icon(Icons.check),
                        label: Text(t('common.ok')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ShapeDecoration(
        color: Colors.black.withOpacity(0.04),
        shape: const StadiumBorder(
          side: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
