import 'package:flutter/material.dart';
import '../../../driver_api.dart';
import '../../../api_service.dart';

class AccountSquareCard extends StatelessWidget {
  final DriverAccount account;
  final bool highlighted;
  const AccountSquareCard({super.key, required this.account, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: highlighted ? kElevationToShadow[3] : kElevationToShadow[1],
          border: Border.all(
            color: highlighted
                ? theme.colorScheme.primary.withOpacity(0.6)
                : const Color(0x14000000),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.name.isEmpty
                  ? ApiService.getTranslationForWidget(context, 'home.account.default_name')
                  : account.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              _formatMoney(account.balance, account.currency),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    account.currency,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMoney(double v, String currencyCode) {
    final whole = v.truncate();
    final wholeStr = _thousandsSep(whole);
    return '$wholeStr $currencyCode';
  }

  static String _thousandsSep(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    var count = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write(' ');
        count = 0;
      }
    }
    return buf.toString().split('').reversed.join();
  }
}
