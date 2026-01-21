// lib/features/home/widgets/car_section.dart
import 'package:flutter/material.dart';
import 'info_card.dart';

class CarSection extends StatelessWidget {
  final bool hasCar;
  final String? number;
  final String? brand;
  final String? model;
  final String? color;       // <-- добавили цвет

  /// ID машины из базы — если он есть, показываем кнопку Start driving
  final int? carId;

  /// Статус проверки документов машины
  final String? carClass;   // "NOCAR" | "AWAITING" | "REJECTED"
  final String? carReason;  // причина (если REJECTED)

  final VoidCallback onAddCar;
  final VoidCallback? onBookRental;   // опционально
  final VoidCallback? onStartDriving; // опционально
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
    this.onStartDriving,
    this.carClass,
    this.carReason,
    this.carId,
    this.color, // <-- новый параметр
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cls = (carClass ?? '').toUpperCase(); // NOCAR / AWAITING / REJECTED
    final hasCarId = carId != null;

    // Бейдж статуса + причина отказа
    Widget statusBlock() {
      if (cls == 'AWAITING' || cls == 'REJECTED') {
        final bool rejected = cls == 'REJECTED';
        final Color color = rejected ? Colors.red : Colors.amber;
        final String label = rejected
            ? t('home.verification.rejected')
            : t('home.verification.pending');

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
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: color)),
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

    // Кнопки Add car
    List<Widget> _buildTopButtons() {
      if (cls == 'AWAITING') {
        return const [];
      } else {
        return [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAddCar,
              icon: const Icon(Icons.add),
              label: Text(t('home.car.add')),
            ),
          ),
        ];
      }
    }

    // Нижняя кнопка Start driving
    Widget _startDrivingButton() {
      if (!hasCarId) return const SizedBox.shrink();

      void fallback() {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start driving is not wired yet')),
        );
      }

      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.drive_eta),
          label: Text(t('drive.start')),
          onPressed: onStartDriving ?? fallback,
        ),
      );
    }

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
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
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
                          if ((color ?? '').isNotEmpty)
                            _colorLine(context, t('home.car.color'), color!),
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
              ..._buildTopButtons(),
            ],
            if (hasCarId) ...[
              const SizedBox(height: 12),
              const Divider(height: 24),
              _startDrivingButton(),
            ],
          ],
        ),
      );
    }

    // Машины нет
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('home.car.title'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          statusBlock(),
          const SizedBox(height: 8),
          ..._buildTopButtons(),
        ],
      ),
    );
  }

  Widget _kvLine(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        Text(v, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _colorLine(BuildContext context, String k, String value) {
    final theme = Theme.of(context);
    final parsed = _parseColor(value);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (parsed != null) ...[
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.dividerColor),
              color: parsed,
            ),
          ),
        ],
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  /// Пытаемся распарсить цвет из строки.
  /// Поддерживаем: #RRGGBB, #AARRGGBB, 0xAARRGGBB, 0xRRGGBB
  Color? _parseColor(String s) {
    final v = s.trim();
    try {
      if (v.startsWith('#')) {
        final hex = v.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('0xFF$hex'));
        } else if (hex.length == 8) {
          return Color(int.parse('0x$hex'));
        }
      } else if (v.startsWith('0x') || v.startsWith('0X')) {
        final hex = v.substring(2);
        if (hex.length == 6) {
          return Color(int.parse('0xFF$hex'));
        } else if (hex.length == 8) {
          return Color(int.parse('0x$hex'));
        }
      }
    } catch (_) {
      // игнорируем ошибки парсинга
    }
    return null;
  }
}
