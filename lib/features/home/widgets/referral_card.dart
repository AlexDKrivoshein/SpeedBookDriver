import 'package:flutter/material.dart';
import 'info_card.dart';
import '../../../translations.dart';

class ReferralCard extends StatelessWidget {
  final String? referalName;
  final bool canAddReferal;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAttach;

  const ReferralCard({
    super.key,
    required this.referalName,
    required this.canAddReferal,
    required this.controller,
    required this.busy,
    required this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    if ((referalName ?? '').isNotEmpty) {
      return InfoCard(
        child: Row(
          children: [
            const Icon(Icons.handshake, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${t(context, "home.referral.current_prefix")}: ${referalName!}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
    }

    if (canAddReferal) {
      return InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context, 'home.referral.title'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            // Поле ввода + кнопка на одном уровне
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t(context, 'home.referral.id_label'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.tag),
                      // чтобы счётчик не увеличивал высоту карточки
                      counterText: '',
                    ),
                    maxLength: 12,
                  ),
                ),
                const SizedBox(width: 8),
                // Кнопка той же высоты, что и TextField ( ~56 )
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onAttach,
                    icon: busy
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.link),
                    label: Text(t(context, 'home.referral.attach')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
