// lib/features/home/delete_account.dart
import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../api_service.dart';

/// Полный поток удаления аккаунта:
/// - предупреждение;
/// - вызов API delete_my_account;
/// - очистка токена/секрета, signOut;
/// - закрытие приложения.
Future<void> deleteAccountFlow(BuildContext context) async {
  final confirmed = await _confirmDeleteDialog(context);
  if (confirmed != true) return;

  // Показать спиннер
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  // Вызов API
  try {
    await ApiService.callAndDecode(
      'delete_my_account',
      const {},
      validateOnline: true,
    );
  } catch (e) {
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.mounted) nav.pop(); // закрыть спиннер
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Delete failed. Please try again.')),
    );
    return;
  }

  // Закрыть спиннер
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.mounted) nav.pop();

  // Очистка локальных данных
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('secret');
  } catch (_) {}

  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}

  // Завершить приложение
  try {
    SystemNavigator.pop();
  } catch (_) {
    try { exit(0); } catch (_) {}
  }
}

Future<bool?> _confirmDeleteDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('⚠️ Attention!'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deleting your account is permanent and cannot be undone.\n'),
            Text('• Your account will be permanently deleted and cannot be restored.'),
            SizedBox(height: 4),
            Text('• All ride data and trip history will be removed.'),
            SizedBox(height: 4),
            Text('• All transaction records, balances and accounts will be deleted.'),
            SizedBox(height: 4),
            Text('• Referral connections will be lost.'),
            SizedBox(height: 4),
            Text('• All accumulated bonuses and discounts will be voided.'),
            SizedBox(height: 4),
            Text('• Your driver rating will be lost.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: const ButtonStyle(
            backgroundColor: MaterialStatePropertyAll(Colors.red),
            foregroundColor: MaterialStatePropertyAll(Colors.white),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
