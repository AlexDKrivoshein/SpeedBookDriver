import 'package:flutter/material.dart';
import '../../../brand.dart';

class PickupActionBar extends StatelessWidget {
  final bool canArrived;
  final bool canStart;
  final bool canFinish;
  final bool canCancel;
  final bool busy;

  final VoidCallback? onArrived;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;
  final VoidCallback? onCancel;

  /// Функция локализации, например: `(k) => t(context, k)`
  final String Function(String key) t;

  const PickupActionBar({
    super.key,
    required this.canArrived,
    required this.canStart,
    required this.canFinish,
    required this.canCancel,
    required this.busy,
    required this.onArrived,
    required this.onStart,
    required this.onFinish,
    required this.onCancel,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final show = canArrived || canStart || canFinish || canCancel;
    if (!show) return const SizedBox.shrink();

    final children = <Widget>[];

    if (canArrived) {
      children.add(
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.yellowDark,
              foregroundColor: Brand.textDark,
            ),
            onPressed: busy ? null : onArrived,
            icon: const Icon(Icons.flag_circle),
            label: Text(t('driving.arrived')),
          ),
        ),
      );
    }

    if (canArrived && (canStart || canCancel)) {
      children.add(const SizedBox(width: 12));
    }

    if (canStart) {
      children.add(
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.yellowDark,
              foregroundColor: Brand.textDark,
            ),
            onPressed: busy ? null : onStart,
            icon: const Icon(Icons.play_arrow),
            label: Text(t('driving.start')),
          ),
        ),
      );
    }

    if (canStart && canCancel) {
      children.add(const SizedBox(width: 12));
    }

    if (canFinish) {
      children.add(
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.yellowDark,
              foregroundColor: Brand.textDark,
            ),
            onPressed: busy ? null : onFinish,
            icon: const Icon(Icons.check_circle),
            label: Text(t('driving.finish')),
          ),
        ),
      );
    }

    if (canFinish && canCancel) {
      children.add(const SizedBox(width: 12));
    }

    if (canCancel) {
      children.add(
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.textDark,
              side: const BorderSide(color: Brand.border),
            ),
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.close),
            label: Text(t('driving.cancel_drive')),
          ),
        ),
      );
    }

    return Row(children: children);
  }
}
