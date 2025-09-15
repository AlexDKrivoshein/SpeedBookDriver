// lib/features/home/widgets/car_section.dart
import 'package:flutter/material.dart';
import 'info_card.dart';

class CarSection extends StatelessWidget {
  final bool hasCar;
  final String? number;
  final String? brand;
  final String? model;

  // Новые поля статуса машины
  final String? carClass;   // "NOCAR" | "AWAITING" | "REJECTED"
  final String? carReason;  // причина (если REJECTED)

  final VoidCallback onAddCar;
  final VoidCallback? onBookRental; // опционально
  final String Function(String key) t;

  const CarSection({
    super.key,
    required this.hasCar,
    required this.number,
    required this.brand,
    required this.model,
    required this.onAddCar,
    required this.t,
    this.onBookRental,
    this.carClass,
    this.carReason,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cls = (carClass ?? '').toUpperCase(); // NOCAR / AWAITING / REJECTED

    // Бейдж статуса + причина отказа
    Widget statusBlock() {
      if (cls == 'AWAITING' || cls == 'REJECTED') {
        final bool rejected = cls == 'REJECTED';
        final Color color = rejected ? Colors.red : Colors.amber;
        final String label = rejected
            ? t('home.verification.rejected')
            : t('home.verification.pending'); // "Документы на проверке"

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ),
            if (rejected && (carReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(carReason!, style: theme.textTheme.bodyMedium),
            ],
          ],
        );
      }
      return const SizedBox.shrink();
    }

    // Кнопки по правилам:
    // NOCAR или REJECTED -> две кнопки (Add car + Book rental car)
    // AWAITING -> только Book rental car
    List<Widget> buttons() {
      void fallbackRental() {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not implemented yet')),
        );
      }

      final bookRental = onBookRental ?? fallbackRental;

      if (cls == 'AWAITING') {
        return [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: bookRental,
              // Иконка совместимая со старыми SDK
              icon: const Icon(Icons.directions_car),
              label: Text(t('home.car.book_rental')),
            ),
          ),
        ];
      } else {
        // NOCAR / REJECTED / (пусто) -> две кнопки
        return [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onAddCar,
                  icon: const Icon(Icons.add),
                  label: Text(t('home.car.add')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: bookRental,
                  icon: const Icon(Icons.directions_car),
                  label: Text(t('home.car.book_rental')),
                ),
              ),
            ],
          ),
        ];
      }
    }

    // Если машина уже есть — показываем карточку с данными,
    // плюс статус и кнопки (если применимо).
    if (hasCar) {
      return InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.directions_car, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('home.car.title'),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          if ((number ?? '').isNotEmpty)
                            _kvLine(context, t('home.car.number'), number!),
                          if ((brand ?? '').isNotEmpty)
                            _kvLine(context, t('home.car.brand'), brand!),
                          if ((model ?? '').isNotEmpty)
                            _kvLine(context, t('home.car.model'), model!),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            statusBlock(),
            if (cls == 'NOCAR' || cls == 'REJECTED' || cls == 'AWAITING') ...[
              const SizedBox(height: 8),
              ...buttons(),
            ],
          ],
        ),
      );
    }

    // Машины нет — заголовок + статус + нужные кнопки
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('home.car.title'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          statusBlock(),
          const SizedBox(height: 8),
          ...buttons(),
        ],
      ),
    );
  }

  Widget _kvLine(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text(v, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
