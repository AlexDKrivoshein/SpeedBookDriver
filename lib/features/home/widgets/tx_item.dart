import 'package:flutter/material.dart';
import '../../../driver_api.dart';

class TxItem extends StatelessWidget {
  final DriverTransaction tx;
  const TxItem({super.key, required this.tx});

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtDate(DateTime d) =>
      '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

  String _formatMoney(double v, String currency) {
    final sign = v >= 0 ? '' : '-';
    final n = v.abs();
    final whole = n.truncate();
    final s = _thousands(whole);
    return '$sign$s $currency';
  }

  String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    var cnt = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      b.write(s[i]);
      cnt++;
      if (cnt == 3 && i != 0) {
        b.write(' ');
        cnt = 0;
      }
    }
    return b.toString().split('').reversed.join();
  }

  IconData _icon(String t) {
    final x = t.toLowerCase();
    if (x.contains('ride') || x.contains('trip')) return Icons.local_taxi;
    if (x.contains('payout') || x.contains('withdraw')) return Icons.payments_outlined;
    if (x.contains('topup') || x.contains('deposit')) return Icons.add_card_outlined;
    if (x.contains('commission')) return Icons.receipt_long_outlined;
    return Icons.swap_vert;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlus = tx.total >= 0;
    final sumColor = isPlus ? Colors.green : Colors.red;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_icon(tx.type), size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (tx.service.isNotEmpty ? tx.service : tx.type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (tx.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(tx.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 2),
              Text(_fmtDate(tx.date), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_formatMoney(tx.total, tx.currency),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: sumColor)),
            if (tx.commission != 0)
              Text('- ${_formatMoney(tx.commission, tx.currency)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ],
        ),
      ],
    );
  }
}
