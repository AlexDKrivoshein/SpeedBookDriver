import 'package:flutter/material.dart';
import '../../../driver_api.dart';
import 'info_card.dart';
import 'tx_item.dart';

class TransactionsSection extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<DriverTransaction> transactions;
  final VoidCallback onRetry;
  final String emptyLabel;
  final String title;
  final String retryLabel;

  const TransactionsSection({
    super.key,
    required this.loading,
    required this.error,
    required this.transactions,
    required this.onRetry,
    required this.emptyLabel,
    required this.title,
    required this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          InfoCard(
            child: Row(
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(width: 12),
                Expanded(child: Text(error!)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
              ],
            ),
          )
        else if (transactions.isEmpty)
            InfoCard(
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Text(emptyLabel)),
                ],
              ),
            )
          else
            InfoCard(
              child: Column(
                children: [
                  for (int i = 0; i < (transactions.length > 10 ? 10 : transactions.length); i++) ...[
                    TxItem(tx: transactions[i]),
                    if (i != (transactions.length > 10 ? 10 : transactions.length) - 1)
                      const Divider(height: 16),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}
