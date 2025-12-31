import 'package:flutter/material.dart';
import '../../../driver_api.dart';
import 'info_card.dart';
import 'account_square_card.dart';

class AccountsCarousel extends StatelessWidget {
  final List<DriverAccount> accounts;
  final PageController pageController;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final String emptyLabel;
  final void Function(DriverAccount account)? onPayout;

  const AccountsCarousel({
    super.key,
    required this.accounts,
    required this.pageController,
    required this.currentIndex,
    required this.onPageChanged,
    required this.emptyLabel,
    this.onPayout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (accounts.isEmpty) {
      return InfoCard(
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet),
            const SizedBox(width: 12),
            Expanded(child: Text(emptyLabel, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    return SizedBox(
      height: 170,
      child: PageView.builder(
        controller: pageController,
        itemCount: accounts.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          final acc = accounts[index];
          final isActive = index == currentIndex;
          final showPayout = acc.isMain;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: isActive ? 6 : 10,
              vertical: isActive ? 0 : 8,
            ),
            child: AccountSquareCard(
              account: acc,
              highlighted: isActive,
              showPayout: showPayout,
              onPayout: (showPayout && onPayout != null) ? () => onPayout!(acc) : null,
            ),
          );
        },
      ),
    );
  }
}
