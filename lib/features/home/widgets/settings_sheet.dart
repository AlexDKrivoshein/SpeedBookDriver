import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../translations.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.current, required this.t});

  static const _langPrefKey = 'user_lang';

  final String current;
  final String Function(String) t;

  static Future<String?> pickLanguage(
    BuildContext context, {
    required String Function(BuildContext, String) t,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getString(_langPrefKey) ?? 'en').toLowerCase();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SettingsSheet(current: current, t: (k) => t(ctx, k)),
    );
    return choice;
  }

  static Future<void> changeLanguage(
    BuildContext context, {
    required String Function(BuildContext, String) t,
  }) async {
    final choice = await pickLanguage(context, t: t);
    if (choice == null || !context.mounted) return;
    try {
      await context.read<Translations>().setLang(choice);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const items = [
      {'code': 'en', 'label': 'English'},
      {'code': 'ru', 'label': 'Русский'},
      {'code': 'km', 'label': 'ខ្មែរ'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t('menu.language'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          for (final it in items)
            ListTile(
              leading: Icon(
                it['code'] == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(it['label']!),
              onTap: () => Navigator.of(context).pop(it['code']),
            ),
        ],
      ),
    );
  }
}
