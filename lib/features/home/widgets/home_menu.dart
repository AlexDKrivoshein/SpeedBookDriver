import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api_service.dart';
import '../../../brand.dart';
import '../../../driver_api.dart'; // DriverDetails

String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

class HomeMenu extends StatelessWidget {
  const HomeMenu({
    super.key,
    required this.details,
    required this.onInvite,
    required this.onOpenVerification,
    required this.onOpenCar,
    required this.onOpenTransactions,
    required this.onOpenAccounts,
    required this.onOpenSettings,
    required this.onOpenSupport,
    required this.onPickLanguage,
    required this.onLogout,
  });

  final DriverDetails details;
  final VoidCallback onInvite;
  final VoidCallback onOpenVerification;
  final VoidCallback onOpenCar;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSupport;
  final Future<void> Function(BuildContext) onPickLanguage;
  final Future<void> Function(BuildContext) onLogout;

  @override
  Widget build(BuildContext context) {
    final verified = (details.driverClass ?? '').toUpperCase() == 'VERIFIED';

    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0,6))],
                border: Border.all(color: const Color(0x11000000)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Brand.yellow.withOpacity(0.9),
                    child: Text(
                      _initials(details.name),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                details.name.isEmpty ? '—' : details.name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (verified) const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.verified, color: Colors.green, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 16),
                            const SizedBox(width: 4),
                            Text(details.rating.isEmpty ? '—' : details.rating,
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.tag, size: 14, color: Colors.black54),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text('${t(context, "home.referral.your_id")}: ${details.id}',
                                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (!verified)
                    _tile(context, Icons.verified_user, t(context, 'menu.verification'), onOpenVerification),

                  _tile(context, Icons.directions_car_filled, t(context, 'menu.car'), onOpenCar),

                  _tile(context, Icons.account_balance_wallet, t(context, 'menu.accounts'), onOpenAccounts),

                  _tile(context, Icons.receipt_long, t(context, 'menu.transactions'), onOpenTransactions),

                  _tile(context, Icons.ios_share, t(context, 'menu.invite'), onInvite),

                  const Divider(height: 16),

                  _tile(context, Icons.settings, t(context, 'menu.settings'), onOpenSettings),

                  _tile(context, Icons.language, t(context, 'menu.language'),
                        () => onPickLanguage(context),
                  ),

                  _tile(context, Icons.support_agent, t(context, 'menu.support'), onOpenSupport),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onLogout(context),
                  icon: const Icon(Icons.logout),
                  label: Text(t(context, 'menu.logout')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ListTile _tile(BuildContext ctx, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.of(ctx).pop(); // закрываем Drawer
        onTap();
      },
    );
  }

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '🙂';
    final one = parts.first[0].toUpperCase();
    final two = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$one$two';
  }
}
