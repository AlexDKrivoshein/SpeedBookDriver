import 'package:flutter/material.dart';

/// Статус верификации водителя
enum DriverVerificationStatus {
  needVerification,
  awaitingVerification,
  verified,
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // ====== захардкоженные значения ======
  final String driverName = 'Иван Петров';
  final String phoneNumber = '+7 999 123-45-67';
  final double balance = 12850.75;
  final DriverVerificationStatus status =
      DriverVerificationStatus.needVerification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Home')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // карточка с именем и телефоном
            _InfoCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    child: Text(
                      _initials(driverName),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone,
                              size: 16, color: theme.hintColor),
                          const SizedBox(width: 6),
                          Text(
                            phoneNumber,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // карточка с балансом
            _InfoCard(
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Баланс на счёте',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    _formatCurrency(balance),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // карточка со статусом
            _InfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Статус верификации',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatusChip(
                        label: _statusLabel(status),
                        color: _statusColor(context, status),
                      ),
                      const Spacer(),
                      if (status == DriverVerificationStatus.needVerification)
                        FilledButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Нажали Add documents'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Add documents'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== helpers =====
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.last : '';
    final i1 = first.isNotEmpty ? first.characters.first.toUpperCase() : '';
    final i2 = last.isNotEmpty ? last.characters.first.toUpperCase() : '';
    return (i1 + i2).isNotEmpty ? (i1 + i2) : 'DR';
  }

  static String _statusLabel(DriverVerificationStatus s) {
    switch (s) {
      case DriverVerificationStatus.needVerification:
        return 'Требуется верификация';
      case DriverVerificationStatus.awaitingVerification:
        return 'Ожидает проверки';
      case DriverVerificationStatus.verified:
        return 'Верифицирован';
    }
  }

  static Color _statusColor(BuildContext context, DriverVerificationStatus s) {
    switch (s) {
      case DriverVerificationStatus.needVerification:
        return Theme.of(context).colorScheme.error;
      case DriverVerificationStatus.awaitingVerification:
        return Colors.amber;
      case DriverVerificationStatus.verified:
        return Colors.green;
    }
  }

  static String _formatCurrency(double v) {
    final whole = v.truncate();
    final frac = ((v - whole) * 100).round().toString().padLeft(2, '0');
    final wholeStr = _thousandsSep(whole);
    return '$wholeStr.$frac ₽';
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
      ),
      child: child,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
