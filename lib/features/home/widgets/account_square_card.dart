import 'package:flutter/material.dart';
import '../../../driver_api.dart';
import '../../../translations.dart';

class AccountSquareCard extends StatelessWidget {
  final DriverAccount account;
  final bool highlighted;
  final VoidCallback? onPayout;
  final bool showPayout;
  const AccountSquareCard({
    super.key,
    required this.account,
    this.highlighted = false,
    this.onPayout,
    this.showPayout = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
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
                  ? t(context, 'home.account.default_name')
                  : account.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _formatMoney(account.balance, account.currency),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (showPayout) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size.fromHeight(28),
                    textStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: onPayout,
                  child: Text(t(context, 'home.payout.button')),
                ),
              ),
            ],
            const Spacer(),
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
